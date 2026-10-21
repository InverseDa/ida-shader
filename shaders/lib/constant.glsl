// =========================== Macros ===========================
#define SHADOW_MAP_BIAS 0.85
#define SUNRISE         23200
#define SUNSET          12800
#define FADE_START      500
#define FADE_END        250
// BLOCKS AND ITEM
#define WATER_FLAG vec4(0.0, 0.0, 1.0, 1.0)
// =========================== Constant ===========================
const int noiseTextureResolution = 256;
const int shadowMapResolution = 2048;   // 阴影分辨率 默认 1024
const float	sunPathRotation	= 0.0;      // 太阳偏移角 默认 0
const int RGB16F = 0;
const int colortex0Format = RGB16F;
const int R16F = 0;
const int colortex3Format = R16F;
// Effect view depth only. TAA reuses colortex0's ping-pong pair.
const vec4 colortex3ClearColor = vec4(65504.0, 0.0, 0.0, 0.0);
const int R11F_G11F_B10F = 0;
const int colortex6Format = R11F_G11F_B10F;
const int colortex7Format = R11F_G11F_B10F;
const int RG32F = 0;
const int RGBA16F = 0;
const int colortex1Format = RGBA16F;
const vec4 colortex1ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
const int RG16 = 0;
const int colortex8Format = RGBA16F;
const int colortex2Format = RG16;
const int colortex4Format = RG32F;
// R=0 before deferred; signed packed normal afterwards. G=FP32 hardware depth.
const bool colortex4Clear = true;
const vec4 colortex4ClearColor = vec4(0.0, 1.0, 0.0, 0.0);
const int colortex9Format = RGB16F;
// Lightmap before deferred; raw opaque radiance afterwards (automatic flip).
const bool colortex9Clear = true;
const int R8 = 0;
const int colortex10Format = R8;
const int colortex11Format = RGB16F;
// Full-screen producers overwrite these before the first read each frame.
// Keep clears on partial geometry targets and colortex4's readiness flag.
const bool colortex6Clear = false;
const bool colortex7Clear = false;
const bool colortex11Clear = false;
const vec4 colortex10ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
const bool colortex8Clear = false;
// Iris 1.8.x directive parsing requires four explicit components.
const vec4 colortex8ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
const vec4 colortex5ClearColor = vec4(0.82, 0.02, 1.0, 0.0);
// =========================== other values ===========================
vec3 skyColorArr[] = vec3[24](vec3(0.46, 0.63, 0.78), // 0-1000
                              vec3(0.46, 0.63, 0.78), // 1000 - 2000
                              vec3(0.46, 0.63, 0.78), // 2000 - 3000
                              vec3(0.46, 0.63, 0.78), // 3000 - 4000
                              vec3(0.46, 0.63, 0.78), // 4000 - 5000
                              vec3(0.46, 0.63, 0.78), // 5000 - 6000
                              vec3(0.46, 0.63, 0.78), // 6000 - 7000
                              vec3(0.46, 0.63, 0.78), // 7000 - 8000
                              vec3(0.46, 0.63, 0.78), // 8000 - 9000
                              vec3(0.46, 0.63, 0.78), // 9000 - 10000
                              vec3(0.46, 0.63, 0.78), // 10000 - 11000
                              vec3(0.46, 0.63, 0.78), // 11000 - 12000
                              vec3(0.46, 0.63, 0.78), // 12000 - 13000
                              vec3(0.02, 0.2, 0.27), // 13000 - 14000
                              vec3(0.02, 0.2, 0.27), // 14000 - 15000
                              vec3(0.02, 0.2, 0.27), // 15000 - 16000
                              vec3(0.02, 0.2, 0.27), // 16000 - 17000
                              vec3(0.02, 0.2, 0.27), // 17000 - 18000
                              vec3(0.02, 0.2, 0.27), // 18000 - 19000
                              vec3(0.02, 0.2, 0.27), // 19000 - 20000
                              vec3(0.02, 0.2, 0.27), // 20000 - 21000
                              vec3(0.02, 0.2, 0.27), // 21000 - 22000
                              vec3(0.02, 0.2, 0.27), // 22000 - 23000
                              vec3(0.02, 0.2, 0.27)  // 23000 - 24000(0)
);

vec3 sunColorArr[] = vec3[24](vec3(2, 2, 1),       // 0-1000
                              vec3(2, 1.5, 1),     // 1000 - 2000
                              vec3(1, 1, 1),       // 2000 - 3000
                              vec3(1, 1, 1),       // 3000 - 4000
                              vec3(1, 1, 1),       // 4000 - 5000
                              vec3(1, 1, 1),       // 5000 - 6000
                              vec3(1, 1, 1),       // 6000 - 7000
                              vec3(1, 1, 1),       // 7000 - 8000
                              vec3(1, 1, 1),       // 8000 - 9000
                              vec3(1, 1, 1),       // 9000 - 10000
                              vec3(1, 1, 1),       // 10000 - 11000
                              vec3(1, 1, 1),       // 11000 - 12000
                              vec3(2, 1.5, 0.5),   // 12000 - 13000
                              vec3(0.3, 0.5, 0.9), // 13000 - 14000
                              vec3(0.3, 0.5, 0.9), // 14000 - 15000
                              vec3(0.3, 0.5, 0.9), // 15000 - 16000
                              vec3(0.3, 0.5, 0.9), // 16000 - 17000
                              vec3(0.3, 0.5, 0.9), // 17000 - 18000
                              vec3(0.3, 0.5, 0.9), // 18000 - 19000
                              vec3(0.3, 0.5, 0.9), // 19000 - 20000
                              vec3(0.3, 0.5, 0.9), // 20000 - 21000
                              vec3(0.3, 0.5, 0.9), // 21000 - 22000
                              vec3(0.3, 0.5, 0.9), // 22000 - 23000
                              vec3(0.3, 0.5, 0.9)  // 23000 - 24000(0)
);
