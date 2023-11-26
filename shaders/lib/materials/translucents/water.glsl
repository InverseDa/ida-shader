#include "/lib/materials/methods/wavingBlock.glsl"

vec3 rayTrace(vec3 origin, vec3 dir) {
    vec3 currPoint = origin;
    int iterations = 20;
    for(int i = 0; i < iterations; i++) {
        currPoint += dir * 0.2;
        vec4 screenPos = gbufferProjection * vec4(currPoint, 1.0);
        screenPos /= screenPos.w;
        screenPos.xyz = screenPos.xyz * 0.5 + 0.5;
        if (screenPos.x < 0.0 || screenPos.x > 1.0 || screenPos.y < 0.0 || screenPos.y > 1.0) {
            return vec3(0.0);
        }
        float depth = texture2D(depthtex0, screenPos.st).x;
        if(depth < screenPos.z || i == iterations - 1) {
            return texture2D(colortex0, screenPos.st).rgb;
        }
    }
    return vec3(0.0);
}

vec3 drawSkyFakeSunInWater(vec4 viewPos) {
    float dis2Sun = 1.0 - dot(normalize(viewPos.xyz), normalize(sunPosition));
    float dis2Moon = 1.0 - dot(normalize(viewPos.xyz), normalize(moonPosition));
    // draw Sun
    vec3 drawSun = vec3(0.f);
    if (dis2Sun < 0.005) {
        drawSun = sunColor * 2 * (1.f - nightValue);
    }
    // draw Moon
    vec3 drawMoon = vec3(0.f);
    if (dis2Moon < 0.05) {
        drawMoon = sunColor * 2 * nightValue;
    }
    return drawSun + drawMoon;
}

vec3 drawSkyFakeReflect(vec4 viewPos) {
    float dis2Sun = 1.0 - dot(normalize(viewPos.xyz), normalize(sunPosition));     // 太阳
    float dis2Moon = 1.0 - dot(normalize(viewPos.xyz), normalize(moonPosition));    // 月亮

    float sunMixFactor = clamp(1.0 - dis2Sun, 0, 1) * (1.0 - nightValue);
    vec3 finalColor = mix(skyColor, sunColor, pow(sunMixFactor, 4));

    float moonMixFactor = clamp(1.0 - dis2Moon, 0, 1) * nightValue;
    finalColor = mix(finalColor, sunColor, pow(moonMixFactor, 4));

    return finalColor;
}

vec3 drawWater(vec3 color, vec4 worldPos, vec4 viewPos, vec3 normal) {
    worldPos.xyz += cameraPosition;
    float wave = GetWave(worldPos);
    
    vec3 normal2 = normal;
    normal2.z += 0.05 * (((wave - 0.4) / 0.6) * 2 - 1);
    normal2 = normalize(normal2);

    vec3 reflectDir = reflect(viewPos.xyz, normal2);

    vec3 finalColor = drawSkyFakeReflect(vec4(reflectDir, 0.0));
    finalColor *= wave;

    vec3 reflectColor = rayTrace(viewPos.xyz, reflectDir);
    if(length(reflectColor) > 0.0) {
        float fadeFactor = 1 - clamp(pow(abs(texcoord.x-0.5)*2, 2), 0, 1);
        finalColor = mix(finalColor, reflectColor, fadeFactor);
    }

    float cosine = dot(normalize(viewPos.xyz), normal); 
    cosine = clamp(abs(cosine), 0, 1);
    float factor = pow(1.0 - cosine, 4);
    finalColor = mix(color, finalColor, factor); 

    finalColor += drawSkyFakeSunInWater(vec4(reflectDir, 0.0));

    return finalColor;
}