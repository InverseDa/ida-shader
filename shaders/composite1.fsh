#version 130

const int R8 = 0;
const int colortex5Format = R8;

uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform vec3 cameraPosition;
uniform sampler2D colortex0;    //color
uniform sampler2D colortex1;    //depth(useless)
uniform sampler2D colortex2;    //normal
uniform sampler2D colortex4;    //blockId
uniform sampler2D colortex5;    //water flag
uniform sampler2D depthtex0;    //depth0
uniform sampler2D depthtex1;    //depth1
uniform int worldTime;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform float far;
uniform float near;

varying vec4 texcoord;
varying vec3 lightPosition;

vec3 normalDecode(vec2 enc) {
    vec4 nn = vec4(2.0 * enc - 1.0, 1.0, -1.0);
    float l = dot(nn.xyz,-nn.xyw);
    nn.z = l;
    nn.xy *= sqrt(l);
    return nn.xyz * 2.0 + vec3(0.0, 0.0, -1.0);
}

float linearizeDepth(float depth) {
    return (2.0 * near) / (far + near - depth * (far - near));
}

vec4 raytrace(vec3 point, vec3 dir) {
    vec3 ray = point;
    vec4 hitcolor = vec4(0.0);
    bool hit = false;
    float sampleDepth;
    int iterations = 40;
    float stepBase = 0.025;
    float alpha = 1.0;
    dir *= stepBase;

    for(int i = 0; i < iterations; i++) {
        ray += dir * pow(float(i + 1), 1.46);

        vec4 coord = gbufferProjection * vec4(ray, 1.0);
        coord.xyz /= coord.w;
        coord.xyz = coord.xyz * 0.5 + 0.5;

        if(coord.x < 0 || coord.y < 0 || coord.x > 1 || coord.y > 1) break;
        sampleDepth = texture2D(depthtex0, coord.st).r;
        // sampleDepth = linearizeDepth(sampleDepth);

        if(sampleDepth < coord.z && coord.z - sampleDepth < (1.0 / 2048.0) * (1.0 + coord.z * 200.0 + float(i))) {
            hit = true;
            hitcolor.rgb = texture2D(colortex0, coord.st).rgb;	
            hitcolor.a = clamp(1.0 - pow(distance(coord.st, vec2(0.5))*2.0, 2.0), 0.0, 1.0);
            break;
        }
    }
    return hitcolor; //淡入淡出
}

float fresnel(float cosine) {
    return 0.02 + 0.98 * pow((1.0 - cosine), 5);
}

vec3 drawWater(vec3 color, vec3 viewPos, vec3 worldPos, vec3 normal) {

    vec3 dir = reflect(normalize(viewPos), normal);
    float fresnel_value = fresnel(dot(normalize(dir), normalize(normal)));
    vec4 hitcolor = raytrace(viewPos + normal * (-viewPos.z / far * 0.2 + 0.05), dir);

    return mix(color, hitcolor.rgb, hitcolor.a * fresnel_value);
}

void main() {
    vec4 color = texture2D(colortex0, texcoord.st);
    vec3 normal = normalDecode(texture2D(colortex2, texcoord.st).rg);
    float blockId = texture2D(colortex4, texcoord.st).r;
    float depth0 = texture2D(depthtex0, texcoord.st).x; //with water
    float depth1 = texture2D(depthtex1, texcoord.st).x; //without water
    vec4 viewPos = gbufferProjectionInverse * vec4(texcoord.st * 2 - 1, depth0 * 2 - 1, 1);
    viewPos /= viewPos.w;
    vec4 worldPos = gbufferModelViewInverse * viewPos;
    worldPos.xyz += cameraPosition;
    float isWater = texture2D(colortex5, texcoord.st).r * 255.0;

    if(isWater == 1.0) {
        gl_FragData[0] = vec4(drawWater(color.rgb, viewPos.xyz, worldPos.xyz, normal), 1.0);
    }
    else
        gl_FragData[0] = color;

}