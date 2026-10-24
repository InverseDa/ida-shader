#ifndef IDA_BLOCK_CLOUDS_GLSL
#define IDA_BLOCK_CLOUDS_GLSL

// Integrate exact XZ cell segments within the thin cloud slab. A coarse
// equal-step march cannot reliably represent narrow faces or camera entry.
vec4 RenderBlockClouds(vec3 OriginWorld, vec3 RayDir, float MaxDistance, bool NeedColor) {
    vec2 Interval = CloudRayInterval(OriginWorld, RayDir, MaxDistance);
    if (Interval.y <= Interval.x) return vec4(0.0);
    vec2 Wind = vec2(2.0, 0.8) * frameTimeCounter;
    vec2 GridOrigin = OriginWorld.xz - Wind;
    vec2 StepSign = sign(RayDir.xz);
    vec2 Cell = floor((GridOrigin + RayDir.xz * (Interval.x + 0.0001)) / BlockCloudCellSize);
    vec2 InvDirection = vec2(1.0) / max(abs(RayDir.xz), vec2(0.0000001));
    vec2 Delta = BlockCloudCellSize * InvDirection;
    vec2 Boundary = (Cell + step(vec2(0.0), RayDir.xz)) * BlockCloudCellSize;
    vec2 Next = (Boundary - GridOrigin) * StepSign * InvDirection;
    if (abs(RayDir.x) < 0.0000001) Next.x = 1e8;
    if (abs(RayDir.z) < 0.0000001) Next.y = 1e8;
    float T = Interval.x;
    vec3 FaceNormal = vec3(0.0, -sign(RayDir.y), 0.0);
    if (T == 0.0) FaceNormal = -RayDir;
    vec3 CloudFaceNormal = FaceNormal;
    float CloudEntryHeight = OriginWorld.y + RayDir.y * T;
    bool InCloud = false;
    vec3 LightDir = vec3(0.0);
    vec3 Light = vec3(0.0);
    vec3 Ambient = vec3(0.0);
    if (NeedColor) {
        LightDir = ViewToWorldNormal(normalize(shadowLightPosition), gbufferModelViewInverse);
        Light = GetDirectionalLightRadiance(SunColor, NightValue) *
                DirectionalHeightStrength(LightDir.y, NightValue) * WeatherDirectFactor(rainStrength);
        float Luma = dot(SkyColor, vec3(0.2126, 0.7152, 0.0722));
        Ambient = mix(vec3(Luma), SkyColor, 0.35) * mix(0.65, 0.40, NightValue) * mix(1.0, 0.75, rainStrength);
    }
    vec3 Sum = vec3(0.0);
    float Alpha = 0.0;
    // 4096 / 24 * sqrt(2) < 242 crossings, including a diagonal ray inside
    // the slab. This bound covers the entire interval, even through empty cells.
    for (int I = 0; I < 256; ++I) {
        if (T >= Interval.y || Alpha >= 0.995) break;
        float End = min(min(Next.x, Next.y), Interval.y);
        float Length = max(End - T, 0.0);
        float Mid = T + Length * 0.5;
        vec3 Position = OriginWorld + RayDir * Mid;
        float Coverage = SampleStyledCloudCoverage(Position, vec2(0.0), true);
        float Opacity = (1.0 - exp(-Coverage * CloudExtinction * Length * CloudDistanceWeight(Mid))) * (1.0 - Alpha);
        if (Coverage > 0.0001 && !InCloud) {
            CloudFaceNormal = FaceNormal;
            CloudEntryHeight = OriginWorld.y + RayDir.y * T;
        }
        if (NeedColor && Opacity > 0.0) {
            // A boundary between occupied cells is not an exposed face.
            // Preserve the cloud's entry surface to avoid a bright tile grid.
            float FaceLight = 0.62 + 0.38 * max(dot(CloudFaceNormal, LightDir), 0.0);
            float Visibility = GetCloudShadow(CloudEntryHeight, LightDir.y, Coverage);
            // The softer scattered component keeps block undersides readable;
            // the face term retains actual side/top/bottom orientation.
            Sum += (Ambient + Light * FaceLight * (0.35 + 0.65 * Visibility)) * Opacity;
        }
        Alpha += Opacity;
        if (Length > 0.0) InCloud = Coverage > 0.0001;
        T = End;
        if (Next.x < Next.y) {
            Cell.x += StepSign.x;
            Next.x += Delta.x;
            FaceNormal = vec3(-StepSign.x, 0.0, 0.0);
        } else {
            Cell.y += StepSign.y;
            Next.y += Delta.y;
            FaceNormal = vec3(0.0, 0.0, -StepSign.y);
        }
    }
    return vec4(Sum / max(Alpha, 0.0001), clamp(Alpha, 0.0, 1.0));
}
#endif
