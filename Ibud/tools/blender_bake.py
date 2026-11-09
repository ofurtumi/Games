"""
Blender bake + glTF export script for the Ibud game pipeline.

Run from the Godot project root, with the *Blender* project file as the .blend:

    blender --background /Users/tumi/Misc/ibud/ibud.blend \
            --python tools/blender_bake.py -- \
            --textures-out assets/textures/baked \
            --gltf-out assets/ibud.glb \
            --resolution 1024

What it does:
  1. Lists every material and the texture image (if any) feeding its Base Color.
  2. For every material:
       - If the Base Color is driven by a single Image Texture node, saves that
         image as <material_name>.png in --textures-out.
       - Otherwise, bakes the diffuse-color pass (texture + tint, no lighting)
         to a square PNG using Cycles.
     Materials that have no mesh using them are skipped with a warning.
  3. Exports the whole scene to --gltf-out as a .glb (embedded textures).

The baked PNGs are still photo-realistic. The stylization step
(tools/stylize_textures.py) runs afterwards to give them a hand-painted look.

Designed to be idempotent: rerunning it overwrites the previous bake outputs.
The .blend file itself is not saved; bake nodes are added in-memory only.
"""
import argparse
import math
import os
import sys
from pathlib import Path

import bpy


def parse_args():
    # Blender forwards args after `--` to the script.
    argv = sys.argv
    if "--" in argv:
        argv = argv[argv.index("--") + 1 :]
    else:
        argv = []

    p = argparse.ArgumentParser()
    p.add_argument("--textures-out", required=True,
                   help="Folder for per-material PNGs (relative to cwd or absolute).")
    p.add_argument("--gltf-out", default=None,
                   help="Optional path for the exported .glb. Skipped if omitted.")
    p.add_argument("--resolution", type=int, default=1024,
                   help="Bake resolution in pixels (square). Default 1024.")
    p.add_argument("--samples", type=int, default=8,
                   help="Cycles samples per bake. Diffuse-color bakes don't need many.")
    p.add_argument("--only", default=None,
                   help="Optional comma-separated material names to limit the bake to.")
    return p.parse_args(argv)


def find_image_node_for_base_color(mat):
    """If the material's Base Color input is driven by a single Image Texture
    node (optionally through a passthrough), return that node; else None."""
    if not mat.use_nodes:
        return None
    output = next((n for n in mat.node_tree.nodes
                   if n.type == "OUTPUT_MATERIAL" and n.is_active_output), None)
    if output is None or not output.inputs["Surface"].is_linked:
        return None
    bsdf = output.inputs["Surface"].links[0].from_node
    if "Base Color" not in bsdf.inputs:
        return None
    bc = bsdf.inputs["Base Color"]
    if not bc.is_linked:
        return None
    src = bc.links[0].from_node
    # Walk through simple passthroughs (Mix, Hue/Sat, etc.) shouldn't qualify
    # — we only return when the chain is literally Image -> Base Color.
    if src.type == "TEX_IMAGE" and src.image is not None:
        return src
    return None


def materials_in_scene_with_meshes():
    """Yield (material, list_of_objects_using_it) for materials actually
    assigned to mesh objects in the current scene."""
    usage = {}
    for obj in bpy.context.scene.objects:
        if obj.type != "MESH":
            continue
        for slot in obj.material_slots:
            if slot.material is None:
                continue
            usage.setdefault(slot.material.name, (slot.material, []))[1].append(obj)
    for name in sorted(usage):
        yield usage[name]


def ensure_uv(obj):
    """Make sure the mesh has at least one UV map, generating a Smart UV
    Project if not. Required for baking."""
    if obj.data.uv_layers:
        return
    print(f"  [uv] {obj.name} has no UV map — generating Smart UV Project")
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    # angle_limit is radians in Blender 4.x/5.x. ~1.15 rad = 66°.
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.02)
    bpy.ops.object.mode_set(mode="OBJECT")


def bake_material(mat, objs, out_path, resolution, samples):
    """Bake the diffuse-color (texture × tint, no lighting) of `mat` to
    out_path PNG. Uses the first object that has the material assigned."""
    if not mat.use_nodes:
        print(f"  [skip] {mat.name} has no node tree, can't bake")
        return False

    obj = next((o for o in objs if any(s.material == mat for s in o.material_slots)), None)
    if obj is None:
        print(f"  [skip] {mat.name} has no mesh user")
        return False
    ensure_uv(obj)

    nt = mat.node_tree
    # Add a temporary image + image texture node we'll bake into.
    img = bpy.data.images.new(
        name=f"_bake_{mat.name}", width=resolution, height=resolution, alpha=True,
    )
    bake_node = nt.nodes.new("ShaderNodeTexImage")
    bake_node.image = img
    bake_node.label = "BAKE_TARGET"
    # Mark it active for the bake.
    for n in nt.nodes:
        n.select = False
    bake_node.select = True
    nt.nodes.active = bake_node

    # Configure render engine + bake settings.
    scene = bpy.context.scene
    prev_engine = scene.render.engine
    scene.render.engine = "CYCLES"
    scene.cycles.samples = samples
    scene.cycles.bake_type = "DIFFUSE"
    scene.render.bake.use_pass_direct = False
    scene.render.bake.use_pass_indirect = False
    scene.render.bake.use_pass_color = True
    scene.render.bake.margin = 8

    # Select only the target object.
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)

    print(f"  [bake] {mat.name} -> {out_path}")
    try:
        bpy.ops.object.bake(type="DIFFUSE")
    except RuntimeError as e:
        print(f"  [error] bake failed for {mat.name}: {e}")
        nt.nodes.remove(bake_node)
        bpy.data.images.remove(img)
        scene.render.engine = prev_engine
        return False

    img.filepath_raw = str(out_path)
    img.file_format = "PNG"
    img.save()

    # Cleanup: remove temp node + image, restore engine.
    nt.nodes.remove(bake_node)
    bpy.data.images.remove(img)
    scene.render.engine = prev_engine
    return True


def save_image_node(node, out_path):
    """Save the image referenced by an image texture node to out_path.

    Blender 5.x lazy-loads externally referenced images, so img.save() can
    fail with 'does not have any image data'. We try image.reload() first,
    and if that still leaves the image unloaded we fall back to a direct
    file-system copy of the source bytes. Returns True on success.
    """
    import shutil
    img = node.image

    if not img.has_data:
        try:
            img.reload()
        except RuntimeError:
            pass

    if img.has_data:
        print(f"  [save]  {img.name} -> {out_path}")
        img.filepath_raw = str(out_path)
        img.file_format = "PNG"
        try:
            img.save()
            return True
        except RuntimeError as e:
            print(f"  [warn] save() failed for {img.name}: {e}; trying file copy")

    src = bpy.path.abspath(img.filepath, library=img.library) if img.filepath else ""
    if src and Path(src).is_file():
        # Preserve source extension since we're copying raw bytes.
        src_ext = Path(src).suffix.lower()
        target = out_path if src_ext == ".png" else out_path.with_suffix(src_ext)
        print(f"  [copy]  {src} -> {target}")
        shutil.copyfile(src, target)
        return True

    print(f"  [warn] {img.name}: no loaded data and no resolvable source file; skipping")
    return False


def export_gltf(gltf_out: Path):
    """Export the current scene to a .glb. Returns (ok, message)."""
    gltf_out.parent.mkdir(parents=True, exist_ok=True)
    print(f"\n# Exporting glTF -> {gltf_out}")
    try:
        bpy.ops.export_scene.gltf(
            filepath=str(gltf_out),
            export_format="GLB",
            export_apply=True,
            export_yup=True,
        )
    except RuntimeError as e:
        msg = str(e).split("\n")[0]
        print(f"  [error] glTF export failed: {msg}")
        # Try to extract the offending mesh name from the message — useful hint.
        if "foreach_get" in str(e):
            print("  [hint] one of your meshes has a broken UV layer "
                  "(layer present but no UV data).")
            print("         Open the .blend, find the mesh that just failed, "
                  "go into Edit Mode, and re-do its UV unwrap (U > Smart UV Project).")
        return False, msg
    return True, "ok"


def main():
    args = parse_args()
    textures_out = Path(args.textures_out).resolve()
    textures_out.mkdir(parents=True, exist_ok=True)
    only = set(s.strip() for s in args.only.split(",")) if args.only else None

    print(f"# Blender bake: textures-out={textures_out}")
    print(f"# {len(bpy.data.materials)} materials in file, "
          f"{sum(1 for o in bpy.context.scene.objects if o.type == 'MESH')} mesh objects in scene\n")

    # 1. Export glTF FIRST, against the untouched scene. The bake step
    #    can mutate UVs on objects that don't have them, which the gltf
    #    addon sometimes can't recover from. Doing the export before any
    #    mutations keeps the two halves independent.
    gltf_status = "skipped"
    if args.gltf_out:
        ok, _ = export_gltf(Path(args.gltf_out).resolve())
        gltf_status = "ok" if ok else "failed"

    # 2. Bake / copy material textures.
    summary = []
    for mat, objs in materials_in_scene_with_meshes():
        if only and mat.name not in only:
            continue
        print(f"\n## {mat.name} (used by {len(objs)} object(s))")
        out_path = textures_out / f"{safe(mat.name)}.png"
        node = find_image_node_for_base_color(mat)
        if node is not None:
            ok = save_image_node(node, out_path)
            summary.append((mat.name, "copied" if ok else "failed",
                            str(out_path) if ok else "-"))
        else:
            ok = bake_material(mat, objs, out_path, args.resolution, args.samples)
            summary.append((mat.name, "baked" if ok else "failed",
                            str(out_path) if ok else "-"))

    print("\n# Summary")
    print(f"  glTF: {gltf_status}")
    for name, status, path in summary:
        print(f"  {status:>6}  {name:30s}  {path}")


def safe(name):
    """Filesystem-safe version of a material name."""
    return "".join(c if c.isalnum() or c in "-_." else "_" for c in name)


if __name__ == "__main__":
    main()
