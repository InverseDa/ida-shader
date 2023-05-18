#version 130

varying vec4 color;
varying vec4 texcoord;

void main() {
    // position in camera(steve)
    vec4 positionInView = gl_ModelViewMatrix * gl_Vertex;
    gl_Position = gl_ProjectionMatrix * positionInView;

    color = gl_Color;
    texcoord = gl_TextureMatrix[0] * gl_MultiTexCoord0;
}