#ifndef IDA_RENDER_STAGE_GLSL
#define IDA_RENDER_STAGE_GLSL

// ---- Render Stage ----

uniform int renderStage;

bool IsHandStage()
{
#if defined(MC_RENDER_STAGE_HAND_SOLID) && defined(MC_RENDER_STAGE_HAND_TRANSLUCENT)
    return renderStage == MC_RENDER_STAGE_HAND_SOLID || renderStage == MC_RENDER_STAGE_HAND_TRANSLUCENT;
#else
    return false;
#endif
}

bool IsOutlineStage()
{
#ifdef MC_RENDER_STAGE_OUTLINE
    return renderStage == MC_RENDER_STAGE_OUTLINE;
#else
    return false;
#endif
}
#endif
