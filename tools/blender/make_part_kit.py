"""Generate the fourteen-part M2 kit using the shared glTF conventions.

Run from the repository root:
  blender -b -P tools/blender/make_part_kit.py -- --out godot/assets/models/parts
Optional --name exports only that part. Metres, Blender +Y forward, flat shading,
one material per part, named outward-facing sockets, and imported convex collision.
"""
import argparse
import math
import os
import sys

import bpy
from mathutils import Vector

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_part import add_empty, build_hull_segment, export_glb, reset_scene


STEEL = (0.36, 0.43, 0.49, 1.0)
ALUMINIUM = (0.62, 0.69, 0.73, 1.0)
FUEL = (0.88, 0.31, 0.055, 1.0)
COOLANT = (0.06, 0.62, 0.73, 1.0)
ENGINE = (0.29, 0.32, 0.37, 1.0)


def revolved(profile, sides=12):
    """Create a closed low-poly surface of revolution around Blender Y."""
    vertices = []
    for forward, radius in profile:
        vertices.extend((radius * math.cos(i * math.tau / sides), forward,
                         radius * math.sin(i * math.tau / sides)) for i in range(sides))
    faces = [tuple(range(sides))]
    for row in range(len(profile) - 1):
        for i in range(sides):
            j = (i + 1) % sides
            faces.append((row * sides + i, (row + 1) * sides + i,
                          (row + 1) * sides + j, row * sides + j))
    faces.append(tuple((len(profile) - 1) * sides + i for i in reversed(range(sides))))
    mesh = bpy.data.meshes.new("Part geometry")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    body = bpy.data.objects.new("Part", mesh)
    bpy.context.scene.collection.objects.link(body)
    return body


def box(size, at=(0, 0, 0)):
    """Create a bevelled box; dimensions are Blender X/Y/Z in metres."""
    bpy.ops.mesh.primitive_cube_add(size=1, location=at)
    body = bpy.context.active_object
    body.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    bevel = body.modifiers.new("Edge bevel", "BEVEL")
    bevel.width = min(size) * 0.12
    bevel.segments = 1
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    return body


def join(objects):
    """Combine a small silhouette assembly into one mesh for convex import."""
    bpy.ops.object.select_all(action="DESELECT")
    for body in objects:
        body.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    return objects[0]


def finish(body, name, kind, mass, value, material, volume, thickness, colour):
    """Attach physical metadata and a single flat material to the exported mesh."""
    body.name = name + "-convcol"
    for key, value_ in {"part_kind": kind, "mass_kg": mass, "value_cr": value,
                        "material": material, "volume_m3": volume,
                        "thickness_mm": thickness}.items():
        body[key] = value_
    mat = bpy.data.materials.new(name + " material")
    mat.diffuse_color = colour
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = colour
    shader.inputs["Roughness"].default_value = 0.82
    body.data.materials.clear()
    body.data.materials.append(mat)
    for poly in body.data.polygons:
        poly.use_smooth = False
        poly.material_index = 0
    return body


def socket(body, name, point, outward, size="M", inboard=0.4, cut_point=None):
    """Place a socket and matching cut marker; socket local +Y faces outward."""
    direction = Vector(outward).normalized()
    rotation = Vector((0, 1, 0)).rotation_difference(direction).to_euler()
    add_empty("SOCKET_" + name + "_" + size, point, rotation, body)
    cut = Vector(cut_point) if cut_point is not None else Vector(point) - direction * inboard
    add_empty("CUT_" + name, cut, rotation, body)


def hull_small(name):
    body = revolved([(-1, .8), (1, .8)])
    finish(body, name, "hull", 480.0, 220.0, "steel", math.pi * .8 ** 2 * 2, 12.0, STEEL)
    socket(body, "fore", (0, 1, 0), (0, 1, 0), cut_point=(.81, .6, 0))
    socket(body, "aft", (0, -1, 0), (0, -1, 0), cut_point=(.81, -.6, 0))
    socket(body, "port", (-.8, 0, 0), (-1, 0, 0), cut_point=(-.7, 0, .42))
    socket(body, "starboard", (.8, 0, 0), (1, 0, 0), cut_point=(.7, 0, .42))
    socket(body, "top", (0, 0, .8), (0, 0, 1), cut_point=(.42, 0, .7))
    socket(body, "bottom", (0, 0, -.8), (0, 0, -1), cut_point=(.42, 0, -.7))
    socket(body, "instrument", (0, -.6, .8), (0, 0, 1), "S", cut_point=(.42, -.6, .7))


def hull_long(name):
    body = build_hull_segment(name, 9.0, 2.0)
    body["mass_kg"] = 6300.0
    body["value_cr"] = 1350.0
    return body


def cap(name, nose):
    length = 1.0 if nose else .25
    body = revolved([(-length / 2, .8), (length / 2, .12 if nose else .8)])
    finish(body, name, "cap", 90.0 if nose else 65.0, 160.0 if nose else 70.0,
           "aluminium", math.pi * .8 ** 2 * length / (3 if nose else 1), 8.0, ALUMINIUM)
    sign = -1 if nose else 1
    socket(body, "aft" if nose else "fore", (0, sign * length / 2, 0), (0, sign, 0),
           cut_point=(.81 if not nose else .55, sign * length * .1, 0))


def tank(name, fuel):
    body = revolved([(-.75, .25), (-.58, .42), (.58, .42), (.75, .25)])
    finish(body, name, "tank", 160.0 if fuel else 190.0, 360.0 if fuel else 240.0,
           "aluminium", math.pi * .42 ** 2 * 1.5, 6.0, FUEL if fuel else COOLANT)
    socket(body, "fore", (0, .75, 0), (0, 1, 0), cut_point=(.43, .35, 0))
    socket(body, "aft", (0, -.75, 0), (0, -1, 0), cut_point=(.43, -.35, 0))
    socket(body, "mount", (0, 0, -.42), (0, 0, -1), cut_point=(.3, 0, -.32))
    # Place the leaking line next to the mount cut point, pointing outwards.
    add_empty("HAZARD_" + ("fuel" if fuel else "coolant") + "_0", (0, 0, -.3),
              Vector((0, 1, 0)).rotation_difference(Vector((0, 0, -1))).to_euler(), body)


def engine(name, chemical):
    length, radius = (1.2, .6) if chemical else (.8, .5)
    profile = [(-length / 2, radius), (-length * .15, radius * .45),
               (length * .15, radius * .45), (length / 2, radius * .7)]
    body = revolved(profile)
    finish(body, name, "engine", 240.0 if chemical else 140.0,
           1200.0 if chemical else 1500.0, "titanium", math.pi * radius ** 2 * length,
           16.0 if chemical else 10.0, ENGINE)
    socket(body, "fore", (0, length / 2, 0), (0, 1, 0),
           cut_point=(radius * .71, length / 2 - .1, 0))


def radiator(name, width, height, fins):
    pieces = [box((width, .08, height))]
    for index in range(fins):
        x = -width / 2 + (index + .5) * width / fins
        pieces.append(box((.035, .12, height * .92), (x, 0, 0)))
    body = join(pieces)
    finish(body, name, "radiator", 36.0 if width > 1.5 else 32.0, 180.0,
           "aluminium", width * height * .12, 3.0, COOLANT)
    socket(body, "mount", (-width / 2, 0, 0), (-1, 0, 0),
           cut_point=(-width / 2 + .2, -.065, 0))
    add_empty("HAZARD_coolant_0", (-width / 2 + .15, 0, 0),
              (0, 0, math.pi / 2), body)


def mast(name):
    body = join([box((.16, 2.0, .16)), box((.65, .08, .4), (0, .85, 0))])
    finish(body, name, "mast", 18.0, 260.0, "aluminium", .65 * 2 * .4, 4.0, ALUMINIUM)
    socket(body, "aft", (0, -1, 0), (0, -1, 0), "S", cut_point=(.09, -.6, 0))


def plating(name):
    body = box((2.0, .1, 1.8))
    finish(body, name, "plating", 75.0, 110.0, "steel", 2 * 1.8 * .1, 8.0, STEEL)
    socket(body, "mount", (0, -.05, 0), (0, -1, 0), cut_point=(0, -.06, 0))


BUILDERS = {
    "hull_segment_a": lambda n: build_hull_segment(n, 6.0, 2.0),
    "hull_segment_b": hull_small,
    "hull_segment_c": hull_long,
    "cap_nose_a": lambda n: cap(n, True),
    "cap_tail_a": lambda n: cap(n, False),
    "tank_fuel_a": lambda n: tank(n, True),
    "tank_coolant_a": lambda n: tank(n, False),
    "engine_chemical_a": lambda n: engine(n, True),
    "engine_ion_a": lambda n: engine(n, False),
    "radiator_panel_a": lambda n: radiator(n, 2.0, 1.0, 8),
    "radiator_panel_b": lambda n: radiator(n, 1.2, 1.6, 6),
    "radiator_panel_c": lambda n: radiator(n, 3.0, 1.0, 12),
    "sensor_mast_a": mast,
    "plating_panel_a": plating,
}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True)
    parser.add_argument("--name", choices=BUILDERS)
    args = parser.parse_args(argv)
    names = [args.name] if args.name else BUILDERS
    for name in names:
        reset_scene()
        BUILDERS[name](name)
        export_glb(os.path.join(args.out, name + ".glb"))
        print("wrote", name)


if __name__ == "__main__":
    main()
