#version 430
#include "/lib/constant.glsl"
uniform vec3 cameraPosition, shadowLightPosition;
uniform mat4 gbufferModelViewInverse, shadowModelView, shadowProjection;
uniform sampler2DShadow shadowtex1;
uniform int worldTime;
uniform float rainStrength, far;
uniform float frameTimeCounter;
uniform sampler2D noisetex;
float NightValue;
#include "/lib/common/color.glsl"
#include "/lib/common/space.glsl"
#include "/lib/lighting/daylight.glsl"
#include "/lib/lighting/cloud_shadow.glsl"
#include "/lib/lighting/voxel_gi.glsl"
#if SHADOW_CSM == 1
#include "/lib/lighting/cascades.glsl"
#endif
layout(local_size_x = 64) in;
const ivec3 workGroups = ivec3(24576, 1, 1);
void main() {
#if (VOXEL_GI == 1 || VOXEL_REFLECTIONS == 1)
    uint Index = gl_GlobalInvocationID.x, M = VoxelMaterial[Index];
    VoxelRadiance[Index] = uvec2(0u);
    if (M == 0u) return;
    int Face = int(Index % 6u); ivec3 Cell = LocalCell(Index / 6u);
    vec3 N = VoxelFaceNormal(Face), P = VoxelFacePosition(Cell, Face, M) + N * 0.04;
    vec3 Relative = P - LocalGridPhase(cameraPosition) - 32.0;
    vec3 L = normalize(mat3(gbufferModelViewInverse) * shadowLightPosition);
    int Time = worldTime % 24000, Hour = Time / 1000;
    float Night = clamp((float(Time)-12000.0)/1000.0,0.0,1.0) * (1.0-clamp((float(Time)-23000.0)/1000.0,0.0,1.0));
    NightValue = Night;
    vec3 Sun = SrgbToLinear(mix(SunColorArr[Hour], SunColorArr[(Hour+1)%24], float(Time%1000)/1000.0));
    vec3 Direct = vec3(0.0);
    if (dot(N,L) > 0.0) {
        vec3 S;
#if SHADOW_CSM == 1
        int C = SelectCascade(length(Relative));
        S = CascadeScreenPosition(Relative, C);
#else
        S = WorldToShadowScreenPos(Relative, shadowModelView, shadowProjection);
#endif
        float Visibility = 0.0;
        if (all(greaterThan(S,vec3(0.0))) && all(lessThan(S,vec3(1.0)))) Visibility = texture(shadowtex1, S - vec3(0,0,0.00002));
        // The shadow atlas covers remote blockers outside the local volume.
        vec3 H; ivec3 B;
        if (TraceVoxel(P,L,24.0,H,B)) Visibility = 0.0;
        Direct = GetDirectionalLightRadiance(Sun,Night) * DirectionalHeightStrength(L.y,Night) *
                 WeatherDirectFactor(rainStrength) * SurfaceSunlightGain(rainStrength,Night) * DIRECT_LIGHT_STRENGTH * max(dot(N,L),0.0) * Visibility;
#if CLOUD_SHADOWS == 1
        if (Visibility > 0.0) Direct *= GetSurfaceCloudVisibility(Relative,L,1.0);
#endif
    }
#if PLACED_LIGHTS == 1
    uint Base = LocalClusterIndex(Cell/4) * 8u;
    for (uint K = 0u; K < 8u; ++K) {
        uint Source = LocalCandidates[Base+K]; if (Source == 0xffffffffu) break;
        uint Type = LocalSources[Source]; vec3 Target = vec3(LocalCell(Source))+PlacedLightOffset(Type);
        vec3 Delta = Target-P; float D2 = dot(Delta,Delta), D = sqrt(D2), Radius = PlacedLightLevel(Type)*0.85;
        float Cosine = max(dot(N,Delta/max(D,0.001)),0.0);
        if (D >= Radius || Cosine <= 0.0) continue;
        vec3 H; ivec3 B;
        if (TraceVoxel(P,Delta/max(D,0.001),max(D-0.05,0.0),H,B) && any(notEqual(B,LocalCell(Source)))) continue;
        float Window = max(1.0-D2/(Radius*Radius),0.0);
        Direct += PlacedLightColor(Type) * (7.0*LOCAL_LIGHT_STRENGTH) * Window*Window/(1.0+0.28*D2) * (PlacedLightLevel(Type)/15.0) * Cosine * LocalCandidateWeight(P,Target,Base);
    }
#endif
    // Lambertian outgoing radiance; the gather's cosine PDF cancels pi.
    VoxelRadiance[Index] = PackVoxelLight(VoxelAlbedo(M) * Direct * (0.96 / 3.14159265));
#if VOXEL_REFLECTIONS == 1
    // Reuse the previously unused half word; GI only reads the RGB components.
    // Cache sky accessibility once per face, rather than marching per 5K pixel.
    vec3 SkyHit; ivec3 SkyCell;
    float SkyAccess=TraceVoxel(P,normalize(vec3(N.x*0.35,1.0,N.z*0.35)),24.0,SkyHit,SkyCell) ? 0.0 : 1.0;
    float Blue=UnpackVoxelLight(VoxelRadiance[Index]).z;
    VoxelRadiance[Index].y=packHalf2x16(vec2(Blue,SkyAccess));
#endif
#endif
}
