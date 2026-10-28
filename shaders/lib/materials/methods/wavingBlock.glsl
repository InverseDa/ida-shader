// ---- Vertex Shader ----

#ifdef VERTEX_SHADER

vec4 GetBump()
{
    vec4 Pos = gl_Vertex;
    Pos.xyz += cameraPosition;
    Pos.y += 0.10 * (sin(Pos.x + frameTimeCounter) + cos(Pos.z + frameTimeCounter));
    Pos.xyz -= cameraPosition;

    return gbufferModelView * Pos;
}
#endif

// ---- Fragment Shader ----

#ifdef FRAGMENT_SHADER

// ---- Water Noise ----

// thanks jackdavenport
// https://www.shadertoy.com/view/Mt2SzR

float Random(float X)
{
    return fract(sin(X) * 10000.);
}

float Noise(vec2 P)
{
    return Random(P.x + P.y * 10000.);
}

vec2 Sw(vec2 P)
{
    return vec2(floor(P.x), floor(P.y));
}

vec2 Se(vec2 P)
{
    return vec2(ceil(P.x), floor(P.y));
}

vec2 Nw(vec2 P)
{
    return vec2(floor(P.x), ceil(P.y));
}

vec2 Ne(vec2 P)
{
    return vec2(ceil(P.x), ceil(P.y));
}

float SmoothNoise(vec2 P)
{
    vec2 Interp = smoothstep(0., 1., fract(P));
    float S = mix(Noise(Sw(P)), Noise(Se(P)), Interp.x);
    float N = mix(Noise(Nw(P)), Noise(Ne(P)), Interp.x);

    return mix(S, N, Interp.y);
}

float FractalNoise(vec2 P)
{
    float X = 0.;
    X += SmoothNoise(P);
    X += SmoothNoise(P * 2.) / 2.;
    X += SmoothNoise(P * 4.) / 4.;
    X += SmoothNoise(P * 8.) / 8.;
    X += SmoothNoise(P * 16.) / 16.;
    X /= 1. + 1. / 2. + 1. / 4. + 1. / 8. + 1. / 16.;

    return X;
}

float MovingNoise(vec2 P)
{
    float X = FractalNoise(P);
    float Y = FractalNoise(P);

    return FractalNoise(P + vec2(X, Y));
}

float NestedNoise(vec2 P)
{
    float X = MovingNoise(P);
    float Y = MovingNoise(P + 100.);

    return MovingNoise(P + vec2(X, Y));
}

float PerlinWaterNoise(vec2 Uv)
{
    return NestedNoise(Uv * 6.0);
}

// ---- Water Waves ----

float GetWave(vec4 WorldPos)
{
    float Speed1 = frameTimeCounter * 45 / (noiseTextureResolution * 7);
    vec3 Coord1 = WorldPos.xyz / noiseTextureResolution;
    Coord1.x *= 3;
    Coord1.x += Speed1;
    Coord1.z += Speed1 * 0.2;
    float Noise1 = PerlinWaterNoise(Coord1.xz);

    // float noise1 = texture2D(noisetex, coord1.xz).x;

    float Speed2 = frameTimeCounter * 45 / (noiseTextureResolution * 7);
    vec3 Coord2 = WorldPos.xyz / noiseTextureResolution;
    Coord2.x *= 0.1;
    Coord2.x -= Speed2 * 0.15 + Noise1 * 0.05;
    Coord2.z -= Speed2 * 0.7 - Noise1 * 0.05;

    // float noise2 = PerlinWaterNoise(coord2.xz);
    float Noise2 = texture2D(noisetex, Coord2.xz).x;

    return Noise2 * 0.6 + 0.4;
}

#endif
