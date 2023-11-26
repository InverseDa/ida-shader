
// ============================================================================
// ========================= Normal encode and decode =========================
// https://aras-p.info/texts/CompactNormalStorage.html
// ============================================================================
vec2 normalEncode(vec3 norm) {
    vec2 ret = normalize(norm.xy) * (sqrt(-norm.z * 0.5 + 0.5));
    ret = ret * 0.5 + 0.5;
    return ret;
}

vec3 normalDecode(vec2 enc) {
    vec4 nn = vec4(2.0 * enc - 1.0, 1.0, -1.0);
    float l = dot(nn.xyz,-nn.xyw);
    nn.z = l;
    nn.xy *= sqrt(l);
    return nn.xyz * 2.0 + vec3(0.0, 0.0, -1.0);
}

vec2 getFishEyeCoord(vec2 ndcPos) {
    return ndcPos / (0.15 + 0.85 * length(ndcPos.xy));
}

float screenDepthToLinerDepth(float near, float far, float screenDepth) {
    return 2 * near * far / ((far + near) - screenDepth * (far - near));
}