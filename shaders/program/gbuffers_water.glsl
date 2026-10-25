#include "/lib/constant.glsl"
#include "/lib/util/functions.glsl"
#include "/lib/materials/materialData.glsl"
#include "/lib/materials/pbr.glsl"
#include "/lib/lighting/frame.glsl"

// =============================================================================
// Fragment Shader
// =============================================================================
#ifdef FRAGMENT_SHADER

uniform sampler2D texture;
uniform sampler2D lightmap;
flat in int Mat;
in vec4 Color;
in vec4 Texcoord;
in vec4 Lmcoord;
in vec3 Normal;
in vec4 ViewPos;
in vec3 WaterRestWorld;
in float WaterWaveMask;
#include "/lib/lighting/scene.glsl"
#include "/lib/misc/atmosphere.glsl"
#define IDA_WATER_SURFACE_PASS
#define IDA_REFLECTION_HISTORY_WRITE
#include "/lib/materials/translucents/water.glsl"
#include "/lib/materials/translucents/composition.glsl"

#if SSR_TEMPORAL == 1
/* RENDERTARGETS: 0,10,1,3,15 */
#else
/* RENDERTARGETS: 0,10 */
#endif
void main() {
    vec2 ScreenUv = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
    vec4 Base = texture2D(texture, Texcoord.st) * Color;
    vec4 Material = WithMaterialSkyLight(GetTranslucentMaterialData(float(Mat)), Lmcoord.t);
    vec3 SurfaceNormal = SafeNormal(Normal);
    vec3 WorldPos = ViewToWorldPos(ViewPos.xyz, gbufferModelViewInverse);
    // Explicit gradients remain valid inside material / refraction branches.
    vec2 Dpdx = dFdx(WaterRestWorld.xz);
    vec2 Dpdy = dFdy(WaterRestWorld.xz);
    float ViewVariance = SpecularNormalVariance(SafeNormal(ViewPos.xyz));
    vec3 Shaded;
    float Alpha = Base.a;
    if (IsWaterEntityId(float(Mat))) {
        if (Base.a <= 0.001) discard;
        float Transmission;
        if (isEyeInWater == 1) {
            Shaded = DrawUnderwaterSurface(WorldPos, ViewPos.xyz, SurfaceNormal, Dpdx, Dpdy, ScreenUv, gl_FragCoord.z, Transmission);
        } else {
            vec2 OpaqueUv = OpaqueUvForUnjitteredUv(ScreenUv);
            vec4 Opaque = SampleOpaqueData(OpaqueUv);
            vec3 Behind = ReconstructOpaqueViewPos(OpaqueUv, Opaque);
            vec3 WaterLight = SrgbToLinear(texture2D(lightmap, Lmcoord.st).rgb);
            Shaded = DrawWater(Color.rgb, WorldPos, ViewPos.xyz, Behind, SurfaceNormal, Dpdx, Dpdy, ViewVariance, ScreenUv, gl_FragCoord.z, Opaque, Lmcoord.st, WaterLight, Transmission);
        }
        Shaded = ApplyAtmosphere(Shaded, ViewPos.xyz, false);
#if SSR_HALF_RES == 1 && SSR_TEMPORAL == 1
        if (ReflectionSurfaceWrite.z < 0.0) ReflectionHitWrite.r *= CameraMediumTransmittance(ViewPos.xyz).r;
#endif
        // The modeled ray includes the opaque background. Factor it out before
        // alpha blending, preserving transparent contributions already drawn.
        vec4 Layer = MakeRefractiveLayer(Shaded, texture2D(colortex11, ScreenUv).rgb, Transmission);
        Shaded = Layer.rgb;
        Alpha = Layer.a;
    } else {
        PbrMaterialSample Pbr = SamplePbrMaterial(Texcoord.st, SurfaceNormal, ViewPos.xyz, Material);
        if (Base.a <= 0.001) discard;
        float TransmissionVisibility;
        vec3 ShadowNormal = Pbr.NormalView;
#if SHADOW_RECEIVER_PLANE == 1
        ShadowNormal = SurfaceNormal;
#endif
        float Visibility = ShadowMapping(WorldPos, ShadowNormal, 1.0, TransmissionVisibility);
        Shaded = ApplySunDirectLight(SrgbToLinear(Base.rgb), Pbr.NormalView, ViewPos.xyz, WorldPos, Pbr.MaterialData, Visibility, TransmissionVisibility, 1.0, SampleLocalSurfaceLightmap(lightmap, Lmcoord.st, ViewPos.xyz), SurfaceNormal);
        if (isEyeInWater != 1 && IsIceEntityId(float(Mat)))
            Shaded = DrawIce(Shaded, WorldPos, ViewPos.xyz, Pbr.NormalView, Pbr.NormalVariance, ViewVariance);
        Shaded = ApplyAtmosphere(Shaded, ViewPos.xyz, false);
    }
    gl_FragData[0] = vec4(Shaded, Alpha);
    // Additive R8 mask: later transparent layers cannot erase earlier coverage.
    gl_FragData[1] = vec4(max(Alpha, 1.0 / 255.0));
#if SSR_TEMPORAL == 1
    gl_FragData[2] = ReflectionColorWrite;
    gl_FragData[3] = ReflectionSurfaceWrite;
    gl_FragData[4] = vec4(ReflectionHitWrite.r, 1.0, 0.0, 0.0);
#endif
}

#endif // FRAGMENT_SHADER

// =============================================================================
// Vertex Shader
// =============================================================================
#ifdef VERTEX_SHADER

uniform mat4 gbufferProjection;
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform vec3 cameraPosition;
uniform float frameTimeCounter;
#include "/lib/materials/translucents/water_noise.glsl"
#include "/lib/misc/water_surface_cache.glsl"

in vec4 mc_Entity;

// `flat` used to disable interpolation
flat out int Mat;

out vec4 Color;
out vec4 Texcoord;
out vec4 Lmcoord;
out vec3 Normal;
out vec4 ViewPos;
out vec3 WaterRestWorld;
out float WaterWaveMask;

void main() {
    Mat = int(mc_Entity.x);
    // Honor the draw's model transform, then displace in world coordinates.
    ViewPos = gl_ModelViewMatrix * gl_Vertex;
    WaterRestWorld = (gbufferModelViewInverse * ViewPos).xyz;
    WaterWaveMask = 0.0;
    if (IsWaterEntityId(float(Mat))) {
        vec3 Absolute = WaterRestWorld + cameraPosition;
        WaterWaveMask = WaterVertexWaveMask(Absolute,1.0);
        float Offset = WaterVertexOffset(Absolute.xz)*WaterWaveMask*WaterShoreWaveMask(WaterRestWorld);
        Offset *= smoothstep(0.1,0.8,(gl_TextureMatrix[1]*gl_MultiTexCoord1).t);
        ViewPos.xyz += mat3(gbufferModelView)*vec3(0.0,Offset,0.0);
    }
    Color = gl_Color;
    Normal = gl_NormalMatrix * gl_Normal;
    gl_Position = gbufferProjection * ViewPos;
    SetupFrameLighting();
    // texture uv
    Texcoord = gl_TextureMatrix[0] * gl_MultiTexCoord0;
    Lmcoord = gl_TextureMatrix[1] * gl_MultiTexCoord1;
}

#endif // VERTEX_SHADER
