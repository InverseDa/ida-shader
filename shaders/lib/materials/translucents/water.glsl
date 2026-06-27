#include "/lib/materials/methods/wavingBlock.glsl"
#include "/lib/materials/translucents/surfaceReflection.glsl"

float sampleWaterWave(vec3 waveWorldPos) {
    return GetWave(vec4(waveWorldPos, 1.0));
}

float getGerstnerPhase(vec2 position, vec2 direction, float wavelength, float speedScale, float phaseOffset) {
    float k = 6.2831853 / wavelength;
    float omega = sqrt(9.81 * k) * speedScale;
    return k * dot(normalize(direction), position) - omega * frameTimeCounter + phaseOffset;
}

void addGerstnerSlope(
    vec2 position,
    vec2 direction,
    float wavelength,
    float amplitude,
    float speedScale,
    float phaseOffset,
    inout float height,
    inout vec2 slope
) {
    vec2 waveDir = normalize(direction);
    float phase = getGerstnerPhase(position, waveDir, wavelength, speedScale, phaseOffset);
    float k = 6.2831853 / wavelength;
    height += amplitude * sin(phase);
    slope += waveDir * (amplitude * k * cos(phase));
}

void buildOceanWaveProfile(vec3 waveWorldPos, float detailScale, out float height, out vec2 slope) {
    vec2 p = waveWorldPos.xz;
    height = 0.0;
    slope = vec2(0.0);

    addGerstnerSlope(p, vec2( 0.86,  0.50), 20.0, 0.170, 0.70, 0.00, height, slope);
    addGerstnerSlope(p, vec2( 0.42,  0.91), 10.5, 0.085, 0.90, 1.70, height, slope);
    addGerstnerSlope(p, vec2(-0.28,  0.96),  6.2, 0.043, 1.16, 3.10, height, slope);

    if (detailScale > 0.5) {
        addGerstnerSlope(p, vec2( 0.97, -0.24), 3.1, 0.017, 1.48, 4.40, height, slope);
        addGerstnerSlope(p, vec2(-0.71,  0.70), 1.9, 0.010, 1.82, 2.30, height, slope);
        float microWave = sampleWaterWave(waveWorldPos * vec3(1.8, 1.0, 1.8)) - 0.5;
        slope += vec2(microWave, -microWave) * 0.026;
    }
}

vec3 buildWaterWaveWorldNormal(
    vec3 worldPos,
    vec3 baseWorldNormal,
    float sampleRadius,
    float normalStrength,
    out float wave,
    out float waveSlope
) {
    vec3 waveWorldPos = worldPos + cameraPosition;
    float height;
    vec2 slope;
    buildOceanWaveProfile(waveWorldPos, 1.0 / max(sampleRadius, 0.001), height, slope);

    vec3 waveNormalWorld = normalize(vec3(-slope.x, 1.0, -slope.y));
    wave = clamp(0.5 + height * 2.65, 0.0, 1.0);
    waveSlope = clamp(length(slope) * 3.35, 0.0, 1.0);
    return normalize(mix(baseWorldNormal, waveNormalWorld, normalStrength));
}

float getWaterThickness(vec3 viewPos, vec3 viewPosBehind) {
    float waterDepth = max(length(viewPosBehind) - length(viewPos), 0.0);
    return clamp(waterDepth, 0.0, 34.0);
}

vec3 sampleRefractedSceneColor(vec3 normalView, float waterDepth, float waveSlope) {
    float refractionStrength = (0.007 + 0.025 * waveSlope) * (1.0 - exp(-waterDepth * 0.18));
    vec2 distortion = normalView.xy * refractionStrength;
    vec2 uv = clamp(texcoord.st + distortion, vec2(0.001), vec2(0.999));
    vec3 centerColor = texture2D(colortex0, uv).rgb;
    vec2 texel = vec2(1.0 / viewWidth, 1.0 / viewHeight);
    centerColor += texture2D(colortex0, uv + vec2(texel.x, 0.0)).rgb * 0.18;
    centerColor += texture2D(colortex0, uv - vec2(texel.x, 0.0)).rgb * 0.18;
    return centerColor / 1.36;
}

vec3 applyWaterVolume(vec3 sceneColor, vec3 baseWaterColor, float waterDepth, float viewCosine) {
    vec3 shallowTint = vec3(0.50, 0.82, 0.82);
    vec3 deepTint = vec3(0.015, 0.155, 0.245);
    vec3 absorption = vec3(0.20, 0.070, 0.030);
    float depthCurve = smoothstep(1.5, 22.0, waterDepth);
    float grazingDensity = mix(1.28, 0.88, viewCosine);
    vec3 transmittance = exp(-absorption * waterDepth * grazingDensity);
    vec3 volumeTint = mix(shallowTint, deepTint, depthCurve);
    float scatter = 1.0 - dot(transmittance, vec3(0.3333));
    vec3 refracted = sceneColor * transmittance + volumeTint * scatter * 0.86;
    return mix(refracted, baseWaterColor * volumeTint, 0.10 + depthCurve * 0.18);
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

vec3 getWaterSunSparkle(
    vec3 worldPos,
    vec3 viewPos,
    vec3 sparkleNormalView,
    float waveSlope,
    float waterDepth,
    float fresnel
) {
    vec3 lightDir = normalize(sunPosition);
    vec3 viewDir = normalize(-viewPos);
    vec3 halfDir = normalize(lightDir + viewDir);
    vec3 reflectedView = normalize(reflect(normalize(viewPos), sparkleNormalView));

    float daylight = 1.0 - nightValue;
    float reflectionAlignment = clamp(dot(reflectedView, lightDir), 0.0, 1.0);
    float sunWindow = smoothstep(0.44, 0.925, reflectionAlignment);
    float broadSun = pow(reflectionAlignment, 30.0);
    float sharpSun = pow(reflectionAlignment, mix(82.0, 160.0, clamp(waveSlope, 0.0, 1.0)));
    float microFacet = pow(clamp(dot(sparkleNormalView, halfDir), 0.0, 1.0), 90.0);

    float depthFade = smoothstep(0.06, 1.45, waterDepth);
    float slopeFade = smoothstep(0.06, 0.62, waveSlope);
    float grazing = mix(0.55, 1.55, clamp(fresnel, 0.0, 1.0));
    float shimmer = mix(0.82, 1.22, slopeFade);
    float sparkle = daylight * depthFade * grazing;
    sparkle *= broadSun * 0.78 + sharpSun * 2.15 + microFacet * 0.72;
    sparkle *= sunWindow;
    sparkle *= shimmer;

    vec3 warmSun = mix(vec3(1.0, 0.86, 0.56), sunColor, 0.45);
    return warmSun * sparkle * 18.0;
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

vec3 drawWater(vec3 color, vec3 worldPos, vec3 viewPos, vec3 viewPosBehind, vec3 normal) {
    vec3 baseWorldNormal = viewToWorldNormal(normalize(normal), gbufferModelViewInverse);
    float wave;
    float waveSlope;
    vec3 worldWaveNormal = buildWaterWaveWorldNormal(
        worldPos,
        baseWorldNormal,
        0.65,
        0.88,
        wave,
        waveSlope
    );
    float reflectionWave;
    float reflectionSlope;
    vec3 worldReflectionNormal = buildWaterWaveWorldNormal(
        worldPos,
        baseWorldNormal,
        3.20,
        0.24,
        reflectionWave,
        reflectionSlope
    );
    vec3 worldNormal = normalize(mix(worldReflectionNormal, worldWaveNormal, 0.34));
    vec3 reflectionNormal = normalize(mix(baseWorldNormal, worldReflectionNormal, 0.94));
    vec3 normal2 = normalize(mat3(gbufferModelView) * reflectionNormal);
    vec3 sparkleNormal = normalize(mat3(gbufferModelView) * normalize(mix(worldReflectionNormal, worldWaveNormal, 0.62)));

    vec3 reflectDir = reflect(normalize(viewPos), normal2);
    float viewCosine = clamp(abs(dot(normalize(viewPos), normal2)), 0.0, 1.0);
    float fresnel = pow(1.0 - viewCosine, 2.35);
    float reflectivity = mix(0.30, 0.96, fresnel) * mix(1.02, 1.10, wave);
    float waterDepth = getWaterThickness(viewPos, viewPosBehind);
    vec3 refractedScene = sampleRefractedSceneColor(normal2, waterDepth, mix(waveSlope, reflectionSlope, 0.25));
    vec3 waterBaseColor = mix(color, vec3(0.06, 0.32, 0.42), 0.52);
    vec3 absorbedBaseColor = applyWaterVolume(refractedScene, waterBaseColor, waterDepth, viewCosine);
    SmoothSurfaceReflectionProfile profile = getWaterReflectionProfile(
        reflectivity,
        wave,
        mix(waveSlope, reflectionSlope, 0.2)
    );
    vec3 surfaceColor = resolveSmoothSurfaceColor(absorbedBaseColor, worldPos, viewPos, reflectionNormal, reflectDir, profile);
    surfaceColor += getWaterSunSparkle(
        worldPos,
        viewPos,
        sparkleNormal,
        max(waveSlope, reflectionSlope),
        waterDepth,
        fresnel
    );
    return surfaceColor;
}

vec3 drawIce(vec3 color, vec3 worldPos, vec3 viewPos, vec3 normal) {
    vec3 smoothNormal = normalize(normal);
    vec3 reflectDir = reflect(normalize(viewPos), smoothNormal);
    float viewCosine = clamp(abs(dot(normalize(viewPos), smoothNormal)), 0.0, 1.0);
    float fresnel = pow(1.0 - viewCosine, 2.4);
    float reflectivity = mix(0.16, 0.68, fresnel);
    vec3 worldNormal = viewToWorldNormal(smoothNormal, gbufferModelViewInverse);
    SmoothSurfaceReflectionProfile profile = getIceReflectionProfile(reflectivity);
    return resolveSmoothSurfaceColor(color, worldPos, viewPos, worldNormal, reflectDir, profile);
}
