#ifndef IDA_PUDDLE_TRACE_GLSL
#define IDA_PUDDLE_TRACE_GLSL
#include "/lib/common/packing.glsl"
#include "/lib/post/screen.glsl"
#include "/lib/reflections/confidence.glsl"

struct PuddleRayProbe {
    vec2 uv;
    vec2 screenUv;
    vec3 sceneView;
    vec3 normalView;
    bool onScreen;
    bool surface;
};

PuddleRayProbe probePuddleRay(vec3 rayView) {
    PuddleRayProbe probe;
    probe.uv = vec2(-1.0);
    probe.screenUv = vec2(-1.0);
    probe.sceneView = vec3(0.0);
    probe.normalView = vec3(0.0);
    probe.surface = false;
    vec4 snapshot;
    probe.onScreen = projectAndSampleOpaque(rayView, probe.uv, snapshot, probe.screenUv);
    if (!probe.onScreen || snapshot.b >= 0.999999) return probe;
    // Reconstruct the exact texel whose depth was fetched, including its own
    // jitter convention. A continuous projected UV belongs to a different ray.
    vec2 size = vec2(textureSize(colortex4, 0));
    probe.uv = (floor(probe.uv * size) + 0.5) / size;
    probe.sceneView = reconstructOpaqueViewPos(probe.uv, snapshot);
    probe.normalView = normalDecode(snapshot.rg);
    probe.surface = true;
    return probe;
}

float puddleTraceDistance(float fraction) {
    // Denser near the pool, deterministic in world distance (no frame noise).
    return 0.06 + 47.94 * fraction * fraction;
}

float puddleHitTolerance(float viewDepth) {
    float pixelSize = 2.0 * viewDepth / (gbufferProjection[1].y * viewHeight);
    return clamp(0.025 + 2.0 * pixelSize, 0.035, 0.18);
}

float puddleHitConfidence(vec3 rayView, vec3 sceneView, vec3 surfaceView,
                          vec3 normalView, vec2 screenUv, float travel) {
    // A depth crossing at a silhouette is NOT necessarily a ray intersection.
    // Bound the full 3D error to a few pixels, never several world blocks.
    float tolerance = puddleHitTolerance(-sceneView.z);
    float error = length(sceneView - rayView);
    float agreement = 1.0 - smoothstep(tolerance * 0.4, tolerance, error);
    float abovePlane = smoothstep(0.025, 0.12, dot(sceneView - surfaceView, normalView));
    return agreement * abovePlane * reflectionEdgeConfidence(screenUv) *
           (1.0 - smoothstep(32.0, 48.0, travel));
}

float puddlePlaneTravel(vec3 origin, vec3 direction, PuddleRayProbe probe) {
    if (!probe.surface) return -1.0;
    float denominator = dot(direction, probe.normalView);
    if (abs(denominator) < 0.02) return -1.0;
    return dot(probe.sceneView - origin, probe.normalView) / denominator;
}

ReflectionResult tracePuddleReflection(vec3 surfaceView, vec3 normalView, vec3 direction, vec3 sky) {
    ReflectionResult miss = createReflectionResult(sky, 0.0);
    vec3 origin = surfaceView + normalView * 0.015;
    float previousTravel = puddleTraceDistance(0.0);
    PuddleRayProbe previous = probePuddleRay(origin + direction * previousTravel);
    if (!previous.onScreen) return miss;
    // A cutout canopy is not a continuous depth function. Bisection can lock
    // onto an alpha-hole boundary and discard a perfectly visible leaf. Use
    // the sampled surface plane as a hint, then verify the proposed hit against
    // the original snapshot. A normal map cannot create fictitious geometry.
    int probes = 1;
    float lastChecked = -1.0;
    float pendingTravel = 1e6;
    // Share a 25-probe budget between denser marching and verification. Solid
    // faces usually need just one verification; cutouts may use several, but
    // cannot multiply the old maximum of 50 packed-snapshot reads.
    for (int i = 0; i < 24; ++i) {
        if (probes >= 25) return miss;
        float travel = puddleTraceDistance(float(i + 1) / 24.0);
        PuddleRayProbe probe = probePuddleRay(origin + direction * travel);
        probes += 1;
        if (!probe.onScreen) return miss;
        float a = puddlePlaneTravel(origin, direction, previous);
        float b = puddlePlaneTravel(origin, direction, probe);
        // A leaf plane can be observed before its intersection distance, then
        // disappear into alpha holes in the next depth sample. Retain its
        // nearest future hint until the march reaches it; do not lose it just
        // because the current pixel sees the wall behind the canopy.
        if (a > travel && a < 48.0) pendingTravel = min(pendingTravel, a);
        if (b > travel && b < 48.0) pendingTravel = min(pendingTravel, b);
        float c = pendingTravel;
        // Allow one interval of look-back when a coarse probe landed in a
        // cutout hole. Every accepted color still belongs to the actual ray.
        float lower = max(0.06, previousTravel - (travel - previousTravel));
        if (a < lower || a > travel) a = 1e6;
        if (b < lower || b > travel) b = 1e6;
        if (c < lower || c > travel) c = 1e6;
        if (pendingTravel <= travel) pendingTravel = 1e6;
        float first = min(min(a, b), c);
        float second = max(min(a, b), min(max(a, b), c));
        float third = max(max(a, b), c);
        for (int j = 0; j < 3; ++j) {
            float candidate = first;
            if (j == 1) candidate = second;
            if (j == 2) candidate = third;
            if (candidate < 48.0 && abs(candidate - lastChecked) > 0.02 && probes < 25) {
                lastChecked = candidate;
                probes += 1;
                vec3 rayView = origin + direction * candidate;
                PuddleRayProbe hit = probePuddleRay(rayView);
                if (hit.onScreen && hit.surface) {
                    float confidence = puddleHitConfidence(rayView, hit.sceneView,
                                                           surfaceView, normalView, hit.screenUv, candidate);
                    if (confidence > 0.0) {
                        vec3 color = textureLod(colortex9, hit.uv, 0.0).rgb;
                        return createReflectionResult(color, confidence);
                    }
                }
                // A hole or unrelated foreground surface invalidates this
                // hint, not the entire ray. Later hits must pass the same test.
            }
        }
        previousTravel = travel;
        previous = probe;
    }
    return miss;
}
#endif
