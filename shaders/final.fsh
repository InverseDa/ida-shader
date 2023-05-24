#version 130

uniform sampler2D gcolor;
uniform sampler2D composite;
uniform float viewWidth;
uniform float viewHeight;

varying vec4 texcoord;

void main() {
    vec4 color = texture2D(gcolor, texcoord.st);
    vec4 bloom = texture2D(composite, texcoord.st);

    color.rgb += bloom.rgb;
    gl_FragData[0] = color;
}