#ifndef IDA_LOCAL_VOXELIZE_GLSL
#define IDA_LOCAL_VOXELIZE_GLSL
#include "/lib/lighting/local_grid.glsl"
#if PLACED_LIGHTS == 1
in vec3 ShadowBlockCentre[];
flat in int ShadowBlockId[];
uniform sampler2D texture;

void StoreLocalVoxel(ivec3 V) {
    if (any(lessThan(V, ivec3(0))) || any(greaterThanEqual(V, ivec3(256)))) return;
    uint I = LocalIndex(V / 4);
    ivec3 S = V & 3;
    uint Bit = uint(S.x + 4 * S.y + 16 * S.z);
    if (Bit < 32u) atomicOr(LocalOccluders[I].x, 1u << Bit);
    else atomicOr(LocalOccluders[I].y, 1u << (Bit - 32u));
}

void CollectLocalGeometry() {
    int Id = ShadowBlockId[0];
    if (Id > 10100 && Id < 10140) {
        ivec3 Cell = ivec3(floor(LocalGridPosition(ShadowBlockCentre[0], cameraPosition)));
        if (InsideLocalGrid(Cell)) {
            atomicMax(LocalSources[LocalIndex(Cell)], uint(Id - 10100));
            atomicOr(LocalCoarse[LocalClusterIndex(Cell / 4)], 1u);
        }
        // Small luminous models must not shadow their own centre.
        // Full luminous cubes can be crossed only at the ray's final source cell.
        if ((Id - 10100) % 16 != 8) return;
    }
    if (Id == 10092 || Id == 10093 || Id == 10190) return; // water / glass / ice
#if LOCAL_LIGHT_SHADOWS == 1
    vec3 A = LocalGridPosition(ShadowWorld[0], cameraPosition) * 4.0;
    vec3 B = LocalGridPosition(ShadowWorld[1], cameraPosition) * 4.0;
    vec3 C = LocalGridPosition(ShadowWorld[2], cameraPosition) * 4.0;
    if (any(lessThan(max(A, max(B, C)), vec3(0.0))) ||
        any(greaterThan(min(A, min(B, C)), vec3(256.0)))) return;
    vec3 N = cross(B - A, C - A);
    float Area = length(N);
    if (Area < 0.00001) return;
    N /= Area;
    // Move a surface slightly inside its solid. This keeps receivers outside
    // their own occupied voxel; normals come from geometry, never normal maps.
    A -= N * 0.03; B -= N * 0.03; C -= N * 0.03;
    vec3 AbsN = abs(N);
    int Z = AbsN.x > AbsN.y ? 0 : 1;
    if (AbsN.z > AbsN[Z]) Z = 2;
    int X = (Z + 1) % 3, Y = (Z + 2) % 3;
    vec2 U = vec2(B[X] - A[X], B[Y] - A[Y]);
    vec2 V = vec2(C[X] - A[X], C[Y] - A[Y]);
    float Det = U.x * V.y - U.y * V.x;
    vec2 Db = vec2(V.y, -V.x) / Det;
    vec2 Dc = vec2(-U.y, U.x) / Det;
    vec3 Pad = vec3(abs(Db.x + Dc.x) + abs(Db.y + Dc.y),
                    abs(Db.x) + abs(Db.y), abs(Dc.x) + abs(Dc.y)) * 0.5;
    ivec2 Lo = max(ivec2(floor(min(vec2(A[X], A[Y]), min(vec2(B[X], B[Y]), vec2(C[X], C[Y]))))), ivec2(0));
    ivec2 Hi = min(ivec2(floor(max(vec2(A[X], A[Y]), max(vec2(B[X], B[Y]), vec2(C[X], C[Y]))))), ivec2(255));
    if (min(A[Z], min(B[Z], C[Z])) > 256.0 || max(A[Z], max(B[Z], C[Z])) < 0.0) return;
    for (int Yp = Lo.y; Yp <= Hi.y; ++Yp) {
        for (int Xp = Lo.x; Xp <= Hi.x; ++Xp) {
            vec2 P = vec2(Xp, Yp) + 0.5;
            vec2 Delta = P - vec2(A[X], A[Y]);
            float Wb = dot(Db, Delta), Wc = dot(Dc, Delta);
            vec3 W = vec3(1.0 - Wb - Wc, Wb, Wc);
            if (any(lessThan(W, -Pad))) continue;
            // Cutout leaves and fences keep holes at the voxel sampling scale.
            vec3 Tw = max(W, vec3(0.0)); Tw /= dot(Tw, vec3(1.0));
            vec2 Uv = ShadowTexcoord[0].st * Tw.x + ShadowTexcoord[1].st * Tw.y + ShadowTexcoord[2].st * Tw.z;
            if (textureLod(texture, Uv, 0.0).a < 0.2) continue;
            float Depth = A[Z] + Wb * (B[Z] - A[Z]) + Wc * (C[Z] - A[Z]);
            ivec3 Cell; Cell[X] = Xp; Cell[Y] = Yp; Cell[Z] = int(floor(Depth));
            StoreLocalVoxel(Cell);
        }
    }
#endif
}
#endif
#endif
