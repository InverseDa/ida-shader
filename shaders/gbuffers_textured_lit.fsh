#version 130

uniform sampler2D texture;
uniform sampler2D lightmap;
uniform int fogMode;

varying vec4 color;
varying vec4 texcoord;
varying vec4 lmcoord;
varying float vertexToCameraDistance;

void main() {
    // color: the biome color, texture: gray texture color
    // texture * color = RealColor
    gl_FragData[0] = texture2D(texture, texcoord.st) * texture2D(lightmap, lmcoord.st) * color;
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