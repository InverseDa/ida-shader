#version 130
/* DRAWBUFFERS:0 */
uniform sampler2D texture;
uniform sampler2D lightmap;
uniform int fogMode;

varying vec4 color;
varying vec4 texcoord;
varying vec4 litcoord;
varying float water;

void main() {
    vec4 resColor = texture2D(lightmap, litcoord.st) * texture2D(texture, texcoord.st) * color;
    // if(water > 0.9)
        gl_FragData[0] = vec4(0.1, 0.2, 0.4, 0.5);
    // else
    //     gl_FragData[0] = resColor;
}