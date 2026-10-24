#ifndef IDA_COMMON_SPACE_GLSL
#define IDA_COMMON_SPACE_GLSL

vec2 GetFishEyeCoord(vec2 NdcPos) {
    return NdcPos / (0.15 + 0.85 * length(NdcPos.xy));
}

float ScreenDepthToLinearDepth(float Near, float Far, float ScreenDepth) {
    return 2.0 * Near * Far / ((Far + Near) - (ScreenDepth * 2.0 - 1.0) * (Far - Near));
}

// Legacy typo-preserving alias for existing code paths.
float ScreenDepthToLinerDepth(float Near, float Far, float ScreenDepth) {
    return ScreenDepthToLinearDepth(Near, Far, ScreenDepth);
}

vec3 ReconstructViewPos(vec2 Uv, float Depth, mat4 ProjectionInverse) {
    vec4 ClipPos = vec4(Uv * 2.0 - 1.0, Depth * 2.0 - 1.0, 1.0);
    vec4 ViewPos = ProjectionInverse * ClipPos;
    return ViewPos.xyz / ViewPos.w;
}

vec3 ProjectViewToScreenPos(vec3 ViewPos, mat4 Projection) {
    vec4 ClipPos = Projection * vec4(ViewPos, 1.0);
    ClipPos /= ClipPos.w;
    return ClipPos.xyz * 0.5 + 0.5;
}

vec3 WorldToViewPos(vec3 WorldPos, mat4 ModelView) {
    vec4 ViewPos = ModelView * vec4(WorldPos, 1.0);
    return ViewPos.xyz / ViewPos.w;
}

vec3 ProjectWorldToScreenPos(vec3 WorldPos, mat4 ModelView, mat4 Projection) {
    vec3 ViewPos = WorldToViewPos(WorldPos, ModelView);
    return ProjectViewToScreenPos(ViewPos, Projection);
}

float GetScreenEdgeFade(vec2 Uv) {
    vec2 EdgeDistance = abs(Uv - 0.5) * 2.0;
    float Edge = max(EdgeDistance.x, EdgeDistance.y);
    return 1.0 - smoothstep(0.72, 1.0, Edge);
}

bool IsScreenUvInRange(vec2 Uv) {
    return Uv.x > 0.0 && Uv.x < 1.0 && Uv.y > 0.0 && Uv.y < 1.0;
}

vec3 ViewToWorldPos(vec3 ViewPos, mat4 ModelViewInverse) {
    vec4 WorldPos = ModelViewInverse * vec4(ViewPos, 1.0);
    return WorldPos.xyz / WorldPos.w;
}

vec3 ViewToWorldNormal(vec3 ViewNormal, mat4 ModelViewInverse) {
    return normalize(mat3(ModelViewInverse) * ViewNormal);
}

vec3 WorldToShadowScreenPos(vec3 WorldPos, mat4 ShadowModelView, mat4 ShadowProjection) {
    vec4 ShadowPos = ShadowProjection * ShadowModelView * vec4(WorldPos, 1.0);
    ShadowPos /= ShadowPos.w;
    ShadowPos.xy = GetFishEyeCoord(ShadowPos.xy);
    return ShadowPos.xyz * 0.5 + 0.5;
}

#endif
