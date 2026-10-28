#ifndef IDA_LIGHTING_BRDF_GLSL
#define IDA_LIGHTING_BRDF_GLSL

// ---- Brdf ----

const float PI = 3.14159265;

float DistributionGGX(float NoH, float Roughness)
{
    float A = Roughness * Roughness;
    float A2 = A * A;
    float Denom = NoH * NoH * (A2 - 1.0) + 1.0;

    // Separate division protection from the HDR peak cap to keep sharp lobes monotonic.
    return min(A2 / max(PI * Denom * Denom, 1e-12), 64.0);
}

float GeometrySchlickGGX(float NoV, float Roughness)
{
    float R = Roughness + 1.0;
    float K = (R * R) / 8.0;

    return NoV / max(NoV * (1.0 - K) + K, 0.0001);
}

float GeometrySmith(float NoV, float NoL, float Roughness)
{
    return GeometrySchlickGGX(NoV, Roughness) * GeometrySchlickGGX(NoL, Roughness);
}

vec3 FresnelSchlick(float CosTheta, vec3 F0)
{
    // Normalized dot products can round slightly above one. GLSL pow with a
    // negative base is undefined, even for the nominal integer exponent 5.
    float Grazing = 1.0 - clamp(CosTheta, 0.0, 1.0);
    float Grazing2 = Grazing * Grazing;

    return F0 + (1.0 - F0) * (Grazing2 * Grazing2 * Grazing);
}

vec3 FresnelSchlickRoughness(float CosTheta, vec3 F0, float Roughness)
{
    vec3 OneMinusRoughness = vec3(1.0 - Roughness);
    float Grazing = 1.0 - clamp(CosTheta, 0.0, 1.0);
    float Grazing2 = Grazing * Grazing;

    return F0 + (max(OneMinusRoughness, F0) - F0) * (Grazing2 * Grazing2 * Grazing);
}

vec3 EvaluateDirectionalBRDF(vec3 Albedo, vec3 Normal, vec3 ViewDir, vec3 LightDir, vec3 Radiance, float Roughness, float Metallic, vec3 F0)
{
    vec3 HalfSum = ViewDir + LightDir;
    vec3 HalfVector = HalfSum * inversesqrt(max(dot(HalfSum, HalfSum), 1e-8));
    float NoV = clamp(dot(Normal, ViewDir), 0.0001, 1.0);
    float NoL = clamp(dot(Normal, LightDir), 0.0, 1.0);
    float NoH = clamp(dot(Normal, HalfVector), 0.0, 1.0);
    float HoV = clamp(dot(HalfVector, ViewDir), 0.0, 1.0);

    vec3 Fresnel = FresnelSchlick(HoV, F0);
    float Distribution = DistributionGGX(NoH, Roughness);
    float Geometry = GeometrySmith(NoV, NoL, Roughness);

    vec3 Numerator = Distribution * Geometry * Fresnel;
    float Denominator = max(4.0 * NoV * NoL, 0.0001);
    vec3 Specular = Numerator / Denominator;

    vec3 KS = Fresnel;
    vec3 KD = (vec3(1.0) - KS) * (1.0 - Metallic);
    vec3 Diffuse = KD * Albedo / PI;

    return (Diffuse + Specular) * Radiance * NoL;
}

#endif
