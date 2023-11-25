
// ============================================================================
// ========================= Normal encode and decode =========================
// https://aras-p.info/texts/CompactNormalStorage.html
// ============================================================================
#ifdef VERTEX_SHADER
    vec2 normalEncode(vec3 norm) {
        vec2 ret = normalize(norm.xy) * (sqrt(-norm.z * 0.5 + 0.5));
        ret = ret * 0.5 + 0.5;
        return ret;
    }
#endif

vec3 normalDecode(vec2 enc) {
    vec4 nn = vec4(2.0 * enc - 1.0, 1.0, -1.0);
    float l = dot(nn.xyz,-nn.xyw);
    nn.z = l;
    nn.xy *= sqrt(l);
    return nn.xyz * 2.0 + vec3(0.0, 0.0, -1.0);
}