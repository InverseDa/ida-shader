#version 430

// ---- Shadowcomp2 ----

#include "/lib/lighting/local_shadow_cache.glsl"
layout(local_size_x = 8, local_size_y = 8) in;
const ivec3 workGroups = ivec3(12, 12, 384);

#if PLACED_LIGHTS == 1 && LOCAL_LIGHT_SHADOWS == 1
float TraceLocalShadowDepth(vec3 Start, vec3 Direction, float Range)
{
    ivec3 Source = ivec3(floor(Start));
    vec3 InvDirection = 1.0 / max(abs(Direction), vec3(0.000001));
    float T = 0.0;

    for (int N = 0; N < 128; ++N)
    {
        if (T >= Range)
        {
            break;
        }

        vec3 P = Start + Direction * T;
        ivec3 Cell = ivec3(floor(P));

        if (!InsideLocalGrid(Cell))
        {
            break;
        }

        float Scale = 0.25;

        if (LocalOccluderCoarse[LocalClusterIndex(Cell / 4)] != 0u)
        {
            Scale = 1.0;

            if (any(notEqual(Cell, Source)))
            {
                uvec2 Mask = LocalOccluders[LocalIndex(Cell)];

                if (any(notEqual(Mask, uvec2(0u))))
                {
                    ivec3 Sub = ivec3(floor(fract(P) * 4.0));
                    uint Bit = uint(Sub.x + 4 * Sub.y + 16 * Sub.z);
                    uint Word = Bit < 32u ? Mask.x : Mask.y;

                    if ((Word & (1u << (Bit & 31u))) != 0u)
                    {
                        return T;
                    }

                    Scale = 4.0;
                }
            }
        }

        vec3 Boundary = (floor(P * Scale) + step(vec3(0.0), Direction)) / Scale;
        vec3 Dt = abs(Boundary - P) * InvDirection;
        Dt = mix(vec3(1e6), Dt, greaterThanEqual(abs(Direction), vec3(0.000001)));
        T += min(Dt.x, min(Dt.y, Dt.z)) + 0.0001;
    }

    return 65504.0;
}
#endif

void main()
{
#if PLACED_LIGHTS == 1 && LOCAL_LIGHT_SHADOWS == 1
    uint Slot = gl_GlobalInvocationID.z / 6u;
    int Face = int(gl_GlobalInvocationID.z % 6u);
    uint Index = LocalShadowSource[Slot];

    if (Index == 0xffffffffu)
    {
        return;
    }

    ivec2 Pixel = ivec2(gl_GlobalInvocationID.xy);
    vec2 Uv = (vec2(Pixel) + 0.5) * (2.0 / float(LocalShadowResolution)) - 1.0;
    uint Type = LocalSources[Index];
    vec3 Start = vec3(LocalCell(Index)) + PlacedLightOffset(Type);
    vec3 RawDirection = LocalCubeDirection(Face, Uv);
    float RayLength = length(RawDirection);
    vec3 Direction = RawDirection / RayLength;
    LocalShadowDepth[LocalShadowAddress(Slot, Face, Pixel)] =
        TraceLocalShadowDepth(Start, Direction, PlacedLightLevel(Type) * 0.85) / RayLength;
#endif
}
