#ifndef IDA_LIGHTING_SCENE_GLSL
#define IDA_LIGHTING_SCENE_GLSL
#include "/lib/settings.glsl"
#include "/lib/lighting/shadow.glsl"
#include "/lib/materials/lighting/sky.glsl"
#include "/lib/lighting/surface.glsl"
#include "/lib/lighting/cloud_shadow.glsl"
#include "/lib/lighting/vegetation.glsl"
#include "/lib/lighting/local_light.glsl"
#include "/lib/lighting/voxel_gi.glsl"
vec3 ApplySunDirectLight(vec3 Color, vec3 Normal, vec3 ViewPos, vec3 WorldPos, vec4 MaterialData, float Shadow, float TransmissionVisibility, float Ssao, vec3 VanillaLight, vec3 GeometryNormal) {
    MaterialLightingProfile Profile = GetMaterialLightingProfile(MaterialData);
    vec3 SurfaceNormal = normalize(Normal);
    vec3 ViewDir = normalize(-ViewPos);
    if (Profile.TransmissionScale > 0.0) SurfaceNormal = VegetationFacingNormal(SurfaceNormal, ViewDir);
    vec3 LightDir = normalize(shadowLightPosition);
    vec3 LightDirWorld = ViewToWorldNormal(LightDir, gbufferModelViewInverse);
    float SunlightStrength = DirectionalHeightStrength(LightDirWorld.y, NightValue);

    float Roughness = AdjustMaterialRoughness(MaterialData, GetMaterialRoughness(MaterialData));
    float Metallic = GetMaterialMetallic(MaterialData);
    vec3 F0 = GetMaterialF0(MaterialData, Color);
    float MaterialAo = GetMaterialAO(MaterialData) * Ssao;
    float SkyVisibility = GetMaterialSkyVisibility(MaterialData);
    vec3 SkyReflection = GetMaterialSkyReflection(reflect(-ViewDir, SurfaceNormal), Roughness);
    vec3 LightRadiance = GetDirectionalLightRadiance(SunColor, NightValue) * SunlightStrength * DIRECT_LIGHT_STRENGTH;
    // Rain suppresses the directional source, including the backlit leaf term;
    // Lightmap, emission, sky fill and reflected sky keep their own budgets.
    LightRadiance *= WeatherDirectFactor(rainStrength) * SurfaceSunlightGain(rainStrength, NightValue);
#if CLOUD_SHADOWS == 1
    bool NeedsDirectLight = dot(SurfaceNormal, LightDir) > 0.0;
#if VEGETATION_TRANSMISSION == 1
    NeedsDirectLight = NeedsDirectLight || Profile.TransmissionScale > 0.0;
#endif
    if (Profile.DirectScale > 0.0 && NeedsDirectLight && SunlightStrength > 0.0) {
        LightRadiance *= GetSurfaceCloudVisibility(WorldPos, LightDirWorld, SkyVisibility);
    }
#endif
    SurfaceLightingResult Lighting = EvaluateSurfaceLighting(Color, SurfaceNormal, ViewDir, LightDir, LightRadiance, SkyColor * SkyVisibility * SKY_AMBIENT_STRENGTH, SkyReflection * SkyVisibility * SKY_AMBIENT_STRENGTH, Roughness, Metallic, F0, MaterialAo, Shadow, Profile);
#if VEGETATION_TRANSMISSION == 1
    if (Profile.TransmissionScale > 0.0) {
        Lighting.Direct += EvaluateVegetationTransmission(Color, SurfaceNormal, ViewDir, LightDir, LightRadiance, F0, Metallic, Profile.TransmissionScale, Profile.DirectScale, SkyVisibility, TransmissionVisibility);
    }
#endif

    // Albedo stays unlit until here. Vanilla light is an ambient term only.
    // Lightmap includes block lights and is not suppressed by sky visibility.
    // Isotropic ambient approximation: dielectric diffuse or conductor F0.
    vec3 LightmapResponse = mix(Color * (vec3(1.0) - F0), F0, Metallic);
    vec3 Ambient = LightmapResponse * VanillaLight * MaterialAo * Profile.AmbientScale * LIGHTMAP_STRENGTH;
    vec3 Emission = Color * Profile.EmissionStrength;
    vec3 Local = EvaluateLocalLights(Color, SurfaceNormal, ViewPos, Roughness, Metallic, F0, GeometryNormal) * Profile.DirectScale;
    vec3 Indirect = vec3(0.0);
#if VOXEL_GI == 1
    Indirect = SampleVoxelBounce(WorldPos, normalize(mat3(gbufferModelViewInverse)*GeometryNormal)) *
               Color * (vec3(1.0)-F0) * (1.0-Metallic) * Profile.AmbientScale * GetMaterialAO(MaterialData);
#endif
    return Ambient + Lighting.Direct + Lighting.Ambient + Emission + Local + Indirect;
}
vec3 ApplySunDirectLight(vec3 Color, vec3 Normal, vec3 ViewPos, vec3 WorldPos, vec4 MaterialData, float Shadow, float TransmissionVisibility, float Ssao, vec3 VanillaLight) {
    return ApplySunDirectLight(Color, Normal, ViewPos, WorldPos, MaterialData, Shadow, TransmissionVisibility, Ssao, VanillaLight, Normal);
}

#endif
