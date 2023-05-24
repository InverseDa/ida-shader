#version 130

uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform sampler2D colortex0;
uniform int worldTime;

varying vec4 texcoord;
varying vec3 lightPosition;

void main() {
    vec4 color = texture2D(colortex0, texcoord.st);
    // vec4 waterColor = texture2D(colortex5, texcoord.st);
    gl_FragData[0] = color;
    
}