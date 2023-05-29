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
varying vec2 normal;

vec4 bump() {
    vec4 pos = gl_Vertex;
    pos.xyz += cameraPosition;
    pos.y += 0.05 * (sin(pos.x + frameTimeCounter) + cos(pos.z + frameTimeCounter));
    pos.xyz -= cameraPosition;
    return gbufferModelView * pos;
}

vec2 normalEncode(vec3 norm) {
    vec2 ret = normalize(norm.xy) * (sqrt(-norm.z * 0.5 + 0.5));
    ret = ret * 0.5 + 0.5;
    return ret;
}

void main() {
    vec4 positionInView;
    
    if (gl_Normal.y > -0.9 && mc_Entity.x == 10092.0) {
        water = 1.0;
        positionInView = bump();
    }
    else {
        positionInView = gbufferModelView * gl_Vertex;
        water = 0.0;
    }
    // if (mc_Entity.x == 79.0) ice = 1.0;
    // if (mc_Entity.x == 90.0) netherPortal = 1.0;
    // if (mc_Entity.x == 95.0) stainedGlass = 1.0;
    // if (mc_Entity.x == 160.0) stainedGlassPlane = 1.0;
    color = gl_Color;
    normal = normalEncode(gl_NormalMatrix * gl_Normal);
    gl_Position = gbufferProjection * positionInView;
    texcoord = gl_TextureMatrix[0] * gl_MultiTexCoord0;
    litcoord = gl_TextureMatrix[1] * gl_MultiTexCoord1;
}