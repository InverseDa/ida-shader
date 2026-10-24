#ifndef IDA_SPECULAR_AA_GLSL
#define IDA_SPECULAR_AA_GLSL
#include "/lib/settings.glsl"

// Evaluate derivatives before divergent screen-space material branches.
float SpecularNormalVariance(vec3 Normal) {
    vec3 Dx = dFdx(Normal);
    vec3 Dy = dFdy(Normal);
    return min(0.15 * (dot(Dx, Dx) + dot(Dy, Dy)), 0.09) * SPECULAR_AA;
}

float FilterSpecularRoughness(float PerceptualRoughness, float Variance) {
    float Alpha = PerceptualRoughness * PerceptualRoughness;
    return sqrt(sqrt(min(Alpha * Alpha + min(2.0 * Variance, 0.18), 1.0)));
}

// Broaden a cosine-power lobe while approximately preserving its integral.
// Zero variance is the original lobe; a filtered peak can never grow.
float FilteredHighlight(float Alignment, float Exponent, float Variance) {
    float FilteredExponent = Exponent / (1.0 + Exponent * Variance);
    float Energy = (FilteredExponent + 1.0) / (Exponent + 1.0);
    return pow(clamp(Alignment, 0.0, 1.0), FilteredExponent) * Energy;
}

float FilteredDisk(float DistanceToLight, float BaseWidth, float Variance) {
    float Width = BaseWidth + min(Variance, 0.18);
    return (1.0 - smoothstep(0.0, Width, DistanceToLight)) * BaseWidth / Width;
}
#endif
