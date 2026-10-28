#ifndef IDA_MATERIALS_PBR_GLSL
#define IDA_MATERIALS_PBR_GLSL

#include "/lib/settings.glsl"
#include "/lib/materials/materialData.glsl"

// ---- Fragment Shader ----

#ifdef FRAGMENT_SHADER

struct PbrMaterialSample
{
    vec3 NormalView;
    vec4 MaterialData;
    float NormalVariance;
};

#if MATERIAL_MODE == 1
#include "/lib/lighting/specular_aa.glsl"
uniform sampler2D normals;
uniform sampler2D specular;

vec3 GetCotangentFrameNormal(vec3 GeometryNormalView, vec3 ViewPos, vec2 Uv, vec3 TangentNormal)
{
    vec3 N = normalize(GeometryNormalView);
    vec3 Dp1 = dFdx(ViewPos);
    vec3 Dp2 = dFdy(ViewPos);
    vec2 Duv1 = dFdx(Uv);
    vec2 Duv2 = dFdy(Uv);

    vec3 Tangent = Dp1 * Duv2.t - Dp2 * Duv1.t;
    vec3 Bitangent = -Dp1 * Duv2.s + Dp2 * Duv1.s;
    float FrameLength = max(dot(Tangent, Tangent), dot(Bitangent, Bitangent));
    float Determinant = Duv1.s * Duv2.t - Duv1.t * Duv2.s;

    if (FrameLength < 1e-24 || abs(Determinant) < 1e-20)
    {
        return N;
    }

    float InvMax = sign(Determinant) * inversesqrt(FrameLength);

    // The derivative bitangent follows increasing atlas V (downwards),
    // matching LabPBR's DirectX Y convention; do not invert Y again.
    mat3 Tbn = mat3(Tangent * InvMax, Bitangent * InvMax, N);
    vec3 MappedNormal = Tbn * TangentNormal;
    float MappedLengthSquared = dot(MappedNormal, MappedNormal);

    // Reject collapsed or non-finite tangent frames before they contaminate G-buffer derivatives.
    if (!(MappedLengthSquared > 1e-12) || isinf(MappedLengthSquared))
    {
        return N;
    }

    return MappedNormal * inversesqrt(MappedLengthSquared);
}

float LabPbrNormalZ(float XyLengthSquared)
{
    return sqrt(max(1.0 - XyLengthSquared, 0.0));
}

float LabPbrPerceptualRoughness(float Smoothness)
{
    // BRDF converts this perceptual value to alpha by squaring once.
    // Keep a finite base lobe even when the normal variance is zero.
    return clamp(1.0 - Smoothness, 0.08, 1.0);
}
#endif

PbrMaterialSample SamplePbrMaterial(vec2 Uv, vec3 GeometryNormalView, vec3 ViewPos, vec4 FallbackMaterialData)
{
    PbrMaterialSample Result;
    Result.NormalView = normalize(GeometryNormalView);
    Result.MaterialData = FallbackMaterialData;
    Result.NormalVariance = 0.0;
#if MATERIAL_MODE == 1
    vec3 NormalSample = texture2D(normals, Uv).rgb;
    vec2 Xy = NormalSample.rg * 2.0 - 1.0;
    float XyLength = dot(Xy, Xy);

    // Invalid XY (including absent black/white normal textures) uses geometry.
    // AO is independent of the normal direction, including a legitimate B=0.
    bool bValidNormal = XyLength <= 1.02;
    vec3 TangentNormal = bValidNormal ? normalize(vec3(Xy, LabPbrNormalZ(XyLength))) : vec3(0.0, 0.0, 1.0);

    // Evaluate derivatives for all fragments, outside texture-dependent branches.
    Result.NormalView = GetCotangentFrameNormal(GeometryNormalView, ViewPos, Uv, TangentNormal);
    Result.NormalVariance = SpecularNormalVariance(Result.NormalView);
    vec4 SpecularData = texture2D(specular, Uv);
    Result.MaterialData.r = FilterSpecularRoughness(LabPbrPerceptualRoughness(SpecularData.r), Result.NormalVariance);
    Result.MaterialData.g = SpecularData.g;
    Result.MaterialData.b = bValidNormal ? NormalSample.b : GetMaterialAO(FallbackMaterialData);

    // Black/white specular pixels are valid data, not missing-texture sentinels.
    // Alpha, porosity/SSS and height are deferred to later material extensions.
#endif
    return Result;
}
#endif

#endif
