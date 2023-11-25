#version 130

#define IS_WATER(x) ((x) > 0.99)

uniform sampler2D texture;
uniform sampler2D lightmap;
uniform int fogMode;

varying vec4 color;
varying vec4 texcoord;
varying vec4 lmcoord;
varying vec3 skyColor;
varying vec2 normal;
varying float water;

/* DRAWBUFFERS:02 */
void main() {
    vec4 light = texture2D(lightmap, lmcoord.st);

    gl_FragData[0] = texture2D(texture, texcoord.st) * light * color;
    gl_FragData[1] = vec4(normal, 0.0, 1.0);
}