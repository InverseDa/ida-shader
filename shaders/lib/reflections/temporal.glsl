#ifndef IDA_REFLECTION_TEMPORAL_GLSL
#define IDA_REFLECTION_TEMPORAL_GLSL

// ---- Temporal ----

#include "/lib/settings.glsl"
#include "/lib/common/color.glsl"

// Only reflection producers write these. A separate composite pass commits
// them after forward rendering; gbuffers never read their own render targets.
vec4 ReflectionColorWrite = vec4(0.0);
vec4 ReflectionSurfaceWrite = vec4(0.0);
vec4 ReflectionHitWrite = vec4(0.0);

#if SSR_TEMPORAL == 1 && defined(IDA_REFLECTION_HISTORY_WRITE)
#include "/lib/materials/materialData.glsl"
uniform sampler2D colortex12; // Previous isolated SSR RGB + confidence.
uniform sampler2D colortex13; // Previous world normal oct, depth, frame/type tag.
uniform sampler2D colortex14; // Signed SSR travel; <= -256 encodes voxel travel.
#ifndef IDA_REFLECTION_MATERIAL_SAMPLER
#define IDA_REFLECTION_MATERIAL_SAMPLER
uniform sampler2D colortex5;
#endif
uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferPreviousProjection;
uniform vec3 previousCameraPosition;
uniform float frameTime;

float ReflectionFrameTag(int Frame, float Kind)
{
    return float(Frame - (Frame / 64) * 64) * 4.0 + Kind;
}

float ReflectionPixelAngle()
{
    return 2.0 / max(abs(gbufferProjection[1].y) * viewHeight, 1.0);
}

vec3 ReflectionPreviousView(vec2 Uv, float Depth, float Kind)
{
    // Puddles follow jittered terrain; water and ice are unjittered.
    if (Kind == 3.0)
    {
        Uv -= GetTaaJitterNdc(frameCounter - 1, vec2(viewWidth, viewHeight)) * 0.5;
    }

    vec2 Ndc = Uv * 2.0 - 1.0;

    return vec3((Ndc.x + gbufferPreviousProjection[2].x) * Depth / gbufferPreviousProjection[0].x,
                (Ndc.y + gbufferPreviousProjection[2].y) * Depth / gbufferPreviousProjection[1].y, -Depth);
}

vec3 ReflectionPreviousWorld(vec3 PreviousView)
{
    // Minecraft's model-view transform is rigid, including camera bobbing.
    return transpose(mat3(gbufferPreviousModelView)) * (PreviousView - gbufferPreviousModelView[3].xyz) + previousCameraPosition - cameraPosition;
}

vec3 ReflectionPreviousHit(vec2 Uv, vec4 Surface, vec2 Hit, float Kind)
{
    vec3 View = ReflectionPreviousView(Uv, Surface.z, Kind);
    vec3 NormalWorld = NormalDecode(Surface.xy);
    vec3 Direction = transpose(mat3(gbufferPreviousModelView)) *
                     reflect(normalize(View), mat3(gbufferPreviousModelView) * NormalWorld);

    return ReflectionPreviousWorld(View) + NormalWorld * 0.015 + Direction * Hit.x;
}

bool ReflectionFrameValid()
{
    if (frameCounter <= 1 || frameTime <= 0.0 || frameTime > 0.25 || isEyeInWater != 0)
    {
        return false;
    }

    if (any(notEqual(textureSize(colortex12, 0), max(ivec2(floor(vec2(viewWidth, viewHeight) * 0.5)), ivec2(1)))))
    {
        return false;
    }

    if (length(cameraPosition - previousCameraPosition) >= 8.0)
    {
        return false;
    }

    // FOV/aspect changes invalidate the sample footprint. Normal camera turns
    // are handled by reprojection, not treated as history resets.
    vec2 Ratio = vec2(gbufferPreviousProjection[0].x / gbufferProjection[0].x,
                      gbufferPreviousProjection[1].y / gbufferProjection[1].y);

    return all(lessThan(abs(Ratio - vec2(1.0)), vec2(0.02)));
}

// ---- History Reprojection ----

vec3 ReflectionHistoryProjection(vec3 SurfaceWorld, vec3 NormalWorld, vec3 HitWorld, bool bHasHit, float Kind)
{
    vec3 PreviousSurface = WorldToViewPos(SurfaceWorld + cameraPosition - previousCameraPosition, gbufferPreviousModelView);
    vec3 Point = PreviousSurface;

    if (bHasHit)
    {
        // Project the virtual mirror image of the hit. Reprojecting only the
        // water point drags reflections sideways when the camera translates.
        vec3 VirtualHit = HitWorld - 2.0 * NormalWorld * dot(HitWorld - SurfaceWorld, NormalWorld);
        vec3 VirtualView = WorldToViewPos(VirtualHit + cameraPosition - previousCameraPosition, gbufferPreviousModelView);
        vec3 PreviousNormal = mat3(gbufferPreviousModelView) * NormalWorld;
        float Denominator = dot(VirtualView, PreviousNormal);

        if (abs(Denominator) < 0.00001)
        {
            return vec3(-1.0);
        }

        float T = dot(PreviousSurface, PreviousNormal) / Denominator;

        if (T <= 0.0 || T >= 1.05)
        {
            return vec3(-1.0);
        }

        Point = VirtualView * T;
    }

    if (Point.z >= -near)
    {
        return vec3(-1.0);
    }

    vec2 Uv = ProjectViewToScreenPos(Point, gbufferPreviousProjection).xy;

    if (Kind == 3.0)
    {
        Uv += GetTaaJitterNdc(frameCounter - 1, vec2(viewWidth, viewHeight)) * 0.5;
    }

    return vec3(Uv, -Point.z);
}

float ReflectionSurfaceAgreement(vec4 Surface, float ExpectedDepth, vec3 NormalWorld, float Kind)
{
    if (Surface.w != ReflectionFrameTag(frameCounter - 1, Kind) || Surface.z <= 0.0)
    {
        return 0.0;
    }

    float DepthLimit = max(0.04, ExpectedDepth * 0.004);
    float DepthWeight = 1.0 - smoothstep(DepthLimit * 0.5, DepthLimit, abs(Surface.z - ExpectedDepth));
    float NormalWeight = smoothstep(0.995, 0.9995, dot(NormalDecode(Surface.xy), NormalWorld));

    return DepthWeight * NormalWeight;
}

struct ReflectionHistorySample
{
    vec3 Color;
    float Confidence;
    vec3 HitWorld;
    float DynamicSign;
    float Support;
    float Match;
};

// ---- History Validation ----

ReflectionHistorySample ReadReflectionHistory(vec3 Projection, vec3 NormalWorld, vec3 ExpectedHit, bool bHasHit, bool bVoxelHit, float Kind)
{
    ReflectionHistorySample History;
    History.Color = vec3(0.0);
    History.Confidence = 0.0;
    History.HitWorld = vec3(0.0);
    History.DynamicSign = 0.0;
    History.Support = 0.0;
    History.Match = 0.0;

    if (!IsScreenUvInRange(Projection.xy))
    {
        return History;
    }

    ivec2 Size = textureSize(colortex12, 0);
    vec2 Position = Projection.xy * vec2(Size) - 0.5;
    ivec2 Base = ivec2(floor(Position));
    vec2 Fraction = fract(Position);
    float HitWeight = 0.0;
    float Dynamic = 1.0;
    vec3 PreviousNormal = mat3(gbufferPreviousModelView) * NormalWorld;
    float PlaneDistance = dot(ReflectionPreviousView(Projection.xy, Projection.z, Kind), PreviousNormal);

    for (int Y = 0; Y < 2; ++Y)
    {
        for (int X = 0; X < 2; ++X)
        {
            ivec2 Pixel = Base + ivec2(X, Y);

            if (any(lessThan(Pixel, ivec2(0))) || any(greaterThanEqual(Pixel, Size)))
            {
                continue;
            }

            vec4 Surface = texelFetch(colortex13, Pixel, 0);
            vec2 TapUv = (vec2(Pixel) + 0.5) / vec2(Size);

            // The half-resolution commit picks a full-resolution texel.
            // Reconstruct THAT sample, including odd viewport dimensions.
            vec2 FullSize = vec2(viewWidth, viewHeight);
            TapUv = (floor(TapUv * FullSize) + 0.5) / FullSize;
            float PlaneDenominator = dot(ReflectionPreviousView(TapUv, 1.0, Kind), PreviousNormal);

            if (abs(PlaneDenominator) < 0.00001)
            {
                continue;
            }

            float ExpectedDepth = PlaneDistance / PlaneDenominator;

            if (ExpectedDepth <= 0.0)
            {
                continue;
            }

            float Weight = (X == 0 ? 1.0 - Fraction.x : Fraction.x) * (Y == 0 ? 1.0 - Fraction.y : Fraction.y);
            Weight *= ReflectionSurfaceAgreement(Surface, ExpectedDepth, NormalWorld, Kind);

            if (Weight <= 0.0)
            {
                continue;
            }

            vec4 Color = texelFetch(colortex12, Pixel, 0);
            float SignedTravel = texelFetch(colortex14, Pixel, 0).r;
            bool bWasVoxel = ReflectionVoxelTag(SignedTravel);
            vec2 Hit = vec2(ReflectionTravel(SignedTravel), bWasVoxel ? 1.0 : sign(SignedTravel));

            if (!IsFiniteRadiance(Color.rgb) || any(isnan(Hit)) || any(isinf(Hit)))
            {
                continue;
            }

            History.Support += Weight;

            // Off-screen history is reusable only with a fresh voxel hit.
            // Removed geometry and newly empty cells cannot leave ghost walls.
            if (bWasVoxel && !bHasHit)
            {
                continue;
            }

            if (Hit.x <= 0.0 || abs(Hit.y) < 1.0 || Color.a <= 0.0)
            {
                continue;
            }

            vec3 World = ReflectionPreviousHit(TapUv, Surface, Hit, Kind);
            float Agreement = 1.0;

            if (bHasHit)
            {
                float Limit = max(0.12, length(ExpectedHit) * ReflectionPixelAngle() * 4.0);

                if (bWasVoxel || bVoxelHit)
                {
                    Limit = max(Limit, 0.4);
                }

                Agreement = 1.0 - smoothstep(Limit * 0.5, Limit, length(World - ExpectedHit));
            }

            Weight *= Agreement;

            if (Weight <= 0.0)
            {
                continue;
            }

            History.Color += Color.rgb * Weight;
            History.Confidence += Color.a * Weight;
            History.HitWorld += World * Weight;

            if (Hit.y < 0.0)
            {
                Dynamic = -1.0;
            }

            HitWeight += Weight;
        }
    }

    if (HitWeight > 0.0)
    {
        History.Color /= HitWeight;
        History.HitWorld /= HitWeight;

        // Keep uncovered support as missing confidence; never normalize a
        // single surviving boundary texel back into a full-strength image.
        History.Confidence = clamp(History.Confidence, 0.0, 1.0);
        History.DynamicSign = Dynamic;
        History.Match = clamp(HitWeight, 0.0, 1.0);
    }

    return History;
}

bool ReflectionHitIsDynamic(vec3 HitView)
{
    ReflectionRayProbe Probe = ProbeReflectionRay(HitView);

    if (!Probe.bSurface)
    {
        return true;
    }

    vec4 Material = FetchMaterialData(colortex5, Probe.Uv);

    return IsVegetationMaterial(Material) || IsMaterial(Material, MaterialIdDynamic) || IsMaterial(Material, MaterialIdUnlit);
}

// ---- Temporal Resolve ----

ReflectionResult ResolveTemporalReflection(ReflectionResult Current, vec3 SurfaceView, vec3 NormalWorld, vec3 DirectionView, float Kind)
{
    vec3 SurfaceWorld = ViewToWorldPos(SurfaceView, gbufferModelViewInverse);
    vec3 DirectionWorld = ViewToWorldNormal(normalize(DirectionView), gbufferModelViewInverse);
    NormalWorld = normalize(NormalWorld);

    if (dot(mat3(gbufferModelView) * NormalWorld, -SurfaceView) < 0.0)
    {
        NormalWorld = -NormalWorld;
    }

    bool bHasHit = Current.Confidence > 0.0 && Current.HitDistance > 0.0;
    vec3 HitWorld = SurfaceWorld + NormalWorld * 0.015 + DirectionWorld * Current.HitDistance;
    float DynamicSign = 1.0;

    if (bHasHit && !Current.bVoxelHit)
    {
        DynamicSign = ReflectionHitIsDynamic(WorldToViewPos(HitWorld, gbufferModelView)) ? -1.0 : 1.0;
    }

    float Dt = clamp(frameTime, 0.001, 0.25);

    if (ReflectionFrameValid())
    {
        vec3 Projection = ReflectionHistoryProjection(SurfaceWorld, NormalWorld, HitWorld, bHasHit, Kind);
        ReflectionHistorySample History = ReadReflectionHistory(Projection, NormalWorld, HitWorld, bHasHit, Current.bVoxelHit, Kind);

        if (History.Support > 0.5)
        {
            if (bHasHit)
            {
                float Response = exp(-Dt / 0.045);
                float Blend = Response * History.Match;

                if (DynamicSign < 0.0 || History.DynamicSign < 0.0)
                {
                    Blend *= 0.45;
                }

                vec3 Range = Current.ColorMaximum - Current.ColorMinimum;
                vec3 Margin = Range * 0.15 + max(Current.Color, vec3(0.1)) * 0.04;
                vec3 OldColor = clamp(History.Color, Current.ColorMinimum - Margin, Current.ColorMaximum + Margin);
                Current.Color = mix(Current.Color, OldColor, Blend);

                // Screen-only coverage may fade in. A fresh voxel background
                // must not disappear because the foreground changed identity.
                float ConfidenceWeight = exp(-Dt / 0.055);

                if (!Current.bStableCoverage && History.Match > 0.5)
                {
                    // Missing history on a newly revealed layer is not missing
                    // current coverage. Do not fade valid new hits into holes.
                    float OldCoverage = clamp(History.Confidence, Current.Confidence - 0.2, Current.Confidence + 0.2);
                    Current.Confidence = mix(Current.Confidence, OldCoverage, ConfidenceWeight * History.Match);
                }
            }
            else if (History.Match > 0.5)
            {
                vec3 ToHit = History.HitWorld - SurfaceWorld - NormalWorld * 0.015;
                float Travel = dot(ToHit, DirectionWorld);
                float RayError = length(ToHit - DirectionWorld * Travel);
                float Limit = max(0.06, Travel * ReflectionPixelAngle() * 2.0);

                if (Travel > 0.06 && RayError < Limit)
                {
                    // Reuse only currently visible, depth-validated hits; hidden history creates unstable strips.
                    vec3 CandidateView = WorldToViewPos(History.HitWorld, gbufferModelView);
                    ReflectionRayProbe Probe = ProbeReflectionRay(CandidateView);
                    ReflectionResult Recovered = CreateReflectionResult(Current.Color, 0.0);

                    if (Probe.bOnScreen)
                    {
                        Recovered = FilterReflectionHit(CandidateView, SurfaceView,
                                                        mat3(gbufferModelView) * NormalWorld, Probe, Travel, Kind == 3.0 ? 48.0 : min(far, 128.0), Current.Color);
                    }

                    if (Recovered.Confidence > 0.0)
                    {
                        Current = Recovered;
                        Current.Confidence = min(Current.Confidence, History.Confidence);
                        DynamicSign = ReflectionHitIsDynamic(CandidateView) ? -1.0 : 1.0;
                    }
                }
            }
        }
    }

    if (isEyeInWater == 0 && -SurfaceView.z > 0.0 && -SurfaceView.z < 65504.0 && IsFiniteRadiance(Current.Color))
    {
        ReflectionColorWrite = vec4(clamp(Current.Color, vec3(0.0), vec3(65504.0)), clamp(Current.Confidence, 0.0, 1.0));
        ReflectionSurfaceWrite = vec4(NormalEncode(NormalWorld), -SurfaceView.z, ReflectionFrameTag(frameCounter, Kind));
        ReflectionHitWrite = vec4(Current.bVoxelHit ? -256.0 - Current.HitDistance : Current.HitDistance * DynamicSign, 0.0, 0.0, 0.0);
    }

    return Current;
}
#else
ReflectionResult ResolveTemporalReflection(ReflectionResult Current, vec3 SurfaceView, vec3 NormalWorld, vec3 DirectionView, float Kind)
{
    return Current;
}
#endif
#endif
