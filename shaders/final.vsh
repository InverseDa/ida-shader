#version 130

varying vec4 texcoord;

void main() {
    gl_Position = ftransform();
    texcoord = gl_MultiTexCoord0;
}