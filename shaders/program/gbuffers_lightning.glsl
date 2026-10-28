#include "/lib/constant.glsl"
#include "/lib/util/functions.glsl"
#include "/lib/materials/materialData.glsl"
#include "/lib/lighting/frame.glsl"

// ---- Fragment Shader ----

#ifdef FRAGMENT_SHADER

in vec4 Color;
in vec3 ViewPos;
#include "/lib/materials/lighting/sky.glsl"
#include "/lib/misc/atmosphere.glsl"
/* RENDERTARGETS: 0,2,5,10 */
void main()
{
    // Lightning writes geometry depth in Iris. Give that geometry matching,
    // explicitly unlit metadata instead of interpreting stale terrain normals.
    vec3 Radiance = SrgbToLinear(Color.rgb);

    if (OpaqueSnapshotReady())
    {
        Radiance = ApplyAtmosphere(Radiance, ViewPos, false);
    }

    gl_FragData[0] = vec4(Radiance, 1.0);

    gl_FragData[1] = vec4(NormalEncode(vec3(0.0, 0.0, 1.0)), NormalEncode(vec3(0.0, 0.0, 1.0)));

    gl_FragData[2] = PackMaterialData(1.0, 0.0, 1.0, MaterialIdUnlit);

    // UNLIT bypasses lightmap lookup. Do not overwrite buffer 9's raw scene
    // when lightning is drawn after deferred.
    gl_FragData[3] = vec4(1.0);
}

#endif // FRAGMENT_SHADER

// ---- Vertex Shader ----

#ifdef VERTEX_SHADER

out vec4 Color;
out vec3 ViewPos;

void main()
{
    gl_Position = ftransform();
    ViewPos = (gl_ModelViewMatrix * gl_Vertex).xyz;
    Color = gl_Color;
    SetupFrameLighting();
}

#endif // VERTEX_SHADER
