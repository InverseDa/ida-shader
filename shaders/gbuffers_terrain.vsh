#version 130

uniform float frameTimeCounter;
uniform int worldTime;
uniform sampler2D noisetex;
uniform vec3 cameraPosition;

attribute vec4 mc_Entity;
attribute vec4 mc_midTexCoord;

varying vec4 color;
varying vec4 texcoord;
varying vec4 lmcoord;
varying float vertexToCameraDistance;
varying vec2 normal;
varying float blockId;

vec2 normalEncode(vec3 norm) {
    vec2 ret = normalize(norm.xy) * (sqrt(-norm.z * 0.5 + 0.5));
    ret = ret * 0.5 + 0.5;
    return ret;
}

void main() {
    color = gl_Color;
    // 0 - texcoord
    // 1 - lightmap texcoord
    texcoord = gl_TextureMatrix[0] * gl_MultiTexCoord0;
    lmcoord = gl_TextureMatrix[1] * gl_MultiTexCoord1;

    vec3 norm = gl_NormalMatrix * gl_Normal;
    normal = normalEncode(norm);

    vec4 position = gl_Vertex;
    position.xyz += cameraPosition;
    float id = mc_Entity.x;
    if((id == 10091) && mc_midTexCoord.t >= gl_MultiTexCoord0.t) {
        vec3 noise = texture2D(noisetex, position.xz / 256.0).rgb;
        position.x += sin(frameTimeCounter * 1.8 + noise.x * 10) * 0.2;
        position.z += sin(frameTimeCounter * 1.8 + noise.y * 10) * 0.2;
    }
    position.xyz -= cameraPosition;

    blockId = id;
    // position in camera(steve)
    vec4 positionInView = gl_ModelViewMatrix * position;
    gl_Position = gl_ProjectionMatrix * positionInView;
    // the length from object vertex to camera center
    vertexToCameraDistance = length(positionInView.xyz);
}