#ifndef IDA_MATERIAL_DATA_GLSL
#define IDA_MATERIAL_DATA_GLSL
#include "/lib/settings.glsl"

const float MATERIAL_ID_DEFAULT = 0.0;
const float MATERIAL_ID_WATER = 1.0;
const float MATERIAL_ID_FOLIAGE = 2.0;
const float MATERIAL_ID_SKY = 3.0;
const float MATERIAL_ID_EMISSIVE = 4.0;
const float MATERIAL_ID_ICE = 5.0;
const float MATERIAL_ID_DYNAMIC = 6.0;
const float MATERIAL_ID_HAND = 7.0;
const float MATERIAL_ID_UNLIT = 8.0;
const float MATERIAL_ID_LEAVES = 9.0;
const float MATERIAL_ID_PLANT = 10.0;
// Rain-retaining opaque terrain. These still use default lighting and static
// TAA; four spare IDs carry the profile without enlarging the RGBA8 buffer.
const float MATERIAL_ID_PUDDLE_SOIL = 11.0;
const float MATERIAL_ID_PUDDLE_SAND = 12.0;
const float MATERIAL_ID_PUDDLE_STONE = 13.0;
const float MATERIAL_ID_PUDDLE_WOOD = 14.0;

const float ENTITY_ID_FOLIAGE = 10091.0;
const float ENTITY_ID_EMISSIVE_LAVA = 10089.0;
const float ENTITY_ID_EMISSIVE_LAVA_CAULDRON = 10090.0;
const float ENTITY_ID_WATER = 10092.0;
const float ENTITY_ID_LEAVES = 10094.0;
const float ENTITY_ID_PLANT = 10095.0;

// RGBA8: perceptual roughness, LabPBR F0/metal code, AO,
// then low 4 bits material ID + high 4 bits vanilla sky-light level.
// Keep IDs below 16. Geometry supplies sky light after material classification.
vec4 packMaterialData(float roughness, float reflectance, float ao, float materialId) {
    return vec4(clamp(roughness, 0.0, 1.0),
                clamp(reflectance, 0.0, 1.0),
                clamp(ao, 0.0, 1.0),
                clamp(materialId / 255.0, 0.0, 1.0));
}

float unpackMaterialId(vec4 materialData) {
    return mod(floor(materialData.a * 255.0 + 0.5), 16.0);
}

float encodeMaterialMetadata(float materialId, float skyLevel) {
    return (materialId + 16.0 * skyLevel) / 255.0;
}

float lightmapSkyLevel(float lightmapY) {
    // Vanilla lightmap texel centers are (level + 0.5) / 16.
    return floor(clamp(lightmapY * 16.0 - 0.5, 0.0, 15.0) + 0.5);
}

vec4 withMaterialSkyLight(vec4 materialData, float lightmapY) {
    materialData.a = encodeMaterialMetadata(unpackMaterialId(materialData), lightmapSkyLevel(lightmapY));
    return materialData;
}

float getMaterialSkyVisibility(vec4 materialData) {
    return floor(floor(materialData.a * 255.0 + 0.5) / 16.0) / 15.0;
}

bool isMaterial(vec4 materialData, float materialId) {
    return abs(unpackMaterialId(materialData) - materialId) < 0.5;
}

#if SURFACE_WETNESS == 1 && PUDDLE_REFLECTIONS == 1
vec4 withPuddleSurface(vec4 materialData, float normalUp) {
    // Classify the actual terrain face before normal mapping. Reconstructing
    // this from adjacent depth pixels makes grass silhouettes change the mask
    // as the camera moves. Reuse the ID; walls keep default lighting and TAA.
    float id = unpackMaterialId(materialData);
    if (id < MATERIAL_ID_PUDDLE_SOIL || id > MATERIAL_ID_PUDDLE_WOOD || normalUp >= 0.995) return materialData;
    return vec4(materialData.rgb, materialData.a - id / 255.0);
}
#endif

bool isVegetationMaterial(vec4 materialData) {
    return isMaterial(materialData, MATERIAL_ID_FOLIAGE) ||
           isMaterial(materialData, MATERIAL_ID_LEAVES) ||
           isMaterial(materialData, MATERIAL_ID_PLANT);
}

// Only surfaces with a valid camera-only motion model use projection jitter.
bool materialUsesTaaJitter(vec4 materialData) {
    return isMaterial(materialData, MATERIAL_ID_DEFAULT) ||
           isMaterial(materialData, MATERIAL_ID_EMISSIVE) ||
           isMaterial(materialData, MATERIAL_ID_LEAVES) ||
           isMaterial(materialData, MATERIAL_ID_PLANT) ||
           isMaterial(materialData, MATERIAL_ID_PUDDLE_SOIL) ||
           isMaterial(materialData, MATERIAL_ID_PUDDLE_SAND) ||
           isMaterial(materialData, MATERIAL_ID_PUDDLE_STONE) ||
           isMaterial(materialData, MATERIAL_ID_PUDDLE_WOOD);
}

vec4 getDefaultMaterialData() {
    return packMaterialData(0.82, 0.04, 1.0, MATERIAL_ID_DEFAULT);
}

vec4 getFoliageMaterialData() {
    return packMaterialData(0.92, 0.04, 1.0, MATERIAL_ID_FOLIAGE);
}

vec4 getLeavesMaterialData() {
    return packMaterialData(0.92, 0.04, 1.0, MATERIAL_ID_LEAVES);
}

vec4 getPlantMaterialData() {
    return packMaterialData(0.92, 0.04, 1.0, MATERIAL_ID_PLANT);
}

vec4 getWaterMaterialData() {
    return packMaterialData(0.04, 0.02, 1.0, MATERIAL_ID_WATER);
}

vec4 getIceMaterialData() {
    return packMaterialData(0.84, 0.04, 1.0, MATERIAL_ID_ICE);
}

vec4 getSkyMaterialData() {
    return packMaterialData(1.0, 0.0, 1.0, MATERIAL_ID_SKY);
}

vec4 getEmissiveMaterialData() {
    return packMaterialData(0.35, 0.04, 1.0, MATERIAL_ID_EMISSIVE);
}

bool isIceEntityId(float entityId) {
    return entityId == 10093.0;
}

bool isWaterEntityId(float entityId) {
    return entityId == ENTITY_ID_WATER;
}

vec4 getTranslucentMaterialData(float entityId) {
    if (isIceEntityId(entityId)) {
        return getIceMaterialData();
    }
    if (isWaterEntityId(entityId)) {
        return getWaterMaterialData();
    }
    return getDefaultMaterialData();
}

vec4 getTerrainMaterialData(float entityId) {
#if SURFACE_WETNESS == 1 && PUDDLE_REFLECTIONS == 1
    if (entityId == 10096.0) return packMaterialData(0.82, 0.04, 1.0, MATERIAL_ID_PUDDLE_SOIL);
    if (entityId == 10097.0) return packMaterialData(0.82, 0.04, 1.0, MATERIAL_ID_PUDDLE_SAND);
    if (entityId == 10098.0) return packMaterialData(0.82, 0.04, 1.0, MATERIAL_ID_PUDDLE_STONE);
    if (entityId == 10099.0) return packMaterialData(0.82, 0.04, 1.0, MATERIAL_ID_PUDDLE_WOOD);
#endif
    if (isIceEntityId(entityId)) return getIceMaterialData();
    if (entityId == ENTITY_ID_LEAVES) return getLeavesMaterialData();
    if (entityId == ENTITY_ID_PLANT) return getPlantMaterialData();
    if (entityId == ENTITY_ID_FOLIAGE) {
        return getFoliageMaterialData();
    }
    if (entityId == ENTITY_ID_EMISSIVE_LAVA || entityId == ENTITY_ID_EMISSIVE_LAVA_CAULDRON) {
        return getEmissiveMaterialData();
    }
    return getDefaultMaterialData();
}

float getMaterialRoughness(vec4 materialData) {
    return materialData.r;
}

float getMaterialMetallic(vec4 materialData) {
    return step(229.5 / 255.0, materialData.g);
}

vec3 getMaterialF0(vec4 materialData, vec3 albedo) {
    // Predefined metals use the standard's permitted albedo-F0 fallback.
    return mix(vec3(materialData.g), albedo, getMaterialMetallic(materialData));
}

float getMaterialAO(vec4 materialData) {
    return materialData.b;
}

#ifdef FRAGMENT_SHADER
vec4 fetchMaterialData(sampler2D materialBuffer, vec2 uv) {
    // Packed metadata and metal codes must never interpolate across surfaces.
    ivec2 size = textureSize(materialBuffer, 0);
    ivec2 pixel = clamp(ivec2(uv * vec2(size)), ivec2(0), size - ivec2(1));
    return texelFetch(materialBuffer, pixel, 0);
}
#endif

#endif
