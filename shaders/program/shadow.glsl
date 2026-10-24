#include "/lib/constant.glsl"
#include "/lib/util/functions.glsl"

// =============================================================================
// Fragment Shader
// =============================================================================
#ifdef FRAGMENT_SHADER

uniform sampler2D texture;

in vec4 Texcoord;
#if SHADOW_CSM == 1
in vec2 CascadeCoord;
#endif

void main() {
#if SHADOW_CSM == 1
    // Rasterization clips to the whole atlas, not to an individual tile.
    // Discard tile overflow before ANY colour or depth write.
    if (any(greaterThan(abs(CascadeCoord), vec2(1.0)))) discard;
#endif
    gl_FragData[0] = texture2D(texture, Texcoord.st);
}

#endif // FRAGMENT_SHADER

// =============================================================================
// Vertex Shader
// =============================================================================
#ifdef VERTEX_SHADER

uniform vec3 cameraPosition;
uniform float frameTimeCounter;
uniform sampler2D noisetex;
uniform mat4 shadowModelView;
uniform mat4 shadowModelViewInverse;
attribute vec4 mc_Entity;
attribute vec4 mc_midTexCoord;
#if PLACED_LIGHTS == 1
attribute vec4 at_midBlock;
out vec3 ShadowBlockCentre;
flat out int ShadowBlockId;
#endif
#include "/lib/materials/methods/foliage.glsl"
out vec4 ShadowTexcoord;
#if SHADOW_CSM == 1 || PLACED_LIGHTS == 1
out vec3 ShadowWorld;
#endif

void main() {
    vec4 ShadowView = gl_ModelViewMatrix * gl_Vertex;
    vec3 RelativeWorld = (shadowModelViewInverse * ShadowView).xyz;
#if PLACED_LIGHTS == 1
    ShadowBlockCentre = RelativeWorld + at_midBlock.xyz / 64.0;
    ShadowBlockId = int(mc_Entity.x + 0.5);
#endif
    RelativeWorld += FoliageOffset(RelativeWorld, mc_Entity.x, gl_MultiTexCoord0.st, mc_midTexCoord.st);
    gl_Position = gl_ProjectionMatrix * shadowModelView * vec4(RelativeWorld, 1.0);
#if SHADOW_CSM == 1 || PLACED_LIGHTS == 1
    ShadowWorld = RelativeWorld;
#endif
#if SHADOW_CSM == 0
    gl_Position.xy = GetFishEyeCoord(gl_Position.xy / gl_Position.w) * gl_Position.w;
#endif
    ShadowTexcoord = gl_TextureMatrix[0] * gl_MultiTexCoord0;
}

#endif // VERTEX_SHADER

#ifdef GEOMETRY_SHADER
layout(triangles) in;
layout(triangle_strip, max_vertices = 12) out;
in vec4 ShadowTexcoord[];
out vec4 Texcoord;
#if SHADOW_CSM == 1 || PLACED_LIGHTS == 1
in vec3 ShadowWorld[];
uniform vec3 cameraPosition;
#endif
#if SHADOW_CSM == 1
out vec2 CascadeCoord;
uniform mat4 shadowModelView, shadowProjection;
uniform float far;
#include "/lib/lighting/cascades.glsl"
#endif
#include "/lib/lighting/local_voxelize.glsl"
void main() {
#if PLACED_LIGHTS == 1
    CollectLocalGeometry();
#endif
#if SHADOW_CSM == 1
    for (int C = 0; C < 4; ++C) {
        vec2 A = CascadeLocalPosition(ShadowWorld[0], C);
        vec2 B = CascadeLocalPosition(ShadowWorld[1], C);
        vec2 D = CascadeLocalPosition(ShadowWorld[2], C);
        // Conservative XY rejection: retain distant casters along the light
        // direction; never reject using their camera distance / receiver split.
        if (any(greaterThan(min(A, min(B, D)), vec2(1.0))) ||
            any(lessThan(max(A, max(B, D)), vec2(-1.0)))) continue;
        for (int V = 0; V < 3; ++V) {
            CascadeCoord = V == 0 ? A : (V == 1 ? B : D);
            gl_Position = gl_in[V].gl_Position;
            gl_Position.xy = (CascadeCoord * 0.5 + CascadeTile(C) - 0.5) * gl_Position.w;
            Texcoord = ShadowTexcoord[V];
            EmitVertex();
        }
        EndPrimitive();
    }
#else
    for (int V = 0; V < 3; ++V) {
        gl_Position = gl_in[V].gl_Position;
        Texcoord = ShadowTexcoord[V];
        EmitVertex();
    }
    EndPrimitive();
#endif
}
#endif
