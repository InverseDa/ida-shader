#version 130
/* DRAWBUFFERS:0 */
uniform sampler2D texture;
uniform sampler2D lightmap;
uniform int fogMode;

varying vec4 color;
varying vec4 texcoord;
varying vec4 litcoord;

void main() {
    vec4 water = texture2D(lightmap, litcoord.st) * texture2D(texture, texcoord.st) * color;
    if(water == vec4(0.0)) water = vec4(1.0);
    gl_FragData[0] = water;
}