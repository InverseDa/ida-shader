#ifndef IDA_SPECULAR_AA_GLSL
#define IDA_SPECULAR_AA_GLSL
#include "/lib/settings.glsl"

// Evaluate derivatives before divergent screen-space material branches.
float specularNormalVariance(vec3 normal) {
    vec3 dx = dFdx(normal);
    vec3 dy = dFdy(normal);
    return min(0.15 * (dot(dx, dx) + dot(dy, dy)), 0.09) * SPECULAR_AA;
}

float filterSpecularRoughness(float perceptualRoughness, float variance) {
    float alpha = perceptualRoughness * perceptualRoughness;
    return sqrt(sqrt(min(alpha * alpha + min(2.0 * variance, 0.18), 1.0)));
}

// Broaden a cosine-power lobe while approximately preserving its integral.
// Zero variance is the original lobe; a filtered peak can never grow.
float filteredHighlight(float alignment, float exponent, float variance) {
    float filteredExponent = exponent / (1.0 + exponent * variance);
    float energy = (filteredExponent + 1.0) / (exponent + 1.0);
    return pow(clamp(alignment, 0.0, 1.0), filteredExponent) * energy;
}

float filteredDisk(float distanceToLight, float baseWidth, float variance) {
    float width = baseWidth + min(variance, 0.18);
    return (1.0 - smoothstep(0.0, width, distanceToLight)) * baseWidth / width;
}
#endif
