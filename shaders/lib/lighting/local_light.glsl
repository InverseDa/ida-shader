#ifndef IDA_LIGHTING_LOCAL_LIGHT_GLSL
#define IDA_LIGHTING_LOCAL_LIGHT_GLSL

// ---- Local Light ----

#include "/lib/lighting/brdf.glsl"

// Iris 1.8.8 supplies item emission, but no world-wide point-light list.
// These are two approximate hand anchors, not animation/bone positions.
uniform int heldBlockLightValue;
uniform int heldBlockLightValue2;
uniform int heldItemId;
uniform int heldItemId2;
uniform vec3 heldBlockLightColor;
uniform vec3 heldBlockLightColor2;
uniform vec3 relativeEyePosition;
uniform vec3 playerLookVector;
uniform bool isSpectator;
uniform sampler2D depthtex1;

float LocalLightAttenuation(float DistanceSquared, float Level)
{
    float Radius = max(Level * 0.85, 0.01);
    float Window = max(1.0 - DistanceSquared / (Radius * Radius), 0.0);

    // Finite at the source and C1 at the range boundary. Euclidean distance
    // gives a sphere instead of the vanilla light grid's diamond footprint.
    return Window * Window / (1.0 + 0.28 * DistanceSquared) * (Level / 15.0);
}

vec3 LocalItemColor(int Item, vec3 ProviderColor)
{
    if (Item == 1001)
    {
        return vec3(1.0, 0.67, 0.32);
    }

    if (Item == 1002)
    {
        return vec3(0.18, 0.65, 1.0);
    }

    if (Item == 1003)
    {
        return vec3(1.0, 0.08, 0.025);
    }

    return max(ProviderColor, vec3(0.0));
}

vec3 LocalHandPosition(float Side)
{
    vec3 Forward = playerLookVector;

    // Horizontal anchors stay below the head when looking vertically.
    vec2 Horizontal = Forward.xz;

    if (dot(Horizontal, Horizontal) < 0.0001)
    {
        Horizontal = -gbufferModelViewInverse[2].xz;
    }

    Horizontal /= max(length(Horizontal), 0.0001);
    vec3 Right = vec3(-Horizontal.y, 0.0, Horizontal.x);
    vec3 RelativeWorld = -relativeEyePosition + vec3(0.0, -0.42, 0.0) +
                         vec3(Horizontal.x, 0.0, Horizontal.y) * 0.22 + Right * (0.28 * Side);

    return (gbufferModelView * vec4(RelativeWorld, 1.0)).xyz;
}

float LocalLightVisibility(vec3 Position, vec3 LightPosition)
{
#if LOCAL_LIGHT_SHADOWS == 1
    vec3 Segment = LightPosition - Position;
    float Distance = length(Segment);

    if (Distance < 0.15)
    {
        return 1.0;
    }

    float Visibility = 1.0;

    // Bounded contact shadows, same-frame depth only. No history/noise and no
    // assumption of occluders outside the screen or behind its first surface.
    for (int I = 0; I < 8; ++I)
    {
        float T = (float(I) + 1.0) / 9.0;
        vec3 P = Position + Segment * T;

        if (P.z >= -near)
        {
            continue;
        }

        vec2 Uv = ProjectViewToScreenPos(P, gbufferProjection).xy + CurrentJitterUv();
        vec2 Edge = min(Uv, vec2(1.0) - Uv);
        float Confidence = smoothstep(0.0, 0.04, min(Edge.x, Edge.y));

        if (Confidence <= 0.0)
        {
            continue;
        }

        float Depth = textureLod(depthtex1, Uv, 0.0).r;

        if (Depth >= 0.999999)
        {
            continue;
        }

        float SceneDistance = ScreenDepthToLinearDepth(near, far, Depth);
        float Delta = -P.z - SceneDistance;

        // Thin screen-depth slab: a silhouette is not an infinitely deep wall.
        float Bias = 0.035 + 0.003 * (-P.z);
        float Occlusion = smoothstep(Bias, Bias * 2.0, Delta) *
                          (1.0 - smoothstep(0.25, 0.65, Delta));
        Visibility = min(Visibility, 1.0 - Occlusion * Confidence);
    }

    return Visibility;
#else
    return 1.0;
#endif
}

#include "/lib/lighting/placed_light.glsl"

vec3 EvaluateLocalLights(vec3 Albedo, vec3 Normal, vec3 ViewPos, float Roughness, float Metallic, vec3 F0, vec3 GeometryNormal)
{
    vec3 Result = vec3(0.0);
#if PLACED_LIGHTS == 1
    Result = EvaluatePlacedLights(Albedo, Normal, ViewPos, Roughness, Metallic, F0, GeometryNormal);
#endif
#if LOCAL_LIGHT == 1
    if (isSpectator || LOCAL_LIGHT_STRENGTH <= 0.0 ||
        max(heldBlockLightValue, heldBlockLightValue2) <= 0)
    {
        return Result;
    }

    for (int Hand = 0; Hand < 2; ++Hand)
    {
        float Level = clamp(float(Hand == 0 ? heldBlockLightValue : heldBlockLightValue2), 0.0, 15.0);

        if (Level <= 0.0)
        {
            continue;
        }

        vec3 Position = LocalHandPosition(Hand == 0 ? 1.0 : -1.0);
        vec3 Delta = Position - ViewPos;
        float D2 = dot(Delta, Delta);
        float Attenuation = LocalLightAttenuation(D2, Level);

        if (Attenuation <= 0.0 || dot(Normal, Delta) <= 0.0)
        {
            continue;
        }

        vec3 L = Delta * inversesqrt(max(D2, 0.0001));
        vec3 Color = LocalItemColor(Hand == 0 ? heldItemId : heldItemId2,
                                    Hand == 0 ? heldBlockLightColor : heldBlockLightColor2);
        float Visibility = LocalLightVisibility(ViewPos, Position);
        Result += EvaluateDirectionalBRDF(Albedo, Normal, normalize(-ViewPos), L,
                                          Color * (4.0 * LOCAL_LIGHT_STRENGTH * Attenuation * Visibility),
                                          max(Roughness, 0.12), Metallic, F0);
    }
#endif
    return Result;
}

vec3 EvaluateLocalLights(vec3 Albedo, vec3 Normal, vec3 ViewPos, float Roughness, float Metallic, vec3 F0)
{
    return EvaluateLocalLights(Albedo, Normal, ViewPos, Roughness, Metallic, F0, Normal);
}
#endif
