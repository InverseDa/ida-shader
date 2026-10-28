#ifndef IDA_REFLECTION_VOXEL_GLSL
#define IDA_REFLECTION_VOXEL_GLSL

// ---- Voxel ----

#include "/lib/reflections/screen_trace.glsl"

#if VOXEL_REFLECTIONS == 1
#include "/lib/lighting/voxel_gi.glsl"

float VoxelReflectionCoverage(vec3 Relative)
{
    // Camera-relative fade is independent of the four-block storage rebase.
    // Even at the worst grid phase, every accepted hit is inside the volume.
    vec3 A = abs(Relative);

    return 1.0 - smoothstep(24.0, 29.0, max(A.x, max(A.y, A.z)));
}

// Intersect the cached planes in a visited BLOCK. Occupancy is conservative:
// entering its quarter-voxel shell does not imply a valid front-facing hit.
bool VoxelReflectionFace(vec3 Origin, vec3 Direction, ivec3 Cell, out float Travel, out uint Index)
{
    Travel = 0.0;
    Index = 0u;

    if (!InsideLocalGrid(Cell))
    {
        return false;
    }

    float Best = 1e6;

    for (int F = 0; F < 6; ++F)
    {
        vec3 N = VoxelFaceNormal(F);
        float Den = dot(Direction, N);

        if (Den >= -0.000001)
        {
            continue;
        }

        uint J = LocalIndex(Cell) * 6u + uint(F);
        uint M = VoxelMaterial[J];

        if (M == 0u)
        {
            continue;
        }

        vec3 Q = VoxelFacePosition(Cell, F, M);
        float T = dot(Q - Origin, N) / Den;
        vec3 H = Origin + Direction * T - N * 0.008;

        if (T <= 0.06 || T >= Best || any(notEqual(ivec3(floor(H)), Cell)))
        {
            continue;
        }

        ivec3 Sub = ivec3(floor(fract(H) * 4.0));
        uint Bit = uint(Sub.x + 4 * Sub.y + 16 * Sub.z);
        uvec2 Mask = LocalOccluders[LocalIndex(Cell)];

        if (((Bit < 32u ? Mask.x : Mask.y) & (1u << (Bit & 31u))) == 0u)
        {
            continue;
        }

        Best = T;
        Travel = T;
        Index = J;
    }

    return Best < 1e6;
}

bool RefitVoxelReflectionFace(vec3 Origin, vec3 Direction, uint FaceId, out float Travel)
{
    Travel = 0.0;

    if (FaceId == 0u || FaceId > 1572864u)
    {
        return false;
    }

    uint Index = FaceId - 1u;
    uint M = VoxelMaterial[Index];

    if (M == 0u)
    {
        return false;
    }

    ivec3 Cell = LocalCell(Index / 6u);
    vec3 N = VoxelFaceNormal(int(Index % 6u));
    float Den = dot(Direction, N);

    if (Den >= -0.000001)
    {
        return false;
    }

    Travel = dot(VoxelFacePosition(Cell, int(Index % 6u), M) - Origin, N) / Den;
    vec3 H = Origin + Direction * Travel - N * 0.008;

    if (Travel <= 0.06 || Travel >= 48.0 || any(notEqual(ivec3(floor(H)), Cell)))
    {
        return false;
    }

    ivec3 Sub = ivec3(floor(fract(H) * 4.0));
    uint Bit = uint(Sub.x + 4 * Sub.y + 16 * Sub.z);
    uvec2 Mask = LocalOccluders[LocalIndex(Cell)];

    return ((Bit < 32u ? Mask.x : Mask.y) & (1u << (Bit & 31u))) != 0u;
}

bool TraceVoxelReflectionFaces(vec3 Origin, vec3 Direction, float Range, out float Travel, out uint Index)
{
    vec3 Inv = 1.0 / max(abs(Direction), vec3(0.000001));
    float T = 0.0;
    Travel = 0.0;
    Index = 0u;

    // At most 48*sqrt(3) unit-cell crossings; empty clusters skip four blocks.
    // Test six cached planes once per occupied block, not once per subcell.
    for (int I = 0; I < 128; ++I)
    {
        vec3 P = Origin + Direction * T;
        ivec3 Cell = ivec3(floor(P));

        if (T >= Range || !InsideLocalGrid(Cell))
        {
            return false;
        }

        float Scale = 0.25;

        if (LocalOccluderCoarse[LocalClusterIndex(Cell / 4)] != 0u)
        {
            Scale = 1.0;

            if (any(notEqual(LocalOccluders[LocalIndex(Cell)], uvec2(0u))) &&
                VoxelReflectionFace(Origin, Direction, Cell, Travel, Index) && Travel < Range)
            {
                return true;
            }
        }

        vec3 Boundary = (floor(P * Scale) + step(vec3(0.0), Direction)) / Scale;
        vec3 Dt = abs(Boundary - P) * Inv;
        Dt = mix(vec3(1e6), Dt, greaterThanEqual(abs(Direction), vec3(0.000001)));
        T += min(Dt.x, min(Dt.y, Dt.z)) + 0.0001;
    }

    // Unlike occlusion rays, exhaustion is never a reflected surface.
    return false;
}

vec3 VoxelReflectionRadiance(uint Index)
{
    uvec2 Light = VoxelRadiance[Index];
    vec3 Albedo = VoxelAlbedo(VoxelMaterial[Index]);
    float SkyVisibility = unpackHalf2x16(Light.y).y;

    // Same day/night palette as surface fill; no solar disk or halo changes.
    vec3 Radiance = UnpackVoxelLight(Light) + Albedo * 0.96 * SkyColor * SKY_AMBIENT_STRENGTH * 0.20 * SkyVisibility;
#if VOXEL_GI == 1
    Radiance += UnpackVoxelLight(VoxelBounce[Index]) * Albedo * 0.96 * VOXEL_GI_STRENGTH;
#endif
    return Radiance;
}

ReflectionResult TraceVoxelReflection(vec3 SurfaceView, vec3 NormalView, vec3 DirectionView, float Range, vec3 Fallback)
{
    ReflectionResult R = CreateReflectionResult(Fallback, 0.0);
    vec3 Surface = ViewToWorldPos(SurfaceView, gbufferModelViewInverse);
    float Coverage = VoxelReflectionCoverage(Surface);

    if (Coverage <= 0.0)
    {
        return R;
    }

    vec3 Origin = LocalGridPosition(Surface + mat3(gbufferModelViewInverse) * NormalView * 0.015, cameraPosition);
    vec3 Direction = normalize(mat3(gbufferModelViewInverse) * DirectionView);
    float Limit = min(Range, 48.0);
    float Travel;
    uint Index;

    if (!TraceVoxelReflectionFaces(Origin, Direction, Limit, Travel, Index))
    {
        return R;
    }

    vec3 Relative = Origin + Direction * Travel - LocalGridPhase(cameraPosition) - 32.0;
    Coverage *= VoxelReflectionCoverage(Relative) * (1.0 - smoothstep(Limit * 0.8, Limit, Travel));

    if (Coverage <= 0.0)
    {
        return R;
    }

    R = CreateReflectionResult(VoxelReflectionRadiance(Index), Coverage);
    R.HitDistance = Travel;
    R.bVoxelHit = true;
    R.bStableCoverage = Coverage >= 0.999;
    R.VoxelFaceId = Index + 1u;
    vec3 HitNormal = mat3(gbufferModelView) * VoxelFaceNormal(int(Index % 6u));
    R.Plane = vec4(HitNormal, dot(HitNormal, SurfaceView + NormalView * 0.015 + DirectionView * Travel));

    return R;
}
#endif

#if VOXEL_REFLECTIONS == 1
ReflectionResult CombineVoxelReflection(ReflectionResult V, ReflectionResult S)
{
    if (V.Confidence > 0.0)
    {
        // An actual nearer screen hit (including entities) wins. A hidden
        // voxel wall must not be replaced by an unrelated farther SSR layer.
        float Difference = S.HitDistance - V.HitDistance;

        if (S.Confidence > 0.0 && Difference < -0.55)
        {
            // A leaf's partial screen footprint covers a real background,
            // not empty sky. Retain that background through occlusion changes.
            float Background = V.Confidence * (1.0 - S.Confidence);
            float Coverage = S.Confidence + Background;
            S.Color = (S.Color * S.Confidence + V.Color * Background) / max(Coverage, 0.0001);
            S.ColorMinimum = (S.ColorMinimum * S.Confidence + V.ColorMinimum * Background) / max(Coverage, 0.0001);
            S.ColorMaximum = (S.ColorMaximum * S.Confidence + V.ColorMaximum * Background) / max(Coverage, 0.0001);
            S.Confidence = Coverage;
            S.bStableCoverage = V.Confidence >= 0.999;

            return S;
        }

        float ScreenWeight = S.Confidence * (1.0 - smoothstep(0.25, 0.55, abs(Difference)));

        if (ScreenWeight >= 0.999)
        {
            S.bStableCoverage = V.Confidence >= 0.999;

            return S;
        }

        float VoxelWeight = V.Confidence * (1.0 - ScreenWeight);
        float Total = ScreenWeight + VoxelWeight;

        if (Total > 0.0)
        {
            V.Color = (S.Color * ScreenWeight + V.Color * VoxelWeight) / Total;
            V.Confidence = Total;

            if (ScreenWeight > 0.001)
            {
                V.ColorMinimum = min(V.ColorMinimum, S.ColorMinimum);
                V.ColorMaximum = max(V.ColorMaximum, S.ColorMaximum);
            }

            return V;
        }
    }

    return S;
}
#endif

ReflectionResult TraceHybridReflection(vec3 View, vec3 N, vec3 D, float Range, int Steps, vec3 Fallback)
{
#if VOXEL_REFLECTIONS == 1
    ReflectionResult V = TraceVoxelReflection(View, N, D, Range, Fallback);

    // Search up to the known opaque voxel face with the full budget to retain foreground entities.
    ReflectionResult S = TraceScreenReflection(View, N, D, Range, Steps, Fallback,
                                               V.Confidence > 0.0 ? min(Range, V.HitDistance + 0.6) : Range);
#else
    ReflectionResult S = TraceScreenReflection(View, N, D, Range, Steps, Fallback);
#endif
#if VOXEL_REFLECTIONS == 1
    ReflectionResult R = CombineVoxelReflection(V, S);
    R.VoxelFaceId = V.VoxelFaceId;

    // Keep foreground geometry as a reconstruction hint; HitDistance still refers to the voxel hit.
    if (R.bVoxelHit && S.HitDistance > 0.06 && S.HitDistance < V.HitDistance - 0.55)
    {
        R.Plane = S.Plane;
    }

    return R;
#else
    return S;
#endif
}
#endif
