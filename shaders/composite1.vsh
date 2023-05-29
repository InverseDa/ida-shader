#version 130

uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform int worldTime;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform vec3 cameraPosition;

varying vec4 texcoord;
varying vec3 lightPosition;

void main() {
    gl_Position = ftransform();
    texcoord = gl_MultiTexCoord0;
}