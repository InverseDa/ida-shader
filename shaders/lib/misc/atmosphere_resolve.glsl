#ifndef IDA_ATMOSPHERE_RESOLVE_GLSL
#define IDA_ATMOSPHERE_RESOLVE_GLSL

// ---- Atmosphere Resolve ----

#if ATMOSPHERE_HALF_RES == 1
uniform sampler2D colortex6;
#include "/lib/misc/atmosphere_sampling.glsl"
#endif

vec3 ApplyOpaqueAtmosphere(vec3 Color, vec3 ViewPos, bool bIsSky, vec2 Uv)
{
#if ATMOSPHERE_HALF_RES == 1
    if (isEyeInWater == 0)
    {
        // One bilinear lookup, no depth comparison or edge retrace. Final TAA
        // integrates the jittered field; haze stays at full resolution.
        vec2 TextureSize = vec2(textureSize(colortex6, 0));
        vec2 Size = AtmosphereCacheSize();
        vec2 SampleUv = clamp(Uv - AtmosphereJitter() / Size, 0.5 / Size, 1.0 - 0.5 / Size) * Size / TextureSize;
        vec4 Scattering = textureLod(colortex6, SampleUv, 0.0);
        vec3 RayDir = SafeNormal(ViewToWorldNormal(SafeNormal(ViewPos), gbufferModelViewInverse));
        vec3 Fogged = ApplyAirHaze(Color, cameraPosition, RayDir, length(ViewPos), bIsSky);

        return Fogged * (1.0 - Scattering.a) + Scattering.rgb;
    }
#endif
    return ApplyAtmosphere(Color, ViewPos, bIsSky);
}
#endif
