#ifndef IDA_REFLECTIONS_CONFIDENCE_GLSL
#define IDA_REFLECTIONS_CONFIDENCE_GLSL

struct ReflectionResult {
    vec3 Color;
    float Confidence;
};

ReflectionResult CreateReflectionResult(vec3 Color, float Confidence) {
    ReflectionResult Result;
    Result.Color = Color;
    Result.Confidence = Confidence;
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

float ReflectionCandidateConfidence(float Quality, float EdgeConfidence, float Visibility) {
    // Artistic visibility may strengthen a reliable hit, but may never undo
    // the screen-edge envelope. This is a bounded blend, not a radiance gain.
    return clamp(Quality * Visibility, 0.0, 1.0) * EdgeConfidence;
}

float ReflectionCandidateWeight(float Score) {
    // Zero color reads below the lower bound, with a continuous entrance into
    // the weighted estimator. Keep geometric quality for ranking candidates.
    return Score * Score * smoothstep(0.002, 0.02, Score);
}

float ReflectionResolveConfidence(float WeightedConfidence, float TotalWeight) {
    // A small support prior prevents an isolated vanishing candidate from
    // normalizing back to full strength. No best-candidate fallback or history.
    return clamp(WeightedConfidence / (TotalWeight + 0.0004), 0.0, 1.0);
}

float ReflectionFilterAmount(float Contribution) {
    // Keep the existing five-tap filter for strong contributions. Weak hits
    // need only one bilinear read; the four extra taps enter with zero weight.
    return smoothstep(0.04, 0.20, Contribution);
}

#endif
