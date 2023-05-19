#version 130

varying vec4 color;
varying vec2 normal;

vec2 normalEncode(vec3 norm) {
    vec2 ret = normalize(norm.xy) * (sqrt(-norm.z * 0.5 + 0.5));
    ret = ret * 0.5 + 0.5;
    return ret;
}

void main() {
    gl_Position = ftransform();
    color = gl_Color;
    vec3 norm = gl_NormalMatrix * gl_Normal;
    normal = normalEncode(norm);
}