#include "/lib/common.glsl"

// =====================================================================================
// ============================== Fragment Shader ======================================
// =====================================================================================
#ifdef FRAGMENT_SHADER
    // ===================== Shader Configuration =====================
    const int RG16 = 0;
    const int gnormalFormat = RG16;
    const bool shadowHardwareFiltering = true;
    const int shadowMapResolution = 2048;
    const int noiseTextureResolution = 256;
    // =================== End Shader Configuration ===================

    uniform mat4 gbufferProjection;
    uniform mat4 gbufferProjectionInverse;
    uniform mat4 gbufferModelViewInverse;
    uniform mat4 shadowModelView;
    uniform mat4 shadowProjection;
    uniform sampler2DShadow shadow;
    uniform sampler2D depthtex0;
    uniform sampler2D depthtex1;
    uniform sampler2D colortex0;
    uniform sampler2D gnormal;
    uniform sampler2D colortex4; // blockId texture
    uniform vec3 sunPosition;
    uniform vec3 moonPosition;
    uniform vec3 cameraPosition;
    uniform float viewWidth;
    uniform float viewHeight;
    uniform float far;
    uniform float near;

    varying vec4 texcoord;
    varying vec3 skyColor;
    varying vec3 sunColor;
    varying vec3 lightPosition;
    varying float nightValue;
    varying float extShadow;

    vec3 normalDecode(vec2 enc) {
        vec4 nn = vec4(2.0 * enc - 1.0, 1.0, -1.0);
        float l = dot(nn.xyz,-nn.xyw);
        nn.z = l;
        nn.xy *= sqrt(l);
        return nn.xyz * 2.0 + vec3(0.0, 0.0, -1.0);
    }

    // ========================== Draw Shadow ==========================
    vec4 getWorldPositionShadow(vec3 normal, float depth) {
        vec4 viewPos = gbufferProjectionInverse * vec4(texcoord.x * 2.0 - 1.0, texcoord.y * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
        viewPos /= viewPos.w;
        vec4 worldPos = gbufferModelViewInverse * (viewPos + vec4(normal * 0.05 * sqrt(abs(viewPos.z)), 0.0));
        return worldPos;
    }

    float shadowMapping(vec4 positionInWorld, float dist, vec3 normal) {
        // dist > 0.9, dont render sky's shadow
        if(dist > 0.9) { 
            return extShadow;
        }

        float shade = 0.0;
        // the angle bettween normal and light
        float cosine = dot(lightPosition, normal);

        if(cosine <= 0.1) {
            shade = 1.0;
        } else {
            vec4 positionInSunNDC = shadowProjection * shadowModelView * positionInWorld;
            float distb = sqrt(positionInSunNDC.x * positionInSunNDC.x + positionInSunNDC.y * positionInSunNDC.y);
            float distortFactor = (1.0 - SHADOW_MAP_BIAS) + distb * SHADOW_MAP_BIAS;
            positionInSunNDC.xy /= distortFactor;
            positionInSunNDC /= positionInSunNDC.w;
            positionInSunNDC = positionInSunNDC * 0.5 + 0.5;
            shade = 1.0 - shadow2D(shadow, vec3(positionInSunNDC.st, positionInSunNDC.z - 0.0001)).z;
            if(cosine < 0.2)  // if light parallel normal (nearly)
                shade = max(shade, 1.0 - (cosine - 0.1) * 10.0);
        }
        shade -= clamp((dist - 0.7) * 5.0, 0.0, 1.0); 
        shade = clamp(shade, 0.0, 1.0);
        return max(shade, extShadow);
    }

    float calcShadow(vec3 normal, float depth) {
        vec4 worldPos = getWorldPositionShadow(normal, depth);
        float dist = length(worldPos.xyz / far);
        float shade = shadowMapping(worldPos, dist, normal);
        return (1.0 - shade * 0.35);
    }

    // ========================== Draw Sky ==========================
    vec3 drawSky(vec3 color, vec4 viewPos, vec4 worldPos) {
        float dis = length(worldPos.xyz) / far;
        float dis2Sun = 1.0 - dot(normalize(viewPos.xyz), normalize(sunPosition));
        float dis2Moon = 1.0 - dot(normalize(viewPos.xyz), normalize(moonPosition));
        // draw Sun
        vec3 drawSun = vec3(0.f);
        if(dis2Sun < 0.005 && dis > 0.99999) {
            drawSun = sunColor * 2 * (1.f - nightValue);
        }
        // draw Moon
        vec3 drawMoon = vec3(0.f);
        if(dis2Moon < 0.05 && dis > 0.99999) {
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

    // ========================== Draw Water ==========================


    // ============================== MAIN ==============================
    /* DRAWBUFFERS:0 */
    void main() {
        // near <= positionInWorld.z
        // depth0 include water and sky
        // depth1 not include water and sky
        float depth0 = texture2D(depthtex0, texcoord.st).x;
        float depth1 = texture2D(depthtex1, texcoord.st).x;
        vec4 clipPos = gbufferProjectionInverse * vec4(texcoord.st * 2 - 1, depth0 * 2 - 1, 1);
        vec4 viewPos = clipPos / clipPos.w;
        vec4 worldPos = gbufferModelViewInverse * viewPos;

        vec4 color = texture2D(colortex0, texcoord.st);
        vec3 normal = normalDecode(texture2D(gnormal, texcoord.st).rg);

        // calculate shadow
        color.rgb *= calcShadow(normal, depth0);
        // draw sky
        color.rgb = drawSky(color.rgb, viewPos, worldPos);
        // TODO draw water

        gl_FragData[0] = color;
    }
#endif

// =====================================================================================
// ============================== Fragment Shader ======================================
// =====================================================================================
#ifdef VERTEX_SHADER
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
#endif