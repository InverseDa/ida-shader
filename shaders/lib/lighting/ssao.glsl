#ifndef IDA_LIGHTING_SSAO_GLSL
#define IDA_LIGHTING_SSAO_GLSL

float SsaoViewDepth(float Depth) {
    // Use the actual perspective projection. Iris's render-distance `far`
    // need not equal the projection's clip plane. Z is independent of jitter.
    float NdcDepth = Depth * 2.0 - 1.0;
    return -(gbufferProjectionInverse[2].z * NdcDepth + gbufferProjectionInverse[3].z) /
           (gbufferProjectionInverse[2].w * NdcDepth + gbufferProjectionInverse[3].w);
}

float SsaoVisibility(float ViewDepth, float RadiusPixels) {
    // Subpixel AO has no reliable depth support. Fade before the render-distance
    // boundary as well, so distant geometry does not acquire a dark horizon rim.
    return smoothstep(1.0, 3.0, RadiusPixels) *
           (1.0 - smoothstep(far * 0.65, far * 0.95, ViewDepth));
}

float SsaoOcclusionWeight(vec3 Delta, vec3 Normal, float DepthDifference, float Radius, float Bias) {
    float DistanceSquared = dot(Delta, Delta);
    float RadiusSquared = Radius * Radius;
    if (DistanceSquared >= 4.0 * RadiusSquared) return 0.0;
    // A depth discontinuity alone is not a nearby occluder. Bound its actual
    // 3D distance and exclude coplanar/behind-plane samples before adding AO.
    // A projected probe can meet a wall beyond its own radius. Allow a soft
    // two-radius support (at most 1.9 blocks), then reject it completely.
    float RangeWeight = 1.0 - smoothstep(RadiusSquared, 4.0 * RadiusSquared, DistanceSquared);
    float PlaneWeight = smoothstep(Bias, Bias + Radius * 0.12, dot(Normal, Delta));
    float DepthWeight = smoothstep(Bias, Bias + Radius * 0.12, DepthDifference);
    return RangeWeight * PlaneWeight * DepthWeight;
}

float GetSsaoSampleOcclusion(ivec2 CenterPixel, vec3 CenterViewPos, vec3 Normal, vec3 SampleViewPos, float Radius, float Bias, vec2 Jitter) {
    if (SampleViewPos.z >= -near) return 0.0;
    vec2 SampleScreenUv = ProjectViewToScreenPos(SampleViewPos, gbufferProjection).xy + Jitter;
    if (!IsScreenUvInRange(SampleScreenUv)) return 0.0;

    // Sample one actual surface. Bilinear depth can invent geometry between
    // foreground and background, while nearest metadata describes only one.
    ivec2 Size = textureSize(depthtex1, 0);
    ivec2 Pixel = clamp(ivec2(SampleScreenUv * vec2(Size)), ivec2(0), Size - 1);
    if (all(equal(Pixel, CenterPixel))) return 0.0;
    float SampleDepth = texelFetch(depthtex1, Pixel, 0).r;
    if (SampleDepth >= 1.0) return 0.0;

    float SceneViewDepth = SsaoViewDepth(SampleDepth);
    float DepthDifference = -SceneViewDepth - SampleViewPos.z;
    // These samples cannot contribute; avoid the metadata read/reconstruction.
    if (DepthDifference <= Bias || abs(SceneViewDepth + CenterViewPos.z) >= 2.0 * Radius) return 0.0;
    vec4 Material = texelFetch(colortex5, Pixel, 0);
    // The first-person hand uses a compressed depth range, not world geometry.
    if (IsMaterial(Material, MaterialIdHand)) return 0.0;
    bool Jittered = MaterialUsesTaaJitter(Material);
    vec2 SampleUv = (vec2(Pixel) + 0.5) / vec2(Size);
    vec3 SceneViewPos = ReconstructSurfaceViewPos(SampleUv, SampleDepth, Jittered);
    return SsaoOcclusionWeight(SceneViewPos - CenterViewPos, Normal, DepthDifference, Radius, Bias);
}

float GetScreenSpaceAmbientOcclusion(vec3 ViewPos, vec3 Normal, bool Jittered) {
    float Radius = clamp(-ViewPos.z * 0.018, 0.30, 0.95);
    float RadiusPixels = 0.5 * viewHeight * abs(gbufferProjection[1].y) * Radius / max(-ViewPos.z, near);
    float Visibility = SsaoVisibility(-ViewPos.z, RadiusPixels);
    if (Visibility <= 0.0) return 1.0;
    vec3 N = normalize(Normal);
    vec3 TangentSeed = abs(N.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
    vec3 Tangent = TangentSeed - N * dot(TangentSeed, N);
    Tangent = normalize(Tangent);
    vec3 Bitangent = normalize(cross(N, Tangent));
    mat3 Tbn = mat3(Tangent, Bitangent, N);

    float Bias = 0.02 + Radius * 0.03;
    float Occlusion = 0.0;
    ivec2 CenterPixel = ivec2(gl_FragCoord.xy);
    vec2 Jitter = Jittered ? CurrentJitterUv() : vec2(0.0);
    // Four near contacts + four wider probes, balanced around the normal.
    // No random rotation, temporal noise, extra normal reads or AO history.
    Occlusion += GetSsaoSampleOcclusion(CenterPixel, ViewPos, N, ViewPos + Tbn * vec3(0.30, 0.00, 0.22) * Radius, Radius, Bias, Jitter);
    Occlusion += GetSsaoSampleOcclusion(CenterPixel, ViewPos, N, ViewPos + Tbn * vec3(-0.30, 0.00, 0.22) * Radius, Radius, Bias, Jitter);
    Occlusion += GetSsaoSampleOcclusion(CenterPixel, ViewPos, N, ViewPos + Tbn * vec3(0.00, 0.30, 0.22) * Radius, Radius, Bias, Jitter);
    Occlusion += GetSsaoSampleOcclusion(CenterPixel, ViewPos, N, ViewPos + Tbn * vec3(0.00, -0.30, 0.22) * Radius, Radius, Bias, Jitter);
    Occlusion += GetSsaoSampleOcclusion(CenterPixel, ViewPos, N, ViewPos + Tbn * vec3(0.58, 0.58, 0.42) * Radius, Radius, Bias, Jitter);
    Occlusion += GetSsaoSampleOcclusion(CenterPixel, ViewPos, N, ViewPos + Tbn * vec3(-0.58, 0.58, 0.42) * Radius, Radius, Bias, Jitter);
    Occlusion += GetSsaoSampleOcclusion(CenterPixel, ViewPos, N, ViewPos + Tbn * vec3(0.58, -0.58, 0.42) * Radius, Radius, Bias, Jitter);
    Occlusion += GetSsaoSampleOcclusion(CenterPixel, ViewPos, N, ViewPos + Tbn * vec3(-0.58, -0.58, 0.42) * Radius, Radius, Bias, Jitter);

    float Ao = 1.0 - Occlusion * 0.55 / 8.0;
    return mix(1.0, clamp(pow(Ao, 1.15), 0.0, 1.0), Visibility);
}

#endif
