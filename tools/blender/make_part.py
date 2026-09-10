"""Generate a starter ship part and export it as .glb using the project's
naming conventions (docs/08-art-pipeline.md). This is the template for every
part-kit script: copy it, change the geometry, keep the conventions.

Run headless from the repo root:
  blender -b -P tools/blender/make_part.py -- --out godot/assets/models/parts --name hull_segment_a

Conventions enforced here:
  * Part "forward" is Blender +Y. The glTF exporter converts to Y-up, so +Y
    becomes -Z in Godot, which is Godot's forward. Length runs along forward.
  * Empties named SOCKET_<name> are attachment points. Their +Y axis points OUT
    of the part; a mating socket points the opposite way.
  * Empties named CUT_<name> are cut points: where the cutter can sever the
    part from its neighbour. Usually one per socket, slightly inboard.
  * Empties named HAZARD_<kind>_<n> mark volatile locations (fuel, coolant,
    pressure, power). The kind is read by the salvage system.
  * Custom properties on the mesh object become glTF extras, which Godot reads
    as node metadata: part_kind, mass_kg, value_cr, material.
  * Low-poly: 8-16 sided cylinders, single-segment bevels, flat shading.
"""
import argparse
import math
import os
import sys

import bpy


def parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--out", required=True, help="output directory")
    p.add_argument("--name", default="hull_segment_a")
    p.add_argument("--length", type=float, default=6.0)
    p.add_argument("--radius", type=float, default=2.0)
    return p.parse_args(argv)


def reset_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


def add_empty(name: str, location, rotation=(0.0, 0.0, 0.0), parent=None):
    e = bpy.data.objects.new(name, None)
    e.empty_display_type = "ARROWS"
    e.empty_display_size = 0.3
    e.location = location
    e.rotation_euler = rotation
    bpy.context.scene.collection.objects.link(e)
    if parent is not None:
        e.parent = parent
    return e


def build_hull_segment(name: str, length: float, radius: float):
    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=radius, depth=length)
    body = bpy.context.active_object
    body.name = name
    # Cylinder axis is Z; rotate so the long axis is +Y (our "forward").
    body.rotation_euler = (math.radians(90.0), 0.0, 0.0)
    bpy.ops.object.transform_apply(rotation=True, scale=True)
    bevel = body.modifiers.new("Bevel", "BEVEL")
    bevel.width = 0.08
    bevel.segments = 1
    for poly in body.data.polygons:
        poly.use_smooth = False

    body["part_kind"] = "hull"
    body["mass_kg"] = 4200.0
    body["value_cr"] = 900.0
    body["material"] = "steel"

    half = length / 2.0
    add_empty("SOCKET_fore", (0.0, half, 0.0), (0.0, 0.0, 0.0), body)
    add_empty("SOCKET_aft", (0.0, -half, 0.0), (0.0, 0.0, math.radians(180.0)), body)
    add_empty("CUT_fore", (0.0, half - 0.4, 0.0), (0.0, 0.0, 0.0), body)
    add_empty("CUT_aft", (0.0, -half + 0.4, 0.0), (0.0, 0.0, 0.0), body)
    add_empty("HAZARD_coolant_1", (radius * 0.6, 0.0, 0.0), (0.0, 0.0, 0.0), body)
    return body


def export_glb(path: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        export_extras=True,
        export_apply=True,
        export_yup=True,
    )


def main() -> None:
    args = parse_args()
    reset_scene()
    build_hull_segment(args.name, args.length, args.radius)
    out = os.path.join(args.out, args.name + ".glb")
    export_glb(out)
    print("wrote", out)


if __name__ == "__main__":
    main()
