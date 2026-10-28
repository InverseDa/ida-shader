#version 430

// ---- Shadowcomp1 ----

#include "/lib/lighting/local_shadow_cache.glsl"
layout(local_size_x = 256) in;
const ivec3 workGroups = ivec3(1, 1, 1);
#if PLACED_LIGHTS == 1
uniform vec3 cameraPosition;
shared uint NearestShadow[64];
#endif
void main()
{
#if PLACED_LIGHTS == 1 && LOCAL_LIGHT_SHADOWS == 1
    uint Lane = gl_LocalInvocationID.x;

    if (Lane < 64u)
    {
        NearestShadow[Lane] = 0xffffffffu;
    }

    barrier();

    for (uint C = Lane; C < 4096u; C += 256u)
    {
        ivec3 Cluster = ivec3(C & 15u, (C >> 4u) & 15u, C >> 8u);
        uvec2 Sources = LocalCoarse[C];

        while (any(notEqual(Sources, uvec2(0u))))
        {
            uint I = LocalIndex(LocalClusterCell(Cluster, PopLocalSourceBit(Sources)));
            uint Type = LocalSources[I];

            if (Type == 0u)
            {
                continue;
            }

            vec3 Delta = vec3(LocalCell(I)) + PlacedLightOffset(Type) - 32.0 - LocalGridPhase(cameraPosition);
            uint Key = (uint(dot(Delta, Delta) * 4.0) << 18u) | I;

            for (int N = 0; N < 64; ++N)
            {
                uint Previous = atomicMin(NearestShadow[N], Key);
                Key = max(Key, Previous);

                if (Key == 0xffffffffu)
                {
                    break;
                }
            }
        }
    }

    barrier();

    if (Lane < 64u)
    {
        uint Key = NearestShadow[Lane];
        uint Index = Key == 0xffffffffu ? Key : (Key & 262143u);
        LocalShadowSource[Lane] = Index;

        if (Index != 0xffffffffu)
        {
            LocalShadowSlot[Index] = Lane + 1u;
        }
    }
#endif
}
