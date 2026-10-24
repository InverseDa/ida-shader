#ifndef IDA_MISC_ATMOSPHERE_GLSL
#define IDA_MISC_ATMOSPHERE_GLSL

#include "/lib/misc/cloud_density.glsl"
#include "/lib/lighting/daylight.glsl"

float getCloudShadow(float height, float lightHeight, float coverage) {
    // Local-column approximation: reuse this sample's coverage and integrate
    // the vertical profile analytically, instead of another 1-3 noise reads.
    float opticalDepth = coverage * CLOUD_EXTINCTION * cloudColumnLengthAbove(height);
    float direct = exp(-opticalDepth / max(lightHeight, 0.16));
    float scattered = exp(-opticalDepth * 0.25);
    return direct * 0.75 + scattered * 0.25;
}

vec2 cloudRayInterval(vec3 originWorld, vec3 rayDir, float maxDistance) {
    float t0 = 0.0;
    float t1 = min(maxDistance, CLOUD_MAX_DISTANCE);
    if (abs(rayDir.y) < 0.000001) {
        if (originWorld.y < CLOUD_BOTTOM || originWorld.y > CLOUD_TOP) return vec2(0.0);
    } else {
        t0 = (CLOUD_BOTTOM - originWorld.y) / rayDir.y;
        t1 = (CLOUD_TOP - originWorld.y) / rayDir.y;
    }
    float startDistance = max(min(t0, t1), 0.0);
    float endDistance = min(max(t0, t1), min(maxDistance, CLOUD_MAX_DISTANCE));
    return vec2(startDistance, max(startDistance, endDistance));
}

float cloudDistanceWeight(float distance) {
    return 1.0 - smoothstep(CLOUD_FADE_START, CLOUD_MAX_DISTANCE, distance);
}

float cloudSamplePhase(vec2 pixel) {
    // Spatially distributed strata remove the visible stack of 12 planes.
    // Deliberately no frame index: a stationary view must not boil each frame.
    return 0.15 + 0.70 * fract(52.9829189 * fract(dot(pixel, vec2(0.06711056, 0.00583715))));
}

vec4 renderVolumetricClouds(vec3 originWorld, vec3 rayDir, float maxDistance, bool needColor) {
    vec2 interval = cloudRayInterval(originWorld, rayDir, maxDistance);
    float travel = interval.y - interval.x;
    if (travel <= 0.0) return vec4(0.0);

    vec3 lightDir = vec3(0.0);
    vec3 cloudLight = vec3(0.0);
    vec3 ambient = vec3(0.0);
    if (needColor) {
        lightDir = viewToWorldNormal(normalize(shadowLightPosition), gbufferModelViewInverse);
        float sunFacing = clamp(dot(rayDir, lightDir), 0.0, 1.0);
        cloudLight = getDirectionalLightRadiance(sunColor, nightValue) *
                     directionalHeightStrength(lightDir.y, nightValue) * weatherDirectFactor(rainStrength);
        cloudLight *= 0.80 + 0.45 * pow(sunFacing, 4.0);
        float skyLuma = dot(skyColor, vec3(0.2126, 0.7152, 0.0722));
        ambient = mix(vec3(skyLuma), skyColor, 0.35) * mix(0.65, 0.40, nightValue) *
                  mix(1.0, 0.75, rainStrength);
    }
    vec3 accumulated = vec3(0.0);
    float alpha = 0.0;
    float stepLength = travel / 12.0;
    // Filter frequencies unresolved by the march or the screen pixel. Explicit
    // world footprints also work in forward / transmission-only branches.
    float pixelAngle = 2.0 / max(abs(gbufferProjection[1][1]) * viewHeight, 1.0);
    float phase = cloudSamplePhase(gl_FragCoord.xy);
    float previousColumn = cloudColumnLengthAbove(originWorld.y + rayDir.y * interval.x);

    for (int i = 0; i < 12; ++i) {
        if (alpha >= 0.995) break;
        float stepValue = (float(i) + phase) / 12.0;
        float t = interval.x + travel * stepValue;
        vec3 absolutePos = originWorld + rayDir * t;
        float nextHeight = originWorld.y + rayDir.y * (interval.x + float(i + 1) * stepLength);
        float nextColumn = cloudColumnLengthAbove(nextHeight);
        float heightDensity = getCloudHeightDensity(absolutePos.y);
        // Exact vertical-envelope integral over the stratum. Moving the sample
        // within it must not make a thin cloud entry gain/lose optical thickness.
        if (abs(rayDir.y) > 0.000001)
            heightDensity = clamp(abs(nextColumn - previousColumn) / max(stepLength * abs(rayDir.y), 0.000001), 0.0, 1.0);
        previousColumn = nextColumn;
        vec2 footprint = max(stepLength * vec2(length(rayDir.xz), abs(rayDir.y)), vec2(t * pixelAngle));
        float coverage = getCloudCoverageAtHeight(absolutePos, footprint);
        float density = coverage * heightDensity * cloudDistanceWeight(t);
        if (density > 0.0) {
            float stepAlpha = (1.0 - exp(-density * CLOUD_EXTINCTION * stepLength)) * (1.0 - alpha);
            // Emissive overlays only need transmission, not lit cloud color.
            if (needColor) {
                float lightVisibility = getCloudShadow(absolutePos.y, lightDir.y, coverage);
                accumulated += (ambient + cloudLight * lightVisibility) * stepAlpha;
            }
            alpha += stepAlpha;
        }
    }

    vec3 cloudColor = accumulated / max(alpha, 0.0001);
    return vec4(cloudColor, clamp(alpha, 0.0, 1.0));
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
    float maxDistance = isSkySurface ? CLOUD_MAX_DISTANCE : max(distance, 0.0);
    vec3 airColor = getSkyRadiance(normalize(mat3(gbufferModelView) * rayDir));
    airColor = mix(airColor, vec3(0.52, 0.58, 0.62), rainStrength * 0.42);
    vec3 fogged = mix(color, airColor, airFogAmount(distance, originWorld.y, rayDir, isSkySurface));
    // Most geometry is below the cloud slab. Do not enter the ray marcher
    // when the entire camera-to-surface segment is below or above it.
    float endHeight = originWorld.y + rayDir.y * maxDistance;
    if (max(originWorld.y, endHeight) < CLOUD_BOTTOM ||
        min(originWorld.y, endHeight) > CLOUD_TOP) return fogged;
    vec4 clouds = renderVolumetricClouds(originWorld, rayDir, maxDistance, true);
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
    if (max(cameraPosition.y, endHeight) >= CLOUD_BOTTOM && min(cameraPosition.y, endHeight) <= CLOUD_TOP)
        transmission *= 1.0 - renderVolumetricClouds(cameraPosition, rayDir, length(viewPos), false).a;
    return vec3(transmission);
}

#endif
