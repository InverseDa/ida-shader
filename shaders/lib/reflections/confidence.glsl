#ifndef IDA_REFLECTIONS_CONFIDENCE_GLSL
#define IDA_REFLECTIONS_CONFIDENCE_GLSL

struct ReflectionResult {
    vec3 color;
    float confidence;
};

ReflectionResult createReflectionResult(vec3 color, float confidence) {
    ReflectionResult result;
    result.color = color;
    result.confidence = confidence;
    return result;
}

float reflectionEdgeConfidence(vec2 unjitteredUv) {
    vec2 size = vec2(viewWidth, viewHeight);
    vec2 edgePixels = min(unjitteredUv, vec2(1.0) - unjitteredUv) * size;
    // Equal pixel widths on both axes, including wide/tall windows. Leave room
    // for one-pixel filtering, bilinear support and the subpixel terrain jitter.
    float fadeWidth = max(8.0, min(size.x, size.y) * 0.14);
    vec2 fade = smoothstep(vec2(2.0), vec2(2.0 + fadeWidth), edgePixels);
    return fade.x * fade.y;
}

float reflectionCandidateConfidence(float quality, float edgeConfidence, float visibility) {
    // Artistic visibility may strengthen a reliable hit, but may never undo
    // the screen-edge envelope. This is a bounded blend, not a radiance gain.
    return clamp(quality * visibility, 0.0, 1.0) * edgeConfidence;
}

float reflectionCandidateWeight(float score) {
    // Zero color reads below the lower bound, with a continuous entrance into
    // the weighted estimator. Keep geometric quality for ranking candidates.
    return score * score * smoothstep(0.002, 0.02, score);
}

float reflectionResolveConfidence(float weightedConfidence, float totalWeight) {
    // A small support prior prevents an isolated vanishing candidate from
    // normalizing back to full strength. No best-candidate fallback or history.
    return clamp(weightedConfidence / (totalWeight + 0.0004), 0.0, 1.0);
}

float reflectionFilterAmount(float contribution) {
    // Keep the existing five-tap filter for strong contributions. Weak hits
    // need only one bilinear read; the four extra taps enter with zero weight.
    return smoothstep(0.04, 0.20, contribution);
}

#endif
