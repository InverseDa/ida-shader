#ifndef IDA_LIGHTING_CASCADES_GLSL
#define IDA_LIGHTING_CASCADES_GLSL

// ---- Cascades ----

// Camera-centred, nested orthographic cascades. A rotation of the camera does
// not resize or rotate these projections. The sun still rotates them normally.
float CascadeRadius(int Index)
{
    if (Index == 0)
    {
        return 8.0;
    }

    if (Index == 1)
    {
        return 32.0;
    }

    if (Index == 2)
    {
        return 96.0;
    }

    return 192.0;
}

vec2 CascadeTile(int Index)
{
    return vec2(float(Index - (Index / 2) * 2), float(Index / 2));
}

vec2 CascadeLocalPosition(vec3 RelativeWorld, int Index)
{
    float Radius = CascadeRadius(Index);
    float Texel = 4.0 * Radius / float(shadowMapResolution);
    vec2 Origin = (mat3(shadowModelView) * cameraPosition).xy;
    vec2 Remainder = Origin - floor(Origin / Texel + 0.5) * Texel;

    return ((mat3(shadowModelView) * RelativeWorld).xy + Remainder) / Radius;
}

vec3 CascadeScreenPosition(vec3 RelativeWorld, int Index)
{
    vec4 Clip = shadowProjection * (shadowModelView * vec4(RelativeWorld, 1.0));

    return vec3(CascadeLocalPosition(RelativeWorld, Index) * 0.25 +
                    CascadeTile(Index) * 0.5 + 0.25,
                Clip.z / Clip.w * 0.5 + 0.5);
}

int SelectCascade(float Distance)
{
    if (Distance < 0.94 * CascadeRadius(0))
    {
        return 0;
    }

    if (Distance < 0.94 * CascadeRadius(1))
    {
        return 1;
    }

    if (Distance < 0.94 * CascadeRadius(2))
    {
        return 2;
    }

    return 3;
}

float CascadeBlend(float Distance, int Index)
{
    return Index == 3 ? 0.0 : smoothstep(0.78 * CascadeRadius(Index), 0.94 * CascadeRadius(Index), Distance);
}

float CascadeCoverage(vec3 Position, int Index)
{
    vec2 Local = Position.xy - CascadeTile(Index) * 0.5;
    vec2 Edge = min(Local, vec2(0.5) - Local);

    return smoothstep(2.0 / float(shadowMapResolution), 0.0125, min(Edge.x, Edge.y)) *
           smoothstep(0.0, 0.02, Position.z) * (1.0 - smoothstep(0.98, 1.0, Position.z));
}

float CascadeDistanceCoverage(float Distance)
{
    float Range = min(far, 192.0);

    return 1.0 - smoothstep(0.70 * Range, Range, Distance);
}

#endif
