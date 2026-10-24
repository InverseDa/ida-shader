#include "/lib/constant.glsl"
#include "/lib/util/functions.glsl"
#include "/lib/materials/materialData.glsl"
#include "/lib/materials/pbr.glsl"
#include "/lib/materials/wetness.glsl"
#include "/lib/post/taa.glsl"

// =============================================================================
// Fragment Shader
// =============================================================================
#ifdef FRAGMENT_SHADER

uniform sampler2D texture;
uniform sampler2D lightmap;

in vec4 Color;
in vec4 Texcoord;
in vec4 Lmcoord;
in float VertexToCameraDistance;
flat in float MaterialId;
in vec3 Normal;
in vec3 ViewPos;
#if SURFACE_WETNESS == 1
flat in vec2 WetnessProfile;
in float WetnessNormalUp;
#endif

/* RENDERTARGETS: 0,2,5,9 */
void main() {
    // color: the biome color, texture: gray texture color
    // texture * color = RealColor
    vec3 GeometryNormal = SafeNormal(Normal);
    vec4 MaterialData = WithMaterialSkyLight(GetTerrainMaterialData(MaterialId), Lmcoord.t);
#if SURFACE_WETNESS == 1 && PUDDLE_REFLECTIONS == 1
    MaterialData = WithPuddleSurface(MaterialData, WetnessNormalUp);
#endif
    PbrMaterialSample Pbr = SamplePbrMaterial(Texcoord.st, GeometryNormal, ViewPos, MaterialData);
    vec4 Base = texture2D(texture, Texcoord.st) * Color;
    vec3 Albedo = SrgbToLinear(Base.rgb);
#if SURFACE_WETNESS == 1
    // PBR/normal derivatives above stay outside weather-dependent control flow.
    if (surfaceWetness > 0.0 && WetnessProfile.x > 0.0) {
        float Amount = surfaceWetness * SURFACE_WETNESS_STRENGTH * RainExposure(Lmcoord.t, WetnessNormalUp);
        vec2 Response = WetSurfaceResponse(Pbr.MaterialData.r, Pbr.NormalVariance, WetnessProfile, Amount, GetMaterialMetallic(Pbr.MaterialData));
        Albedo *= Response.x;
        Pbr.MaterialData.r = Response.y;
    }
#endif
    gl_FragData[0] = vec4(Albedo, Base.a);
    gl_FragData[3] = vec4(SrgbToLinear(texture2D(lightmap, Lmcoord.st).rgb), 1.0);
    gl_FragData[1] = vec4(NormalEncode(Pbr.NormalView), 0.0, 1.0);
    gl_FragData[2] = Pbr.MaterialData;
}

#endif // FRAGMENT_SHADER

// =============================================================================
// Vertex Shader
// =============================================================================
#ifdef VERTEX_SHADER

uniform float frameTimeCounter;
uniform sampler2D noisetex;
uniform vec3 cameraPosition;

attribute vec4 mc_Entity;
attribute vec4 mc_midTexCoord;

out vec4 Color;
out vec4 Texcoord;
out vec4 Lmcoord;
out float VertexToCameraDistance;
flat out float MaterialId;
out vec3 Normal;
out vec3 ViewPos;
#if SURFACE_WETNESS == 1
uniform mat4 gbufferModelViewInverse;
flat out vec2 WetnessProfile;
out float WetnessNormalUp;
#endif

#include "/lib/materials/methods/foliage.glsl"

void main() {
    Color = gl_Color;
    // 0 - texcoord
    // 1 - lightmap texcoord
    Texcoord = gl_TextureMatrix[0] * gl_MultiTexCoord0;
    Lmcoord = gl_TextureMatrix[1] * gl_MultiTexCoord1;

    vec4 Position = gl_Vertex;
    MaterialId = mc_Entity.x;
    Position.xyz += FoliageOffset(Position.xyz, MaterialId, gl_MultiTexCoord0.st, mc_midTexCoord.st);

    // position in camera(steve)
    vec4 PositionInView = gl_ModelViewMatrix * Position;
    ViewPos = PositionInView.xyz;
    gl_Position = gl_ProjectionMatrix * PositionInView;
    if (MaterialUsesTaaJitter(GetTerrainMaterialData(MaterialId))) ApplyTaaJitter(gl_Position);
    // the length from object vertex to camera center
    VertexToCameraDistance = length(PositionInView.xyz);
    Normal = gl_NormalMatrix * gl_Normal;
#if SURFACE_WETNESS == 1
    WetnessProfile = GetWetnessProfile(MaterialId);
    // Geometric orientation avoids a moving wet/dry pattern from normal maps.
    WetnessNormalUp = (mat3(gbufferModelViewInverse) * SafeNormal(Normal)).y;
#endif
}

#endif // VERTEX_SHADER
