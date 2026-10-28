#version 430 compatibility

// ---- Gbuffers Particles Translucent ----

// Shader Stage
#define VERTEX_SHADER

// Program Configuration
#define OVERWORLD
#define PARTICLE
#define FORWARD_TRANSLUCENT
#include "/program/gbuffers_entities.glsl"
