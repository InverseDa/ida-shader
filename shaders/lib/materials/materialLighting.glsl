#ifndef IDA_MATERIAL_LIGHTING_GLSL
#define IDA_MATERIAL_LIGHTING_GLSL

// ---- Material Lighting ----

#include "/lib/materials/materialData.glsl"

struct MaterialLightingProfile
{
    float ShadowLift;
    float DirectScale;
    float AmbientScale;
    float EmissionStrength;
    float TransmissionScale;
};

MaterialLightingProfile GetMaterialLightingProfile(vec4 MaterialData)
{
    MaterialLightingProfile Profile;
    Profile.ShadowLift = 0.24;
    Profile.DirectScale = 1.0;
    Profile.AmbientScale = 1.0;
    Profile.EmissionStrength = 0.0;
    Profile.TransmissionScale = 0.0;

    if (IsMaterial(MaterialData, MaterialIdSky))
    {
        Profile.ShadowLift = 1.0;
        Profile.DirectScale = 0.0;
        Profile.AmbientScale = 0.0;

        return Profile;
    }

    if (IsMaterial(MaterialData, MaterialIdWater))
    {
        Profile.ShadowLift = 1.0;
        Profile.DirectScale = 0.0;
        Profile.AmbientScale = 0.0;

        return Profile;
    }

    if (IsVegetationMaterial(MaterialData))
    {
        // Replace the old unconditional 26% ambient boost with a directional
        // thin-surface term. New leaves/plants retain their static TAA path.
        Profile.ShadowLift = 0.24;
        Profile.DirectScale = 0.82;
        Profile.AmbientScale = 1.0;
        Profile.TransmissionScale = IsMaterial(MaterialData, MaterialIdLeaves) ? 0.55 : 0.8;

        return Profile;
    }

    if (IsMaterial(MaterialData, MaterialIdEmissive))
    {
        Profile.ShadowLift = 1.0;
        Profile.DirectScale = 0.18;
        Profile.AmbientScale = 0.45;
        Profile.EmissionStrength = 1.55;

        return Profile;
    }

    if (IsMaterial(MaterialData, MaterialIdIce))
    {
        Profile.DirectScale = 0.55;
        Profile.AmbientScale = 0.45;

        return Profile;
    }

    return Profile;
}

float AdjustMaterialRoughness(vec4 MaterialData, float Roughness)
{
    if (IsMaterial(MaterialData, MaterialIdIce))
    {
        return max(Roughness, 0.72);
    }

    return Roughness;
}

#endif
