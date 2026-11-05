"""Decimate and re-export the raw Poly Haven photoscans into game-ready LODs.

Run with the bundled Blender:
  .tools/blender-4.5.3-linux-x64/blender -b -noaudio --factory-startup --python-exit-code 1 \
      --python tools/process_cc0_models.py -- [--only id ...]

Input : assets/third_party/polyhaven/raw/<id>/<id>_<res>.gltf  (from tools/fetch_cc0_assets.py)
Output: assets/third_party/processed/<id>/<id>_lod{0,1,2}.gltf + .bin + textures/ + .import sidecars,
        assets/third_party/processed/hdri/<id>_<res>.hdr, assets/third_party/processed/manifest.json
"""
import hashlib
import json
import math
import shutil
import sys
from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "assets" / "third_party" / "polyhaven" / "raw"
OUT = ROOT / "assets" / "third_party" / "processed"
CONFIG = json.loads((ROOT / "tools" / "cc0_assets.json").read_text())
# Triangle targets per LOD. Alpha-card leaves keep a milder ratio so the canopy does not shred.
BUDGET = {
    "tree": (12000, 4000, 1500),
    "shrub": (1500, 500, 200),
    "grass": (1000, 400, 150),
    "prop": (2000, 800, 250),
}
TEXTURE_IMPORT = """[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="res://{source}"

[params]

compress/mode=2
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map={normal}
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=0
"""
SCENE_IMPORT = """[remap]

importer="scene"
importer_version=1
type="PackedScene"

[deps]

source_file="res://{source}"

[params]

nodes/root_type=""
nodes/root_name=""
nodes/apply_root_scale=true
nodes/root_scale=1.0
nodes/import_as_skeleton_bones=false
nodes/use_name_suffixes=true
nodes/use_node_type_suffixes=true
meshes/ensure_tangents=true
meshes/generate_lods=false
meshes/create_shadow_meshes=true
meshes/light_baking=0
meshes/lightmap_texel_size=0.2
meshes/force_disable_compression=false
skins/use_named_skins=true
animation/import=false
animation/fps=30
animation/trimming=false
animation/remove_immutable_tracks=true
animation/import_rest_as_RESET=false
import_script/path=""
_subresources={{}}
gltf/naming_version=1
gltf/embedded_image_handling=1
"""
HDR_IMPORT = """[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="res://{source}"

[params]

compress/mode=0
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=0
"""


def md5_of(path):
    digest = hashlib.md5()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def triangles(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def has_alpha(material):
    if not material or not material.use_nodes:
        return False
    return material.blend_method != "OPAQUE" or any(
        link.to_socket.name == "Alpha" for link in material.node_tree.links)


def import_raw(asset_id, res):
    path = RAW / asset_id / ("%s_%s.gltf" % (asset_id, res))
    bpy.ops.import_scene.gltf(filepath=str(path))
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    for obj in bpy.context.scene.objects:
        if obj.type != "MESH":
            bpy.data.objects.remove(obj, do_unlink=True)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in meshes:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    # One object per material so leaves and bark can be decimated differently.
    bpy.ops.object.join()
    body = bpy.context.view_layer.objects.active
    body.name = asset_id
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.separate(type="MATERIAL")
    bpy.ops.object.mode_set(mode="OBJECT")
    parts = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    # Ground the model: origin at the centre of the footprint, base at z = 0.
    corners = [o.matrix_world @ Vector(c) for o in parts for c in o.bound_box]
    lo = Vector((min(c.x for c in corners), min(c.y for c in corners), min(c.z for c in corners)))
    hi = Vector((max(c.x for c in corners), max(c.y for c in corners), max(c.z for c in corners)))
    shift = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))
    for obj in parts:
        for v in obj.data.vertices:
            v.co -= shift
        obj.location = (0, 0, 0)
    return parts, hi - lo


def decimate(parts, target):
    total = sum(triangles(o) for o in parts)
    if total <= target:
        return
    for obj in parts:
        count = triangles(obj)
        leafy = any(has_alpha(slot.material) for slot in obj.material_slots)
        ratio = target / total
        if leafy:
            ratio = min(1.0, ratio * 1.6)
        if ratio >= 0.98 or count < 24:
            continue
        mod = obj.modifiers.new("Decimate", "DECIMATE")
        mod.decimate_type = "COLLAPSE"
        mod.ratio = ratio
        mod.use_collapse_triangulate = True
        mod.use_symmetry = False
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=mod.name)


def export_lod(asset_id, parts, lod):
    folder = OUT / asset_id
    folder.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in parts:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    body = bpy.context.view_layer.objects.active
    body.name = "%s_lod%d" % (asset_id, lod)
    path = folder / ("%s_lod%d.gltf" % (asset_id, lod))
    bpy.ops.export_scene.gltf(
        filepath=str(path), export_format="GLTF_SEPARATE", use_selection=True, export_apply=True,
        export_animations=False, export_skins=False, export_morph=False, export_yup=True,
        export_tangents=True, export_normals=True, export_texcoords=True, export_vertex_color="NONE",
        export_image_format="AUTO", export_keep_originals=False, export_texture_dir="textures",
        export_lights=False, export_cameras=False)
    return body, path


def write_sidecars(asset_id):
    folder = OUT / asset_id
    for image in sorted((folder / "textures").glob("*")):
        if image.suffix.lower() not in (".jpg", ".jpeg", ".png", ".webp"):
            continue
        normal = 1 if "nor" in image.name else 0
        rel = image.relative_to(ROOT).as_posix()
        (image.parent / (image.name + ".import")).write_text(TEXTURE_IMPORT.format(source=rel, normal=normal))
    for scene in sorted(folder.glob("*.gltf")):
        rel = scene.relative_to(ROOT).as_posix()
        (scene.parent / (scene.name + ".import")).write_text(SCENE_IMPORT.format(source=rel))


def process_model(asset_id, spec, manifest):
    budget = BUDGET[spec["class"]]
    record = {"class": spec["class"], "lods": []}
    for lod, target in enumerate(budget):
        clear_scene()
        parts, size = import_raw(asset_id, spec["res"])
        source = sum(triangles(o) for o in parts)
        decimate(parts, target)
        body, path = export_lod(asset_id, parts, lod)
        count = triangles(body)
        record["lods"].append({"file": path.name, "triangles": count})
        record["source_triangles"] = source
        record["size"] = [round(size.x, 3), round(size.z, 3), round(size.y, 3)]  # x, height, depth in Godot terms
        print("%-30s lod%d %7d -> %6d tris  (%.1f x %.1f x %.1f m)" % (asset_id, lod, source, count, size.x, size.y, size.z), flush=True)
    write_sidecars(asset_id)
    manifest["models"][asset_id] = record


def process_hdris(manifest):
    folder = OUT / "hdri"
    folder.mkdir(parents=True, exist_ok=True)
    for asset_id, spec in CONFIG["hdris"].items():
        name = "%s_%s.%s" % (asset_id, spec["res"], spec["fmt"])
        src = RAW / asset_id / name
        if not src.exists():
            print("missing HDRI %s" % src)
            continue
        dst = folder / name
        shutil.copyfile(src, dst)
        (folder / (name + ".import")).write_text(HDR_IMPORT.format(source=dst.relative_to(ROOT).as_posix()))
        manifest["hdris"][asset_id] = {"file": "hdri/" + name}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = set(argv[argv.index("--only") + 1:]) if "--only" in argv else None
    manifest_path = OUT / "manifest.json"
    manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else {"models": {}, "hdris": {}, "files": []}
    manifest.setdefault("models", {})
    manifest.setdefault("hdris", {})
    for asset_id, spec in CONFIG["models"].items():
        if only and asset_id not in only:
            continue
        if not (RAW / asset_id).exists():
            print("skipping %s: not downloaded" % asset_id)
            continue
        process_model(asset_id, spec, manifest)
    if not only:
        process_hdris(manifest)
    files = []
    for path in sorted(OUT.rglob("*")):
        if path.is_file() and path.name != "manifest.json" and path.suffix != ".import":
            files.append({"path": path.relative_to(OUT).as_posix(), "size": path.stat().st_size, "md5": md5_of(path)})
    manifest["files"] = files
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    print("processed %d files" % len(files))


main()
