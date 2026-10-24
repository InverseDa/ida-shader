#ifndef IDA_MATERIAL_DATA_GLSL
#define IDA_MATERIAL_DATA_GLSL
#include "/lib/settings.glsl"

const float MaterialIdDefault = 0.0;
const float MaterialIdWater = 1.0;
const float MaterialIdFoliage = 2.0;
const float MaterialIdSky = 3.0;
const float MaterialIdEmissive = 4.0;
const float MaterialIdIce = 5.0;
const float MaterialIdDynamic = 6.0;
const float MaterialIdHand = 7.0;
const float MaterialIdUnlit = 8.0;
const float MaterialIdLeaves = 9.0;
const float MaterialIdPlant = 10.0;
// Rain-retaining opaque terrain. These still use default lighting and static
// TAA; four spare IDs carry the profile without enlarging the RGBA8 buffer.
const float MaterialIdPuddleSoil = 11.0;
const float MaterialIdPuddleSand = 12.0;
const float MaterialIdPuddleStone = 13.0;
const float MaterialIdPuddleWood = 14.0;

const float EntityIdFoliage = 10091.0;
const float EntityIdEmissiveLava = 10089.0;
const float EntityIdEmissiveLavaCauldron = 10090.0;
const float EntityIdWater = 10092.0;
const float EntityIdLeaves = 10094.0;
const float EntityIdPlant = 10095.0;

// RGBA8: perceptual roughness, LabPBR F0/metal code, AO,
// then low 4 bits material ID + high 4 bits vanilla sky-light level.
// Keep IDs below 16. Geometry supplies sky light after material classification.
vec4 PackMaterialData(float Roughness, float Reflectance, float Ao, float MaterialId) {
    return vec4(clamp(Roughness, 0.0, 1.0), clamp(Reflectance, 0.0, 1.0), clamp(Ao, 0.0, 1.0), clamp(MaterialId / 255.0, 0.0, 1.0));
}

float UnpackMaterialId(vec4 MaterialData) {
    return mod(floor(MaterialData.a * 255.0 + 0.5), 16.0);
}

float EncodeMaterialMetadata(float MaterialId, float SkyLevel) {
    return (MaterialId + 16.0 * SkyLevel) / 255.0;
}

float LightmapSkyLevel(float LightmapY) {
    // Vanilla lightmap texel centers are (level + 0.5) / 16.
    return floor(clamp(LightmapY * 16.0 - 0.5, 0.0, 15.0) + 0.5);
}

vec4 WithMaterialSkyLight(vec4 MaterialData, float LightmapY) {
    MaterialData.a = EncodeMaterialMetadata(UnpackMaterialId(MaterialData), LightmapSkyLevel(LightmapY));
    return MaterialData;
}

float GetMaterialSkyVisibility(vec4 MaterialData) {
    return floor(floor(MaterialData.a * 255.0 + 0.5) / 16.0) / 15.0;
}

bool IsMaterial(vec4 MaterialData, float MaterialId) {
    return abs(UnpackMaterialId(MaterialData) - MaterialId) < 0.5;
}

#if SURFACE_WETNESS == 1 && PUDDLE_REFLECTIONS == 1
vec4 WithPuddleSurface(vec4 MaterialData, float NormalUp) {
    // Classify the actual terrain face before normal mapping. Reconstructing
    // this from adjacent depth pixels makes grass silhouettes change the mask
    // as the camera moves. Reuse the ID; walls keep default lighting and TAA.
    float Id = UnpackMaterialId(MaterialData);
    if (Id < MaterialIdPuddleSoil || Id > MaterialIdPuddleWood || NormalUp >= 0.995) return MaterialData;
    return vec4(MaterialData.rgb, MaterialData.a - Id / 255.0);
}
#endif

bool IsVegetationMaterial(vec4 MaterialData) {
    return IsMaterial(MaterialData, MaterialIdFoliage) ||
           IsMaterial(MaterialData, MaterialIdLeaves) ||
           IsMaterial(MaterialData, MaterialIdPlant);
}

// Only surfaces with a valid camera-only motion model use projection jitter.
bool MaterialUsesTaaJitter(vec4 MaterialData) {
    return IsMaterial(MaterialData, MaterialIdDefault) ||
           IsMaterial(MaterialData, MaterialIdEmissive) ||
           IsMaterial(MaterialData, MaterialIdLeaves) ||
           IsMaterial(MaterialData, MaterialIdPlant) ||
           IsMaterial(MaterialData, MaterialIdPuddleSoil) ||
           IsMaterial(MaterialData, MaterialIdPuddleSand) ||
           IsMaterial(MaterialData, MaterialIdPuddleStone) ||
           IsMaterial(MaterialData, MaterialIdPuddleWood);
}

vec4 GetDefaultMaterialData() {
    return PackMaterialData(0.82, 0.04, 1.0, MaterialIdDefault);
}

vec4 GetFoliageMaterialData() {
    return PackMaterialData(0.92, 0.04, 1.0, MaterialIdFoliage);
}

vec4 GetLeavesMaterialData() {
    return PackMaterialData(0.92, 0.04, 1.0, MaterialIdLeaves);
}

vec4 GetPlantMaterialData() {
    return PackMaterialData(0.92, 0.04, 1.0, MaterialIdPlant);
}

vec4 GetWaterMaterialData() {
    return PackMaterialData(0.04, 0.02, 1.0, MaterialIdWater);
}

vec4 GetIceMaterialData() {
    return PackMaterialData(0.84, 0.04, 1.0, MaterialIdIce);
}

vec4 GetSkyMaterialData() {
    return PackMaterialData(1.0, 0.0, 1.0, MaterialIdSky);
}

vec4 GetEmissiveMaterialData() {
    return PackMaterialData(0.35, 0.04, 1.0, MaterialIdEmissive);
}

bool IsIceEntityId(float EntityId) {
    return EntityId == 10093.0;
}

bool IsWaterEntityId(float EntityId) {
    return EntityId == EntityIdWater;
}

vec4 GetTranslucentMaterialData(float EntityId) {
    if (IsIceEntityId(EntityId)) {
        return GetIceMaterialData();
    }
    if (IsWaterEntityId(EntityId)) {
        return GetWaterMaterialData();
    }
    return GetDefaultMaterialData();
}

vec4 GetTerrainMaterialData(float EntityId) {
#if SURFACE_WETNESS == 1 && PUDDLE_REFLECTIONS == 1
    if (EntityId == 10096.0) return PackMaterialData(0.82, 0.04, 1.0, MaterialIdPuddleSoil);
    if (EntityId == 10097.0) return PackMaterialData(0.82, 0.04, 1.0, MaterialIdPuddleSand);
    if (EntityId == 10098.0) return PackMaterialData(0.82, 0.04, 1.0, MaterialIdPuddleStone);
    if (EntityId == 10099.0) return PackMaterialData(0.82, 0.04, 1.0, MaterialIdPuddleWood);
#endif
    if (IsIceEntityId(EntityId)) return GetIceMaterialData();
    if (EntityId == EntityIdLeaves) return GetLeavesMaterialData();
    if (EntityId == EntityIdPlant) return GetPlantMaterialData();
    if (EntityId == EntityIdFoliage) {
        return GetFoliageMaterialData();
    }
    if (EntityId == EntityIdEmissiveLava || EntityId == EntityIdEmissiveLavaCauldron || (EntityId > 10100.0 && EntityId < 10140.0)) {
        return GetEmissiveMaterialData();
    }
    return GetDefaultMaterialData();
}

float GetMaterialRoughness(vec4 MaterialData) {
    return MaterialData.r;
}

float GetMaterialMetallic(vec4 MaterialData) {
    return step(229.5 / 255.0, MaterialData.g);
}

vec3 GetMaterialF0(vec4 MaterialData, vec3 Albedo) {
    // Predefined metals use the standard's permitted albedo-F0 fallback.
    return mix(vec3(MaterialData.g), Albedo, GetMaterialMetallic(MaterialData));
}

float GetMaterialAO(vec4 MaterialData) {
    return MaterialData.b;
}

// =============================================================================
// Fragment Shader
// =============================================================================
#ifdef FRAGMENT_SHADER

vec4 FetchMaterialData(sampler2D MaterialBuffer, vec2 Uv) {
    // Packed metadata and metal codes must never interpolate across surfaces.
    ivec2 Size = textureSize(MaterialBuffer, 0);
    ivec2 Pixel = clamp(ivec2(Uv * vec2(Size)), ivec2(0), Size - ivec2(1));
    return texelFetch(MaterialBuffer, Pixel, 0);
}
#endif

#endif
