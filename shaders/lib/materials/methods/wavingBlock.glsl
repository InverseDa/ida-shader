vec4 GetBump() {
    vec4 pos = gl_Vertex;
    pos.xyz += cameraPosition;
    pos.y += 0.10 * (sin(pos.x + frameTimeCounter) + cos(pos.z + frameTimeCounter));
    pos.xyz -= cameraPosition;
    return gbufferModelView * pos;
}

vec4 GetWave(vec4 worldPos) {
    float speed1 = worldTime * 85 / (noiseTextureResolution * 15);
    vec3 coord1 = worldPos.xyz / noiseTextureResolution;
    coord1.x *= 3;
    coord1.x += speed1;
    coord1.z += speed1 * 0.2;
    float noise1 = texture(noisetex, coord1.xz).x;

    float speed2 = worldTime * 85 / (noiseTextureResolution * 7);
    vec3 coord2 = worldPos.xyz / noiseTextureResolution;
    coord2.x *= 0.5;
    coord2.x -= speed2 * 0.15 + noise1 * 0.05;
    coord2.z -= speed2 * 0.7 - noise1 * 0.05;
    float noise2 = texture(noisetex, coord2.xz).x;

    return noise2 * 0.6 + 0.4;
}