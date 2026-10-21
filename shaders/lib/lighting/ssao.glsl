#ifndef IDA_LIGHTING_SSAO_GLSL
#define IDA_LIGHTING_SSAO_GLSL

float getSsaoSampleOcclusion(vec2 uv, vec3 centerViewPos, vec3 sampleViewPos, float radius, float bias) {
    if (sampleViewPos.z >= -near) return 0.0;
    vec3 screenPos = projectSceneViewPos(sampleViewPos);
    if (!isScreenUvInRange(screenPos.xy)) {
        return 0.0;
    }

    float sampleDepth = texture2D(depthtex1, screenPos.xy).x;
    if (sampleDepth >= 1.0) {
        return 0.0;
    }

    bool jittered = materialUsesTaaJitter(texture2D(colortex5, screenPos.xy));
    vec3 sceneViewPos = reconstructSurfaceViewPos(screenPos.xy, sampleDepth, jittered);
    float depthDelta = abs(centerViewPos.z - sceneViewPos.z);
    float rangeWeight = smoothstep(0.0, 1.0, radius / max(depthDelta, 0.0001));
    rangeWeight *= rangeWeight;
    return (sceneViewPos.z >= sampleViewPos.z + bias) ? rangeWeight : 0.0;
}

float getScreenSpaceAmbientOcclusion(vec2 uv, vec3 viewPos, vec3 normal) {
    vec3 n = normalize(normal);
    vec3 tangentSeed = abs(n.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
    vec3 tangent = tangentSeed - n * dot(tangentSeed, n);
    tangent = normalize(tangent);
    vec3 bitangent = normalize(cross(n, tangent));
    mat3 tbn = mat3(tangent, bitangent, n);

    float radius = clamp(-viewPos.z * 0.018, 0.30, 0.95);
    float bias = 0.075;
    float occlusion = 0.0;

    occlusion += getSsaoSampleOcclusion(uv, viewPos, viewPos + tbn * vec3( 0.54,  0.18, 0.32) * radius, radius, bias);
    occlusion += getSsaoSampleOcclusion(uv, viewPos, viewPos + tbn * vec3(-0.45,  0.36, 0.28) * radius, radius, bias);
    occlusion += getSsaoSampleOcclusion(uv, viewPos, viewPos + tbn * vec3( 0.22, -0.62, 0.42) * radius, radius, bias);
    occlusion += getSsaoSampleOcclusion(uv, viewPos, viewPos + tbn * vec3(-0.66, -0.24, 0.36) * radius, radius, bias);
    occlusion += getSsaoSampleOcclusion(uv, viewPos, viewPos + tbn * vec3( 0.78, -0.38, 0.58) * radius, radius, bias);
    occlusion += getSsaoSampleOcclusion(uv, viewPos, viewPos + tbn * vec3(-0.24,  0.82, 0.52) * radius, radius, bias);
    occlusion += getSsaoSampleOcclusion(uv, viewPos, viewPos + tbn * vec3( 0.38,  0.72, 0.78) * radius, radius, bias);
    occlusion += getSsaoSampleOcclusion(uv, viewPos, viewPos + tbn * vec3(-0.82, -0.56, 0.72) * radius, radius, bias);

    float ao = 1.0 - occlusion * 0.55 / 8.0;
    return clamp(pow(ao, 1.15), 0.0, 1.0);
}

#endif
