# Blender → Godot texture pipeline

This folder holds two scripts that move materials/textures from `ibud.blend`
into the Godot project, with a hand-painted stylization step in the middle.

## The pipeline

```
ibud.blend   ──blender_bake.py──▶  assets/textures/baked/*.png   (photo-real)
                                          │
                                          ▼
                              stylize_textures.py
                                          │
                                          ▼
                          assets/textures/stylized/*.png         (cartoony)
                                          │
                                          ▼
                          toon_triplanar.gdshader materials      (in Godot)


ibud.blend   ──blender_bake.py──▶  assets/ibud.glb                (geometry refresh)
```

Two outputs feed Godot:

1. **PNG textures** sit next to the existing `.tres` materials. The materials
   point at them via `toon_triplanar.gdshader`, which projects the texture
   world-space — no UV unwrap needed on the mesh.
2. **Updated geometry** as `assets/ibud.glb`. Replace the current `ibud.obj`
   reference in `scenes/Ibud.tscn` once you're ready.

## Step 1 — bake textures + export geometry from Blender

Run from the Godot project root (`/Users/tumi/Misc/Games/Ibud`). Replace the
Blender path with wherever your Blender lives on macOS:

```bash
/Applications/Blender.app/Contents/MacOS/Blender \
    --background /Users/tumi/Misc/ibud/ibud.blend \
    --python tools/blender_bake.py -- \
    --textures-out assets/textures/baked \
    --gltf-out assets/ibud.glb \
    --resolution 1024
```

What it does:

- For every material assigned to a mesh in the scene:
  - If its Base Color is driven by a single Image Texture, it copies that
    image to `assets/textures/baked/<MaterialName>.png`.
  - Otherwise it bakes the diffuse-color pass (texture × tint, no lighting)
    to a 1024² PNG using Cycles. Smart UV Project is generated on the fly
    if a mesh has no UVs.
- Exports the whole scene to `assets/ibud.glb` with embedded textures.
- Doesn't save the .blend file; bake nodes live in memory only.

Limit the run to specific materials with `--only "Plywood,Trim"` if needed.

## Step 2 — stylize the baked PNGs

```bash
python3 tools/stylize_textures.py \
    --in assets/textures/baked \
    --out assets/textures/stylized \
    --max-size 1024 \
    --levels 5 \
    --smooth 4 \
    --saturation 1.15
```

Knobs to taste:

- `--levels` (default 5) — colour levels per channel. Lower = more cartoon.
- `--smooth` (default 4) — median filter radius. Higher = fewer details.
- `--soften` (default 1.2) — Gaussian blur after posterize, softens hard
  step edges so they read as brush strokes.
- `--saturation` / `--warmth` — push colours past photoreal.
- `--max-size` (default 1024) — stylized textures look better small.

Pillow is the only required dependency (numpy is used if present, but the
script falls back to a Pillow-only path otherwise). If Pillow is missing:

```bash
pip3 install pillow
```

## Step 3 — wire textures into Godot materials

Two example materials are already in place that use `toon_triplanar` with the
stylized PNGs:

- `assets/materials/Floor_RedPainted.tres` → `stylized/raudar.png`
- `assets/materials/Wall_PatternPainted.tres` → `stylized/hvitar-svartar.png`

Use them as templates. To convert one of your existing flat-colour materials
(say `Wall_MintGreen.tres`) into a textured version:

```diff
 [gd_resource type="ShaderMaterial" load_steps=2 format=3 uid="uid://mint_wall_ibud01"]

-[ext_resource type="Shader" path="res://assets/shaders/toon_flat.gdshader" id="1_mint"]
+[ext_resource type="Shader" path="res://assets/shaders/toon_triplanar.gdshader" id="1_mint"]
+[ext_resource type="Texture2D" path="res://assets/textures/stylized/Wall_MintGreen.png" id="2_minttex"]

 [resource]
 shader = ExtResource("1_mint")
-shader_parameter/albedo = Color(0.56, 0.76, 0.72, 1)
+shader_parameter/albedo_texture = ExtResource("2_minttex")
+shader_parameter/texture_scale = 0.5
+shader_parameter/albedo_tint = Color(1, 1, 1, 1)
 shader_parameter/roughness = 0.92
```

If the baked texture is already correctly tinted, leave `albedo_tint` white.
If you want to keep the flat-colour mood and just add a subtle texture
overlay, set `albedo_tint` to your existing colour and bake a near-white
detail texture instead.

## Step 4 — refresh geometry (optional)

When `assets/ibud.glb` is fresh, swap the mesh reference in
`scenes/Ibud.tscn`. The simplest way is to open the scene in Godot, drag the
new `.glb` in, copy the surface-material assignments across, and delete the
old `MeshInstance3D` for `ibud.obj`. Or hand-edit the `.tscn` if you're
comfortable with it.

## Re-running

The whole pipeline is idempotent: rerunning Step 1 + Step 2 overwrites the
PNGs, and Godot picks up the new bytes on its next focus. The `.blend` is
never modified on disk.
