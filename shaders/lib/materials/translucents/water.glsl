#include "/lib/materials/translucents/surfaceReflection.glsl"
#include "/lib/materials/translucents/water_waves.glsl"
#include "/lib/materials/translucents/shore_foam.glsl"
#include "/lib/lighting/daylight.glsl"

float getWaterThickness(vec3 viewPos, vec3 viewPosBehind) {
    float waterDepth = max(length(viewPosBehind) - length(viewPos), 0.0);
    return clamp(waterDepth, 0.0, 512.0);
}

vec3 sampleRefractedSceneColor(vec2 screenUv, float surfaceDepth, vec3 normalView, float waterDepth, float waveSlope) {
    float refractionStrength = (0.007 + 0.025 * waveSlope) * (1.0 - exp(-waterDepth * 0.18));
    vec2 distortion = normalView.xy * refractionStrength;
    vec2 texel = vec2(1.0 / viewWidth, 1.0 / viewHeight);
    vec2 uv = opaqueUvForUnjitteredUv(screenUv + distortion);
    // Do not refract foreground objects across a silhouette.
    if (sampleOpaqueData(uv).b < surfaceDepth) uv = opaqueUvForUnjitteredUv(screenUv);
    vec3 centerColor = texture2D(colortex9, uv).rgb;
    float weight = 1.0;
    for (int i = -1; i <= 1; i += 2) {
        vec2 tapUv = clamp(uv + vec2(float(i) * texel.x, 0.0), texel * 0.5, vec2(1.0) - texel * 0.5);
        if (sampleOpaqueData(tapUv).b >= surfaceDepth) {
            centerColor += texture2D(colortex9, tapUv).rgb * 0.18;
            weight += 0.18;
        }
    }
    return centerColor / weight;
}

vec3 waterSurfaceScatter(vec3 biomeColor, vec3 vanillaLight) {
    // Vertex water tint is sRGB; use only a bounded hue contribution. It is
    // not illumination, and the air-side fogColor is not a water-biome color.
    vec3 biome = srgbToLinear(clamp(biomeColor, 0.0, 1.0));
    float peak = max(biome.r, max(biome.g, biome.b));
    vec3 tint = mix(vec3(0.025, 0.14, 0.20), biome / max(peak, 0.0001) * 0.20, 0.35);
    // Local lightmap already follows weather, night vision and block lights.
    // No unlit cyan floor, second day/night curve or extra direct-light boost.
    return tint * max(vanillaLight, vec3(0.0)) * LIGHTMAP_STRENGTH;
}

vec3 applyWaterVolume(vec3 sceneColor, vec3 scatterColor, vec3 transmittance) {
    // Beer-Lambert is per channel. The background is already lit: only the
    // added in-scattering uses local illumination. At zero length this is the
    // unchanged background, with no fixed tint/opacity or extra grazing gain.
    return sceneColor * transmittance + scatterColor * (vec3(1.0) - transmittance);
}

float waterLayerTransmission(vec3 transmittance, float reflectivity) {
    // Alpha blending can preserve prior transparent layers with one scalar.
    // Use the least-transmitted channel so no colored layer bypasses absorption.
    return (1.0 - clamp(reflectivity, 0.0, 1.0)) *
           min(transmittance.r, min(transmittance.g, transmittance.b));
}

SmoothSurfaceReflectionProfile getWaterReflectionProfile(float reflectivity, float wave, float waveSlope) {
    return createSmoothSurfaceReflectionProfile(
        mix(0.035, 0.085, waveSlope),
        reflectivity,
        1.72,
        mix(1.95, 1.28, waveSlope),
        0.66,
        mix(1.08, 1.22, wave),
        0.045,
        vec3(0.94, 1.02, 0.98),
        0.93
    );
}

float waterSunLightWeight(float sunHeight, float lightmapY) {
    // Use the existing interpolated sky light level, independent of block light
    // and weather-darkened Lightmap RGB. This is conservative shelter gating,
    // not directional visibility: a side-cast shadow can still have level 15.
    float skyLevel = clamp(lightmapY * 16.0 - 0.5, 0.0, 15.0);
    float exposure = smoothstep(14.0, 15.0, skyLevel);
    // Normalize the shared elevation curve to preserve clear-noon sparkle.
    float elevation = directionalHeightStrength(sunHeight, 0.0) / 1.32;
    return exposure * elevation * (1.0 - clamp(nightValue, 0.0, 1.0)) *
           weatherDirectFactor(rainStrength) * max(DIRECT_LIGHT_STRENGTH, 0.0);
}

vec3 waterSunTint(vec3 lightColor) {
    // Keep the established warm noon tint, without importing the legacy sky
    // table's HDR dawn gain into this extra surface highlight.
    vec3 boundedSun = getDirectionalLightRadiance(lightColor, 0.0) / 0.9;
    return mix(vec3(1.0, 0.86, 0.56), boundedSun, 0.45);
}

vec3 getWaterSunSparkle(
    vec3 viewPos,
    vec3 sparkleNormalView,
    float variance,
    float waveSlope,
    float waterDepth,
    float fresnel,
    float lightmapY
) {
    vec3 lightDir = normalize(sunPosition);
    float sunHeight = viewToWorldNormal(lightDir, gbufferModelViewInverse).y;
    float lightWeight = waterSunLightWeight(sunHeight, lightmapY);
    if (lightWeight <= 0.0) return vec3(0.0);
    vec3 viewDir = normalize(-viewPos);
    vec3 halfSum = lightDir + viewDir;
    vec3 halfDir = halfSum * inversesqrt(max(dot(halfSum, halfSum), 1e-8));
    vec3 reflectedView = normalize(reflect(normalize(viewPos), sparkleNormalView));

    float reflectionAlignment = clamp(dot(reflectedView, lightDir), 0.0, 1.0);
    float sunWindow = smoothstep(0.44, 0.925, reflectionAlignment);
    float broadSun = filteredHighlight(reflectionAlignment, 30.0, 4.0 * variance);
    float sharpSun = filteredHighlight(reflectionAlignment, mix(82.0, 160.0, clamp(waveSlope, 0.0, 1.0)), 4.0 * variance);
    float microFacet = filteredHighlight(dot(sparkleNormalView, halfDir), 90.0, variance);

    float depthFade = smoothstep(0.06, 1.45, waterDepth);
    float slopeFade = smoothstep(0.06, 0.62, waveSlope);
    float grazing = mix(0.55, 1.55, clamp(fresnel, 0.0, 1.0));
    float shimmer = mix(0.82, 1.22, slopeFade);
    float sparkle = lightWeight * depthFade * grazing;
    sparkle *= broadSun * 0.78 + sharpSun * 2.15 + microFacet * 0.72;
    sparkle *= sunWindow;
    sparkle *= shimmer;

    return waterSunTint(sunColor) * sparkle * 18.0;
}

SmoothSurfaceReflectionProfile getIceReflectionProfile(float reflectivity) {
    return createSmoothSurfaceReflectionProfile(
        0.18,
        reflectivity,
        0.96,
        0.72,
        0.38,
        0.94,
        0.05,
        vec3(1.0),
        0.95
    );
}

vec3 drawWater(vec3 color, vec3 worldPos, vec3 viewPos, vec3 viewPosBehind, vec3 normal,
               vec2 dpdx, vec2 dpdy, float viewVariance,
               vec2 screenUv, float surfaceDepth, vec2 opaqueUv, vec4 opaque,
               vec2 lightmapUv, vec3 vanillaLight, out float transmission) {
    vec3 baseWorldNormal = viewToWorldNormal(normalize(normal), gbufferModelViewInverse);
    WaterWaves waves = sampleWaterWaves(worldPos, dpdx, dpdy);
    float wave = clamp(0.5 + waves.height * 2.65, 0.0, 1.0);
    float waveSlope = clamp(length(waves.slope) * 3.35, 0.0, 1.0);
    float reflectionSlope = clamp(length(waves.broadSlope) * 3.35, 0.0, 1.0);
    vec3 worldWaveNormal = waterWaveNormal(baseWorldNormal, waves.slope, 0.88);
    vec3 worldReflectionNormal = waterWaveNormal(baseWorldNormal, waves.broadSlope, 0.24);
    vec3 reflectionNormal = normalize(mix(baseWorldNormal, worldReflectionNormal, 0.94));
    vec3 normal2 = normalize(mat3(gbufferModelView) * reflectionNormal);
    vec3 sparkleNormal = normalize(mat3(gbufferModelView) * normalize(mix(worldReflectionNormal, worldWaveNormal, 0.62)));

    vec3 reflectDir = reflect(normalize(viewPos), normal2);
    float viewCosine = clamp(abs(dot(normalize(viewPos), normal2)), 0.0, 1.0);
    float fresnel = pow(1.0 - viewCosine, 2.35);
    float reflectivity = mix(0.30, 0.96, fresnel) * mix(1.02, 1.10, wave);
    float waterDepth = getWaterThickness(viewPos, viewPosBehind);
    vec3 refractedScene = sampleRefractedSceneColor(screenUv, surfaceDepth, normal2, waterDepth, mix(waveSlope, reflectionSlope, 0.25));
    // Scalar transmission preserves already drawn transparent layers during
    // ordinary alpha blending. Spectral absorption remains in the water color.
    vec3 transmittance = waterTransmittance(waterDepth);
    transmission = waterLayerTransmission(transmittance, reflectivity);
    vec3 absorbedBaseColor = applyWaterVolume(refractedScene, waterSurfaceScatter(color, vanillaLight), transmittance);
    SmoothSurfaceReflectionProfile profile = getWaterReflectionProfile(
        reflectivity,
        wave,
        mix(waveSlope, reflectionSlope, 0.2)
    );
    // Do not change planar eligibility with the AA roughness: its 0.22 cutoff
    // would otherwise make reflections switch off when a normal varies rapidly.
    profile.highlightVariance = 4.0 * waves.variance * 0.051 + viewVariance;
    vec3 surfaceColor = resolveSmoothSurfaceColor(absorbedBaseColor, worldPos, viewPos, reflectionNormal, reflectDir, profile);
    surfaceColor += getWaterSunSparkle(
        viewPos,
        sparkleNormal,
        waves.variance * 0.41 + viewVariance * 0.25,
        max(waveSlope, reflectionSlope),
        waterDepth,
        fresnel,
        lightmapUv.y
    );
#if SHORE_FOAM == 1 && defined(IDA_WATER_SURFACE_PASS)
    float foam = sampleShoreFoam(worldPos, viewPos, viewPosBehind, baseWorldNormal,
                                opaqueUv, opaque, surfaceDepth, dpdx, dpdy, waves.height);
    if (foam > 0.0) {
        vec3 foamColor = shoreFoamRadiance(vanillaLight);
        surfaceColor = mix(surfaceColor, foamColor, foam);
        // Foam replaces reflection/refraction and reduces modeled transmission
        // by its coverage, before the shared atmosphere and layer resolve.
        transmission *= 1.0 - foam;
    }
#endif
    return surfaceColor;
}

vec3 drawIce(vec3 color, vec3 worldPos, vec3 viewPos, vec3 normal, float normalVariance, float viewVariance) {
    vec3 smoothNormal = normalize(normal);
    vec3 reflectDir = reflect(normalize(viewPos), smoothNormal);
    float viewCosine = clamp(abs(dot(normalize(viewPos), smoothNormal)), 0.0, 1.0);
    float fresnel = pow(1.0 - viewCosine, 2.4);
    float reflectivity = mix(0.16, 0.68, fresnel);
    vec3 worldNormal = viewToWorldNormal(smoothNormal, gbufferModelViewInverse);
    SmoothSurfaceReflectionProfile profile = getIceReflectionProfile(reflectivity);
    profile.highlightVariance = 4.0 * normalVariance + viewVariance + 0.00104976 * SPECULAR_AA;
    return resolveSmoothSurfaceColor(color, worldPos, viewPos, worldNormal, reflectDir, profile);
}

vec3 traceSubmergedReflection(vec3 viewPos, vec3 direction, vec3 waterNormalWorld) {
    vec3 surfaceWorld = viewToWorldPos(viewPos, gbufferModelViewInverse);
    // A missed underwater reflection sees the water volume, not the sky.
    vec3 fallback = waterScatterColor();
    for (int i = 0; i < 12; ++i) {
        float fraction = float(i + 1) / 12.0;
        float travel = 0.35 + 48.0 * fraction * fraction;
        vec3 candidate = viewPos + direction * travel;
        vec2 uv;
        vec4 opaque;
        if (!projectAndSampleOpaque(candidate, uv, opaque)) break;
        if (opaque.b >= 0.999999) continue;
        vec3 hit = reconstructOpaqueViewPos(uv, opaque);
        float crossing = hit.z - candidate.z;
        if (crossing < 0.0 || crossing >= max(0.25, travel * 0.12)) continue;
        vec3 hitWorld = viewToWorldPos(hit, gbufferModelViewInverse);
        if (dot(hitWorld - surfaceWorld, waterNormalWorld) > -0.15) {
            return applyUnderwaterMedium(texture2D(colortex9, uv).rgb, length(hit - viewPos));
        }
    }
    return fallback;
}

vec3 drawUnderwaterSurface(vec3 worldPos, vec3 viewPos, vec3 normal,
                           vec2 dpdx, vec2 dpdy, vec2 screenUv, float surfaceDepth, out float transmission) {
    vec3 incident = safeNormal(viewPos);
    vec3 baseWorldNormal = viewToWorldNormal(safeNormal(normal), gbufferModelViewInverse);
    // Keep side faces as side faces; only perturb near-horizontal water tops.
    vec3 outward = baseWorldNormal.y < 0.0 ? -baseWorldNormal : baseWorldNormal;
    WaterWaves waves = sampleWaterWaves(worldPos, dpdx, dpdy);
    vec3 waveNormal = waterWaveNormal(outward, waves.slope,
                         0.35 * smoothstep(0.70, 0.95, abs(outward.y)));
    vec3 n = safeNormal(mat3(gbufferModelView) * waveNormal);
    if (dot(n, incident) > 0.0) n = -n;
    vec3 inwardWorld = viewToWorldNormal(n, gbufferModelViewInverse);
    float fresnel = waterFresnel(-dot(incident, n), 1.333);
    vec3 reflected = traceSubmergedReflection(viewPos, reflect(incident, n), inwardWorld);
    transmission = (1.0 - fresnel) * 0.82;
    if (fresnel >= 0.99999) return reflected;

    vec3 transmitted = refract(incident, n, 1.333);
    vec3 transmittedWorld = viewToWorldNormal(transmitted, gbufferModelViewInverse);
    vec2 originalUv = opaqueUvForUnjitteredUv(screenUv);
    vec4 original = sampleOpaqueData(originalUv);
    vec3 originalBehind = reconstructOpaqueViewPos(originalUv, original);
    float travel = original.b >= 0.999999 ? 64.0 : clamp(length(originalBehind - viewPos), 1.0, 64.0);
    vec3 probe = viewPos + transmitted * travel;
    vec2 uv = probe.z < -near ? projectOpaqueViewPos(probe).xy : vec2(-1.0);
    bool sky = !isScreenUvInRange(uv);
    vec3 radiance = getSkyRadiance(transmitted);
    float airDistance = 900.0;
    if (!sky) {
        vec4 opaque = sampleOpaqueData(uv);
        if (opaque.b < surfaceDepth) {
            uv = originalUv;
            opaque = original;
        }
        sky = opaque.b >= 0.999999;
        vec3 behind = reconstructOpaqueViewPos(uv, opaque);
        vec3 behindWorld = viewToWorldPos(behind, gbufferModelViewInverse);
        // Never use a submerged foreground object as the air-side refraction.
        if (!sky && opaque.b >= surfaceDepth && dot(behindWorld - worldPos, inwardWorld) < 0.0) {
            radiance = texture2D(colortex9, uv).rgb;
            airDistance = length(behind - viewPos);
        } else {
            sky = true;
        }
    }
    radiance = applyAirSegment(radiance, cameraPosition + worldPos,
                              transmittedWorld, airDistance, sky);
    // The caller applies the camera-to-water segment exactly once.
    return mix(radiance, reflected, fresnel);
}
