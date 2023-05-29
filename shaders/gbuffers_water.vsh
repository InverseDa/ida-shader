#version 130

attribute vec4 mc_Entity;

uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;

uniform vec3 cameraPosition;

uniform int worldTime;
uniform float frameTimeCounter;

varying vec4 color;
varying vec4 texcoord;
varying vec4 litcoord;
varying float water;

vec4 bump() {
    vec4 pos = gl_Vertex;
    pos.xyz += cameraPosition;
    pos.y += 0.05 * (sin(pos.x + frameTimeCounter) + cos(pos.z + frameTimeCounter));
    pos.xyz -= cameraPosition;
    return gbufferModelView * pos;
}

void main() {
    if (mc_Entity.x == 8.0 || mc_Entity.x == 9.0) water = 1.0;
    // if (mc_Entity.x == 79.0) ice = 1.0;
    // if (mc_Entity.x == 90.0) netherPortal = 1.0;
    // if (mc_Entity.x == 95.0) stainedGlass = 1.0;
    // if (mc_Entity.x == 160.0) stainedGlassPlane = 1.0;

    vec4 positionInView = bump();
    gl_Position = gbufferProjection * positionInView;
    color = gl_Color;
    texcoord = gl_TextureMatrix[0] * gl_MultiTexCoord0;
    litcoord = gl_TextureMatrix[1] * gl_MultiTexCoord1;
}