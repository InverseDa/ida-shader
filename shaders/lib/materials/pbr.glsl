#ifndef IDA_MATERIALS_PBR_GLSL
#define IDA_MATERIALS_PBR_GLSL

#include "/lib/settings.glsl"
#include "/lib/materials/materialData.glsl"

#ifdef FRAGMENT_SHADER
struct PbrMaterialSample {
    vec3 normalView;
    vec4 materialData;
    float normalVariance;
};

#if MATERIAL_MODE == 1
#include "/lib/lighting/specular_aa.glsl"
uniform sampler2D normals;
uniform sampler2D specular;

vec3 getCotangentFrameNormal(vec3 geometryNormalView, vec3 viewPos, vec2 uv, vec3 tangentNormal) {
    vec3 n = normalize(geometryNormalView);
    vec3 dp1 = dFdx(viewPos);
    vec3 dp2 = dFdy(viewPos);
    vec2 duv1 = dFdx(uv);
    vec2 duv2 = dFdy(uv);

    vec3 tangent = dp1 * duv2.t - dp2 * duv1.t;
    vec3 bitangent = -dp1 * duv2.s + dp2 * duv1.s;
    float frameLength = max(dot(tangent, tangent), dot(bitangent, bitangent));
    float determinant = duv1.s * duv2.t - duv1.t * duv2.s;

    if (frameLength < 1e-24 || abs(determinant) < 1e-20) {
        return n;
    }

    float invMax = sign(determinant) * inversesqrt(frameLength);
    // The derivative bitangent follows increasing atlas V (downwards),
    // matching LabPBR's DirectX Y convention; do not invert Y again.
    mat3 tbn = mat3(tangent * invMax, bitangent * invMax, n);
    vec3 mappedNormal = tbn * tangentNormal;
    float mappedLengthSquared = dot(mappedNormal, mappedNormal);
    // Nonzero UV derivatives do not guarantee independent geometry tangents.
    // Collapsed geometry can cancel a grazing normal; never normalize zero
    // (or a non-finite result) into the G-buffer and specular-AA derivatives.
    if (!(mappedLengthSquared > 1e-12) || isinf(mappedLengthSquared)) {
        return n;
    }
    return mappedNormal * inversesqrt(mappedLengthSquared);
}

float labPbrNormalZ(float xyLengthSquared) {
    return sqrt(max(1.0 - xyLengthSquared, 0.0));
}

float labPbrPerceptualRoughness(float smoothness) {
    // BRDF converts this perceptual value to alpha by squaring once.
    // Keep a finite base lobe even when the normal variance is zero.
    return clamp(1.0 - smoothness, 0.08, 1.0);
}
#endif

PbrMaterialSample samplePbrMaterial(
    vec2 uv,
    vec3 geometryNormalView,
    vec3 viewPos,
    vec4 fallbackMaterialData
) {
    PbrMaterialSample result;
    result.normalView = normalize(geometryNormalView);
    result.materialData = fallbackMaterialData;
    result.normalVariance = 0.0;
#if MATERIAL_MODE == 1
    vec3 normalSample = texture2D(normals, uv).rgb;
    vec2 xy = normalSample.rg * 2.0 - 1.0;
    float xyLength = dot(xy, xy);
    // Invalid XY (including absent black/white normal textures) uses geometry.
    // AO is independent of the normal direction, including a legitimate B=0.
    bool validNormal = xyLength <= 1.02;
    vec3 tangentNormal = validNormal ? normalize(vec3(xy, labPbrNormalZ(xyLength))) : vec3(0.0, 0.0, 1.0);
    // Evaluate derivatives for all fragments, outside texture-dependent branches.
    result.normalView = getCotangentFrameNormal(geometryNormalView, viewPos, uv, tangentNormal);
    result.normalVariance = specularNormalVariance(result.normalView);
    vec4 specularData = texture2D(specular, uv);
    result.materialData.r = filterSpecularRoughness(labPbrPerceptualRoughness(specularData.r),
                                                   result.normalVariance);
    result.materialData.g = specularData.g;
    result.materialData.b = validNormal ? normalSample.b : getMaterialAO(fallbackMaterialData);
    // Black/white specular pixels are valid data, not missing-texture sentinels.
    // Alpha, porosity/SSS and height are deferred to later material extensions.
#endif
    return result;
}
#endif

#endif
