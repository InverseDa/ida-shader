#version 430

// ---- Deferred10 ----

#include "/lib/constant.glsl"
#include "/lib/util/functions.glsl"
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;
uniform sampler2DShadow shadowtex1;
uniform sampler2D noisetex;
uniform vec3 cameraPosition;
uniform vec3 sunPosition;
uniform float viewWidth;
uniform float viewHeight;
uniform float far;
uniform float frameTimeCounter;
uniform float rainStrength;
uniform int frameCounter;
#include "/lib/misc/water_medium.glsl"
vec3 SunColor;
float NightValue;
vec2 AtmospherePixel;
#define IDA_ATMOSPHERE_PIXEL AtmospherePixel
#if VOLUMETRIC_LIGHT_CACHE == 1 && (VOLUMETRIC_LIGHT == 1 || UNDERWATER_LIGHT == 1)
#define IDA_VOLUME_CACHE_WRITE
#endif
#include "/lib/misc/cloud_density.glsl"
#include "/lib/lighting/daylight.glsl"
#include "/lib/misc/godrays.glsl"
#include "/lib/misc/water_lighting.glsl"

layout(local_size_x = 8, local_size_y = 8) in;
const ivec3 workGroups = ivec3(128, 128, 1);

void main()
{
#if VOLUMETRIC_LIGHT_CACHE == 1 && (VOLUMETRIC_LIGHT == 1 || UNDERWATER_LIGHT == 1)
    bool bWater = isEyeInWater == 1;
    ivec2 Size = bWater ? WaterShaftCacheSize() : SunShaftCacheSize();
    ivec2 Pixel = ivec2(gl_GlobalInvocationID.xy);

    if (any(greaterThanEqual(Pixel, Size)))
    {
        return;
    }

    int Time = worldTime - (worldTime / 24000) * 24000;
    int Hour = Time / 1000;
    SunColor = SrgbToLinear(mix(SunColorArr[Hour], SunColorArr[(Hour + 1) % 24], float(Time % 1000) / 1000.0));
    NightValue = clamp((float(Time) - 12000.0) / 1000.0, 0.0, 1.0) *
                 (1.0 - clamp((float(Time) - 23000.0) / 1000.0, 0.0, 1.0));
    vec3 LightDir = ViewToWorldNormal(normalize(sunPosition), gbufferModelViewInverse);
    float Source = (1.0 - smoothstep(0.0, 1.0, NightValue)) * smoothstep(0.04, 0.16, LightDir.y) *
                   (1.0 - smoothstep(0.0, 1.0, rainStrength)) *
                   (1.0 - smoothstep(CloudBottom - 24.0, CloudBottom, cameraPosition.y));
    bool bActive = isEyeInWater == 0 && Source > 0.0 && VOLUMETRIC_LIGHT_STRENGTH > 0.0 && far > 0.05;
    bActive = bActive && VOLUMETRIC_LIGHT == 1;

    if (bWater)
    {
        bActive = UNDERWATER_LIGHT == 1 && UNDERWATER_LIGHT_STRENGTH > 0.0 &&
                  NightValue < 1.0 && rainStrength < 1.0 && LightDir.y > 0.04;
    }

    // Iris inserts an SSBO barrier after this compute dispatch and before the
    // same-name fullscreen pass. No in-dispatch reader consumes this header.
    if (all(equal(Pixel, ivec2(0))))
    {
        SunShaftVolumeHeader = uvec4(uint(frameCounter) + 1u, uvec2(Size),
                                     (bWater ? WaterShaftCacheTag : 0u) | (bActive ? uint(VOLUMETRIC_LIGHT_SAMPLES) : 0u));
    }

    if (!bActive)
    {
        return;
    }

    vec2 Uv = SunShaftCacheUv(Pixel, Size);
    AtmospherePixel = floor(Uv * vec2(viewWidth, viewHeight)) + 0.5;
    vec3 ViewRay = normalize(ReconstructViewPos(Uv, 1.0, gbufferProjectionInverse));
    vec3 Ray = ViewToWorldNormal(ViewRay, gbufferModelViewInverse);
    SunShaftWritePixel = Pixel;
    SunShaftWriteSize = Size;

    if (bWater)
    {
        RenderUnderwaterLight(Ray * 32.0);
    }
    else
    {
        RenderSunShafts(cameraPosition, Ray, min(128.0, far));
    }
#endif
}
