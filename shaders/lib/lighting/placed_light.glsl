#ifndef IDA_PLACED_LIGHT_GLSL
#define IDA_PLACED_LIGHT_GLSL

// ---- Placed Light ----

#include "/lib/lighting/local_grid.glsl"
#include "/lib/lighting/local_shadow_cache.glsl"
#if PLACED_LIGHTS == 1
float PlacedLightVisibility(vec3 Position, vec3 LightPosition, vec3 Normal)
{
#if LOCAL_LIGHT_SHADOWS == 1
    vec3 Start = Position + Normal * 0.08;
    vec3 Segment = LightPosition - Start;
    float Distance = length(Segment);

    if (Distance < 0.1)
    {
        return 1.0;
    }

    vec3 Direction = Segment / Distance;
    vec3 InvDirection = 1.0 / max(abs(Direction), vec3(0.000001));
    ivec3 SourceCell = ivec3(floor(LightPosition));
    float T = 0.0;

    // Hierarchical DDA: jump empty 4-block regions, then blocks, then 1/4
    // block. 128 covers every cell on the longest (12.75 block) diagonal ray.
    for (int Step = 0; Step < 128; ++Step)
    {
        if (T >= Distance - 0.06)
        {
            return 1.0;
        }

        vec3 P = Start + Direction * T;
        ivec3 Cell = ivec3(floor(P));

        if (!InsideLocalGrid(Cell) || all(equal(Cell, SourceCell)))
        {
            return 1.0;
        }

        float Scale = 0.25;

        if (LocalOccluderCoarse[LocalClusterIndex(Cell / 4)] != 0u)
        {
            uvec2 Occupied = LocalOccluders[LocalIndex(Cell)];
            Scale = 1.0;

            if (any(notEqual(Occupied, uvec2(0u))))
            {
                ivec3 Sub = ivec3(floor(fract(P) * 4.0));
                uint Bit = uint(Sub.x + 4 * Sub.y + 16 * Sub.z);
                uint Word = Bit < 32u ? Occupied.x : Occupied.y;

                if ((Word & (1u << (Bit & 31u))) != 0u)
                {
                    return 0.0;
                }

                Scale = 4.0;
            }
        }

        vec3 Boundary = (floor(P * Scale) + step(vec3(0.0), Direction)) / Scale;
        vec3 Dt = abs(Boundary - P) * InvDirection;
        Dt = mix(vec3(1e6), Dt, greaterThanEqual(abs(Direction), vec3(0.000001)));
        T += min(Dt.x, min(Dt.y, Dt.z)) + 0.0001;
    }

    return 0.0;
#else
    return 1.0;
#endif
}

vec3 EvaluatePlacedLights(vec3 Albedo, vec3 Normal, vec3 ViewPos, float Roughness, float Metallic, vec3 F0, vec3 GeometryNormal)
{
    vec3 WorldPos = (gbufferModelViewInverse * vec4(ViewPos, 1.0)).xyz;
    vec3 P = LocalGridPosition(WorldPos, cameraPosition);
    float Coverage = LocalGridCoverage(P - LocalGridPhase(cameraPosition));

    if (Coverage <= 0.0 || LOCAL_LIGHT_STRENGTH <= 0.0)
    {
        return vec3(0.0);
    }

    uint Base = LocalClusterIndex(ivec3(floor(P)) / 4) * 8u;

    if (LocalCandidates[Base] == 0xffffffffu)
    {
        return vec3(0.0);
    }

    float CandidateLimit = LocalCandidateLimit(P, Base);
    vec3 Result = vec3(0.0);
    vec3 WorldNormal = normalize(mat3(gbufferModelViewInverse) * Normal);
    vec3 ShadowNormal = normalize(mat3(gbufferModelViewInverse) * GeometryNormal);

    if (dot(ShadowNormal, WorldNormal) < 0.0)
    {
        ShadowNormal = -ShadowNormal;
    }

    for (uint K = 0u; K < 8u; ++K)
    {
        uint Index = LocalCandidates[Base + K];

        if (Index == 0xffffffffu)
        {
            break;
        }

        uint Type = LocalSources[Index];
        vec3 LightPosition = vec3(LocalCell(Index)) + PlacedLightOffset(Type);
        vec3 Delta = LightPosition - P;
        float D2 = dot(Delta, Delta);
        float Attenuation = LocalLightAttenuation(D2, PlacedLightLevel(Type));

        if (Attenuation <= 0.0 || dot(WorldNormal, Delta) <= 0.0)
        {
            continue;
        }

        Attenuation *= LocalCandidateWeight(P, LightPosition, CandidateLimit);

        if (Attenuation <= 0.0)
        {
            continue;
        }

        float Visibility = 1.0;
#if LOCAL_LIGHT_SHADOWS == 1
        Visibility = LocalShadowSlot[Index] != 0u ? CachedPlacedLightVisibility(Index, Delta, ShadowNormal) : PlacedLightVisibility(P, LightPosition, ShadowNormal);
#endif
        if (Visibility <= 0.0)
        {
            continue;
        }

        vec3 L = mat3(gbufferModelView) * (Delta * inversesqrt(max(D2, 0.0001)));
        Result += EvaluateDirectionalBRDF(Albedo, Normal, normalize(-ViewPos), L,
                                          PlacedLightColor(Type) * (7.0 * LOCAL_LIGHT_STRENGTH * Coverage * Attenuation * Visibility),
                                          max(Roughness, 0.12), Metallic, F0);
    }

    return Result;
}
#endif
#endif
