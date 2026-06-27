#ifndef IDA_MATERIAL_DATA_GLSL
#define IDA_MATERIAL_DATA_GLSL

const float MATERIAL_ID_DEFAULT = 0.0;
const float MATERIAL_ID_WATER = 1.0;
const float MATERIAL_ID_FOLIAGE = 2.0;
const float MATERIAL_ID_SKY = 3.0;
const float MATERIAL_ID_EMISSIVE = 4.0;
const float MATERIAL_ID_ICE = 5.0;

const float ENTITY_ID_FOLIAGE = 10091.0;
const float ENTITY_ID_EMISSIVE_LAVA = 10089.0;
const float ENTITY_ID_EMISSIVE_LAVA_CAULDRON = 10090.0;
const float ENTITY_ID_WATER = 10092.0;

vec4 packMaterialData(float roughness, float metallic, float ao, float materialId) {
    return vec4(clamp(roughness, 0.0, 1.0),
                clamp(metallic, 0.0, 1.0),
                clamp(ao, 0.0, 1.0),
                clamp(materialId / 255.0, 0.0, 1.0));
}

float unpackMaterialId(vec4 materialData) {
    return floor(materialData.a * 255.0 + 0.5);
}

bool isMaterial(vec4 materialData, float materialId) {
    return abs(unpackMaterialId(materialData) - materialId) < 0.5;
}

vec4 getDefaultMaterialData() {
    return packMaterialData(0.82, 0.02, 1.0, MATERIAL_ID_DEFAULT);
}

vec4 getFoliageMaterialData() {
    return packMaterialData(0.92, 0.0, 1.0, MATERIAL_ID_FOLIAGE);
}

vec4 getWaterMaterialData() {
    return packMaterialData(0.04, 0.0, 1.0, MATERIAL_ID_WATER);
}

vec4 getIceMaterialData() {
    return packMaterialData(0.84, 0.0, 1.0, MATERIAL_ID_ICE);
}

vec4 getSkyMaterialData() {
    return packMaterialData(1.0, 0.0, 1.0, MATERIAL_ID_SKY);
}

vec4 getEmissiveMaterialData() {
    return packMaterialData(0.35, 0.0, 1.0, MATERIAL_ID_EMISSIVE);
}

bool isIceEntityId(float entityId) {
    return entityId == 79.0 || entityId == 174.0 || entityId == 212.0 || entityId == 266.0;
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
    return materialData.g;
}

float getMaterialAO(vec4 materialData) {
    return materialData.b;
}

#endif
