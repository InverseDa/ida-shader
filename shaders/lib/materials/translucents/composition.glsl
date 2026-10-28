#ifndef IDA_TRANSLUCENT_COMPOSITION_GLSL
#define IDA_TRANSLUCENT_COMPOSITION_GLSL

// ---- Composition ----

// Reproduce resolved color over opaque background while attenuating prior transparent layers.
// Bound transmission to keep alpha-blended source radiance nonnegative.
vec4 MakeRefractiveLayer(vec3 Resolved, vec3 OpaqueBackground, float Transmission)
{
    vec3 Ratio = max(Resolved, vec3(0.0)) / max(OpaqueBackground, vec3(0.0001));
    float Keep = clamp(min(Transmission, min(Ratio.r, min(Ratio.g, Ratio.b))), 0.0, 0.95);
    float Alpha = 1.0 - Keep;

    return vec4(max(Resolved - OpaqueBackground * Keep, vec3(0.0)) / Alpha, Alpha);
}

#endif
