#ifndef IDA_LIGHTING_SSAO_GLSL
#define IDA_LIGHTING_SSAO_GLSL

float ssaoViewDepth(float depth) {
    // Use the actual perspective projection. Iris's render-distance `far`
    // need not equal the projection's clip plane. Z is independent of jitter.
    float ndcDepth = depth * 2.0 - 1.0;
    return -(gbufferProjectionInverse[2].z * ndcDepth + gbufferProjectionInverse[3].z) /
             (gbufferProjectionInverse[2].w * ndcDepth + gbufferProjectionInverse[3].w);
}

float ssaoVisibility(float viewDepth, float radiusPixels) {
    // Subpixel AO has no reliable depth support. Fade before the render-distance
    // boundary as well, so distant geometry does not acquire a dark horizon rim.
    return smoothstep(1.0, 3.0, radiusPixels) *
           (1.0 - smoothstep(far * 0.65, far * 0.95, viewDepth));
}

float ssaoOcclusionWeight(vec3 delta, vec3 normal, float depthDifference, float radius, float bias) {
    float distanceSquared = dot(delta, delta);
    float radiusSquared = radius * radius;
    if (distanceSquared >= 4.0 * radiusSquared) return 0.0;
    // A depth discontinuity alone is not a nearby occluder. Bound its actual
    // 3D distance and exclude coplanar/behind-plane samples before adding AO.
    // A projected probe can meet a wall beyond its own radius. Allow a soft
    // two-radius support (at most 1.9 blocks), then reject it completely.
    float rangeWeight = 1.0 - smoothstep(radiusSquared, 4.0 * radiusSquared, distanceSquared);
    float planeWeight = smoothstep(bias, bias + radius * 0.12, dot(normal, delta));
    float depthWeight = smoothstep(bias, bias + radius * 0.12, depthDifference);
    return rangeWeight * planeWeight * depthWeight;
}

float getSsaoSampleOcclusion(ivec2 centerPixel, vec3 centerViewPos, vec3 normal, vec3 sampleViewPos,
                            float radius, float bias, vec2 jitter) {
    if (sampleViewPos.z >= -near) return 0.0;
    vec2 sampleScreenUv = projectViewToScreenPos(sampleViewPos, gbufferProjection).xy + jitter;
    if (!isScreenUvInRange(sampleScreenUv)) return 0.0;

    // Sample one actual surface. Bilinear depth can invent geometry between
    // foreground and background, while nearest metadata describes only one.
    ivec2 size = textureSize(depthtex1, 0);
    ivec2 pixel = clamp(ivec2(sampleScreenUv * vec2(size)), ivec2(0), size - 1);
    if (all(equal(pixel, centerPixel))) return 0.0;
    float sampleDepth = texelFetch(depthtex1, pixel, 0).r;
    if (sampleDepth >= 1.0) return 0.0;

    float sceneViewDepth = ssaoViewDepth(sampleDepth);
    float depthDifference = -sceneViewDepth - sampleViewPos.z;
    // These samples cannot contribute; avoid the metadata read/reconstruction.
    if (depthDifference <= bias || abs(sceneViewDepth + centerViewPos.z) >= 2.0 * radius) return 0.0;
    vec4 material = texelFetch(colortex5, pixel, 0);
    // The first-person hand uses a compressed depth range, not world geometry.
    if (isMaterial(material, MATERIAL_ID_HAND)) return 0.0;
    bool jittered = materialUsesTaaJitter(material);
    vec2 sampleUv = (vec2(pixel) + 0.5) / vec2(size);
    vec3 sceneViewPos = reconstructSurfaceViewPos(sampleUv, sampleDepth, jittered);
    return ssaoOcclusionWeight(sceneViewPos - centerViewPos, normal, depthDifference, radius, bias);
}

float getScreenSpaceAmbientOcclusion(vec3 viewPos, vec3 normal, bool jittered) {
    float radius = clamp(-viewPos.z * 0.018, 0.30, 0.95);
    float radiusPixels = 0.5 * viewHeight * abs(gbufferProjection[1].y) * radius / max(-viewPos.z, near);
    float visibility = ssaoVisibility(-viewPos.z, radiusPixels);
    if (visibility <= 0.0) return 1.0;
    vec3 n = normalize(normal);
    vec3 tangentSeed = abs(n.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
    vec3 tangent = tangentSeed - n * dot(tangentSeed, n);
    tangent = normalize(tangent);
    vec3 bitangent = normalize(cross(n, tangent));
    mat3 tbn = mat3(tangent, bitangent, n);

    float bias = 0.02 + radius * 0.03;
    float occlusion = 0.0;
    ivec2 centerPixel = ivec2(gl_FragCoord.xy);
    vec2 jitter = jittered ? currentJitterUv() : vec2(0.0);
    // Four near contacts + four wider probes, balanced around the normal.
    // No random rotation, temporal noise, extra normal reads or AO history.
    occlusion += getSsaoSampleOcclusion(centerPixel, viewPos, n, viewPos + tbn * vec3( 0.30,  0.00, 0.22) * radius, radius, bias, jitter);
    occlusion += getSsaoSampleOcclusion(centerPixel, viewPos, n, viewPos + tbn * vec3(-0.30,  0.00, 0.22) * radius, radius, bias, jitter);
    occlusion += getSsaoSampleOcclusion(centerPixel, viewPos, n, viewPos + tbn * vec3( 0.00,  0.30, 0.22) * radius, radius, bias, jitter);
    occlusion += getSsaoSampleOcclusion(centerPixel, viewPos, n, viewPos + tbn * vec3( 0.00, -0.30, 0.22) * radius, radius, bias, jitter);
    occlusion += getSsaoSampleOcclusion(centerPixel, viewPos, n, viewPos + tbn * vec3( 0.58,  0.58, 0.42) * radius, radius, bias, jitter);
    occlusion += getSsaoSampleOcclusion(centerPixel, viewPos, n, viewPos + tbn * vec3(-0.58,  0.58, 0.42) * radius, radius, bias, jitter);
    occlusion += getSsaoSampleOcclusion(centerPixel, viewPos, n, viewPos + tbn * vec3( 0.58, -0.58, 0.42) * radius, radius, bias, jitter);
    occlusion += getSsaoSampleOcclusion(centerPixel, viewPos, n, viewPos + tbn * vec3(-0.58, -0.58, 0.42) * radius, radius, bias, jitter);

    float ao = 1.0 - occlusion * 0.55 / 8.0;
    return mix(1.0, clamp(pow(ao, 1.15), 0.0, 1.0), visibility);
}

#endif
