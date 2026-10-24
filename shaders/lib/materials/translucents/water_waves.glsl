#ifndef IDA_WATER_WAVES_GLSL
#define IDA_WATER_WAVES_GLSL

struct WaterWaves {
    float Height;
    vec2 Slope;
    vec2 BroadSlope;
    float Variance;
};

float WaterWaveVisibility(float CyclesPerPixel) {
    return 1.0 - smoothstep(0.125, 0.5, CyclesPerPixel);
}

void AddFilteredWaterWave(vec2 P, vec2 Dpdx, vec2 Dpdy, vec2 Direction, float Wavelength, float Amplitude, float Speed, float Offset, inout float Height, inout vec2 Slope, inout vec2 SlopeDx, inout vec2 SlopeDy, inout float UnresolvedVariance) {
    vec2 Dir = normalize(Direction);
    float K = 6.2831853 / Wavelength;
    vec2 PhaseGradient = K * vec2(dot(Dir, Dpdx), dot(Dir, Dpdy));
    float Visibility = WaterWaveVisibility(max(abs(PhaseGradient.x), abs(PhaseGradient.y)) / 6.2831853);
    float SlopeAmplitude = Amplitude * K;
    UnresolvedVariance += 0.5 * SlopeAmplitude * SlopeAmplitude * (1.0 - Visibility * Visibility);
    if (Visibility <= 0.0) return;
    float Phase = K * dot(Dir, P) - sqrt(9.81 * K) * Speed * frameTimeCounter + Offset;
    float Sine = sin(Phase);
    Height += Amplitude * Sine * Visibility;
    Slope += Dir * (SlopeAmplitude * cos(Phase) * Visibility);
    vec2 SlopeDerivative = -Dir * SlopeAmplitude * Sine * Visibility;
    SlopeDx += SlopeDerivative * PhaseGradient.x;
    SlopeDy += SlopeDerivative * PhaseGradient.y;
}

WaterWaves SampleWaterWaves(vec3 RelativeWorld, vec2 Dpdx, vec2 Dpdy) {
    vec2 P = (RelativeWorld + cameraPosition).xz;
    WaterWaves Waves;
    Waves.Height = 0.0;
    Waves.Slope = vec2(0.0);
    vec2 SlopeDx = vec2(0.0);
    vec2 SlopeDy = vec2(0.0);
    float Unresolved = 0.0;
    // Share the three broad waves between the reflection and sparkle normals.
    AddFilteredWaterWave(P, Dpdx, Dpdy, vec2(0.86, 0.50), 20.0, 0.170, 0.70, 0.00, Waves.Height, Waves.Slope, SlopeDx, SlopeDy, Unresolved);
    AddFilteredWaterWave(P, Dpdx, Dpdy, vec2(0.42, 0.91), 10.5, 0.085, 0.90, 1.70, Waves.Height, Waves.Slope, SlopeDx, SlopeDy, Unresolved);
    AddFilteredWaterWave(P, Dpdx, Dpdy, vec2(-0.28, 0.96), 6.2, 0.043, 1.16, 3.10, Waves.Height, Waves.Slope, SlopeDx, SlopeDy, Unresolved);
    Waves.BroadSlope = Waves.Slope;
    AddFilteredWaterWave(P, Dpdx, Dpdy, vec2(0.97, -0.24), 3.1, 0.017, 1.48, 4.40, Waves.Height, Waves.Slope, SlopeDx, SlopeDy, Unresolved);
    AddFilteredWaterWave(P, Dpdx, Dpdy, vec2(-0.71, 0.70), 1.9, 0.010, 1.82, 2.30, Waves.Height, Waves.Slope, SlopeDx, SlopeDy, Unresolved);

    float Footprint = max(length(Dpdx), length(Dpdy));
    float MicroVisibility = WaterWaveVisibility(Footprint * 1.8);
    if (MicroVisibility > 0.0) {
        // The old nested procedural warp was very expensive for this tiny lobe.
        // Reuse the existing noise texture, original flow and anisotropic scale.
        vec2 Scale = vec2(0.1, 1.0) * (1.8 / 256.0);
        vec2 Uv = P * Scale - frameTimeCounter * (45.0 / (256.0 * 7.0)) * vec2(0.15, 0.7);
        float Micro = textureGrad(noisetex, Uv, Dpdx * Scale, Dpdy * Scale).r - 0.5;
        Waves.Slope += vec2(Micro, -Micro) * (0.0156 * MicroVisibility);
    }
    // Variance lost by removing subpixel waves broadens the highlight instead
    // of turning unresolved waves into a perfectly sharp mirror.
    Waves.Variance = min(0.15 * (dot(SlopeDx, SlopeDx) + dot(SlopeDy, SlopeDy)) + Unresolved + 0.000041 * (1.0 - MicroVisibility * MicroVisibility), 0.09) *
                     SPECULAR_AA;
    return Waves;
}

vec3 WaterWaveNormal(vec3 BaseNormal, vec2 Slope, float Strength) {
    vec3 WaveNormal = normalize(vec3(-Slope.x, 1.0, -Slope.y));
    return normalize(mix(BaseNormal, WaveNormal, Strength));
}
#endif
