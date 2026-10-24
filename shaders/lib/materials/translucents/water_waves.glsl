#ifndef IDA_WATER_WAVES_GLSL
#define IDA_WATER_WAVES_GLSL

struct WaterWaves {
    float height;
    vec2 slope;
    vec2 broadSlope;
    float variance;
};

float waterWaveVisibility(float cyclesPerPixel) {
    return 1.0 - smoothstep(0.125, 0.5, cyclesPerPixel);
}

void addFilteredWaterWave(vec2 p, vec2 dpdx, vec2 dpdy, vec2 direction,
                         float wavelength, float amplitude, float speed, float offset,
                         inout float height, inout vec2 slope, inout vec2 slopeDx,
                         inout vec2 slopeDy, inout float unresolvedVariance) {
    vec2 dir = normalize(direction);
    float k = 6.2831853 / wavelength;
    vec2 phaseGradient = k * vec2(dot(dir, dpdx), dot(dir, dpdy));
    float visibility = waterWaveVisibility(max(abs(phaseGradient.x), abs(phaseGradient.y)) / 6.2831853);
    float slopeAmplitude = amplitude * k;
    unresolvedVariance += 0.5 * slopeAmplitude * slopeAmplitude * (1.0 - visibility * visibility);
    if (visibility <= 0.0) return;
    float phase = k * dot(dir, p) - sqrt(9.81 * k) * speed * frameTimeCounter + offset;
    float sine = sin(phase);
    height += amplitude * sine * visibility;
    slope += dir * (slopeAmplitude * cos(phase) * visibility);
    vec2 slopeDerivative = -dir * slopeAmplitude * sine * visibility;
    slopeDx += slopeDerivative * phaseGradient.x;
    slopeDy += slopeDerivative * phaseGradient.y;
}

WaterWaves sampleWaterWaves(vec3 relativeWorld, vec2 dpdx, vec2 dpdy) {
    vec2 p = (relativeWorld + cameraPosition).xz;
    WaterWaves waves;
    waves.height = 0.0;
    waves.slope = vec2(0.0);
    vec2 slopeDx = vec2(0.0);
    vec2 slopeDy = vec2(0.0);
    float unresolved = 0.0;
    // Share the three broad waves between the reflection and sparkle normals.
    addFilteredWaterWave(p, dpdx, dpdy, vec2( 0.86, 0.50), 20.0, 0.170, 0.70, 0.00, waves.height, waves.slope, slopeDx, slopeDy, unresolved);
    addFilteredWaterWave(p, dpdx, dpdy, vec2( 0.42, 0.91), 10.5, 0.085, 0.90, 1.70, waves.height, waves.slope, slopeDx, slopeDy, unresolved);
    addFilteredWaterWave(p, dpdx, dpdy, vec2(-0.28, 0.96),  6.2, 0.043, 1.16, 3.10, waves.height, waves.slope, slopeDx, slopeDy, unresolved);
    waves.broadSlope = waves.slope;
    addFilteredWaterWave(p, dpdx, dpdy, vec2( 0.97,-0.24), 3.1, 0.017, 1.48, 4.40, waves.height, waves.slope, slopeDx, slopeDy, unresolved);
    addFilteredWaterWave(p, dpdx, dpdy, vec2(-0.71, 0.70), 1.9, 0.010, 1.82, 2.30, waves.height, waves.slope, slopeDx, slopeDy, unresolved);

    float footprint = max(length(dpdx), length(dpdy));
    float microVisibility = waterWaveVisibility(footprint * 1.8);
    if (microVisibility > 0.0) {
        // The old nested procedural warp was very expensive for this tiny lobe.
        // Reuse the existing noise texture, original flow and anisotropic scale.
        vec2 scale = vec2(0.1, 1.0) * (1.8 / 256.0);
        vec2 uv = p * scale - frameTimeCounter * (45.0 / (256.0 * 7.0)) * vec2(0.15, 0.7);
        float micro = textureGrad(noisetex, uv, dpdx * scale, dpdy * scale).r - 0.5;
        waves.slope += vec2(micro, -micro) * (0.0156 * microVisibility);
    }
    // Variance lost by removing subpixel waves broadens the highlight instead
    // of turning unresolved waves into a perfectly sharp mirror.
    waves.variance = min(0.15 * (dot(slopeDx, slopeDx) + dot(slopeDy, slopeDy)) + unresolved +
                         0.000041 * (1.0 - microVisibility * microVisibility), 0.09) * SPECULAR_AA;
    return waves;
}

vec3 waterWaveNormal(vec3 baseNormal, vec2 slope, float strength) {
    vec3 waveNormal = normalize(vec3(-slope.x, 1.0, -slope.y));
    return normalize(mix(baseNormal, waveNormal, strength));
}
#endif
