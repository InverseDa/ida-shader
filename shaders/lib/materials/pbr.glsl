#ifndef IDA_MATERIALS_PBR_GLSL
#define IDA_MATERIALS_PBR_GLSL

#include "/lib/materials/materialData.glsl"

#ifdef FRAGMENT_SHADER
uniform sampler2D normals;
uniform sampler2D specular;

struct PbrMaterialSample {
    vec3 normalView;
    vec4 materialData;
};

vec3 getCotangentFrameNormal(vec3 geometryNormalView, vec3 viewPos, vec2 uv, vec3 tangentNormal) {
    vec3 n = normalize(geometryNormalView);
    vec3 dp1 = dFdx(viewPos);
    vec3 dp2 = dFdy(viewPos);
    vec2 duv1 = dFdx(uv);
    vec2 duv2 = dFdy(uv);

    vec3 tangent = dp1 * duv2.t - dp2 * duv1.t;
    vec3 bitangent = -dp1 * duv2.s + dp2 * duv1.s;
    float frameLength = max(dot(tangent, tangent), dot(bitangent, bitangent));

    if (frameLength < 0.000001) {
        return n;
    }

    float invMax = inversesqrt(frameLength);
    mat3 tbn = mat3(tangent * invMax, bitangent * invMax, n);
    return normalize(tbn * tangentNormal);
}

vec3 samplePbrNormal(vec2 uv, vec3 geometryNormalView, vec3 viewPos) {
    vec3 normalSample = texture2D(normals, uv).xyz;
    vec2 encodedXY = normalSample.xy * 2.0 - 1.0;
    float xyLength = dot(encodedXY, encodedXY);

    if (normalSample.z < 0.45 || xyLength > 1.72) {
        return normalize(geometryNormalView);
    }

    vec3 tangentNormal = vec3(encodedXY, normalSample.z * 2.0 - 1.0);
    if (dot(tangentNormal, tangentNormal) < 0.0001) {
        return normalize(geometryNormalView);
    }

    tangentNormal.z = max(tangentNormal.z, 0.12);
    return getCotangentFrameNormal(geometryNormalView, viewPos, uv, normalize(tangentNormal));
}

vec4 samplePbrMaterialData(vec2 uv, vec4 fallbackMaterialData) {
    vec4 specularData = texture2D(specular, uv);
    float specularPresence = max(max(specularData.r, specularData.g), specularData.b);
    bool looksLikeMissingBlack = specularPresence < 0.003;
    bool looksLikeMissingWhite = min(min(specularData.r, specularData.g), specularData.b) > 0.997;
    if (looksLikeMissingBlack || looksLikeMissingWhite) {
        return fallbackMaterialData;
    }

    float roughness = clamp(1.0 - specularData.r, 0.08, 1.0);
    float metallic = smoothstep(0.96, 1.0, specularData.g);
    float ao = getMaterialAO(fallbackMaterialData);
    float materialId = unpackMaterialId(fallbackMaterialData);

    return packMaterialData(roughness, metallic, ao, materialId);
}

PbrMaterialSample samplePbrMaterial(
    vec2 uv,
    vec3 geometryNormalView,
    vec3 viewPos,
    vec4 fallbackMaterialData
) {
    PbrMaterialSample result;
    result.normalView = samplePbrNormal(uv, geometryNormalView, viewPos);
    result.materialData = samplePbrMaterialData(uv, fallbackMaterialData);
    return result;
}
#endif

#endif
