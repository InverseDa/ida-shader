#ifndef IDA_REFLECTION_ENVIRONMENT_GLSL
#define IDA_REFLECTION_ENVIRONMENT_GLSL
#include "/lib/settings.glsl"
#include "/lib/misc/atmosphere.glsl"

vec4 SampleReflectionEnvironment(vec3 Sky, vec3 RelativeWorld, vec3 ViewDirection) {
#if REFLECTION_CLOUDS == 1
    vec3 DirectionWorld = ViewToWorldNormal(normalize(ViewDirection), gbufferModelViewInverse);
    vec3 Origin = cameraPosition + RelativeWorld;
    vec2 Interval = CloudRayInterval(Origin, DirectionWorld, CloudMaxDistance);
    float Travel = Interval.y - Interval.x;
    if (Travel <= 0.0) return vec4(Sky, 1.0);
    // A continuous column approximation avoids the fixed 12-slice reflection
    // pattern at grazing angles. Share weather/wind/density with the sky, but
    // spend at most three noise reads instead of a second volume march per pixel.
    float Distance = (Interval.x + Interval.y) * 0.5;
    // Decide invisible columns before density/noise and cloud lighting. These
    // are the same exact-zero fades previously multiplied into alpha below.
    float Visibility = CloudDistanceWeight(Distance) * smoothstep(0.015, 0.12, abs(DirectionWorld.y));
    if (Visibility <= 0.0) return vec4(Sky, 1.0);
    vec3 Position = Origin + DirectionWorld * Distance;
    float PixelAngle = 2.0 / max(abs(gbufferProjection[1].y) * viewHeight, 1.0);
    vec2 Footprint = max(Travel * vec2(length(DirectionWorld.xz), abs(DirectionWorld.y)) * 0.5,
                         vec2(Distance * PixelAngle));
    float Coverage = SampleStyledCloudCoverage(Position, Footprint, false);
    if (Coverage <= 0.0) return vec4(Sky, 1.0);
    float Column = GetCloudHeightDensity(Position.y) * Travel;
    if (abs(DirectionWorld.y) > 0.000001)
        Column = abs(CloudColumnLengthAbove(Origin.y + DirectionWorld.y * Interval.x) -
                     CloudColumnLengthAbove(Origin.y + DirectionWorld.y * Interval.y)) / abs(DirectionWorld.y);
    float Alpha = 1.0 - exp(-Coverage * Column * CloudExtinction);
    // Long grazing paths cannot resolve a single column. Fade the approximation
    // into the sky, instead of stretching its texture into horizontal bands.
    Alpha *= Visibility;
    vec3 LightDir = ViewToWorldNormal(normalize(shadowLightPosition), gbufferModelViewInverse);
    vec3 Light = GetDirectionalLightRadiance(SunColor, NightValue) *
                 DirectionalHeightStrength(LightDir.y, NightValue) * WeatherDirectFactor(rainStrength);
    Light *= 0.80 + 0.45 * pow(max(dot(DirectionWorld, LightDir), 0.0), 4.0);
    float Luma = dot(SkyColor, vec3(0.2126, 0.7152, 0.0722));
    vec3 Ambient = mix(vec3(Luma), SkyColor, 0.35) * mix(0.65, 0.40, NightValue) * mix(1.0, 0.75, rainStrength);
    vec3 CloudColor = Ambient + Light * GetCloudShadow(Position.y, LightDir.y, Coverage);
    return vec4(mix(Sky, CloudColor, Alpha), 1.0 - Alpha);
#else
    return vec4(Sky, 1.0);
#endif
}
#endif
