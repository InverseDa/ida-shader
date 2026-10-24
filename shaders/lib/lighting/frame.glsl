#ifndef IDA_LIGHTING_FRAME_GLSL
#define IDA_LIGHTING_FRAME_GLSL

// Shared by the opaque lighting pass and forward translucent geometry.

// =============================================================================
// Fragment Shader
// =============================================================================
#ifdef FRAGMENT_SHADER

uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;
uniform sampler2DShadow shadowtex1;
uniform sampler2D colortex4;  // Packed normal/state R, full-precision depth G.
uniform sampler2D colortex9;  // Lightmap input to deferred, then immutable raw opaque radiance.
uniform sampler2D colortex11; // Immutable opaque radiance AFTER atmosphere.
uniform sampler2D noisetex;
uniform vec3 shadowLightPosition;
uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform vec3 cameraPosition;
uniform float viewWidth;
uniform float viewHeight;
uniform float far;
uniform float near;
uniform float frameTimeCounter;
uniform float rainStrength;
#include "/lib/misc/water_medium.glsl"
in vec3 SkyColor;
in vec3 SunColor;
in float NightValue;
#include "/lib/post/screen.glsl"
#endif

// =============================================================================
// Vertex Shader
// =============================================================================
#ifdef VERTEX_SHADER

uniform int worldTime;
out vec3 SkyColor;
out vec3 SunColor;
out float NightValue;
void SetupFrameLighting() {
    int Time = worldTime - (worldTime / 24000) * 24000;
    int Hour = Time / 1000;
    int Next = (Hour + 1 < 24) ? Hour + 1 : 0;
    float Delta = float(Time - Hour * 1000) / 1000.0;
    SkyColor = SrgbToLinear(mix(SkyColorArr[Hour], SkyColorArr[Next], Delta));
    SunColor = SrgbToLinear(mix(SunColorArr[Hour], SunColorArr[Next], Delta));
    NightValue = clamp((float(Time) - 12000.0) / 1000.0, 0.0, 1.0) *
                 (1.0 - clamp((float(Time) - 23000.0) / 1000.0, 0.0, 1.0));
}
#endif
#endif
