#version 130
/* DRAWBUFFERS:025 */

uniform sampler2D texture;
uniform int fogMode;
varying vec2 normal;

varying vec4 color;
varying vec4 texcoord;
varying float vertexToCameraDistance;

void main() {
    // color: the biome color, texture: gray texture color
    // texture * color = RealColor
    gl_FragData[0] = texture2D(texture, texcoord.st) * color;
    gl_FragData[1] = vec4(normal, 0.0, 1.0);
    gl_FragData[2] = vec4(2.0 / 255.0, 0.0, 0.0, 1.0);
    // 9729 - linear fog
    // 2048 - exp fog
    if(fogMode == 9729)
        gl_FragData[0].rgb = mix(gl_Fog.color.rgb, gl_FragData[0].rgb,
                             clamp((gl_Fog.end - vertexToCameraDistance) / (gl_Fog.end - gl_Fog.start), 0.0, 1.0));
    else if(fogMode == 2048) {
        gl_FragData[0].rgb = mix(gl_Fog.color.rgb, gl_FragData[0].rgb, 
                                 clamp(exp(-vertexToCameraDistance * gl_Fog.density), 0.0, 1.0));
    } 
}