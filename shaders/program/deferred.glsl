#include "/lib/constant.glsl"
#include "/lib/util/functions.glsl"
#include "/lib/materials/materialData.glsl"
#include "/lib/lighting/frame.glsl"
#ifdef FRAGMENT_SHADER
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
uniform sampler2D colortex0;
uniform sampler2D colortex2;
uniform sampler2D colortex5;
uniform sampler2D colortex10;
in vec4 texcoord;
#include "/lib/lighting/scene.glsl"
#include "/lib/lighting/ssao.glsl"

// Reading lightmap 9 and writing raw radiance 9 uses Iris's automatic flip.
/* RENDERTARGETS: 4,10,9 */
void main() {
    vec2 uv = texcoord.st;
    float depth = texture2D(depthtex0, uv).r;
    vec3 color = texture2D(colortex0, uv).rgb;
    vec3 normal = normalDecode(texture2D(colortex2, uv).rg);
    vec4 material = texture2D(colortex5, uv);
    bool isHand = isMaterial(material, MATERIAL_ID_HAND);
    bool isSky = depth >= 0.999999;
    bool jittered = !isSky && materialUsesTaaJitter(material);
    vec3 viewPos = reconstructSurfaceViewPos(uv, depth, jittered);
    vec3 worldPos = viewToWorldPos(viewPos, gbufferModelViewInverse);
    if (!isSky && !isHand && !isMaterial(material, MATERIAL_ID_UNLIT)) {
        float ao = getScreenSpaceAmbientOcclusion(uv, viewPos, normal);
        float visibility = shadowMapping(worldPos, normal, 1.0);
        color = applySunDirectLight(color, normal, viewPos, material, visibility, ao,
                                   texture2D(colortex9, uv).rgb);
    }
    if (isSky) color = getSkyRadiance(normalize(viewPos));
    gl_FragData[0] = vec4(normalEncode(normal), isHand ? 1.0 : depth, jittered ? 2.0 : 1.0);
    // Keep marks from cracks, glint and other effects drawn before deferred.
    gl_FragData[1] = vec4(max(jittered ? 0.0 : 1.0, texture2D(colortex10, uv).r));
    gl_FragData[2] = vec4(color, 1.0);
}
#endif
#ifdef VERTEX_SHADER
out vec4 texcoord;
void main() {
    gl_Position = ftransform();
    texcoord = gl_MultiTexCoord0;
    setupFrameLighting();
}
#endif
