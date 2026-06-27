#ifndef IDA_MATERIAL_LIGHTING_GLSL
#define IDA_MATERIAL_LIGHTING_GLSL

#include "/lib/materials/materialData.glsl"

struct MaterialLightingProfile {
    float shadowLift;
    float directScale;
    float ambientScale;
    float emissionStrength;
};

MaterialLightingProfile getMaterialLightingProfile(vec4 materialData) {
    MaterialLightingProfile profile;
    profile.shadowLift = 0.24;
    profile.directScale = 1.0;
    profile.ambientScale = 1.0;
    profile.emissionStrength = 0.0;

    if (isMaterial(materialData, MATERIAL_ID_SKY)) {
        profile.shadowLift = 1.0;
        profile.directScale = 0.0;
        profile.ambientScale = 0.0;
        return profile;
    }

    if (isMaterial(materialData, MATERIAL_ID_WATER)) {
        profile.shadowLift = 1.0;
        profile.directScale = 0.0;
        profile.ambientScale = 0.0;
        return profile;
    }

    if (isMaterial(materialData, MATERIAL_ID_FOLIAGE)) {
        profile.shadowLift = 0.62;
        profile.directScale = 0.82;
        profile.ambientScale = 1.26;
        return profile;
    }

    if (isMaterial(materialData, MATERIAL_ID_EMISSIVE)) {
        profile.shadowLift = 1.0;
        profile.directScale = 0.18;
        profile.ambientScale = 0.45;
        profile.emissionStrength = 1.55;
        return profile;
    }

    if (isMaterial(materialData, MATERIAL_ID_ICE)) {
        profile.directScale = 0.55;
        profile.ambientScale = 0.45;
        return profile;
    }

    return profile;
}

float adjustMaterialRoughness(vec4 materialData, float roughness) {
    if (isMaterial(materialData, MATERIAL_ID_ICE)) {
        return max(roughness, 0.72);
    }

    return roughness;
}

#endif
