#ifndef IDA_SHORE_FOAM_GLSL
#define IDA_SHORE_FOAM_GLSL
#if SHORE_FOAM == 1 && defined(IDA_WATER_SURFACE_PASS)
uniform sampler2D colortex5;

float shoreFoamSupport(float normalUp, float backgroundState, float backgroundDepth,
                       float surfaceDepth, float distanceToCamera, float footprint) {
    // Static opaque geometry only: entities, unready snapshots and sky cannot
    // become a moving shoreline. The underwater path never calls this helper.
    if (backgroundState < 1.5 || backgroundDepth >= 0.999999 || backgroundDepth <= surfaceDepth) return 0.0;
    float top = smoothstep(0.85, 0.98, normalUp);
    float range = 1.0 - smoothstep(40.0, 72.0, distanceToCamera);
    float resolved = 1.0 - smoothstep(0.10, 0.35, footprint);
    return top * range * resolved * SHORE_FOAM_STRENGTH;
}

float shoreFoamContact(vec3 toSurface, vec3 bankNormal, vec3 worldUpView, float waveHeight) {
    // Signed distance to the visible bank/bottom plane, not camera-ray length.
    // A flat bottom at one block depth stays clear. Only observed shallow
    // geometry supports contact: a deep rock face need not reach the surface.
    float belowSurface = dot(toSurface, worldUpView);
    float contactDistance = dot(toSurface, bankNormal);
    float bankUp = dot(bankNormal, worldUpView);
    if (belowSurface <= 0.0 || contactDistance <= 0.0 || bankUp < -0.1) return 0.0;
    // Do not extend an arbitrary underwater plane up to an imaginary shoreline.
    // Deep visible bank samples conservatively lose foam at grazing views.
    float shallow = 1.0 - smoothstep(0.80, 1.25, belowSurface);
    float width = 0.62 + clamp(waveHeight, -0.30, 0.30) * 0.35;
    return shallow * (1.0 - smoothstep(0.04, width, contactDistance));
}

float sampleShoreFoam(vec3 relativeWorld, vec3 viewPos, vec3 viewPosBehind,
                      vec3 baseWorldNormal, vec2 opaqueUv, vec4 opaque, float surfaceDepth,
                      vec2 dpdx, vec2 dpdy, float waveHeight) {
    float footprint = max(length(dpdx), length(dpdy));
    float support = shoreFoamSupport(baseWorldNormal.y, opaque.a, opaque.b,
                                    surfaceDepth, length(viewPos), footprint);
    if (support <= 0.0) return 0.0;
    vec3 upView = mat3(gbufferModelView) * vec3(0.0, 1.0, 0.0);
    float contact = shoreFoamContact(viewPos - viewPosBehind, normalDecode(opaque.rg), upView, waveHeight);
    if (contact <= 0.0) return 0.0;
    // Even near the surface, kelp/seagrass cutouts are not solid banks. Reuse
    // immutable material metadata at exactly the snapshot texel; only contact
    // candidates pay this one fetch, with no additional depth query.
    if (isVegetationMaterial(fetchMaterialData(colortex5, opaqueUv))) return 0.0;
    // Existing 128-square custom noise: one block per texel, world anchored. Wave
    // height animates coverage; camera motion does not scroll the noise field.
    vec2 uv = (relativeWorld + cameraPosition).xz / 128.0;
    float noise = textureGrad(noisetex, uv, dpdx / 128.0, dpdy / 128.0).r;
    float filterWidth = footprint * 0.8;
    float breakup = smoothstep(0.40 - filterWidth, 0.64 + filterWidth, noise + waveHeight * 0.12);
    return clamp(0.82 * support * contact * breakup, 0.0, 1.0);
}

vec3 shoreFoamRadiance(vec3 vanillaLight) {
    // Cheap diffuse lighting from the local lightmap, including weather, night
    // and block lights. No emission floor or extra shadow/cloud sampling.
    return vec3(0.82, 0.86, 0.84) * vanillaLight * LIGHTMAP_STRENGTH;
}

#endif
#endif
