#include "/lib/constant.glsl"
#include "/lib/util/functions.glsl"
#include "/lib/materials/materialData.glsl"
#include "/lib/lighting/frame.glsl"

#ifdef FRAGMENT_SHADER
uniform sampler2D colortex5;
in vec4 Texcoord;
vec2 AtmospherePixel;
#define IDA_ATMOSPHERE_PIXEL AtmospherePixel
#include "/lib/materials/lighting/sky.glsl"
#include "/lib/misc/atmosphere.glsl"
#include "/lib/misc/atmosphere_sampling.glsl"

/* RENDERTARGETS: 6 */
void main() {
    gl_FragData[0] = vec4(0.0);
#if ATMOSPHERE_HALF_RES == 1
    // The submerged camera keeps its full-resolution water-medium path.
    if (isEyeInWater != 0) discard;
    ivec2 Size = textureSize(colortex4, 0);
    vec2 CacheSize = AtmosphereCacheSize();
    vec2 Uv = clamp(Texcoord.st + AtmosphereJitter() / CacheSize, 0.5 / vec2(Size), 1.0 - 0.5 / vec2(Size));
    ivec2 Pixel = clamp(ivec2(Uv * vec2(Size)), ivec2(0), Size - 1);
    AtmospherePixel = vec2(Pixel) + 0.5;
    if (IsMaterial(FetchMaterialData(colortex5, Uv), MaterialIdHand)) return;
    vec4 Snapshot = FetchOpaqueData(Pixel);
    bool IsSky = Snapshot.b >= 0.999999;
    vec3 ViewPos = ReconstructOpaqueViewPos(Uv, Snapshot);
    vec3 RayDir = SafeNormal(ViewToWorldNormal(SafeNormal(ViewPos), gbufferModelViewInverse));
    gl_FragData[0] = AirScattering(cameraPosition, RayDir, IsSky ? CloudMaxDistance : length(ViewPos));
#endif
}
#endif

#ifdef VERTEX_SHADER
out vec4 Texcoord;
uniform int isEyeInWater;
void main() {
    // Skip rasterization altogether when the air cache has no consumer.
#if ATMOSPHERE_HALF_RES == 1
    gl_Position = isEyeInWater == 0 ? ftransform() : vec4(2.0, 2.0, 2.0, 1.0);
#else
    // The same-name compute producer can still be enabled for transparent
    // volumes. A disabled opaque cache must not draw over shared scratch.
    gl_Position = vec4(2.0, 2.0, 2.0, 1.0);
#endif
    Texcoord = gl_MultiTexCoord0;
    SetupFrameLighting();
}
#endif
