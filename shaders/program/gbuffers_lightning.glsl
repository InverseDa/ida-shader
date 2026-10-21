#include "/lib/constant.glsl"
#include "/lib/util/functions.glsl"
#include "/lib/materials/materialData.glsl"
#include "/lib/lighting/frame.glsl"
#ifdef FRAGMENT_SHADER
in vec4 color;
in vec3 viewPos;
#include "/lib/materials/lighting/sky.glsl"
#include "/lib/misc/atmosphere.glsl"
/* RENDERTARGETS: 0,2,5,10 */
void main() {
    // Lightning writes geometry depth in Iris. Give that geometry matching,
    // explicitly unlit metadata instead of interpreting stale terrain normals.
    vec3 radiance = srgbToLinear(color.rgb);
    if (texelFetch(colortex4, ivec2(0), 0).a > 0.5)
        radiance = applyAtmosphere(radiance, viewPos, false);
    gl_FragData[0] = vec4(radiance, 1.0);
    gl_FragData[1] = vec4(normalEncode(vec3(0.0, 0.0, 1.0)), 0.0, 1.0);
    gl_FragData[2] = packMaterialData(1.0, 0.0, 1.0, MATERIAL_ID_UNLIT);
    // UNLIT bypasses lightmap lookup. Do not overwrite buffer 9's raw scene
    // when lightning is drawn after deferred.
    gl_FragData[3] = vec4(1.0);
}
#endif
#ifdef VERTEX_SHADER
out vec4 color;
out vec3 viewPos;
void main() {
    gl_Position = ftransform();
    viewPos = (gl_ModelViewMatrix * gl_Vertex).xyz;
    color = gl_Color;
    setupFrameLighting();
}
#endif
