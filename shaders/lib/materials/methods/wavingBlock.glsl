#ifdef VERTEX_SHADER
vec4 GetBump() {
    vec4 pos = gl_Vertex;
    pos.xyz += cameraPosition;
    pos.y += 0.10 * (sin(pos.x + frameTimeCounter) + cos(pos.z + frameTimeCounter));
    pos.xyz -= cameraPosition;
    return gbufferModelView * pos;
}
#endif

#ifdef FRAGMENT_SHADER

// ============================================================================
// ========================== Water noise generator ===========================
// thanks jackdavenport
// https://www.shadertoy.com/view/Mt2SzR
// ============================================================================
float random(float x) {
    return fract(sin(x) * 10000.);   
}

float noise(vec2 p) {
    return random(p.x + p.y * 10000.);
}

vec2 sw(vec2 p) { return vec2(floor(p.x), floor(p.y)); }
vec2 se(vec2 p) { return vec2(ceil(p.x), floor(p.y)); }
vec2 nw(vec2 p) { return vec2(floor(p.x), ceil(p.y)); }
vec2 ne(vec2 p) { return vec2(ceil(p.x), ceil(p.y)); }

float smoothNoise(vec2 p) {
    vec2 interp = smoothstep(0., 1., fract(p));
    float s = mix(noise(sw(p)), noise(se(p)), interp.x);
    float n = mix(noise(nw(p)), noise(ne(p)), interp.x);
    return mix(s, n, interp.y);  
}

float fractalNoise(vec2 p) {
    float x = 0.;
    x += smoothNoise(p      );
    x += smoothNoise(p * 2. ) / 2.;
    x += smoothNoise(p * 4. ) / 4.;
    x += smoothNoise(p * 8. ) / 8.;
    x += smoothNoise(p * 16.) / 16.;
    x /= 1. + 1./2. + 1./4. + 1./8. + 1./16.;
    return x;   
}

float movingNoise(vec2 p) {
    float x = fractalNoise(p);
    float y = fractalNoise(p);
    return fractalNoise(p + vec2(x, y));   
}

float nestedNoise(vec2 p) {
    float x = movingNoise(p);
    float y = movingNoise(p + 100.);
    return movingNoise(p + vec2(x, y));
}

float PerlinWaterNoise(vec2 uv) {
    return nestedNoise(uv * 6.0);
}

float GetWave(vec4 worldPos) {
    float speed1 = frameTimeCounter * 45 / (noiseTextureResolution * 15);
    vec3 coord1 = worldPos.xyz / noiseTextureResolution;
    coord1.x *= 3;
    coord1.x += speed1;
    coord1.z += speed1 * 0.2;
    float noise1 = PerlinWaterNoise(coord1.xz);

    float speed2 = frameTimeCounter * 45 / (noiseTextureResolution * 7);
    vec3 coord2 = worldPos.xyz / noiseTextureResolution;
    coord2.x *= 3;
    coord2.x -= speed2 * 0.15 + noise1 * 0.05;
    coord2.z -= speed2 * 0.7 - noise1 * 0.05;
    float noise2 = PerlinWaterNoise(coord2.xz);

    return noise2 * 0.6 + 0.4;
}
#endif