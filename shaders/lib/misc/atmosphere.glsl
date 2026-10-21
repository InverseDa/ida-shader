#ifndef IDA_MISC_ATMOSPHERE_GLSL
#define IDA_MISC_ATMOSPHERE_GLSL

float sampleAtmosphereNoise(vec2 uv) {
    return texture2D(noisetex, fract(uv)).r;
}

float getCloudLayerDensity(vec3 absolutePos) {
    float bottomFade = smoothstep(168.0, 196.0, absolutePos.y);
    float topFade = 1.0 - smoothstep(248.0, 286.0, absolutePos.y);
    if (bottomFade * topFade <= 0.0) return 0.0;
    vec2 wind = vec2(frameTimeCounter * 0.0035, frameTimeCounter * 0.0016);
    vec2 baseUv = absolutePos.xz * 0.00072 + wind;
    float base = sampleAtmosphereNoise(baseUv);
    // Noise is normalized [0,1]. Skip remaining octaves when even their
    // maximum contribution cannot reach the cloud coverage threshold.
    if (base * 0.62 + 0.38 <= 0.54) return 0.0;
    float detail = sampleAtmosphereNoise(absolutePos.xz * 0.0028 - wind * 1.7);
    if (base * 0.62 + detail * 0.28 + 0.10 <= 0.54) return 0.0;
    float wisps = sampleAtmosphereNoise(absolutePos.xz * 0.0080 + wind * 3.2);
    float cloudShape = base * 0.62 + detail * 0.28 + wisps * 0.10;

    float horizonBreakup = smoothstep(0.54, 0.88, cloudShape);
    return clamp(horizonBreakup * bottomFade * topFade, 0.0, 1.0);
}

float getCloudShadow(vec3 absolutePos, vec3 lightDir) {
    float upper = getCloudLayerDensity(absolutePos + lightDir * 26.0 + vec3(0.0, 12.0, 0.0));
    return mix(1.0, 0.58, upper);
}

vec4 renderVolumetricClouds(vec3 originWorld, vec3 rayDir, float maxDistance, bool needColor) {
    float lowerHeight = 168.0;
    float upperHeight = 286.0;
    float t0 = 0.0;
    float t1 = maxDistance;
    if (abs(rayDir.y) < 0.0001) {
        if (originWorld.y < lowerHeight || originWorld.y > upperHeight) return vec4(0.0);
    } else {
        t0 = (lowerHeight - originWorld.y) / rayDir.y;
        t1 = (upperHeight - originWorld.y) / rayDir.y;
    }
    float startDistance = max(min(t0, t1), 0.0);
    float endDistance = min(max(t0, t1), maxDistance);
    if (endDistance <= startDistance) {
        return vec4(0.0);
    }

    vec3 lightDir = vec3(0.0);
    vec3 cloudLight = vec3(0.0);
    vec3 ambient = vec3(0.0);
    if (needColor) {
        lightDir = viewToWorldNormal(normalize(shadowLightPosition), gbufferModelViewInverse);
        float sunFacing = clamp(dot(rayDir, lightDir) * 0.5 + 0.5, 0.0, 1.0);
        cloudLight = mix(vec3(0.18, 0.24, 0.36), sunColor, 1.0 - nightValue) *
                     mix(0.24, 0.92, sunFacing * sunFacing);
        ambient = skyColor * mix(0.34, 0.58, 1.0 - nightValue);
    }
    vec3 accumulated = vec3(0.0);
    float alpha = 0.0;
    float travel = endDistance - startDistance;

    for (int i = 0; i < 12; i++) {
        if (alpha >= 0.995) break;
        float stepValue = (float(i) + 0.5) / 12.0;
        float t = startDistance + travel * stepValue;
        vec3 absolutePos = originWorld + rayDir * t;
        float density = getCloudLayerDensity(absolutePos);
        if (density > 0.001) {
            float stepAlpha = (1.0 - exp(-density * 0.006 * travel / 12.0)) * (1.0 - alpha);
            // Emissive overlays only need transmission, not lit cloud color.
            if (needColor) {
                float lightVisibility = getCloudShadow(absolutePos, lightDir);
                accumulated += (ambient + cloudLight * lightVisibility) * stepAlpha;
            }
            alpha += stepAlpha;
        }
    }

    vec3 cloudColor = accumulated / max(alpha, 0.0001);
    float edgeFade = smoothstep(0.0, 8.0, travel);
    return vec4(cloudColor, clamp(alpha * edgeFade, 0.0, 1.0));
}

float airFogAmount(float distance, float originHeight, vec3 rayDir, bool isSkySurface) {
    float rainFog = 1.0 + rainStrength * 2.15;
    float nightFog = mix(1.0, 1.32, nightValue);
    float heightFog = mix(1.24, 0.76, smoothstep(70.0, 130.0, originHeight));
    float fogDensity = 0.00082 * rainFog * nightFog * heightFog;
    float fogAmount = isSkySurface ? smoothstep(0.02, 0.26, 1.0 - max(rayDir.y, 0.0)) * 0.028
                                   : 1.0 - exp(-distance * fogDensity);

    return clamp(fogAmount, 0.0, 0.86);
}

vec3 applyAirSegment(vec3 color, vec3 originWorld, vec3 rayDir, float distance, bool isSkySurface) {
    float maxDistance = isSkySurface ? 900.0 : max(distance, 0.0);
    vec3 airColor = getSkyRadiance(normalize(mat3(gbufferModelView) * rayDir));
    airColor = mix(airColor, vec3(0.52, 0.58, 0.62), rainStrength * 0.42);
    vec3 fogged = mix(color, airColor, airFogAmount(distance, originWorld.y, rayDir, isSkySurface));
    // Most geometry is below the cloud slab. Do not enter the ray marcher
    // when the entire camera-to-surface segment is below or above it.
    float endHeight = originWorld.y + rayDir.y * maxDistance;
    if (max(originWorld.y, endHeight) < 168.0 ||
        min(originWorld.y, endHeight) > 286.0) return fogged;
    vec4 clouds = renderVolumetricClouds(originWorld, rayDir, maxDistance, true);
    if (isSkySurface) {
        clouds.a *= 0.32;
    }
    return mix(fogged, clouds.rgb, clouds.a);
}

vec3 applyAtmosphere(vec3 color, vec3 viewPos, bool isSkySurface) {
    if (isEyeInWater == 1) return applyUnderwaterMedium(color, length(viewPos));
    vec3 rayDir = safeNormal(viewToWorldNormal(safeNormal(viewPos), gbufferModelViewInverse));
    return applyAirSegment(color, cameraPosition, rayDir, length(viewPos), isSkySurface);
}

// Additive light is attenuated; adding in-scattering would paint fog over the
// background a second time. Used by eyes, glint and other additive overlays.
vec3 cameraMediumTransmittance(vec3 viewPos) {
    if (isEyeInWater == 1) return waterTransmittance(length(viewPos));
    vec3 rayDir = safeNormal(viewToWorldNormal(safeNormal(viewPos), gbufferModelViewInverse));
    float transmission = 1.0 - airFogAmount(length(viewPos), cameraPosition.y, rayDir, false);
    float endHeight = cameraPosition.y + rayDir.y * length(viewPos);
    if (max(cameraPosition.y, endHeight) >= 168.0 && min(cameraPosition.y, endHeight) <= 286.0)
        transmission *= 1.0 - renderVolumetricClouds(cameraPosition, rayDir, length(viewPos), false).a;
    return vec3(transmission);
}

#endif
