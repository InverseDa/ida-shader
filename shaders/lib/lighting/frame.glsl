#ifndef IDA_LIGHTING_FRAME_GLSL
#define IDA_LIGHTING_FRAME_GLSL

// Shared by the opaque lighting pass and forward translucent geometry.
#ifdef FRAGMENT_SHADER
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;
uniform sampler2D shadowtex1;
uniform sampler2D colortex4;  // Opaque normal RG, depth B, ready/jitter code A (0/1/2).
uniform sampler2D colortex9; // Lightmap input to deferred, then immutable raw opaque radiance.
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
in vec3 skyColor;
in vec3 sunColor;
in float nightValue;
#include "/lib/post/screen.glsl"
#endif

#ifdef VERTEX_SHADER
uniform int worldTime;
out vec3 skyColor;
out vec3 sunColor;
out float nightValue;
void setupFrameLighting() {
    int time = worldTime - (worldTime / 24000) * 24000;
    int hour = time / 1000;
    int next = (hour + 1 < 24) ? hour + 1 : 0;
    float delta = float(time - hour * 1000) / 1000.0;
    skyColor = srgbToLinear(mix(skyColorArr[hour], skyColorArr[next], delta));
    sunColor = srgbToLinear(mix(sunColorArr[hour], sunColorArr[next], delta));
    nightValue = clamp((float(time) - 12000.0) / 1000.0, 0.0, 1.0) *
                 (1.0 - clamp((float(time) - 23000.0) / 1000.0, 0.0, 1.0));
}
#endif
#endif
