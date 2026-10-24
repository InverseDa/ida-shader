#include "/lib/constant.glsl"
#include "/lib/util/functions.glsl"
#include "/lib/materials/materialData.glsl"

// =============================================================================
// Fragment Shader
// =============================================================================
#ifdef FRAGMENT_SHADER

uniform sampler2D texture;

in vec4 Color;
in vec4 Texcoord;
in float VertexToCameraDistance;
in vec3 Normal;

/* DRAWBUFFERS:025 */
void main() {
    // Vanilla cloud and sky geometry are replaced in composite.
    gl_FragData[0] = vec4(0.0);
    gl_FragData[1] = vec4(NormalEncode(SafeNormal(Normal)), 0.0, 1.0);
    gl_FragData[2] = GetSkyMaterialData();
}

#endif // FRAGMENT_SHADER

// =============================================================================
// Vertex Shader
// =============================================================================
#ifdef VERTEX_SHADER

out vec4 Color;
out vec4 Texcoord;
out float VertexToCameraDistance;
out vec3 Normal;

void main() {
    // position in camera(steve)
    vec4 PositionInView = gl_ModelViewMatrix * gl_Vertex;
    gl_Position = gl_ProjectionMatrix * PositionInView;
    // the length from object vertex to camera center
    VertexToCameraDistance = length(PositionInView.xyz);

    Color = gl_Color;
    Texcoord = gl_TextureMatrix[0] * gl_MultiTexCoord0;
    Normal = gl_NormalMatrix * gl_Normal;
}

#endif // VERTEX_SHADER
