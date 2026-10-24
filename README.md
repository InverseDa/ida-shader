# ida-shader
This project implements Minecraft shaders. IDA Shader is graphical effects that enhance the visual experience of the game by adding lighting, shadows, and other effects.

## Current: closer CSM and placed local lights (2026-10-25)

**Lighting → Cascaded Shadows (CSM)** is now enabled by default. The existing
4096 atlas uses 8/32/96/192-block cascade radii: twice the near linear precision
without enlarging the atlas. Texel snapping, cascade blending, receiver-plane
correction and shared volumetric occlusion remain. The user confirmed the prior
CSM runs; this tighter configuration still needs visual acceptance in game.

**Lighting → Local Lights → Placed Block Lights** is also enabled by default.
Torches, lanterns, their soul variants, lit redstone torches/lamps, glowstone,
shroomlights and jack o'lanterns receive spherical attenuation and dynamic world
shadows. Geometry collected during shadow rendering includes off-screen casters
submitted by Iris. A fixed local voxel volume and per-source six-face shadow
cache avoid repeating full shadow traces for every 5K pixel. Known block-light
contributions are replaced locally; distant and unknown sources retain lightmap
lighting. Nearby entity/material shading and water highlights share the result.

The local data uses 17.66 MiB independent of screen resolution and requires
OpenGL 4.3 / Iris SSBO + compute. Geometry precision is 1/4 block; dense clusters
select eight sources, and 64 shadow caches have a voxel-trace overflow fallback.
Held lights retain their existing screen-space contact shadows. See
[implementation, limits and measurements](docs/placed-local-light-2026-10-25.md).

Production shader compilation, synthetic GPU shadow/occluder/cache checks and
fixed-input day/night colour regressions pass. The yellow solar halo and v0.1a
night palette are preserved. Local-light appearance, resource-pack geometry and
whole-game 5K frame time remain game acceptance items.

## Accepted visual baseline: daylight volumetric shafts (2026-10-24)

The **Volumetric Light / 体积光** page now enables warm sunlight in air below
the cloud base, occluded by the existing terrain/foliage shadow map and the selected
cloud field. Default quality is 32 samples, strength 1.0; 24/48 samples and an
independent off switch are available. Rays extend up to 128 blocks, with denser
near sampling. No new render pass, buffer or history is allocated.

The first version was not visible enough in the user's close-canopy screenshot.
Solar scattering now concentrates more of its existing column budget in nearby
air, with the full-column bound retained. Bright-sky canopy tests at 3/6/12 blocks
include production Bloom and final grading. The user confirmed the updated
appearance can pass; extended scene coverage and whole-game timings remain open.

The solar yellow halo, cloud rendering and v0.1a night palette are retained.
Shafts fade out at sunset, full rain and near the cloud base; underwater and hand
paths keep their existing treatment. Scattering follows each surface's own air
segment, so water uses its existing refraction composition and additive effects
receive attenuation only. This stage uses approximate cloud columns and existing
shadow-map coverage, without CSM, lens flare or underwater shafts.

Production GLSL GPU checks cover both cloud styles, cutout occlusion, depth/view
changes, night preservation and Bloom/halo colors. These are synthetic tests;
They do not establish total 5K game frame time or every extended acceptance case.
See [implementation and measurements](docs/volumetric-light-2026-10-24.md).

## Rendering contract

The current implementation targets the Overworld on Iris. It requires
`ENTITY_TRANSLUCENT` and `PER_BUFFER_BLENDING` support.

1. `shadow`: light-space depth, with the same foliage deformation as terrain.
2. Opaque `gbuffers`: linear albedo, octahedral normals, material data, and a
   separate linear surface lightmap (block baseline plus calibrated sky fill).
   Hand rendering is forward-lit and tagged.
   Early overlays/emission accumulate separately in colortex1, with
   view depth in colortex3; they do not replace opaque normals or material IDs.
3. `deferred`: opaque direct/ambient lighting, SSAO and sky. Saves **unfogged**
   radiance in colortex9 (reusing the consumed lightmap buffer) and matching
   opaque normal/depth/jitter in colortex4.
   Initializes the temporal rejection mask in colortex10 while retaining early
   effect/crack marks. Unlit depth geometry (lightning) bypasses surface lighting.
4. `deferred1`: opaque ice reflections, then one camera-to-surface atmosphere
   evaluation. Saves its immutable fogged baseline (11), then composites early
   effects into the visible scene using their own depth/medium treatment.
   With reflection history enabled, initializes current SSR data in 1/3/15
   after consuming early effect color and depth.
5. Translucent `gbuffers`: water/ice, glass, entities and block entities shade
   during their own draw calls. World surfaces apply atmosphere to their own
   contribution before alpha blending. Hands skip air fog but receive short-path
   water attenuation when submerged.
   These passes write color (0) and an additive temporal rejection mask (10).
   Water/ice also write SSR scratch 1/3/15, preserving the opaque snapshot and
   materials. Particles use `particles.ordering=mixed`:
   opaque particles enter deferred, translucent particles and rain use forward shading.
6. `composite`: fused one-pixel reactive-mask expansion, directional spatial AA,
   and TAA with current/previous jitter compensation and depth-validated
   history taps for static surfaces. Static surfaces without accepted history
   also use current-frame spatial AA while history becomes available.
   Hand, foliage, dynamic entities/block entities,
   particles, water, ice and sky use spatial AA instead. These dedicated geometry
   paths do not jitter. Covered pixels and their immediate neighbors reject history,
   even if the transparent layer did not write depth. History depth is positive
   in air, negative in water, and zero when invalid. Crossing the water surface
   rejects history from the other medium. Resolved color writes back to the
   colortex0 ping-pong pair; history uses RGBA16F with finite-range protection.
   This pass does not relight surfaces or apply atmosphere to the combined image.
7. `composite1`: commit isolated SSR scratch 1/3/15 to half-resolution persistent
   history 12/13/14, rejecting surfaces covered by later depth-writing geometry.
   Disabled when SSR temporal stability is off. Scene color is unchanged.
   The reflection producers read only the previous committed history.
8. `composite2/3`: half-resolution Bloom extraction/filtering.
9. `final`: combine linear HDR color and Bloom, tone-map, then encode sRGB.

| Attachment | Meaning | Writer |
| --- | --- | --- |
| colortex0 | Linear albedo, then atmospheric scene, then forward/spatial-AA/TAA result, RGB16F | Geometry, deferred1, composite |
| colortex1 | Early premultiplied effects, then current isolated SSR RGB/confidence; RGBA16F | Effects/hand, deferred1, water/ice |
| colortex2 | Opaque shading normal RG; LabPBR also stores geometric normal BA (RGBA16); Vanilla uses RG16 | Opaque geometry |
| colortex3 | Early effect depth in R, then SSR world normal oct.xy / linear depth.z / frame and material tag.w; RGBA16F with SSR history on, R16F otherwise | Effects, deferred1, water/ice |
| colortex4 | Packed 12+12-bit geometric octahedral normal and readiness/jitter sign in R, unchanged FP32 hardware depth in G; RG32F; hand depth is invalidated | deferred only |
| colortex5 | Perceptual roughness, F0/metal code, AO, packed material ID + sky-light level; RGBA8 | Opaque geometry |
| colortex6/7 | Half-resolution Bloom, R11F_G11F_B10F | composite2/3 |
| colortex8 | History RGB plus medium-tagged linear depth A: positive air / negative water / zero invalid, RGBA16F; retained across frames | composite |
| colortex9 | Linear vanilla lightmap before deferred; immutable raw opaque radiance afterwards, RGB16F | Opaque geometry, then deferred |
| colortex10 | Temporal rejection mask, R8; effect/transparent coverage accumulates; composite evaluates expanded coverage without writing another mask | Effects, deferred, translucent geometry |
| colortex11 | Immutable opaque scene after ice reflections and atmosphere, excluding early effect layers, RGB16F | deferred1 only |
| colortex12 | Previous isolated SSR RGB and confidence, half-resolution RGBA16F; persistent | composite1 only |
| colortex13 | Previous SSR world normal, surface depth, frame/material tag; half-resolution RGBA16F; persistent | composite1 only |
| colortex14 | Previous signed hit distance (negative for dynamic hits), half-resolution R16F; persistent | composite1 only |
| colortex15 | Current signed hit distance, R16F | deferred1, water/ice |

Forward reflection passes read snapshots 4/9/11, material 5 and previous SSR
history 12/13/14. In particular, a gbuffers shader
must not sample colortex0-3 (Iris binds atlas textures there), nor sample its own
active color/depth attachments. See the [Iris buffer documentation](https://shaders.properties/current/reference/buffers/colortex/)
and [blending/flip rules](https://shaders.properties/current/reference/shadersproperties/rendering/).

Water resolves refraction/absorption/reflection from the **unfogged** opaque
snapshot, then applies the camera-to-water atmosphere once. Its alpha layer is
factored against the already fogged opaque snapshot: over an unchanged background
it reproduces the resolved water ray exactly; earlier transparent layer changes
are attenuated by the remaining transmission, rather than erased or counted twice.
Later glass/rain/particles blend over this result in the engine's draw order.
This is a scalar-transmission approximation for layered transparency, not OIT.

Normals are interpolated in 3D and encoded only in fragment shaders. Generic
projection functions in `space.glsl` are unjittered; current-frame depth consumers
use `screen.glsl` and the per-surface jitter flag to compensate jitter. Refraction
also compensates the opaque snapshot's jitter when viewed through an unjittered
water surface. Sky radiance functions take **view-space**
directions; cloud density and slab intersections use **absolute world** positions.
Reflections trace the actual surface ray in view space; their cloud fallback starts
at the absolute world surface position. No water-plane height quantization is used.

## Post-v0.1a daylight and vanilla sky (2026-10-24)

The corrected M1 batch strengthens clear-day surface sunlight by up to 1.6x while
retaining the released shared cloud/moon source. The initial 2.4 shared source
and per-channel inverse sky tone mapping were rejected after an in-game screenshot
showed white clouds and blue foliage/water; neither remains in this revision.
Directional shadow visibility now fully blocks direct light in covered near/mid
regions, fading only in the last 30% of view distance and at shadow-map edges.
Ambient light retains shade detail. This remains the existing 2048 distorted map
with five hardware PCF queries; CSM is the next precision route, and Virtual
Shadow Maps are deferred pending a mod/engine integration assessment.

`DAY_SKY_LIGHTMAP` (Lighting Baseline, default 0.45) reduces only the positive
daytime sky increment of the vanilla lightmap. An additional lookup at the same
block-light coordinate on the zero-skylight row preserves the block-light baseline.
Rain restores at least 0.65 sky fill; night restores the complete input. Terrain,
deferred entities/particles and forward glass/ice share the calibration. Hands,
translucent effects and water-volume/foam illumination retain their existing paths.
No pass or target is added; affected daytime surfaces add one lightmap lookup.

Daytime sky color comes from Iris's vanilla `skyColor`, including biome/weather;
night retains the released v0.1a palette. Ambient, visible sky and reflections receive
linear color; the final pass applies exposure and ACES once after Bloom. This uses
the vanilla palette as a source, rather than matching its display RGB by inverting
individual channels into incident HDR light. Daytime aerial haze uses the sky base without
the solar disk and retains 35% of its chroma at the same luminance, avoiding blue
mid-distance shade. The sky retains a soft world-space horizon, localized twilight
tint and weather-dimmed sun disk. The water/lava-sensitive
`fogColor` is not used to color the air-side sky. See
[Iris rendering uniforms](https://shaders.properties/current/reference/uniforms/rendering/).
The local Iris 1.8.8 `CommonUniforms.getSkyColor` path was also checked against its
vanilla world-color source. Cloud geometry and its directional source budget are
unchanged from v0.1a. Extra water sparkle retains its previous tint/strength.

Solar glow correction: the elevation-only tint faded toward white too early at
`/time set day` (1000). The previous synthetic fixture used Y=0.18, whereas the
actual overworld orbit gives Y≈0.463315. `GetSkyScatteringRadiance` now restores
v0.1a's broad cosine^6 gradient toward the original HDR `SunColor` time table;
the solar disk tint and its surrounding glow also use the released equations.
The same layer feeds visible and reflected sky, with rough-reflection filtering.
Day haze excludes the solar halo, retaining the new daytime sky/fog palette and
surface lighting. The sun still fades below the horizon and in rain; clouds
attenuate it before Bloom. Night colors are unchanged by this correction.

Night palette rollback (user request, 2026-10-24): the vanilla night colors and
subsequent gray-blue floor were rejected. Night now uses the actual v0.1a ZIP's
sRGB `(0.02, 0.20, 0.27)` base, broad moon-facing fifth-power color gradient and
`SunColor * 0.22` filtered moon disk. The brighter white moon/Bloom boost is removed.
The existing 12000–13000 and 23000–24000 transitions blend the current daytime
palette into/out of the released night color before linearization. At full night,
sky, moon, material sky reflections and fog color match the released helpers;
clouds and sky fill also receive the restored palette. Daytime lighting/shadows,
engine Lightmap, the moon's directional source and global exposure are preserved.

Validation covers three compile/link variants (Vanilla, LabPBR with Bloom 1.0,
optional effects disabled), CPU invariants and hidden OpenGL renders.
`tools/check_daylight_gpu.py --output <png>` checks surface light/shadow and lightmap
preservation. `tools/check_daylight_composite_gpu.py --output <png>` adds production
clouds, distance fog, the LabPBR texture reader, water sky fallback, packed Bloom
targets and final grading; `--before-dir <saved-shader-root>` adds a comparison.
Add `--celestial` to face sunrise/sunset/moon directly, including cloud occlusion,
rain and water fallback. These rows use the time-dependent MC 1.21.4 orbit,
checked against the local DimensionType and Iris 1.8.8 CelestialUniforms code;
they include day 1000, sunset 12000 and noon 6000. It checks color outside the disk so a bright disk alone
cannot pass a missing-aureole regression. `tools/check_celestial.py` checks source
bounds, horizon continuity, camera invariance and rough-reflection peak reduction.
The composite test executes the production `SetupFrameLighting` before lighting,
and also combines night sky, moonlit/shaded sand, a synthetic block light and water
fallback. Dim and brighter night lightmaps exercise the ground/sky relationship.
`tools/check_v01a_night.py --release-zip dist/Ida-Shader-v0.1a.zip` checks the ZIP
checksum and compares night color helpers against the actual released GLSL.
The composite test's `--preserve-day --before-dir <saved-shader-root>` option
also checks that the rollback leaves day, rain, dawn/dusk, fog and water pixels
unchanged. Night acceptance is against v0.1a, without requiring extra moon Bloom.
`tools/check_v01a_solar.py --release-zip dist/Ida-Shader-v0.1a.zip` separately
compares the solar gradient and disk/glow against released GLSL on the same
ambient background. `--preserve-night` in the composite test checks that solar
changes leave the restored night sky, clouds, reflections and moon unchanged.
These use synthetic geometry/materials and do not validate the actual resource
pack, in-game appearance, SSR motion or performance. Game acceptance remains open.
The legacy CPU test reader reverses the exact identifiers renamed by `afd0998`;
production compilation and the new GPU test always read the original source.
Visual acceptance is tracked in [GAME_ACCEPTANCE.md](GAME_ACCEPTANCE.md).
The older sections below describe the v0.1a baseline where settings differ.

## Material and color baseline

Shader settings now expose **Materials**, **Lighting Baseline** and **Exposure and
Color** (with Chinese and English labels). `MATERIAL_MODE=0` is the default Vanilla
mode: geometry normals and built-in material values, with no normal/specular map
reads. Select `MATERIAL_MODE=1` explicitly for a LabPBR resource pack; the old
heuristic format detection is no longer used.

The LabPBR path reconstructs normal Z from RG and reads material AO from B. Its
derivative tangent frame handles UV mirrors and small derivatives, with no
texture-dependent branch around derivative evaluation. Specular R is stored as
perceptual roughness (`1 - smoothness`); the GGX BRDF squares it to alpha once.
The base minimum roughness remains 0.08; bounded screen-space normal variance
now increases the filtered roughness before it enters the existing material buffer.
Specular G retains the original F0/metal code: 0..229 are dielectric F0, 230..255
use albedo as conductor F0. Predefined metal optical constants are not yet used.
Black/white specular pixels are valid material data, so they are not treated as
missing textures. An absent map in LabPBR mode uses Iris's texture defaults;
Vanilla mode is the explicit fallback for non-PBR packs.
See the [LabPBR material standard](https://shaderlabs.org/wiki/LabPBR_Material_Standard).

Rain-night bright-spot hardening (2026-10-24): collapsed/non-finite tangent-frame
results fall back to geometry normals before G-buffer storage and normal-variance
evaluation. Fresnel clamps cosine inputs and evaluates the fifth power with
multiplications, avoiding GLSL's undefined negative-base `pow` after FP32 dot
product overshoot. AA sanitizes current/neighbour colors and rejects non-finite
history RGB before accumulation, keeping invalid samples out of the Bloom source.
Valid finite HDR colors retain their brightness. These changes add arithmetic,
with no additional texture reads, buffers or passes. Switching LabPBR to Vanilla
reduced the reported rain-night spots, but the patched LabPBR path still needs
the same-view in-game retest described in GAME_ACCEPTANCE.md.

No attachment was added or enlarged. The material alpha byte stores the material
ID in the low four bits and the 0..15 sky-light level in the high four bits.
Classification and TAA decode only the ID bits; material reads use `texelFetch`
so neighboring metadata cannot interpolate. Sky diffuse/specular fill is gated
by this sky-light level, while the vanilla Lightmap (including block light) and
emission remain independent. The 16-level sky approximation needs an in-game
check at cave entrances; it is not a visibility ray or GI. Forward surfaces use
the same encoding and lighting model. Hands remain Lightmap-only and skip PBR
samples; texture emission, porosity, texture SSS and POM are not implemented.

Exposure 0.92, Bloom strength 0.66, threshold 0.68 and existing display adjustments
remain the defaults. Lighting scales and post controls are compile-time options,
with no new pass. For a neutral comparison use contrast 1, vibrance 0, saturation
1 and Bloom strength 0. This skips Bloom texture work and writes black targets;
the two passes and their allocations still exist. Tone
mapping still follows linear scene/Bloom composition and precedes sRGB encoding.
Visual tuning and GPU timing remain game acceptance work, tracked in [ROADMAP](ROADMAP.md).

## Highlight and motion stability

The **Highlight and Edge Stability** settings page exposes `SPECULAR_AA` and
`DYNAMIC_AA_STRENGTH`, both defaulting to 1.0. These are compile-time controls;
they add no render targets or passes. No object motion-vector buffer was added.

LabPBR normal variation broadens the GGX lobe using bounded normal-derivative
variance, a technique also described in [Filament's specular AA documentation](https://google.github.io/filament/main/materials.html#anti-aliasing:specularantialiasing).
Derivatives are evaluated before alpha discard. The filtered perceptual roughness
is written into the existing RGBA8 material target. GGX now separates its tiny
division guard from a peak cap of 64: the previous large denominator floor
incorrectly made extremely smooth peaks darker and then brighter as roughness
increased. Very glossy LabPBR materials therefore need a brightness comparison.
Direct-sky rendering retains its original disks; reflected sun/moon disks are
broadened with peak compensation. Ice computes derivatives before the per-pixel
material branch, and both opaque and forward ice use this reflection filtering.
AA variance does not modify planar-reflection eligibility, avoiding the existing
roughness cutoff switching the reflection on and off.

Water evaluates its five long/short waves once (previously eight evaluations
across separate fine/coarse profiles), sharing the three long waves. Each wave
smoothly fades between eight and two pixels per wavelength, skipping trigonometry
when fully unresolved. The removed slope variance contributes to highlight width.
Micro ripples now use one explicit-gradient sample of the existing noise texture,
without the old nested procedural warp or its directional mean bias; unresolved
micro ripples skip the texture read. Main wave directions, amplitudes and speeds
remain unchanged, but the fine ripple pattern is intentionally different.
Reflection highlights and sparkle lobes widen while reducing their peaks.
Underwater surfaces use the same filtered wave profile.

Spatial AA checks four cardinal neighbors, including thin horizontal/vertical
features missed by the previous diagonal-only detector. Flat pixels use four
color reads; edges use at most eight, as before. A bounded subpixel blend handles
thin features even when the direction gradient is zero. Directional support is
limited to the same 3x3 area protected by reactive dilation. HDR filtering uses
a compress/filter/expand approximation to reduce bright edge fringes; it is not
an energy-conserving light-transport filter. The strength option allows sharper
edges when the default is too soft. Unaccepted static history gets spatial AA
instead of an unfiltered frame. Accepted history is weighted by its valid bilinear
coverage, and camera motion excludes Halton jitter and uses each screen axis's
pixel scale. Reactive pixels still write invalid history depth.

Color-target storage is unchanged. Additional ALU/derivative work and spatial AA
on newly exposed static pixels must be timed in-game; reduced water calculations
alone do not establish a net FPS gain. Screen-space reflection hit changes,
subpixel geometry loss and normal-map variance already lost in texture mipmaps
can still shimmer. Reflection confidence is handled as described below; dynamic
temporal accumulation remains a separate decision after in-game acceptance.

## Shadow and contact AO refinement

The next stage follows shadows/SSAO, basic wetness, shore foam, then clouds/Bloom.
The first batch retains the 2048 shadow map, five shadow queries, eight AO probes,
all current passes and all buffer formats. Incremental render-target storage is
zero. Shadow filtering now uses `sampler2DShadow` with matching Iris directives;
it interpolates comparison results instead of comparing an interpolated depth.
See [Iris hardware shadow sampling](https://shaders.properties/current/reference/buffers/shadowtex/#hardware-sampling).
Each hardware query may compare multiple texels, so the unchanged query count
does not guarantee unchanged GPU time. The kernel has no temporal randomization.
Direct shadows and vegetation visibility both fade at the shadow-map boundary,
including the filter footprint. Existing bias coefficients and daylight budgets
are retained; shared angle/noon terms are evaluated once per shadow lookup path.

AO uses exact depth/material texel pairs and reconstructs each sample at its
texel center, accounting for its own jitter state. Early depth rejection uses
the actual inverse projection, not an assumed equality between render distance
and the clip plane. Four near and four wider probes use bounded 3D support,
surface-plane rejection and smooth depth thresholds. The probe radius remains
0.30–0.95 blocks; support fades to zero at twice that radius. First-person hand
depth cannot occlude the world. Subpixel footprints and the final 65–95% of the
render distance fade AO, with a zero-read exit when its contribution is zero.
Rejected depth probes skip metadata/reconstruction; the upper bound remains
eight depth plus eight material reads, with no extra normals, noise or history.

CPU checks cover filtered shadow-edge continuity and atlas guard bands, flat
and sloped self-occlusion, local contacts, mixed jitter, hand/sky/far rejection,
and projections whose clip plane differs from render distance. Eight sparse AO
probes still cannot resolve every thin contact or offscreen occluder; real-game
contact strength, shadow acne, edge motion and GPU time remain acceptance items.

## Basic surface wetness

The **Weather and Wetness** page enables terrain wetness (default on, strength 1).
Rain changes linear albedo and perceptual roughness in the existing terrain pass.
The 305 listed vanilla blocks retain their original dry lighting and static TAA.
With puddles enabled, four spare packed material IDs also carry rain-retention
classes without changing the RGBA8 format. Basic wetness uses these responses:

| Terrain profile | Maximum linear albedo reduction | Wet roughness target before normal filtering |
| --- | --- | --- |
| Soil / moss | 28% | 0.70 |
| Sand / gravel | 22% | 0.76 |
| Stone / masonry | 12% | 0.38 |
| Wood | 18% | 0.50 |

Targets apply at full wetness to exposed upward faces. Smooth LabPBR materials
darken less and never become rougher; the wet target uses the already computed
normal variance so wetting cannot undo specular AA. Metal-coded pixels are left
unchanged. F0, AO, alpha, normal direction and packed skylight remain intact.
This baseline does not decode texture porosity or add a water coating BRDF.

Shelter uses raw interpolated skylight levels, independent of lightmap RGB,
time of day and sun-shadow visibility. Levels at or below 14 reject rain;
14–15 fade into exposure. Vertical faces have reduced response and undersides
remain dry. This conservative approximation can miss exposed surfaces or leak
at eaves, and cannot reliably distinguish transparent roofs or complex cutouts.
There is no vertical rain shadow map. Leaves/plants, entities, held items, water,
ice, emissive blocks and unclassified terrain retain their existing materials.

`surfaceWetness` is an [Iris CPU custom uniform](https://shaders.properties/current/reference/shadersproperties/custom_uniforms/)
using rain strength only when the player's biome reports rain. Local Iris 1.8.8
`parsing.SmoothFloat` bytecode confirms its parameters are scaled by 0.1 before
applying exponential decay in seconds: our values 120/480 give approximately
12 s wetting and 48 s drying half-lives, in addition to the engine rain ramp.
The first update uses the current target; shader reload/world load does not
preserve previous surface moisture. Biome transitions also fade, but the single
player-biome value cannot describe distant biome or altitude boundaries.

With **Puddle Reflections off**, no texture samples, targets, GPU history or passes
are added. There are three
extra scalar varying components, a vertex normal transform and fragment ALU;
dry/ineligible fragments skip response work. In this basic mode ground SSR is disabled and
color-target storage remains 1471.12 MiB at 5120×2739. GPU time is unmeasured.
The compile-time switch removes the wetness path; strength 0 is a visual control,
not the recommended performance baseline. Compare switch on/off after weather
settles, and see F4 in [GAME_ACCEPTANCE.md](GAME_ACCEPTANCE.md) for roof, rain-night
and transition tests. Four material/switch combinations compile and link offline.

## Local puddle reflections

The user's follow-up confirmed basic wetting was visible and requested reflected
trees/buildings. **Puddle Reflections** now defaults on under Weather and Wetness;
disabling it keeps the earlier basic wetness response. This extends stage F's
scope and texture-read budget; it is not a zero-GPU-cost adjustment.

Puddles form local, world-anchored patches using one read of the existing noise
texture (the custom asset has 128 texels, about 3 blocks per texel). Coverage grows and shrinks with the same
smoothed weather. Stone retains more water, followed by wood/soil, with little on
sand/gravel. Only eligible upward terrain is affected; leaves, plants, entities,
water/ice, metal-coded pixels and immersed views are excluded. The terrain pass
tags upward geometric faces before normal mapping using the existing material ID.
No depth derivatives are used to infer eligibility: neighbouring grass or a cliff
cannot change a ground pixel's puddle classification as the camera moves.
Skylight shelter remains approximate
and the stored 16-level mask can have sharper boundaries than base wetness.

The existing opaque-atmosphere pass reads the immutable normal/depth snapshot and
raw scene radiance, applies puddles, then applies atmosphere and early effects in
their original order. Materials 11–14 reuse the existing four-bit field and retain
static TAA. No additional pass, buffer, texture allocation or GPU history is needed.
The air/water interface is level, with 2% face-on Schlick Fresnel that
increases at grazing angles. This replaces the overly pale 10% + cubic blend.
Scene/sky mixing preserves the Fresnel budget as hits enter
and leave the screen. Rain/night sky fallback omits sharp disk glare; HDR values
of actual scene hits are retained. It does not reuse a dry material's F0 as water.

Search fades from 32 to 64 blocks from the camera and is skipped when dry, sheltered,
non-horizontal, outside a puddle patch or below the reflection-contribution threshold.
The puddle path uses the packed normal/depth snapshot to propose local ray/plane
intersections, then samples and validates the proposed position. This replaces
bisection across alpha holes, which could converge on the wrong edge and drop a
visible canopy. The nearest future plane hint is retained within the current ray;
failed hints allow continued search, while actual cutout holes stay transparent.
The march and validation share a hard **25-probe budget** (up to 24 march steps).
Reconstructed positions use the fetched pixel center and its jitter state; a full
3D error bound of 0.035–0.35 blocks rejects unrelated silhouettes, and coplanar
ground is excluded. A normal is only a search hint, never proof of a hit.
Each searched puddle pixel uses at most **50 packed snapshot + 4 raw-color reads**,
plus one coverage-noise read and up to 36 cloud-noise reads when cloud fallback
is enabled. The shared four-texel reconstruction rejects unrelated depth and
retains missing coverage as confidence loss. These counts do not establish a GPU
speedup; water/ice use the larger shared-trace budget described below.
Large rainy foregrounds can still add meaningful
GPU cost despite the 0 MiB target increment; use the independent switch to measure.

This is a screen-space approximation, not a water simulation. Off-screen geometry
falls back to sky/clouds; transparent layers are not reflected, hit loss/thin geometry can
still shimmer, and reflected travel does not integrate its own atmospheric volume.
It does not infer true terrain depressions or model pooling around grass blades.
The first version failed the user's motion/appearance check; the following wall
tests did not cover the canopy holes reported afterwards. The regression now runs
1,440 solid, 576 cutout-canopy and 272 layered leaf/wall cases, including camera
motion, jitter and two resolutions. In the fixed synthetic canopy samples,
visible-leaf recovery improved from 10/80 to 77/80, with zero misplaced leaf hits;
227 unambiguous visible layered samples retain the correct layer, including 35
wall hits through real holes. These are CPU regression results, not in-game hit
rates; screen-space occlusion, subpixel alpha edges and finite steps still lose data.
Six Vanilla/LabPBR × puddles/base-only/wetness-off configurations are validated
offline; corrected in-game appearance and GPU timing remain open under F6.

## Cloud shadows and vegetation transmission

The **Cloud Shadows and Vegetation** settings page provides independent compile-time
switches and strengths. Both effects default on: cloud shadow strength 0.8 and
vegetation transmission strength 0.65. No render target, history, pass, texture or
uniform was added. Standard surface direct light also fades to 45% in full rain;
Lightmap, sky fill and emission retain independent lighting budgets.

Surface direct lighting uses the actual world-space light elevation. It fades
smoothly to zero at the horizon, retaining the clear-noon and high-moon reference
levels. Legacy dawn/dusk sky tints reach sRGB 2 (about 4.95 in linear space);
surface lighting now preserves their hue while bounding that source gain. The
sky-art tint table is still used for sky/atmosphere rendering. This prevents its
HDR color gain from multiplying surface highlights and vegetation backlighting.

`Nature → Cloud Style` selects two volumetric modes, with matching broad fields
for visible clouds, surface shadows and the approximate reflection fallback:

- **Block clouds (0):** 24-block world-space XZ cells in a thin layer at Y=192–216.
  Exact cell-boundary traversal integrates occupied segments, including views
  inside/above the layer. Cloud interiors retain continuous density texture;
  adjoining occupied cells do not create fictitious exposed faces or bright seams.
- **Natural clouds (1, default):** the continuous layer at Y=168–286 gains fine
  erosion, darker bases and a sample towards the light for directional self-shadow.
  `Natural Cloud Quality` selects 12 / **20 default** / 32 integration samples;
  it does not affect block traversal. No new cloud buffer, pass or history is added.

The natural mode's broad field uses `cloud_density.glsl`: a 384-block weather
field and continuous 96x48x96-block 3D value noise, common wind, the 168–286 block
layer, vertical envelope and extinction coefficient. Two adjacent lattice-plane
reads form the 3D body, plus one weather read, using the existing 128x128 custom
noise asset and its queried bound texture size. Rain smoothly increases coverage.
Ground shadows integrate the vertical envelope analytically (85 blocks of equivalent
full density for a complete column) and evaluate the 3D coverage once at the
midpoint of the remaining light path. This costs at most three existing noise reads
per applicable fragment, with early coverage rejection. Noise uses explicit LOD 0
inside divergent branches. Absolute world coordinates prevent camera translation
from dragging the shadow pattern; the active sun/moon direction matches the BRDF.
Block clouds use two reads for their cell/weather coverage. Natural cloud shadows
and reflected columns omit the finer erosion and directional self-shadow sample;
these are corresponding approximations, not exact mirrored/shadowed volumes.
Both styles keep the existing sky palette, shared light source and warm solar halo.
The cloud shapes and their occlusion naturally change, including at night.

The new natural mode costs more than the previous 12-step cloud march. At 5K,
isolated cloud renders measured 4.53–6.44 ms below and 6.35–9.10 ms inside it,
versus 3.50 / 4.01 ms for the saved baseline. The block fixture measured about
1.12–1.24 ms, but represents a different, thinner volume. These short GPU timestamp
spans exclude the game and may contain submission gaps. See the
[dual-style implementation, costs and limitations](docs/cloud-styles-2026-10-24.md).

Receivers above the layer, surfaces with zero sky light and lights below the horizon
fade threshold skip all added reads. Light elevation fades between 0.04 and 0.16
to bound grazing-angle projection and ease sun/moon transitions. The cloud term
attenuates standard direct surface lighting and plant transmission only. It does
not darken ambient light, emission, atmospheric scattering or sky reflections.
Cloud contrast has a smooth optical-depth bound instead of tending towards black
along thick, low-angle paths. At the default strength, clouds alone remove at most
40% of the clear-day direct source, 18% in full rain, 14% at night and 6.3% on a
rainy night. These are shader bounds, not measured image-brightness changes.
Rain already attenuates the source; reducing cloud contrast avoids compounding
that loss. The combined directional weight never increases with rainfall.
The single column sample approximates vertical and oblique paths through changing coverage;
it is not a second volumetric march or an exact cloud-shadow map.

Material IDs 9/10 classify 11 leaf types and 56 static plants, including pale oak,
saplings, crops, flowers, vines and aquatic plants; names were checked against the
installed 1.21.4 assets. Existing RGBA8 metadata stores these IDs without expansion.
These groups retain static camera-only TAA and gain no new animation. Short grass
and fern remain the original animated foliage group with spatial AA. Solid trunks,
grass blocks, cactus, bamboo stalks and flower pots are not assigned thin foliage
transmission; unknown/modded blocks require explicit mapping.

Thin vegetation uses a view-facing normal on both sides, plus a broad backlighting
lobe tinted by its linear texture/biome color. Leaves have a lower transmission
scale than thin plants. Sky-light visibility, dielectric reflectance, metallic
classification, weather and cloud visibility constrain the result. The existing
five PCF samples also return unlifted light visibility, avoiding another shadow
lookup or the artistic shadow-floor boost for transmission. Range, grazing-angle
and shadow-atlas boundaries fade continuously. Fully blocked, in-range samples
and zero sky-light samples receive no added transmission; outside shadow coverage,
the sky-light level is only an approximation to occlusion.

Peak transmission is capped at 60% of that material's unshadowed normal-incidence
diffuse reference, even at the highest strength option. Weather weighting lowers
this cap to 39% in rain, 21% at night and 13.65% on rainy nights, before sky and
blocker visibility. This is a local backlighting budget, not a full SSS energy
model. The extra shadow-map modulation of sky fill also softens in rain/night
(floor 0.70 to 0.90), while material AO/SSAO and the original sky-fill budget stay
active. Lightmap and emission are not raised to compensate for dark shadows.

The old moving-foliage ambient multiplier 1.26 is now 1.0, and its extra shadow lift
is removed. These baseline/classification changes remain when transmission is off.
This is local thin-surface backlighting, without a thickness map, multi-layer light
transport or texture SSS. Dense cubic leaf blocks can remain dark from self-shadowing.
The existing procedural water glints and Lightmap-only hands/particles do not run
the added cloud lookup. Day/night/rain arithmetic has offline regression coverage;
visual tuning and GPU timing remain game acceptance work. This calibration adds
only arithmetic, keeping the existing noise and five-tap PCF budgets, with no new
storage. Low sample counts and unchanged storage do not establish an FPS result.

## Underwater rendering

`isEyeInWater == 1` selects water as the camera medium, following the
[Iris camera-fluid convention](https://shaders.properties/current/reference/uniforms/status/).
RGB transmittance follows Beer-Lambert attenuation with extinction coefficients
(0.20, 0.070, 0.030) per block. Scattering uses the biome fog hue, smoothed eye
light levels, day/night illumination and night vision. This replaces the air fog
and cloud march along submerged camera rays; `underwaterOverlay=false` removes
the additional flat vanilla water texture overlay.

The underwater water surface uses an oriented wave normal and water-to-air IOR
1.333. Dielectric Fresnel reaches total internal reflection beyond the critical
angle. Refraction samples unfogged opaque radiance and applies air fog/clouds
starting at the exit point, then applies the camera-to-surface water segment once.
Reflection searches nearby submerged screen geometry; a miss falls back to water
scattering, rather than reflecting the sky through a totally reflecting interface.
Hands, translucent entities, particles and effects receive the same water medium.

## Special-effect routes

| Program | Treatment |
| --- | --- |
| gbuffers_armor_glint | Additive, unlit glint; preserves the squared source-color term; medium attenuates emission without adding fog again |
| gbuffers_spidereyes | Additive, unlit eye emission; independent of the surface lightmap |
| gbuffers_beaconbeam | Premultiplied transparent color at its own depth; beam depth writes are disabled |
| gbuffers_damagedblock | Multiplies the existing linear color; preserves normals, lightmap and material ID; matches terrain deformation/jitter |
| gbuffers_lightning | Explicit unlit depth geometry, marked reactive; no stale terrain normal or second lighting evaluation |
| gbuffers_line / basic | Color-only overlays; selection outlines follow terrain jitter, other lines remain unjittered |
| gbuffers_textured / textured_lit | Explicit unlit/lightmapped overlay fallback, preserving texture alpha |

The shader distinguishes early and late effect draws using colortex4's readiness
flag, not a guess based on entity type. Early layers are composed after opaque
lighting and medium evaluation in deferred1; late layers blend directly over the
visible scene. Their blend state is premultiplied `ONE / ONE_MINUS_SRC_ALPHA`;
additive layers use zero opacity. Automatic alpha testing is disabled for these
routes because their primary output is deliberately zero on an early draw; the
shader explicitly discards empty source texels instead.

Effect view depth is stored in colortex3 to reject an early layer
covered by later opaque geometry. FP16 linear view depth uses a small relative
tolerance; hardware depth must not be stored in FP16. The first-person hand
clears covered early world effects before its own glint is drawn. The opaque
snapshot used as the water mixing baseline excludes effects, so their visible
contribution remains a transmitted destination difference rather than being
subtracted away by water composition. See the
[Iris program/fallback definitions](https://shaders.properties/current/reference/programs/gbuffers/).

## Reflection and memory budget

Water, ice and puddles now share `reflections/screen_trace.glsl`. Water/ice use
`SSR_TRACE_STEPS` (24 / **32 default** / 48) and a 128-block maximum ray length;
puddles use 24 steps and 48 blocks. This replaces the 14+12 approximate candidates,
water-plane snapping and multi-object color averaging. Vertical ice faces can
reflect too. Sampled planes only propose an intersection: the fetched texel's
actual position must agree with the reflection ray, its depth and jitter state.

The march grows through empty space, slows near visible depth and limits projected
travel across sky gaps so it cannot skip a whole canopy. Candidate checks no longer
advance a fixed distance schedule. A future leaf-plane hint survives intervening
alpha holes; local depth refits a candidate at most twice, only on the same face.

Hit acceptance combines a pixel footprint (grazing expansion capped at 2×) with
an independent plane-distance test that accounts for perspective depth precision.
LabPBR normal maps affect shading, not the geometric planes used to propose hits.
Vanilla retains RG16 normals; LabPBR widens buffer 2 to RGBA16 to keep both normals.
A four-texel depth-aware footprint reconstructs accepted color, preserving missing
coverage as reduced confidence. Even when the center falls in a leaf hole, valid
neighbours can fade out gradually. Screen-edge fade has a two-pixel guard and spans
14% of the shorter dimension on both axes. Distance and roughness fade as well;
material visibility cannot amplify away these fades. Confidence chooses scene
versus environment; Fresnel/transmission budgets remain independent of hit loss.

March, verification and footprint depth reads share a budget: at most
`2 * (SSR_TRACE_STEPS + 1)` packed snapshot reads plus four raw-color reads for
water/ice (66 + 4 at default), and 50 + 4 for puddles. Rejected taps never read
color. These are upper bounds, not GPU timing measurements. The separate 12-step
submerged reflection search is unchanged. These limits describe spatial tracing;
the temporal validation and history reads below add separate work.

`SSR_TEMPORAL` (Stability, default on) gives water, ice and puddles isolated
reflection history. A valid hit projects its virtual mirror image into the previous
camera, then validates each of four history taps against the reflection plane,
normal, material kind, frame stamp and reconstructed world hit. Puddles account for
terrain jitter. Historical color is clipped to the current validated source color
range before accumulation; confidence is filtered separately from Fresnel.

When tracing misses, the previous intersection must still agree with the current
reflection ray and current snapshot depth before its current color can be used.
Invisible/off-screen hits immediately use the environment; the earlier unverified
0.18-second cache was rejected after gameplay showed artifacts. Normal/depth
changes, stale frames, camera/FOV cuts and underwater views reject history too.
History only stabilizes observable geometry; it is not off-screen scene data.

`composite1` commits history at half width and height after all geometry. It reuses
consumed effect color buffer 1 for full-resolution scratch. Each history tap
reconstructs the actual full-resolution texel selected
by the commit, including odd viewport sizes. Geometry never samples its outputs.
Turning `SSR_TEMPORAL` off disables the commit pass, restores buffer 3 to R16F and
reduces 12–15 to 1×1 placeholders, actually releasing the large history allocation.

`REFLECTION_CLOUDS` (default on) uses a continuous column approximation of the
existing weather/wind/density/light field, at most three noise reads per eligible
ray. It replaces the fixed 12-slice reflected cloud march (up to 36 reads); grazing
rays smoothly fade to sky instead of stretching cloud slices into bands. This is
a softer approximate cloud reflection, not an exact mirrored volume. The visible
sky/clouds were unchanged by the SSR round; the subsequent cloud-style changes
are described above. Daylight glow and the v0.1a sky palette retain their source.

Off-screen buildings/trees still require scene data (probes, world cache or an
engine-assisted capture). This batch provides sky/cloud environment fallback,
not those missing objects. Occlusion/disocclusion, subpixel cutouts and moving
normals can still invalidate history. Dynamic hits have no object motion vectors;
current-color clipping and validation limit trails. The synthetic tests do not establish zero popping
in gameplay.

TAA reuses color buffer 0. Buffer 3 now uses RGBA16F to share the effect-depth
and reflection-metadata lifetimes. The linear-depth history in buffer 8 uses RGBA16F; its rounding error is
below 0.05% over 0.05–65504 blocks, compared with the existing 1% depth tolerance.
Out-of-range depths reject temporal history, and history color is bounded to
the finite FP16 range.

The opaque snapshot now uses RG32F: G retains the original hardware depth bit
for bit, while R stores an exact integer payload for two 12-bit octahedral
normal coordinates. Adding one reserves zero for "not ready"; the sign selects
the jitter convention. The largest magnitude is 2^24, representable exactly in
FP32. All reads go through `opaque_snapshot.glsl` with `texelFetch`; interpolating
the packed payload is forbidden. The snapshot stores geometric normals; main
surface lighting and ice reflection directions retain the shading normal.
Snapshot normal precision is reduced only for reflection consumers;
30,000 sampled directions show a maximum angular change of 0.05821 degrees.

Spatial AA and TAA now share one full-screen pass. One-pixel mask expansion is
evaluated locally; already-reactive pixels need one mask tap instead of nine,
and skip opaque reconstruction/history reads. TAA clamps to the unfiltered
current neighborhood, using exact edge-clamped texel coordinates; the old fixed
0.001 UV inset incorrectly skipped several edge pixels at high resolutions.
Invalid history skips neighborhood filtering entirely, and valid reprojection
reuses the view position already reconstructed for depth validation. Removing
the intermediate color/mask pass avoids one full-screen RGB16F + R8 write and
subsequent read (14 logical bytes per pixel; actual bandwidth depends on caching).

Cloud rays reject segments outside the layer; unresolved frequencies fall back to
their mean, and an upper-bound rejection can skip the weather lookup. The natural
march uses a fixed spatial stratum phase (no per-frame random phase), analytic
vertical-envelope integration and footprint filtering. Both sky and opaque-backed
clouds now use full opacity, without the old sky-only 0.32 factor. Emission-only
attenuation uses identical sampling/opacity and omits color calculations.
Natural-cloud detail uses at most five noise reads per step, plus at most three
for directional self-shadow when color is needed: 160 lit / 100 transmission-only
reads at the default 20, before early exits and footprint rejection. Block traversal
has at most 256 cell segments, four noise reads per occupied segment and two per
empty segment; it stops at opacity 0.995. These are worst-case bounds, not timings.
There are no new buffers/passes/history. The range fades from 2048 to 4096
blocks instead of stopping at 900; greater horizon coverage and added arithmetic
mean a net GPU improvement still needs measurement. The underwater water path
also skips the redundant air-side background lookup.

Bloom alone uses packed unsigned HDR; scene color, lightmaps and reflection
sources retain RGB16F. Packed Bloom has lower color precision and should be
checked on dim colored glows. These formats are supported by the installed
Iris 1.8.8 and documented in the [Iris format table](https://shaders.properties/current/reference/buffers/image_format/).

Bloom now fuses extraction/downsampling with an eleven-tap horizontal Gaussian,
then filters vertically in the second existing pass. Thresholding individual
source texels before interpolation keeps the extraction independent of the
filter's sampling phase. The normalized kernel (sigma 1.8 half-resolution pixels)
produces a compact glow without the old sparse rings. Horizontal extraction uses
44 single-texel reads; vertical paired linear taps use six. Total queries drop
from 72 to 50 per half-resolution pixel, excluding final's unchanged one read.
Iris 1.8.8's RenderTarget selects linear min/mag filtering for non-integer formats,
including these packed targets. Bounds use texel centers, including odd sizes.
The prefilter's 32 HDR limit, soft knee, threshold, strength and exposure defaults
remain unchanged. Tiny-source energy and peak brightness can differ from the old
interpolate-then-extract path; review compactness in game. More threshold arithmetic
and different cache behavior mean the query reduction is not a GPU timing result.

Buffer 9 changes from lightmap to raw opaque scene when deferred finishes.
Automatic ping-pong flipping keeps the lightmap read separate from the radiance
write. Later forward/effect draws must not write buffer 9; unlit lightning does
not need a lightmap output. The fogged snapshot lives in 11; 12 is now dedicated
SSR history. Buffers 6, 7, 11 and 15 skip per-frame clears because their full-screen
producers write every pixel before use. Geometry targets, effect depth and the
snapshot readiness flag still clear each frame. SSR history 12/13/14 persists
across frames and is fully overwritten by the commit pass.

Logical color-target storage in Vanilla mode, including both textures per Iris ping-pong pair:

| Resolution | Temporal off | Previous full-resolution history | Current half-resolution history |
| --- | ---: | ---: | ---: |
| 1920×1080 | 217.53 MiB | 383.64 MiB | 266.97 MiB |
| 2560×1440 | 386.72 MiB | 682.03 MiB | 474.61 MiB |
| 3840×2160 | 870.12 MiB | 1534.57 MiB | 1067.87 MiB |
| 5120×2739 | 1471.12 MiB | 2594.54 MiB | 1805.43 MiB |

History now adds approximately 25 bytes per full-resolution pixel, including both
banks (odd half-size rounding changes this slightly). The 5K reduction from the
rejected version is 789.11 MiB; disabling temporal history saves another 334.31 MiB.
LabPBR's separate geometric normal adds 8 logical bytes per full-resolution pixel
across both banks: 106.99 MiB at 5120×2739. LabPBR totals are 1912.42 MiB with
history and 1578.12 MiB without history. No additional attachment or pass is added.

On this machine's RTX 4070 Ti, repeated 5120×2739 synthetic snapshot + SSR + commit
GPU timestamp spans had wall-scene medians of 8.35 ms with the rejected 32-step
fixed schedule and 6.37–7.16 ms with adaptive tracing. Cutout-scene medians changed
from 9.50 to 8.45–8.60 ms; its repeated P95 did not consistently improve.
These exclude Minecraft, cloud reflections and the LabPBR geometry pass, may
include submission gaps, and do not establish gameplay FPS. See the
[adaptive trace comparison and samples](docs/ssr-adaptive-2026-10-24.md).

These are format-based estimates, not measured GPU residency: driver padding or
compression, depth/shadow targets, texture atlases and Minecraft memory are
excluded. RGB16F may have padding on a particular driver. Inspect the current
per-buffer budget with `python tools/shader_memory.py --width 5120 --height 2739`.
Add `--material-mode 1` for the LabPBR budget.

## Validation

Install Python 3.10+ and put `glslangValidator` on PATH, then run:

```text
python tools/validate_shaderpack.py --output-dir <scratch-directory>
python tools/validate_shaderpack.py --material-mode 1 --output-dir <another-scratch-directory>
python tools/validate_shaderpack.py --cloud-shadows 0 --vegetation-transmission 0 --output-dir <disabled-effects-directory>
python tools/validate_shaderpack.py --bloom-strength 0 --output-dir <disabled-bloom-directory>
python tools/validate_shaderpack.py --ssr-temporal 0 --output-dir <disabled-reflection-history-directory>
```

Each invocation compiles one material mode (default 0). It checks that Vanilla
has no PBR map reads and LabPBR uses one normal and one specular read per applicable
fragment path. Additional numerical checks cover all 256 metadata combinations,
all 256 F0 codes, normal/roughness boundaries, mirrored/small UV tangent frames,
exposure monotonicity and independent sky/Lightmap/emission terms.
Program-state checks reject blend/alphaTest keys that Iris cannot bind, unused
attachment overrides and missing translucent-entity separation. On Windows,
`python tools/check_entity_opacity_gpu.py` (numpy and glslangValidator required)
renders the actual hand shader with production MRT formats. It reproduces the
old property-name failure, checks 256 sky-light/background combinations, early
effect occlusion and five skin-alpha cases. This is separate from game acceptance.
Stability checks execute shader expressions for roughness and GGX peak bounds,
highlight integral preservation, wave cutoff continuity, flat/thin/HDR/screen-edge
AA with its eight-read budget, and 48 motion/jitter cases. Reflection checks cover
edge/corner continuity at four aspect ratios, 601 subpixel silhouette positions,
strict rejection of off-ray geometry, bounded confidence and constant Fresnel
composition. `python tools/check_puddle_trace.py` executes 9,152 production traces
across the puddle and three water/ice budgets, including mixed jitter, cutout holes,
layered leaves/walls and two resolutions. On Windows,
`python tools/check_ssr_gpu.py --output <outside-shaders>/ssr.png` (numpy/Pillow)
uses the actual packed snapshot and SSR GLSL for 41 camera pan/yaw frames,
eight terrain jitter phases, cutout geometry and vertical ice. These synthetic
cases do not replace pixel comparison in the game.
Add `--completeness --verify --width 5120 --height 2739` for six analytic scenes
with an independent visible-intersection oracle: nearby/distant/sloped walls,
two narrow-post widths and stairs. The report separates misses and wrong-layer
colors; neither the test nor the current implementation promises complete cutouts.
`python tools/check_reflection_normals_gpu.py` checks actual terrain/deferred GLSL:
four LabPBR normal maps change lighting normals while leaving SSR geometry unchanged.
The hand MRT test also accepts `--material-mode 1` for the widened normal target.
`python tools/check_ssr_temporal_gpu.py --output <outside-shaders>/ssr-temporal.png`
executes the production temporal resolve and commit with persistent FP16 history.
It covers pan/yaw, intermittent occlusion, trace recovery, new foreground color,
late depth-writing foreground rejection, ice/puddle jitter, stale frames, camera/FOV
cuts, medium changes, odd dimensions and immediate invisible-hit rejection at
5/30/60/144 FPS. The `--benchmark --width 5120 --height 2739` mode measures GPU
timestamp spans without image readbacks; `--shader-root` selects a saved baseline.
Use `--benchmark-scene cutout` to measure the foreground cutout fixture as well.
Nature checks compare analytic cloud-column length with numerical volume integration,
exercise height/horizon boundaries, verify shared world/wind coordinates and the
three-noise-read budget, and test vegetation IDs/TAA, two-sided backlight, metal,
cave and blocker rejection, plus shadow coverage transitions. Calibration sweeps
cover the actual 24-hour tint interpolation and day wrap, light elevations,
rain/night cloud bounds, monotonic rain response at every cloud strength, the
vegetation diffuse budget and the bounded sky-fill shadow floor. The two switches
can be independently set to 0/1 for compile checks; disabled paths are checked in
preprocessed deferred lighting.
Cloud checks execute the actual production march for 147 below/inside/above-layer
rays, checking lit/transmission-only opacity equality, uniform-column integration,
night/rain lighting bounds and the configured read limit. Additional checks cover the 3D
lattice, 128/256 texture sizes, world scale, coherent wind and filter continuity.
`python tools/check_cloud_styles_gpu.py --style 0 --output <preview.png>` uses
production cloud GLSL/noise in a hidden Windows OpenGL context (numpy/Pillow).
Use `--style 1` for natural clouds, `--samples 12|20|32` for their quality, or
`--benchmark --width 5120 --height 2739` for isolated timestamp spans. It checks
visible/emissive opacity agreement, wind/camera coordinates and a five-height
independent filled-slab oracle for block traversal. The preview excludes game
terrain, TAA and Bloom. `check_daylight_composite_gpu.py --cloud-style 0 --celestial
--reflection-environment --output <preview.png>` also checks actual sky colors,
warm halo through cloud gaps, the night palette, reflections and Bloom/final.
Bloom checks execute threshold-before-interpolation, normalized DC gain, HDR and
edge bounds, tiny/odd sizes, paired bilinear equivalence and eight moving emitters'
extracted-energy preservation. `tools/check_bloom_gpu.py --output <preview.png>`
(Windows, numpy and Pillow) runs the actual Bloom passes in hidden OpenGL with
RGB16F input and packed HDR targets. It checks 18 synthetic scenes, including dim
colors and odd sizes; disabled programs must eliminate source samplers. The PNG
shows amplified isolated halos; it is neither a game capture nor GPU timing.
Water sunlight checks run 4,480 lighting states and 16 camera rotations against
the production highlight: clear-noon baseline, rain/direct-strength response,
night/horizon/shelter rejection and continuous sky-level gating. These add no
texture reads and do not claim accurate directional roof or cloud visibility.
The validator expands includes, compiles all stages, links vertex/fragment pairs,
checks active MRT branches, attachment sizes, immutable snapshot ownership,
per-buffer blending and history retention, and tests depth linearization against
perspective-projected distances. It also checks forward sampler hazards, snapshot
and atmosphere ownership, particle ordering, and 45 numeric water-composition cases
(135 color channels) including preservation of earlier transparent contributions.
Additional checks cover monotonic RGB water extinction, split-path composition,
2,002 Fresnel samples and the critical angle, history rejection on medium changes,
early/late effect blending, foreground/background effect occlusion, and buffer
reuse. FP16 tests cover every depth interval in range; reflection tests check
zero-mask rejection boundaries and compare the actual cached-fetch helper with
the original two-fetch lookup over 2,928 probes (eight jitter phases, mixed
static/dynamic texels, three sizes and viewport boundaries), including an unchanged
unjittered output UV across mixed jitter states. The validator
also checks 49,152 signed snapshot round trips, bit-exact hardware depth,
sampled normal quantization error, all 512 reactive neighborhoods at nine pixel
positions, and 20,000 cloud-noise bounds. The validator
supplies Iris 1.8.8 hand/outline stage macros so those branches
are compiled as well.
Expanded files remain in the scratch directory
for diagnostics. It does not emulate Iris patching or validate rendered pixels.

In-game acceptance checks:

The focused day/night/weather protocol, fixed conditions and measurement forms are
in [the in-game acceptance checklist](<D:/Minecraft/Default/.minecraft/versions/1.21.4-Fabric 0.18.4/shaderpacks/ida-shader/GAME_ACCEPTANCE.md>).

- Reload the pack and resize the window: no shader/FBO errors or stale history.
- Stand still, rotate and walk past edges: static terrain should converge without
  jitter drift; revealed surfaces must reject unrelated history.
- Look up/down at noon/sunset: sun tint, fog and cloud illumination should stay
  anchored to the world. Fly above and inside the cloud slab to test intersections.
- Inspect water over ordinary, emissive and plant blocks: material classification
  must not change with the background. Move vertically to check reflection stability.
- Inspect normal/packed/blue/frosted ice, short grass and ferns; grass shadows should
  follow the same deformation. Check glass, translucent entities, hands and rain.
- Hold still near animated grass, moving mobs and water glints: these surfaces
  should have no Halton-induced wobble. Walk across their silhouettes and check
  that the revealed terrain has no history trails.
- Place stained glass in front of and behind shallow/deep water, then add rain
  and translucent particles. Check that foreground layers remain visible and
  that water does not gain a second distance-fog veil. Repeat with distant water
  and ice at sunrise and in rain, and with the camera inside/above the cloud slab.
- Compare day/night lighting and bright emissive surfaces after the linear-color
  change; exposure/Bloom artistic tuning needs an actual game view.
- Swim into and out of shallow/deep water while moving: no stale air/water history.
  Compare a lit surface at 1, 8 and 32 blocks; red should fade first, without a
  second white fog veil. Repeat at night, in a flooded cave, and with night vision.
- Look upward through the water surface, then towards grazing angles: refraction
  should transition to underwater reflection. Check side walls, flowing water,
  waterlogged blocks and underwater particles/held items for discontinuities.
- Inspect enchanted held items and armor, spider/enderman eyes at night, the beacon
  core and halo, lightning, selection outlines, and cracks while mining stone,
  foliage, ice and chests. Put an opaque object in front of and behind a beacon;
  repeat through glass/water. Reload and resize to check effect buffers are cleared.
- Compare the same water/ice view at the same resolution before and after reload,
  including screen edges, vertical ice faces and submerged total reflection.
  Check dark colored Bloom, resize to an odd height, and test lightning behind
  water to catch buffer-lifetime mistakes. Measure GPU frame time and memory
  after warm-up; an offline sample count is not an FPS result.
- Inspect fine normal maps on ice and shore reflections after snapshot packing;
  camera motion should not introduce new normal-stepping artifacts. Check the
  outermost screen pixels and static terrain next to moving mobs after AA fusion.
  Compare clouds from below/inside/above, including glint and eyes behind clouds.
- Compare `SPECULAR_AA` 0 and 1 while moving past low-angle water glints, near/far
  ice and fine LabPBR normal maps. Check that bright spots widen without a new
  moving brightness peak, and compare glossy-metal brightness after the GGX fix.
- Compare dynamic AA strengths 0, 0.5 and 1 on moving mobs, held items, grass,
  fences and thin particles; check silhouette sharpness and newly revealed
  terrain. Include a camera teleport, resize and water entry/exit for history.
- Time close/distant water and a quiet land view at the same resolution; water
  noise savings and added derivative/spatial work have different scene costs.
- Slowly pan shore/tree/building reflections across all four screen edges and
  corners, then repeat on ice and with a wide/tall window. Check smooth fallback,
  overly faint ice reflections, and remaining strong-hit occlusion flicker. Test
  both lateral/vertical camera motion, near/far water and LabPBR ice; record GPU
  frame time at fixed weather, time, resolution and view distance.
- Toggle cloud shadows over a sunlit plain or coast and walk/rotate beneath moving
  clouds; the pattern must remain world anchored. Repeat below/inside/above the
  cloud layer, at sunrise/sunset, in rain and at night; inspect horizon transitions.
- Compare front/backlit leaves, short grass, tall plants, flowers and crops with
  transmission 0/0.65/1. Check building shadows, closed caves, pale oak, underwater
  plants and both resource-pack modes. Dense leaf self-shadowing is expected, but
  leaves should not gain unconditional ambient brightness. Time a forest, plain
  and heavy transparent-overdraw scene with each effect independently disabled.

## Remaining limitations

This is a raster, screen-space renderer. Reflections cannot recover off-screen
geometry. Refraction/reflection use opaque snapshots: earlier transparent layers
are preserved at their original screen coordinates with scalar transmission, but
are not themselves refracted. Intersecting layers still depend on engine sorting;
this is not order-independent or recursive transparency. Above-water geometry-hit rays do not integrate reflected-segment air fog or clouds
between the surface and the hit; the sky environment fallback includes clouds.
Underwater reflection/refraction remain screen-space approximations; caustics,
closed air pockets and multiple water/air boundary crossings are not modeled.
The combined early-effect layer uses the last drawn effect's representative depth;
intersecting early layers with different depths still depend on engine sorting and
cannot be individually occluded. Early emission is not present in the raw opaque
reflection snapshot, although it remains visible through the composited water layer.
There are no object motion vectors: the dynamic path uses current-frame spatial
AA, not temporal supersampling; it cannot fully remove subpixel/specular shimmer.
PBR has an explicit basic LabPBR path, but texture emission, porosity, texture SSS,
POM and predefined metal optical constants remain unsupported. Hand lighting is
still Lightmap-only; the isotropic Lightmap response is not a directional local
light reflection. The minimum perceptual roughness is still 0.08.
Vanilla lightmap is an ambient approximation; this is not GI or physically complete
light transport. Geometric water displacement and other previously unimplemented
effects remain outside this stage. Cloud shadows use a single horizontal coverage
sample; vegetation transmission has no thickness or multi-layer transport. Offline checks cannot establish
GPU frame time. The fogged snapshot, R8 mask, early RGBA16F effect layer and
opaque-atmosphere pass cost memory/bandwidth. TAA reuses scene color, and raw
opaque radiance reuses the consumed lightmap pair; phase detection reuses the
packed snapshot sentinel. Buffer 4 retains full-precision hardware depth in
half the former storage; further precision/resolution cuts need visual targets
and in-game profiling.
Cloud rays skip segments outside the layer and terminate above
99.5% opacity; zero-weight reflection candidates skip HDR color reads, while weak
contributions use one bilinear color read and strong ones use the five-tap filter.
The net performance change needs in-game GPU timing, especially inside clouds or
with heavy transparent overdraw.

## Roadmap checkpoint and effect alignment

当前版本的主线实现已完成，进入收尾：冻结新效果范围，补必要缺陷、最终
场景巡检和性能记录。状态与已知边界见 [ROADMAP.md](ROADMAP.md) 顶部。
水面额外太阳闪光现已接入共同天气 / 直射强度与世界空间太阳高度衰减，并
复用天空光等级做保守遮蔽；晴天高太阳下保留原基准。此项新增纹理读取与
渲染缓冲均为 0，精确方向阴影 / 云影仍未接入该闪光项；不改变天空圆盘倒影。
本轮新画面按 [最终巡检](GAME_ACCEPTANCE.md) 的 S-A 复验，云层精修留待后续。

后续水体透射修正（S5）：移除固定浅青色与零深度染色，按 RGB 吸收并使用局部
Lightmap 控制散射，轻量复用水面顶点群系色；深水继续衰减，不再卡在 34 格。
泡沫只接纳浅处实体接触，并排除海草 / 树叶，避免把深水物体轮廓误涂成白色。
水体与泡沫共用一次 Lightmap，泡沫候选最多读取一次已有材质和一次原噪声；
无新增深度查询、pass 或渲染缓冲（0 MiB）。代价是只可见深处岸壁时可能缺少泡沫。
散射仍是局部光照近似，不含水中光源传播或焦散；透明叠层使用保守的标量透射。
1440 组颜色 / 光照 / 水深与 576 组透明合成定向检查通过；游戏画面按 S-F 对比
截图同一海岸的白天 / 13000 / 深夜，GPU 增量待测。

人物 / 手部假透明修正（S6）：Iris 的混合与 alphaTest 配置改用无目录程序名，
避免材质编号与背景混合、早期特效穿过手部；启用实体透明分流，让前向透明人物
在延迟光照之后绘制。真实皮肤镂空 / 外层和透明物品继续使用原 alpha。
独立 GPU 回归覆盖 256 组天空光 / 背景与 5 组 alpha；没有增加采样、全屏 pass
或渲染缓冲。游戏内按 S-G 检查石墙前手部、第三人称皮肤和水边 / 特效叠层。

上一阶段“材质与颜色 → 高光和运动稳定性 → 云影与植被透光”实现已完成，
用户已整体确认常规画面通过；雨夜亮点修复复测、配置与量化性能记录单独跟踪。

本轮主线：**阴影与 SSAO 优化 → 基础湿润 → 岸边泡沫 → 云层与 Bloom 优化**。
阶段范围、预算与进度见 [ROADMAP.md](ROADMAP.md)。阴影 / 接触 AO 与基础湿润
已完成代码和离线回归；按用户反馈补充局部积水倒影。新增渲染缓冲均为 0 MiB；
基础湿润无新增读取；积水改为验证射线交点，每个有效像素最多 1 次噪声、
50 次快照与 1 次颜色读取。用户接受不可见树叶面 / 离屏几何缺失为 SSR 边界，
不继续以此阻塞主线；F4 / F6 其余场景及性能记录仍保留。
维持 5 次阴影查询和最多 8 组 AO 采样。G 岸边泡沫已接入：复用岸底深度 /
法线和波纹，世界坐标碎泡沫，复用水体 Lightmap 漫反射；仅近岸候选最多
1 次材质 + 1 次噪声读取，无新增深度查询或缓冲。设置位于“水面”，
默认开启、强度 1；水下、侧面、深水与植被跳过，仍受可见岸底信息限制。
两种材质模式 × 泡沫开 / 关的编译和数值回归通过；G4 需要游戏内对照。
H1 云形已获用户阶段性认可，云细节按要求暂缓，完整场景与帧时间记录仍保留。
H2 Bloom 已改为提取后插值和连续可分离高斯光晕；两阶段纹理查询由 72 降到
50 次，保持现有曝光、阈值和两个半分辨率目标。新增渲染缓冲仍为 0 MiB。
独立 OpenGL 与数值回归通过；2026-10-24 用户确认本轮 Bloom 当前配置的
游戏内画面验收通过。云细节优化暂缓，GPU 帧时间与实测显存记录仍待补。
其他阶段记录独立保留，后续回归条件见 [GAME_ACCEPTANCE.md](GAME_ACCEPTANCE.md)。

上述 v0.1a 阶段以复用已有数据和缓冲为主；当前 SSR 时域阶段已增加历史存储，
预算见前文。若后续削减需要降低分辨率或改变效果，将根据计时与画面目标另行决定；
不把采样次数或逻辑显存预算当作实测性能。

下面保留其他效果方向作为候选；未进入上述主线的项目尚未排期。

| 效果方向 | 当前基础 / 老效果待优化 | 新效果候选 / 需要对齐的取舍 |
| --- | --- | --- |
| 光照与材质 | 线性 Lightmap、原版 / 基础 LabPBR、阴影、SSAO、简化植被背光；需校准昼夜与洞穴观感 | 纹理自发光、纹理 SSS / 厚度与更多材质通道 |
| 天空与云雾 | 程序天空、体积云、低采样地表云影、距离雾；云内和大量透明物体仍需计时 | 体积光、更精细的云影与天气过渡；确定风格与可接受的采样预算 |
| 水与反射 | 波纹法线、折射、水下吸收、屏幕空间反射、基础岸边泡沫；离屏和多层透明仍有限制 | 几何波浪、浪花 / 泡沫输运、焦散、离屏反射补偿；确定优先场景 |
| 抗锯齿与稳定性 | 静态 TAA、动态空间 AA、高光过滤、反射置信度过渡；细高光仍需实测 | 动态时域积累；确定拖影与锐度容忍度 |
| 后期与颜色 | Bloom、可配置固定曝光和调色；需实际画面校色 | 自动曝光；确定亮暗适应和默认色彩基准 |
| 环境与兼容性 | 主世界、水下和已列出的特殊绘制路径 | 下界/末地、熔岩/细雪、更多状态效果；先确定覆盖范围 |

对齐时建议明确：参考画面与使用场景、必做/可选优先级、目标分辨率和帧时间预算、
默认质量与可降低的项目。由这些约束决定下一阶段实现顺序和老效果的重构范围。
