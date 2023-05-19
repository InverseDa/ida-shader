#version 130

uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform int worldTime;

varying vec4 texcoord;
varying vec3 lightPosition;

void main() {
    gl_Position = ftransform();
    texcoord = gl_MultiTexCoord0;
    
}