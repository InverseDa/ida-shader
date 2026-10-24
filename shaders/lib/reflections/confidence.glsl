#ifndef IDA_REFLECTIONS_CONFIDENCE_GLSL
#define IDA_REFLECTIONS_CONFIDENCE_GLSL

struct ReflectionResult {
    vec3 Color;
    float Confidence;
    float HitDistance;
    vec3 ColorMinimum;
    vec3 ColorMaximum;
};

ReflectionResult CreateReflectionResult(vec3 Color, float Confidence) {
    ReflectionResult Result;
    Result.Color = Color;
    Result.Confidence = Confidence;
    Result.HitDistance = 0.0;
    Result.ColorMinimum = Color;
    Result.ColorMaximum = Color;
    return Result;
}

float ReflectionEdgeConfidence(vec2 UnjitteredUv) {
    vec2 Size = vec2(viewWidth, viewHeight);
    vec2 EdgePixels = min(UnjitteredUv, vec2(1.0) - UnjitteredUv) * Size;
    // Equal pixel widths on both axes, including wide/tall windows. Leave room
    // for one-pixel filtering, bilinear support and the subpixel terrain jitter.
    float FadeWidth = max(8.0, min(Size.x, Size.y) * 0.14);
    vec2 Fade = smoothstep(vec2(2.0), vec2(2.0 + FadeWidth), EdgePixels);
    return Fade.x * Fade.y;
}

#endif
