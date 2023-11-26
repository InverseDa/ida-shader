float UnderWaterFadeOut(float d0, float d1, vec4 viewPos, vec3 normal) {
    d0 = screenDepthToLinerDepth(near, far, d0);
    d1 = screenDepthToLinerDepth(near, far, d1);

    float cosine = dot(normalize(viewPos.xyz), normalize(normal));
    cosine = clamp(abs(cosine), 0, 1);

    return clamp(1.0 - (d1 - d0) * cosine * 0.1, 0, 1);
}

float shadowMapping(vec4 worldPos, vec3 normal, float strength) {
    vec4 positionInSunNDC = shadowProjection * shadowModelView * worldPos;
    positionInSunNDC /= positionInSunNDC.w;
    // fish eye distortion
    positionInSunNDC.xy = getFishEyeCoord(positionInSunNDC.xy);
    positionInSunNDC = positionInSunNDC * 0.5 + 0.5; // screen space [0, 1]
    
    float currentDepth = positionInSunNDC.z;
    float dis = length(worldPos.xyz) / far;
    float shadowStrength = strength * 0.6 * (1 - dis) * (1 - 0.6 * nightValue); // 控制昼夜阴影强度

    int radius = 1;
    float shade = pow(radius * 2 + 1, 2);
    for(int x = -radius; x <= radius; x++) {
        for(int y = -radius; y <= radius; y++) {
            vec2 offset = vec2(x, y) / shadowMapResolution;
            float closest = texture2D(shadowtex1, positionInSunNDC.xy + offset).x;
            if (closest + 0.001 <= currentDepth && dis < 0.99) {
                shade -= 1.0;
            }
        }
    }
    shade /= pow(radius * 2 + 1, 2);
    
    return shade * shadowStrength + (1 - shadowStrength);
}