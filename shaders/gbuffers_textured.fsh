#version 130

uniform sampler2D texture;

varying vec4 color;
varying vec4 texcoord;

void main() {
    // color: the biome color, texture: gray texture color
    // texture * color = RealColor
    gl_FragData[0] = texture2D(texture, texcoord.st) * color;
}