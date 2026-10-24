#ifndef IDA_LIGHTING_BRDF_GLSL
#define IDA_LIGHTING_BRDF_GLSL

const float PI = 3.14159265;

float DistributionGGX(float NoH, float roughness) {
    float a = roughness * roughness;
    float a2 = a * a;
    float denom = NoH * NoH * (a2 - 1.0) + 1.0;
    // A large denominator epsilon made the sharpest lobes DARKER, so increasing
    // roughness could create a bright flash. Protect division separately from
    // a bounded HDR peak (the old curve's maximum was approximately 56).
    return min(a2 / max(PI * denom * denom, 1e-12), 64.0);
}

float GeometrySchlickGGX(float NoV, float roughness) {
    float r = roughness + 1.0;
    float k = (r * r) / 8.0;
    return NoV / max(NoV * (1.0 - k) + k, 0.0001);
}

float GeometrySmith(float NoV, float NoL, float roughness) {
    return GeometrySchlickGGX(NoV, roughness) * GeometrySchlickGGX(NoL, roughness);
}

vec3 FresnelSchlick(float cosTheta, vec3 f0) {
    // Normalized dot products can round slightly above one. GLSL pow with a
    // negative base is undefined, even for the nominal integer exponent 5.
    float grazing = 1.0 - clamp(cosTheta, 0.0, 1.0);
    float grazing2 = grazing * grazing;
    return f0 + (1.0 - f0) * (grazing2 * grazing2 * grazing);
}

vec3 FresnelSchlickRoughness(float cosTheta, vec3 f0, float roughness) {
    vec3 oneMinusRoughness = vec3(1.0 - roughness);
    float grazing = 1.0 - clamp(cosTheta, 0.0, 1.0);
    float grazing2 = grazing * grazing;
    return f0 + (max(oneMinusRoughness, f0) - f0) * (grazing2 * grazing2 * grazing);
}

vec3 EvaluateDirectionalBRDF(
    vec3 albedo,
    vec3 normal,
    vec3 viewDir,
    vec3 lightDir,
    vec3 radiance,
    float roughness,
    float metallic,
    vec3 f0
) {
    vec3 halfSum = viewDir + lightDir;
    vec3 halfVector = halfSum * inversesqrt(max(dot(halfSum, halfSum), 1e-8));
    float NoV = clamp(dot(normal, viewDir), 0.0001, 1.0);
    float NoL = clamp(dot(normal, lightDir), 0.0, 1.0);
    float NoH = clamp(dot(normal, halfVector), 0.0, 1.0);
    float HoV = clamp(dot(halfVector, viewDir), 0.0, 1.0);

    vec3 fresnel = FresnelSchlick(HoV, f0);
    float distribution = DistributionGGX(NoH, roughness);
    float geometry = GeometrySmith(NoV, NoL, roughness);

    vec3 numerator = distribution * geometry * fresnel;
    float denominator = max(4.0 * NoV * NoL, 0.0001);
    vec3 specular = numerator / denominator;

    vec3 kS = fresnel;
    vec3 kD = (vec3(1.0) - kS) * (1.0 - metallic);
    vec3 diffuse = kD * albedo / PI;

    return (diffuse + specular) * radiance * NoL;
}

#endif
