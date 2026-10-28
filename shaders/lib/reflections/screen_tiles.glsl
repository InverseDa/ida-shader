#ifndef IDA_REFLECTION_SCREEN_TILES_GLSL
#define IDA_REFLECTION_SCREEN_TILES_GLSL

// ---- Screen Tiles ----

#include "/lib/reflections/water_hierarchy.glsl"
#if VOXEL_REFLECTIONS == 1
// Conservative screen occupancy, rebuilt from the immutable opaque snapshot.
// 64x64 words plus frame/viewport header: 16 KiB, independent of resolution.
bool ReflectionTilesReady()
{
    return ReflectionTiles[4096] == uint(frameCounter) + 1u &&
           ReflectionTiles[4097] == uint(viewWidth) && ReflectionTiles[4098] == uint(viewHeight);
}

float SkipEmptyReflectionTiles(vec3 Origin, vec3 D, float Travel, float Limit)
{
    float End = Limit;

    if (D.z > 0.0)
    {
        End = min(End, (-near * 1.01 - Origin.z) / D.z);
    }

    if (End <= Travel)
    {
        return Travel;
    }

    vec2 Uv = ProjectViewToScreenPos(Origin + D * Travel, gbufferProjection).xy;

    if (!IsScreenUvInRange(Uv))
    {
        return Travel;
    }

    vec2 Delta = ProjectViewToScreenPos(Origin + D * End, gbufferProjection).xy - Uv;

    if (dot(Delta, Delta) < 1e-12)
    {
        return Travel;
    }

    vec2 Inv = 1.0 / max(abs(Delta), vec2(1e-8));
    float T = 0.0;

    for (int I = 0; I < 128; ++I)
    {
        vec2 P = Uv + Delta * T;
        ivec2 Cell = ivec2(floor(P * 64.0));

        if (T >= 1.0 || any(lessThan(Cell, ivec2(0))) || any(greaterThanEqual(Cell, ivec2(64))))
        {
            return End;
        }

        if (ReflectionTiles[Cell.x + 64 * Cell.y] != 0u)
        {
            break;
        }

        vec2 Boundary = (vec2(Cell) + step(vec2(0.0), Delta)) / 64.0;
        vec2 Dt = abs(Boundary - P) * Inv;
        Dt = mix(vec2(1e8), Dt, greaterThanEqual(abs(Delta), vec2(1e-8)));
        T += min(Dt.x, Dt.y) + 0.000001;
    }

    if (T <= 0.0)
    {
        return Travel;
    }

    int Axis = abs(Delta.x) > abs(Delta.y) ? 0 : 1;
    vec2 Q = ((Uv + Delta * T) * 2.0 - 1.0 + gbufferProjection[2].xy) / vec2(gbufferProjection[0].x, gbufferProjection[1].y);
    float Den = D[Axis] + Q[Axis] * D.z;

    if (abs(Den) < 1e-8)
    {
        return Travel;
    }

    return clamp(-(Origin[Axis] + Q[Axis] * Origin.z) / Den, Travel, End);
}
#endif
#endif
