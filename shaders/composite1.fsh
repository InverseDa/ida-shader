#version 130
/* DRAWBUFFERS:03 */

uniform sampler2D gcolor;
uniform sampler2D composite;
uniform float viewWidth;
uniform float viewHeight;

varying vec4 texcoord;

vec3 bloomColumn() {
    int radius = 15;
    vec3 sum = texture2D(composite, texcoord.st).rgb;
    for(int i = 1; i < radius; i++) {
        vec2 offset = vec2(i / viewWidth, 0);
        sum += texture2D(composite, texcoord.st + offset).rgb;
        sum += texture2D(composite, texcoord.st - offset).rgb;
    }
    sum /= (2 * radius + 1);
    return sum;
}

void main() {
    vec4 color = texture2D(gcolor, texcoord.st);
    gl_FragData[0] = color;
    gl_FragData[1] = vec4(bloomColumn(), 1.0);
}