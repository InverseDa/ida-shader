#ifndef IDA_MATERIALS_PUDDLES_GLSL
#define IDA_MATERIALS_PUDDLES_GLSL
#include "/lib/settings.glsl"

#if SURFACE_WETNESS == 1 && PUDDLE_REFLECTIONS == 1
#include "/lib/materials/wetness.glsl"
#include "/lib/reflections/puddle_trace.glsl"
#include "/lib/materials/lighting/sky.glsl"

float puddleRetention(vec4 material) {
    if (isMaterial(material, MATERIAL_ID_PUDDLE_SOIL)) return 0.78;
    if (isMaterial(material, MATERIAL_ID_PUDDLE_SAND)) return 0.22;
    if (isMaterial(material, MATERIAL_ID_PUDDLE_STONE)) return 1.0;
    if (isMaterial(material, MATERIAL_ID_PUDDLE_WOOD)) return 0.85;
    return 0.0;
}

float puddleExposure(float skyVisibility, float viewDistance) {
    // Use the existing 16-level skylight metadata, never camera brightness or
    // sun shadows. Terrain already tagged only upward geometric faces, without
    // screen-space derivatives. Fade distant ground BEFORE noise / SSR.
    float sky = smoothstep(14.0 / 15.0, 1.0, skyVisibility);
    return sky * (1.0 - smoothstep(32.0, 64.0, viewDistance));
}

vec2 puddleNoiseUv(vec3 relativeWorld) {
    // 128px custom noise: one texel per 3 blocks, repeat every 384 blocks.
    // No time term: puddles grow in place, never swim with camera or wind.
    return (relativeWorld + cameraPosition).xz / 384.0;
}

float puddleCoverage(float noiseValue, float wetAmount) {
    float wet = clamp(wetAmount, 0.0, 1.0);
    float threshold = mix(0.86, 0.46, wet);
    float patch = smoothstep(threshold, threshold + 0.16, noiseValue);
    return patch * smoothstep(0.10, 0.75, wet);
}

float puddleReflectivity(float viewCosine, float coverage) {
    // Air/water Fresnel: 2% face-on, increasing at grazing angles. The previous
    // 10% + cubic response turned a missed SSR hit into a broad pale overlay.
    float grazing = 1.0 - clamp(viewCosine, 0.0, 1.0);
    float grazing2 = grazing * grazing;
    return clamp(coverage, 0.0, 1.0) * (0.02 + 0.98 * grazing2 * grazing2 * grazing);
}

vec3 composePuddleReflection(vec3 base, vec3 sky, vec3 scene, float confidence, float reflectivity) {
    // Confidence only selects scene versus sky; a lost hit cannot suddenly
    // remove the puddle or change the amount of base color it replaces.
    vec3 reflected = mix(sky, scene, clamp(confidence, 0.0, 1.0));
    return mix(base, reflected, clamp(reflectivity, 0.0, 1.0));
}

vec3 drawPuddleReflection(vec3 baseColor, vec3 viewPos, vec4 material, float viewVariance) {
    float retention = puddleRetention(material);
    if (retention <= 0.0 || surfaceWetness <= 0.10 || SURFACE_WETNESS_STRENGTH <= 0.0) return baseColor;
    // Do not reinterpret LabPBR metal pixels or a dry material's F0 as water.
    if (getMaterialMetallic(material) > 0.5) return baseColor;
    float exposure = puddleExposure(getMaterialSkyVisibility(material), length(viewPos));
    if (exposure <= 0.0) return baseColor;
    vec3 worldPos = viewToWorldPos(viewPos, gbufferModelViewInverse);
    float wetAmount = surfaceWetness * SURFACE_WETNESS_STRENGTH;
    float noiseValue = textureLod(noisetex, puddleNoiseUv(worldPos), 0.0).r;
    float coverage = puddleCoverage(noiseValue, wetAmount) * retention * exposure;
    if (coverage <= 0.0) return baseColor;

    // A shallow pool has a level air/water interface, independent of the
    // underlying material's fine normal map. No extra normal texture reads.
    vec3 worldNormal = vec3(0.0, 1.0, 0.0);
    vec3 normalView = normalize(mat3(gbufferModelView) * worldNormal);
    vec3 viewDir = normalize(-viewPos);
    vec3 reflectDir = reflect(-viewDir, normalView);
    float reflectivity = puddleReflectivity(dot(normalView, viewDir), coverage);
    float highlightVariance = 0.0001 + viewVariance;
    // Suppress the HDR sky disk during rain and at night, avoiding isolated
    // bright points in the fallback. Scene reflections keep their HDR values.
    vec3 sky = mix(getSkyBaseRadiance(reflectDir), skyColor, clamp(rainStrength, 0.0, 1.0) * 0.75);
    sky += getFilteredSkyDiskRadiance(reflectDir, highlightVariance) *
           (1.0 - smoothstep(0.0, 1.0, rainStrength)) * (1.0 - nightValue) * 0.25;
    ReflectionResult reflected = createReflectionResult(sky, 0.0);
    // An almost invisible edge gets sky only, fading SSR in continuously.
    float searchVisibility = smoothstep(0.01, 0.04, reflectivity);
    if (searchVisibility > 0.0) {
        reflected = tracePuddleReflection(viewPos, normalView, reflectDir, sky);
        reflected.confidence *= searchVisibility;
    }
    return composePuddleReflection(baseColor, sky, reflected.color, reflected.confidence, reflectivity);
}
#endif
#endif
