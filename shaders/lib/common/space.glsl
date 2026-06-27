#ifndef IDA_COMMON_SPACE_GLSL
#define IDA_COMMON_SPACE_GLSL

// ============================================================================
// ============================ Fish Eye Distortion ===========================
// ============================================================================
vec2 getFishEyeCoord(vec2 ndcPos) {
    return ndcPos / (0.15 + 0.85 * length(ndcPos.xy));
}

// ============================================================================
// =========================== Linear depth function ==========================
// ============================================================================
float screenDepthToLinearDepth(float near, float far, float screenDepth) {
    return 2.0 * near * far / ((far + near) - screenDepth * (far - near));
}

// Legacy typo-preserving alias for existing code paths.
float screenDepthToLinerDepth(float near, float far, float screenDepth) {
    return screenDepthToLinearDepth(near, far, screenDepth);
}

vec3 reconstructViewPos(vec2 uv, float depth, mat4 projectionInverse) {
    vec4 clipPos = vec4(uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    vec4 viewPos = projectionInverse * clipPos;
    return viewPos.xyz / viewPos.w;
}

vec3 projectViewToScreenPos(vec3 viewPos, mat4 projection) {
    vec4 clipPos = projection * vec4(viewPos, 1.0);
    clipPos /= clipPos.w;
    return clipPos.xyz * 0.5 + 0.5;
}

vec3 worldToViewPos(vec3 worldPos, mat4 modelView) {
    vec4 viewPos = modelView * vec4(worldPos, 1.0);
    return viewPos.xyz / viewPos.w;
}

vec3 projectWorldToScreenPos(vec3 worldPos, mat4 modelView, mat4 projection) {
    vec3 viewPos = worldToViewPos(worldPos, modelView);
    return projectViewToScreenPos(viewPos, projection);
}

float getScreenEdgeFade(vec2 uv) {
    vec2 edgeDistance = abs(uv - 0.5) * 2.0;
    float edge = max(edgeDistance.x, edgeDistance.y);
    return 1.0 - smoothstep(0.72, 1.0, edge);
}

bool isScreenUvInRange(vec2 uv) {
    return uv.x > 0.0 && uv.x < 1.0 && uv.y > 0.0 && uv.y < 1.0;
}

vec3 viewToWorldPos(vec3 viewPos, mat4 modelViewInverse) {
    vec4 worldPos = modelViewInverse * vec4(viewPos, 1.0);
    return worldPos.xyz / worldPos.w;
}

vec3 viewToWorldNormal(vec3 viewNormal, mat4 modelViewInverse) {
    return normalize(mat3(modelViewInverse) * viewNormal);
}

vec3 worldToShadowScreenPos(vec3 worldPos, mat4 shadowModelView, mat4 shadowProjection) {
    vec4 shadowPos = shadowProjection * shadowModelView * vec4(worldPos, 1.0);
    shadowPos /= shadowPos.w;
    shadowPos.xy = getFishEyeCoord(shadowPos.xy);
    return shadowPos.xyz * 0.5 + 0.5;
}

#endif
