#version 130

uniform float frameTimeCounter;
uniform int worldTime;
uniform sampler2D noisetex;

attribute vec4 mc_Entity;
attribute vec4 mc_midTexCoord;

varying vec4 color;
varying vec4 texcoord;
varying vec4 lmcoord;
varying float vertexToCameraDistance;

void main() {
    color = gl_Color;
    // 0 - texcoord
    // 1 - lightmap texcoord
    texcoord = gl_TextureMatrix[0] * gl_MultiTexCoord0;
    lmcoord = gl_TextureMatrix[1] * gl_MultiTexCoord1;

    vec4 position =  gl_Vertex;
    float blockId = mc_Entity.x;
    if((blockId == 31.0 || blockId == 37.0 || blockId == 38.0) && mc_midTexCoord.t >= gl_MultiTexCoord0.t) {
        vec3 noise = texture2D(noisetex, texcoord.st).rgb;
        position.x += sin(frameTimeCounter * 1.8 + noise.x * 10) * 0.2;
        position.z += sin(frameTimeCounter * 1.8 + noise.y * 10) * 0.2;
    }

    // position in camera(steve)
    vec4 positionInView = gl_ModelViewMatrix * position;
    gl_Position = gl_ProjectionMatrix * positionInView;
    // the length from object vertex to camera center
    vertexToCameraDistance = length(positionInView.xyz);
}