#version 130
/* DRAWBUFFERS:025 */
uniform sampler2D texture;
uniform sampler2D lightmap;
uniform int fogMode;

varying vec4 color;
varying vec4 texcoord;
varying vec4 litcoord;
varying float water;
varying vec2 normal;

void main() {
    vec4 resColor = texture2D(lightmap, litcoord.st) * texture2D(texture, texcoord.st) * color;
    if(water > 0.99)
        gl_FragData[0] = vec4(0.1, 0.2, 0.4, 0.5);
    else
        gl_FragData[0] = resColor;
    gl_FragData[1] = vec4(normal, 0.0, 1.0);
    gl_FragData[2] = vec4(water / 255.0, 0.0, 0.0, 1.0);
}