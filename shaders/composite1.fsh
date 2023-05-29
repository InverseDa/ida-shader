#version 130

uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform vec3 cameraPosition;
uniform sampler2D colortex0;    //color
uniform sampler2D colortex1;    //depth
uniform sampler2D colortex2;    //normal
uniform sampler2D colortex4;    //blockId
uniform sampler2D depthtex0;    //depth0
uniform sampler2D depthtex1;    //depth1
uniform int worldTime;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;

varying vec4 texcoord;
varying vec3 lightPosition;

vec3 normalDecode(vec2 enc) {
    vec4 nn = vec4(2.0 * enc - 1.0, 1.0, -1.0);
    float l = dot(nn.xyz,-nn.xyw);
    nn.z = l;
    nn.xy *= sqrt(l);
    return nn.xyz * 2.0 + vec3(0.0, 0.0, -1.0);
}

bool rayIsOutOfScreen(vec3 ray) {
    return (ray.x > 1 || ray.y > 1 || ray.x < 0 || ray.y < 0);
}

vec3 raytrace(vec3 point, vec3 dir) {
    vec3 ray = point;
    vec3 hitcolor = vec3(0.0);
    bool hit = false;
    float sampleDepth;

    for(int i = 0; i < 20; i++) {
        ray += dir * 0.2;

        vec4 coord = gbufferProjection * vec4(ray, 1.0);
        coord.xyz /= coord.w;
        coord.xyz = coord.xyz * 0.5 + 0.5;

        if(rayIsOutOfScreen(coord.xyz)) break;
        sampleDepth = texture2D(depthtex0, coord.st).r;

        if(i == 24 || sampleDepth < coord.z) {
            hit = true;
            hitcolor = texture2D(colortex0, coord.st).rgb;
            break;
        }
    }
    return hitcolor;
}

void main() {
    vec4 color = texture2D(colortex0, texcoord.st);
    vec3 normal = normalDecode(texture2D(colortex2, texcoord.st).rg);
    float blockId = texture2D(colortex4, texcoord.st).r;
    float depth0 = texture2D(depthtex0, texcoord.st).x; //with water
    float depth1 = texture2D(depthtex1, texcoord.st).x; //without water
    vec4 viewPos = vec4(texcoord.st * 2 - 1, depth0 * 2 - 1, 1);
    viewPos = gbufferProjectionInverse * viewPos;
    vec4 worldPos = gbufferModelViewInverse * viewPos;
    worldPos.xyz += cameraPosition;

    // if(depth0 != depth1) {
    //     vec3 dir = reflect(viewPos.xyz, normal);
    //     vec3 hitcolor = raytrace(viewPos.xyz, dir);
    //     gl_FragData[0] = color + vec4(hitcolor, 1.0);
    // }
    // else 
        gl_FragData[0] = color;

}