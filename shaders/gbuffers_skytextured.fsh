#version 130

uniform sampler2D texture;

varying vec4 color;
varying vec4 texcoord;
varying vec2 normal;

void main() {
    // color: the biome color, texture: gray texture color
    // texture * color = RealColor
/* DRAWBUFFERS:02 */
    gl_FragData[0] = texture2D(texture, texcoord.st) * color;
    gl_FragData[1] = vec4(normal, 0.0, 1.0);
}