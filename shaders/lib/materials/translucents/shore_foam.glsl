#ifndef IDA_SHORE_FOAM_GLSL
#define IDA_SHORE_FOAM_GLSL
#if SHORE_FOAM == 1 && defined(IDA_WATER_SURFACE_PASS)
uniform sampler2D colortex5;

float ShoreFoamSupport(float NormalUp, float BackgroundState, float BackgroundDepth, float SurfaceDepth, float DistanceToCamera, float Footprint) {
    // Static opaque geometry only: entities, unready snapshots and sky cannot
    // become a moving shoreline. The underwater path never calls this helper.
    if (BackgroundState < 1.5 || BackgroundDepth >= 0.999999 || BackgroundDepth <= SurfaceDepth) return 0.0;
    float Top = smoothstep(0.85, 0.98, NormalUp);
    float Range = 1.0 - smoothstep(40.0, 72.0, DistanceToCamera);
    float Resolved = 1.0 - smoothstep(0.10, 0.35, Footprint);
    return Top * Range * Resolved * SHORE_FOAM_STRENGTH;
}

float ShoreFoamContact(vec3 ToSurface, vec3 BankNormal, vec3 WorldUpView, float WaveHeight) {
    // Signed distance to the visible bank/bottom plane, not camera-ray length.
    // A flat bottom at one block depth stays clear. Only observed shallow
    // geometry supports contact: a deep rock face need not reach the surface.
    float BelowSurface = dot(ToSurface, WorldUpView);
    float ContactDistance = dot(ToSurface, BankNormal);
    float BankUp = dot(BankNormal, WorldUpView);
    if (BelowSurface <= 0.0 || ContactDistance <= 0.0 || BankUp < -0.1) return 0.0;
    // Do not extend an arbitrary underwater plane up to an imaginary shoreline.
    // Deep visible bank samples conservatively lose foam at grazing views.
    float Shallow = 1.0 - smoothstep(0.80, 1.25, BelowSurface);
    float Width = 0.62 + clamp(WaveHeight, -0.30, 0.30) * 0.35;
    return Shallow * (1.0 - smoothstep(0.04, Width, ContactDistance));
}

float SampleShoreFoam(vec3 RelativeWorld, vec3 ViewPos, vec3 ViewPosBehind, vec3 BaseWorldNormal, vec2 OpaqueUv, vec4 Opaque, float SurfaceDepth, vec2 Dpdx, vec2 Dpdy, float WaveHeight) {
    float Footprint = max(length(Dpdx), length(Dpdy));
    float Support = ShoreFoamSupport(BaseWorldNormal.y, Opaque.a, Opaque.b, SurfaceDepth, length(ViewPos), Footprint);
    if (Support <= 0.0) return 0.0;
    vec3 UpView = mat3(gbufferModelView) * vec3(0.0, 1.0, 0.0);
    float Contact = ShoreFoamContact(ViewPos - ViewPosBehind, NormalDecode(Opaque.rg), UpView, WaveHeight);
    if (Contact <= 0.0) return 0.0;
    // Even near the surface, kelp/seagrass cutouts are not solid banks. Reuse
    // immutable material metadata at exactly the snapshot texel; only contact
    // candidates pay this one fetch, with no additional depth query.
    if (IsVegetationMaterial(FetchMaterialData(colortex5, OpaqueUv))) return 0.0;
    // Existing 128-square custom noise: one block per texel, world anchored. Wave
    // height animates coverage; camera motion does not scroll the noise field.
    vec2 Uv = (RelativeWorld + cameraPosition).xz / 128.0;
    float Noise = textureGrad(noisetex, Uv, Dpdx / 128.0, Dpdy / 128.0).r;
    float FilterWidth = Footprint * 0.8;
    float Breakup = smoothstep(0.40 - FilterWidth, 0.64 + FilterWidth, Noise + WaveHeight * 0.12);
    return clamp(0.82 * Support * Contact * Breakup, 0.0, 1.0);
}

vec3 ShoreFoamRadiance(vec3 VanillaLight) {
    // Cheap diffuse lighting from the local lightmap, including weather, night
    // and block lights. No emission floor or extra shadow/cloud sampling.
    return vec3(0.82, 0.86, 0.84) * VanillaLight * LIGHTMAP_STRENGTH;
}

#endif
#endif
