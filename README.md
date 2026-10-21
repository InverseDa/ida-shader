# ida-shader
This project implements Minecraft shaders. IDA Shader is graphical effects that enhance the visual experience of the game by adding lighting, shadows, and other effects.

## Rendering contract

The current implementation targets the Overworld on Iris. It requires
`ENTITY_TRANSLUCENT` and `PER_BUFFER_BLENDING` support.

1. `shadow`: light-space depth, with the same foliage deformation as terrain.
2. Opaque `gbuffers`: linear albedo, octahedral normals, material data, and a
   separate linear vanilla lightmap. Hand rendering is forward-lit and tagged.
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
5. Translucent `gbuffers`: water/ice, glass, entities and block entities shade
   during their own draw calls. World surfaces apply atmosphere to their own
   contribution before alpha blending. Hands skip air fog but receive short-path
   water attenuation when submerged.
   These passes only write color (0) and an additive temporal rejection mask (10),
   preserving opaque normals/materials/depth. Particles use `particles.ordering=mixed`:
   opaque particles enter deferred, translucent particles and rain use forward shading.
6. `composite`: expands the rejection mask by one pixel and applies a directional
   spatial AA filter to dynamic/transparent edges. It does not relight, shade
   water, or apply atmosphere to the combined image.
7. `composite1`: TAA with current/previous jitter compensation and depth-validated
   history taps for static surfaces. Hand, foliage, dynamic entities/block entities,
   particles, water, ice and sky use spatial AA instead. These dedicated geometry
   paths do not jitter. Covered pixels and their immediate neighbors reject history,
   even if the transparent layer did not write depth. History depth is positive
   in air, negative in water, and zero when invalid. Crossing the water surface
   rejects history from the other medium. Resolved color writes back to the
   colortex0 ping-pong pair; history uses RGBA16F with finite-range protection.
8. `composite2/3`: half-resolution Bloom extraction/filtering.
9. `final`: combine linear HDR color and Bloom, tone-map, then encode sRGB.

| Attachment | Meaning | Writer |
| --- | --- | --- |
| colortex0 | Linear albedo, then atmospheric scene, then forward/spatial-AA/TAA result, RGB16F | Geometry, deferred1, composite, composite1 |
| colortex1 | Early effects: premultiplied HDR radiance RGB and opacity A (additive emission uses A=0), RGBA16F | Effect draws; opaque hand clears covered pixels |
| colortex2 | Opaque surface octahedral normal, RG16 | Opaque geometry |
| colortex3 | Effect view depth, R16F | Effect draws |
| colortex4 | Opaque normal RG, hardware depth B; A=0 before deferred, A=1 unjittered / A=2 jittered afterwards; RGBA32F; hand depth is invalidated | deferred only |
| colortex5 | Opaque roughness, metallic, AO, material ID / 255 | Opaque geometry |
| colortex6/7 | Half-resolution Bloom, R11F_G11F_B10F | composite2/3 |
| colortex8 | History RGB plus medium-tagged linear depth A: positive air / negative water / zero invalid, RGBA16F; retained across frames | composite1 |
| colortex9 | Linear vanilla lightmap before deferred; immutable raw opaque radiance afterwards, RGB16F | Opaque geometry, then deferred |
| colortex10 | Temporal rejection mask, R8; effect/transparent coverage accumulates, then expands at silhouettes | Effects, deferred, translucent geometry, composite |
| colortex11 | Immutable opaque scene after ice reflections and atmosphere, excluding early effect layers, RGB16F | deferred1 only |

The forward passes read snapshots 4/9/11 only. In particular, a gbuffers shader
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
Reflection plane quantization happens in absolute world height before conversion
back to camera-relative coordinates.

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

Reflection keeps the existing 14 main plus 12 lateral planar probes, five-tap
color filter, and 12-step submerged search. A zero planar weight skips the entire
search. Probes reject near-plane/off-screen positions before snapshot reads, and
reject exactly zero depth/reprojection/height/alignment masks before expensive
normal and world-space work. The five color taps are deferred until the final
weighted score is useful; the small-score best-candidate fallback is preserved.
Jittered projection reuses its first snapshot read if the destination texel did
not change, including on unjittered dynamic surfaces. Crossing a texel boundary
still performs a second read. Search length and reflection mixing are unchanged.

TAA now reuses color buffer 0, reducing effect-depth buffer 3 from RGB16F to
R16F. The linear-depth history in buffer 8 uses RGBA16F; its rounding error is
below 0.05% over 0.05–65504 blocks, compared with the existing 1% depth tolerance.
Out-of-range depths reject temporal history, and history color is bounded to
the finite FP16 range. Hardware depth and normal snapshots remain RGBA32F.
Bloom alone uses packed unsigned HDR; scene color, lightmaps and reflection
sources retain RGB16F. Packed Bloom has lower color precision and should be
checked on dim colored glows. These formats are supported by the installed
Iris 1.8.8 and documented in the [Iris format table](https://shaders.properties/current/reference/buffers/image_format/).

Buffer 9 changes from lightmap to raw opaque scene when deferred finishes.
Automatic ping-pong flipping keeps the lightmap read separate from the radiance
write. Later forward/effect draws must not write buffer 9; unlit lightning does
not need a lightmap output. The fogged snapshot moves to 11 and buffer 12 is
removed. Buffers 6, 7 and 11 skip per-frame clears because their full-screen
producers write every pixel before use. Geometry targets, effect depth and the
snapshot readiness flag still clear each frame.

Logical color-target storage, including both textures per Iris ping-pong pair:

| Resolution | Before this optimization | After | Saved |
| --- | ---: | ---: | ---: |
| 1920×1080 | 324.32 MiB | 249.17 MiB | 75.15 MiB |
| 2560×1440 | 576.56 MiB | 442.97 MiB | 133.59 MiB |
| 3840×2160 | 1297.27 MiB | 996.68 MiB | 300.59 MiB |
| 5120×2739 | 2193.31 MiB | 1685.11 MiB | 508.20 MiB |

These are format-based estimates, not measured GPU residency: driver padding or
compression, depth/shadow targets, texture atlases and Minecraft memory are
excluded. RGB16F may have padding on a particular driver. Inspect the current
per-buffer budget with `python tools/shader_memory.py --width 5120 --height 2739`.

## Validation

Install Python 3.10+ and put `glslangValidator` on PATH, then run:

```text
python tools/validate_shaderpack.py --output-dir <scratch-directory>
```

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
static/dynamic texels, three sizes and viewport boundaries). The validator
supplies Iris 1.8.8 hand/outline stage macros so those branches
are compiled as well.
Expanded files remain in the scratch directory
for diagnostics. It does not emulate Iris patching or validate rendered pixels.

In-game acceptance checks:

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

## Remaining limitations

This is a raster, screen-space renderer. Reflections cannot recover off-screen
geometry. Refraction/reflection use opaque snapshots: earlier transparent layers
are preserved at their original screen coordinates with scalar transmission, but
are not themselves refracted. Intersecting layers still depend on engine sorting;
this is not order-independent or recursive transparency. Above-water reflection
rays do not integrate a separate atmospheric volume along their reflected segment.
Underwater reflection/refraction remain screen-space approximations; caustics,
closed air pockets and multiple water/air boundary crossings are not modeled.
The combined early-effect layer uses the last drawn effect's representative depth;
intersecting early layers with different depths still depend on engine sorting and
cannot be individually occluded. Early emission is not present in the raw opaque
reflection snapshot, although it remains visible through the composited water layer.
There are no object motion vectors: the dynamic path uses current-frame spatial
AA, not temporal supersampling; it cannot fully remove subpixel/specular shimmer.
PBR texture decoding remains
a simplified normal/smoothness/metallic convention, not full LabPBR support.
Vanilla lightmap is an ambient approximation; this is not GI or physically complete
light transport. Cloud shadows on terrain, geometric water displacement and other
previously unimplemented effects have not been added. Offline checks cannot establish
GPU frame time. The fogged snapshot, R8 mask, early RGBA16F effect layer and
opaque-atmosphere pass cost memory/bandwidth. TAA reuses scene color, and raw
opaque radiance reuses the consumed lightmap pair; phase detection reuses the
opaque snapshot's alpha. Buffer 4 retains full-precision hardware depth and is
still a substantial memory cost at high resolutions.
Cloud rays skip segments outside the layer and terminate above
99.5% opacity; zero-weight reflection candidates skip their five HDR color taps.
The net performance change needs in-game GPU timing, especially inside clouds or
with heavy transparent overdraw.
