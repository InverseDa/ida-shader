vec3 drawSky(vec3 color, vec4 viewPos, vec4 worldPos) {
    float dis = length(worldPos.xyz) / far;
    float dis2Sun = 1.0 - dot(normalize(viewPos.xyz), normalize(sunPosition));
    float dis2Moon = 1.0 - dot(normalize(viewPos.xyz), normalize(moonPosition));
    // draw Sun
    vec3 drawSun = vec3(0.f);
    if (dis2Sun < 0.005 && dis > 0.99999) {
        drawSun = sunColor * 2 * (1.f - nightValue);
    }
    // draw Moon
    vec3 drawMoon = vec3(0.f);
    if (dis2Moon < 0.005 && dis > 0.99999) {
        drawMoon = sunColor * 2 * nightValue;
    }
    // fog with sun color mix
    float sunMixFactor = clamp(1.0 - dis2Sun, 0, 1) * (1.f - nightValue);
    vec3 finalColor = mix(skyColor, sunColor, pow(sunMixFactor, 4));
    // fog with moon color mix
    float moonMixFactor = clamp(1.0 - dis2Moon, 0, 1) * nightValue;
    finalColor = mix(finalColor, sunColor, pow(moonMixFactor, 4));

    return mix(color, finalColor, clamp(pow(dis, 3), 0, 1)) + drawSun + drawMoon;
}