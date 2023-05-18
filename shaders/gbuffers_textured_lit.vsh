#version 130

varying vec4 color;
varying vec4 texcoord;
varying vec4 lmcoord;

void main() {
    gl_Position = ftransform();
    color = gl_Color;
    // 0 - texcoord
    // 1 - lightmap texcoord
    texcoord = gl_TextureMatrix[0] * gl_MultiTexCoord0;
    lmcoord = gl_TextureMatrix[1] * gl_MultiTexCoord1;
}