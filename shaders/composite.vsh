#version 130

#define SUNRISE 23200
#define SUNSET 12800
#define FADE_START 500
#define FADE_END 250

uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform int worldTime;

varying vec4 texcoord;
varying vec3 lightPosition;
varying vec3 skyColor;
varying vec3 sunColor;
varying float nightValue;
varying float extShadow;

vec3 skyColorArr[] = vec3[24](
    vec3(0.1, 0.6, 0.9),        // 0-1000
    vec3(0.1, 0.6, 0.9),        // 1000 - 2000
    vec3(0.1, 0.6, 0.9),        // 2000 - 3000
    vec3(0.1, 0.6, 0.9),        // 3000 - 4000
    vec3(0.1, 0.6, 0.9),        // 4000 - 5000 
    vec3(0.1, 0.6, 0.9),        // 5000 - 6000
    vec3(0.1, 0.6, 0.9),        // 6000 - 7000
    vec3(0.1, 0.6, 0.9),        // 7000 - 8000
    vec3(0.1, 0.6, 0.9),        // 8000 - 9000
    vec3(0.1, 0.6, 0.9),        // 9000 - 10000
    vec3(0.1, 0.6, 0.9),        // 10000 - 11000
    vec3(0.1, 0.6, 0.9),        // 11000 - 12000
    vec3(0.1, 0.6, 0.9),        // 12000 - 13000
    vec3(0.02, 0.2, 0.27),      // 13000 - 14000
    vec3(0.02, 0.2, 0.27),      // 14000 - 15000
    vec3(0.02, 0.2, 0.27),      // 15000 - 16000
    vec3(0.02, 0.2, 0.27),      // 16000 - 17000
    vec3(0.02, 0.2, 0.27),      // 17000 - 18000
    vec3(0.02, 0.2, 0.27),      // 18000 - 19000
    vec3(0.02, 0.2, 0.27),      // 19000 - 20000
    vec3(0.02, 0.2, 0.27),      // 20000 - 21000
    vec3(0.02, 0.2, 0.27),      // 21000 - 22000
    vec3(0.02, 0.2, 0.27),      // 22000 - 23000
    vec3(0.02, 0.2, 0.27)       // 23000 - 24000(0)
);

vec3 sunColorArr[] = vec3[24](
    vec3(2, 2, 1),      // 0-1000
    vec3(2, 1.5, 1),    // 1000 - 2000
    vec3(1, 1, 1),      // 2000 - 3000
    vec3(1, 1, 1),      // 3000 - 4000
    vec3(1, 1, 1),      // 4000 - 5000 
    vec3(1, 1, 1),      // 5000 - 6000
    vec3(1, 1, 1),      // 6000 - 7000
    vec3(1, 1, 1),      // 7000 - 8000
    vec3(1, 1, 1),      // 8000 - 9000
    vec3(1, 1, 1),      // 9000 - 10000
    vec3(1, 1, 1),      // 10000 - 11000
    vec3(1, 1, 1),      // 11000 - 12000
    vec3(2, 1.5, 0.5),      // 12000 - 13000
    vec3(0.3, 0.5, 0.9),      // 13000 - 14000
    vec3(0.3, 0.5, 0.9),      // 14000 - 15000
    vec3(0.3, 0.5, 0.9),      // 15000 - 16000
    vec3(0.3, 0.5, 0.9),      // 16000 - 17000
    vec3(0.3, 0.5, 0.9),      // 17000 - 18000
    vec3(0.3, 0.5, 0.9),      // 18000 - 19000
    vec3(0.3, 0.5, 0.9),      // 19000 - 20000
    vec3(0.3, 0.5, 0.9),      // 20000 - 21000
    vec3(0.3, 0.5, 0.9),      // 21000 - 22000
    vec3(0.3, 0.5, 0.9),      // 22000 - 23000
    vec3(0.3, 0.5, 0.9)       // 23000 - 24000(0)
);

void main() {
    gl_Position = ftransform();
    texcoord = gl_MultiTexCoord0;

    // 阴影昼夜交替
    if(worldTime >= SUNRISE - FADE_START && worldTime <= SUNRISE + FADE_START) {
        extShadow = 1.0;
        if(worldTime < SUNRISE - FADE_END) 
            extShadow -= float(SUNRISE - FADE_END - worldTime) / float(FADE_END); 
        else if(worldTime > SUNRISE + FADE_END)
            extShadow -= float(worldTime - SUNRISE - FADE_END) / float(FADE_END);
    } else if(worldTime >= SUNSET - FADE_START && worldTime <= SUNSET + FADE_START) {
        extShadow = 1.0;
        if(worldTime < SUNSET - FADE_END) 
            extShadow -= float(SUNSET - FADE_END - worldTime) / float(FADE_END); 
        else if(worldTime > SUNSET + FADE_END)
            extShadow -= float(worldTime - SUNSET - FADE_END) / float(FADE_END);
    } else{
        extShadow = 0.0;
    }
    if(worldTime < SUNSET || worldTime > SUNRISE)
        lightPosition = normalize(sunPosition);
    else
        lightPosition = normalize(moonPosition);
    
    // 颜色插值
    int hour = worldTime / 1000;
    int next = (hour + 1 < 24) ? hour + 1 : 0;
    float delta = float(worldTime - hour * 1000) / 1000.0;
    skyColor = mix(skyColorArr[hour], skyColorArr[next], delta);
    sunColor = mix(sunColorArr[hour], sunColorArr[next], delta);

    // 昼夜交替插值, 0.f表示白天, 1.f表示黑夜
    nightValue = 0.f;
    if (worldTime > 12000 && worldTime < 13000) {
        // 此时傍晚
        nightValue = 1.0 - (13000 - worldTime) / 1000.f; 
    } else if (worldTime >= 13000 && worldTime <= 23000) {
        // 此时夜晚
        nightValue = 1.f;
    } else if (worldTime > 23000 && worldTime < 24000) {
        // 此时凌晨
        nightValue = (24000 - worldTime) / 1000.f;
    }

}