#ifndef IDA_TRANSLUCENT_COMPOSITION_GLSL
#define IDA_TRANSLUCENT_COMPOSITION_GLSL

// Standard SRC_ALPHA / ONE_MINUS_SRC_ALPHA blending must reproduce resolved
// exactly over opaqueBackground, and attenuate (rather than erase) any layers
// that have already changed that background. Bound transmission to keep the
// source nonnegative, including strongly colored absorption and dark water.
vec4 makeRefractiveLayer(vec3 resolved, vec3 opaqueBackground, float transmission) {
    vec3 ratio = max(resolved, vec3(0.0)) / max(opaqueBackground, vec3(0.0001));
    float keep = clamp(min(transmission, min(ratio.r, min(ratio.g, ratio.b))), 0.0, 0.95);
    float alpha = 1.0 - keep;
    return vec4(max(resolved - opaqueBackground * keep, vec3(0.0)) / alpha, alpha);
}

#endif
