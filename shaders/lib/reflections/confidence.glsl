#ifndef IDA_REFLECTIONS_CONFIDENCE_GLSL
#define IDA_REFLECTIONS_CONFIDENCE_GLSL

struct ReflectionResult {
    vec3 Color;
    float Confidence;
    float HitDistance;
    vec3 ColorMinimum;
    vec3 ColorMaximum;
    bool VoxelHit;       // Which geometry supplies HitDistance.
    bool StableCoverage; // Fresh voxel coverage, including behind partial SSR.
    vec4 Plane; // Current view-space surface plane; zero means no geometric hint.
    uint VoxelFaceId; // Current frame background face, retained behind screen foliage.
};

ReflectionResult CreateReflectionResult(vec3 Color, float Confidence) {
    ReflectionResult Result;
    Result.Color = Color;
    Result.Confidence = Confidence;
    Result.HitDistance = 0.0;
    Result.ColorMinimum = Color;
    Result.ColorMaximum = Color;
    Result.VoxelHit = false;
    Result.StableCoverage = false;
    Result.Plane = vec4(0.0);
    Result.VoxelFaceId = 0u;
    return Result;
}

// Preserve the existing R16F history target: screen hits are signed 0..128,
// voxel hits use -(256+distance). Never use the encoded value as ray travel.
bool ReflectionVoxelTag(float Packed) { return Packed <= -256.0; }
float ReflectionTravel(float Packed) { return ReflectionVoxelTag(Packed) ? -Packed-256.0 : abs(Packed); }

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
