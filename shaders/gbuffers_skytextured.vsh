#version 130

varying vec4 color;
varying vec4 texcoord;
varying vec2 normal;

vec2 normalEncode(vec3 norm) {
    vec2 ret = normalize(norm.xy) * (sqrt(-norm.z * 0.5 + 0.5));
    ret = ret * 0.5 + 0.5;
    return ret;
}

void main() {
    // position in camera(steve)
    vec4 positionInView = gl_ModelViewMatrix * gl_Vertex;
    gl_Position = gl_ProjectionMatrix * positionInView;

    color = gl_Color;
    texcoord = gl_TextureMatrix[0] * gl_MultiTexCoord0;
    
    vec3 norm = gl_NormalMatrix * gl_Normal;
    normal = normalEncode(norm);
}