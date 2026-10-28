#ifndef IDA_LIGHTING_LIGHTMAP_GLSL
#define IDA_LIGHTING_LIGHTMAP_GLSL

// ---- Lightmap ----

#include "/lib/common/color.glsl"
#include "/lib/settings.glsl"

uniform float sunAngle;
uniform float rainStrength;
#ifndef IDA_LIGHTING_POSITION_UNIFORMS
#define IDA_LIGHTING_POSITION_UNIFORMS
uniform mat4 gbufferModelViewInverse;
uniform vec3 cameraPosition;
#endif
#include "/lib/lighting/local_grid.glsl"

float SurfaceSkyLightmapWeight(float SunAngle, float RainAmount)
{
    // Iris sunAngle: sunrise 0, noon .25, sunset .5, midnight .75.
    // Restore the vanilla contribution at night and soften contrast in rain.
    float Daylight = smoothstep(0.0, 0.25, sin(SunAngle * 6.28318530718));
    float DayWeight = mix(DAY_SKY_LIGHTMAP, max(DAY_SKY_LIGHTMAP, 0.65), smoothstep(0.0, 1.0, RainAmount));

    return mix(1.0, DayWeight, Daylight);
}

vec3 SampleSurfaceLightmap(sampler2D Lightmap, vec2 Uv)
{
    vec3 FullLight = SrgbToLinear(texture2D(Lightmap, Uv).rgb);
    float SkyWeight = SurfaceSkyLightmapWeight(sunAngle, rainStrength);

    if (SkyWeight >= 1.0)
    {
        return FullLight;
    }

    // The zero-skylight row preserves engine block-light color, gamma and night vision.
    vec3 BlockLight = SrgbToLinear(texture2D(Lightmap, vec2(Uv.x, 0.5 / 16.0)).rgb);
    vec3 SkyIncrement = max(FullLight - BlockLight, vec3(0.0));

    return FullLight - SkyIncrement * (1.0 - SkyWeight);
}

vec3 SampleLocalSurfaceLightmap(sampler2D Lightmap, vec2 Uv, vec3 ViewPosition)
{
    vec3 Legacy = SampleSurfaceLightmap(Lightmap, Uv);
#if PLACED_LIGHTS == 1
    if (LOCAL_LIGHT_STRENGTH <= 0.0)
    {
        return Legacy;
    }

    vec3 P = LocalGridPosition((gbufferModelViewInverse * vec4(ViewPosition, 1.0)).xyz, cameraPosition);
    float Coverage = LocalGridCoverage(P - LocalGridPhase(cameraPosition));

    if (Coverage <= 0.0)
    {
        return Legacy;
    }

    uint Base = LocalClusterIndex(ivec3(floor(P)) / 4) * 8u;

    if (LocalCandidates[Base] == 0xffffffffu)
    {
        return Legacy;
    }

    float CandidateLimit = LocalCandidateLimit(P, Base);
    float Level = clamp(Uv.x * 16.0 - 0.5, 0.0, 15.0);
    float Represented = 0.0;

    for (uint K = 0u; K < 8u; ++K)
    {
        uint Index = LocalCandidates[Base + K];

        if (Index == 0xffffffffu)
        {
            break;
        }

        uint Type = LocalSources[Index];
        vec3 Light = vec3(LocalCell(Index)) + PlacedLightOffset(Type);
        vec3 Delta = abs(P - (vec3(LocalCell(Index)) + 0.5));
        float Estimate = max(PlacedLightLevel(Type) - dot(Delta, vec3(1.0)), 0.0);
        Represented = max(Represented, smoothstep(-2.0, 0.5, Estimate - Level) *
                                           smoothstep(0.0, 2.0, Estimate) * LocalCandidateWeight(P, Light, CandidateLimit));
    }

    if (Represented <= 0.0)
    {
        return Legacy;
    }

    // Replace positive block light near known sources; preserve engine darkness and indirect light.
    vec3 NoBlock = SampleSurfaceLightmap(Lightmap, vec2(0.5 / 16.0, Uv.y));
    vec3 BlockIncrement = max(Legacy - NoBlock, vec3(0.0));

    return max(Legacy - BlockIncrement * (0.88 * Coverage * Represented), vec3(0.0));
#else
    return Legacy;
#endif
}

#endif
