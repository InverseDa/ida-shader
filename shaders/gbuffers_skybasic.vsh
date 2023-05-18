#version 130

varying vec4 color;
varying vec4 texcoord;
varying float vertexToCameraDistance;

void main() {
    // position in camera(steve)
    vec4 positionInView = gl_ModelViewMatrix * gl_Vertex;
    gl_Position = gl_ProjectionMatrix * positionInView;
    // the length from object vertex to camera center
    vertexToCameraDistance = length(positionInView.xyz);

    color = gl_Color;
    texcoord = gl_TextureMatrix[0] * gl_MultiTexCoord0;
}