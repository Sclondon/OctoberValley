"""Builds the October Valley heroes (Joe, Matt, Alex, Jon) from the 8 Bit Evil Returns sprites.

Each hero is a stack of boxes measured in sprite pixels (1 px = PX metres), skinned rigidly to a
small armature, with idle / run / jump / fall actions. Colours are the sprites' own palette.

    blender -b --factory-startup --python art/build_heroes.py [-- <preview dir>]

Writes art/<hero>.blend and models/<hero>.glb. With a preview dir it also renders
<hero>_front.png, <hero>_back.png and <hero>_run.png there.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Euler, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
PX = 0.08  # metres per sprite pixel: a 22 px hero stands 1.76 m
FPS = 24

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
PREVIEW_DIR = argv[0] if argv else None


def srgb(hex_color):
    """'f0bd8c' -> linear RGBA."""
    out = []
    for i in (0, 2, 4):
        c = int(hex_color[i:i + 2], 16) / 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return (out[0], out[1], out[2], 1.0)


class Body:
    """Collects boxes (in px, +X = the hero's left, -Y = front, +Z = up) into one skinned mesh."""

    def __init__(self, palette):
        self.palette = palette
        self.verts = []
        self.faces = []
        self.face_mats = []
        self.vert_bones = []
        self.mat_names = []

    def box(self, bone, color, x, y, z, mirror=False):
        self._box(bone, color, x, y, z)
        if mirror:
            other = bone[:-2] + "_R" if bone.endswith("_L") else bone
            self._box(other, color, (-x[1], -x[0]), y, z)

    def _box(self, bone, color, x, y, z):
        if color not in self.mat_names:
            self.mat_names.append(color)
        base = len(self.verts)
        for vz in z:
            for vy in y:
                for vx in x:
                    self.verts.append((vx * PX, vy * PX, vz * PX))
                    self.vert_bones.append(bone)
        quads = [(0, 2, 3, 1), (4, 5, 7, 6), (0, 1, 5, 4), (2, 6, 7, 3), (0, 4, 6, 2), (1, 3, 7, 5)]
        for q in quads:
            self.faces.append(tuple(base + i for i in q))
            self.face_mats.append(self.mat_names.index(color))

    def to_object(self, name):
        mesh = bpy.data.meshes.new(name)
        mesh.from_pydata(self.verts, [], self.faces)
        for mat_name in self.mat_names:
            mat = bpy.data.materials.new(mat_name)
            rgba = srgb(self.palette[mat_name])
            mat.diffuse_color = rgba
            mat.use_nodes = True
            bsdf = mat.node_tree.nodes["Principled BSDF"]
            bsdf.inputs["Base Color"].default_value = rgba
            bsdf.inputs["Roughness"].default_value = 1.0
            mesh.materials.append(mat)
        for poly, index in zip(mesh.polygons, self.face_mats):
            poly.material_index = index
        bm = bmesh.new()
        bm.from_mesh(mesh)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(mesh)
        bm.free()
        mesh.update()
        obj =bpy.data.objects.new(name, mesh)
        bpy.context.collection.objects.link(obj)
        groups = {}
        for i, bone in enumerate(self.vert_bones):
            if bone not in groups:
                groups[bone] = obj.vertex_groups.new(name=bone)
            groups[bone].add([i], 1.0, "REPLACE")
        return obj


# name: (parent, head, tail) in px. The pivot is the head.
BONES = {
    "root": (None, (0, 0, 0), (0, 0, 2)),
    "hips": ("root", (0, 0, 7), (0, 0, 8.5)),
    "spine": ("hips", (0, 0, 8.5), (0, 0, 13.5)),
    "head": ("spine", (0, 0, 13.5), (0, 0, 20)),
    "hair": ("head", (0, 2, 20), (0, 2, 23)),
    "arm_L": ("spine", (3.7, 0, 13), (3.7, 0, 8.5)),
    "arm_R": ("spine", (-3.7, 0, 13), (-3.7, 0, 8.5)),
    "leg_L": ("hips", (2, 0, 7), (2, 0, 0)),
    "leg_R": ("hips", (-2, 0, 7), (-2, 0, 0)),
}


def build_armature(name):
    data = bpy.data.armatures.new(name + "_rig")
    arm = bpy.data.objects.new(name + "_rig", data)
    bpy.context.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    for bone_name, (parent, head, tail) in BONES.items():
        bone = data.edit_bones.new(bone_name)
        bone.head = Vector(head) * PX
        bone.tail = Vector(tail) * PX
        if parent:
            bone.parent = data.edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    for pose_bone in arm.pose.bones:
        pose_bone.rotation_mode = "QUATERNION"
    return arm


def apply_pose(arm, pose):
    """pose: bone -> (rx, ry, rz) degrees about the armature's axes, relative to the parent.
    +rx leans a bone that points up forward, so it swings a hanging arm or leg back.
    'hips_loc' moves the hips in px."""
    for pose_bone in arm.pose.bones:
        rest = pose_bone.bone.matrix_local.to_3x3()
        rx, ry, rz = pose.get(pose_bone.name, (0, 0, 0))
        turn = Euler((math.radians(rx), math.radians(ry), math.radians(rz)), "XYZ").to_matrix()
        pose_bone.rotation_quaternion = (rest.inverted() @ turn @ rest).to_quaternion()
        offset = Vector(pose.get("hips_loc", (0, 0, 0))) * PX if pose_bone.name == "hips" else Vector()
        pose_bone.location = rest.inverted() @ offset


def add_action(arm, name, keys):
    """keys: list of (frame, pose). Every bone is keyed on every key, and stashed on an NLA track."""
    action = bpy.data.actions.new(name)
    arm.animation_data.action = action
    last = {}
    for frame, pose in keys:
        apply_pose(arm, pose)
        for pose_bone in arm.pose.bones:
            quat = pose_bone.rotation_quaternion.copy()
            if pose_bone.name in last and last[pose_bone.name].dot(quat) < 0:
                quat.negate()
                pose_bone.rotation_quaternion = quat
            last[pose_bone.name] = quat
            pose_bone.keyframe_insert("rotation_quaternion", frame=frame)
            pose_bone.keyframe_insert("location", frame=frame)
    track = arm.animation_data.nla_tracks.new()
    track.name = name
    track.strips.new(name, int(action.frame_range[0]), action)
    arm.animation_data.action = None
    apply_pose(arm, {})


def mirror_pose(pose):
    out = {}
    for key, value in pose.items():
        if key.endswith("_L"):
            key = key[:-2] + "_R"
        elif key.endswith("_R"):
            key = key[:-2] + "_L"
        out[key] = (value[0], -value[1], -value[2]) if key != "hips_loc" else (-value[0], value[1], value[2])
    return out


IDLE_UP = {"hair": (0, 0, 0), "arm_L": (0, -4, 0), "arm_R": (0, 4, 0)}
IDLE_DOWN = {"hips_loc": (0, 0, -0.5), "spine": (3, 0, 0), "head": (-2, 0, 0), "hair": (-8, 0, 0),
             "arm_L": (0, -10, 0), "arm_R": (0, 10, 0), "leg_L": (0, -4, 0), "leg_R": (0, 4, 0)}

RUN_REACH = {"hips_loc": (0, 0, -0.9), "hips": (0, 0, 9), "spine": (14, 0, -14), "head": (-8, 0, 5),
             "hair": (-10, 0, 0), "leg_L": (-48, 0, 0), "leg_R": (42, 0, 0),
             "arm_L": (55, -8, 0), "arm_R": (-55, 8, 0)}
RUN_PASS = {"hips_loc": (0, 0, 0.5), "spine": (12, 0, 0), "head": (-6, 0, 0), "hair": (8, 0, 0),
            "leg_L": (8, 0, 0), "leg_R": (-20, 0, 0), "arm_L": (8, -6, 0), "arm_R": (-8, 6, 0)}

JUMP_A = {"spine": (-6, 0, 0), "head": (-8, 0, 0), "hair": (14, 0, 0), "leg_L": (-38, 0, 0), "leg_R": (22, 0, 0),
          "arm_L": (-20, -70, 0), "arm_R": (-20, 70, 0)}
JUMP_B = dict(JUMP_A, arm_L=(-20, -78, 0), arm_R=(-20, 78, 0), hair=(18, 0, 0))

FALL_A = {"spine": (8, 0, 0), "head": (-4, 0, 0), "hair": (-30, 0, 0), "leg_L": (-14, -14, 0), "leg_R": (20, 14, 0),
          "arm_L": (0, -125, 0), "arm_R": (0, 125, 0)}
FALL_B = dict(FALL_A, arm_L=(0, -140, 0), arm_R=(0, 140, 0), hair=(-38, 0, 0),
              leg_L=(-8, -18, 0), leg_R=(14, 18, 0))


def add_actions(arm):
    arm.animation_data_create()
    add_action(arm, "idle", [(0, IDLE_UP), (24, IDLE_DOWN), (48, IDLE_UP)])
    add_action(arm, "run", [(0, RUN_REACH), (4, RUN_PASS), (8, mirror_pose(RUN_REACH)),
                            (12, mirror_pose(RUN_PASS)), (16, RUN_REACH)])
    add_action(arm, "jump", [(0, JUMP_A), (6, JUMP_B), (12, JUMP_A)])
    add_action(arm, "fall", [(0, FALL_A), (5, FALL_B), (10, FALL_A)])


# ---------------------------------------------------------------- the heroes

def base_body(b, torso_half=3.0, shoes=None, sleeve="shirt", hand_rows=1.0):
    """Legs, hips, neck, head, face and arms shared by every hero. The torso and hair are per hero."""
    b.box("leg_L", "pants", (1.3, 2.7), (-0.7, 0.7), (0, 7), mirror=True)
    if shoes:
        b.box("leg_L", shoes, (1.2, 2.8), (-2.0, 0.8), (0, 1.1), mirror=True)
    b.box("hips", "pants", (-torso_half, torso_half), (-1.6, 1.6), (6.8, 8.5))
    b.box("spine", "skin_shade", (-1.5, 1.5), (-1.2, 1.2), (13.5, 14.6))
    b.box("head", "skin", (-4, 4), (-3.5, 3.5), (15.2, 19.6))
    b.box("head", "skin", (-3.3, 3.3), (-3.2, 3.2), (14.4, 15.2))
    b.box("head", "eye", (1.0, 2.0), (-3.62, -3.4), (15.6, 18.4), mirror=True)
    b.box("head", "blush", (2.9, 3.9), (-3.58, -3.4), (15.4, 16.4), mirror=True)
    arm_in = torso_half
    b.box("arm_L", sleeve, (arm_in, arm_in + 1.4), (-0.8, 0.8), (8.6 + hand_rows, 13.4), mirror=True)
    b.box("arm_L", "skin", (arm_in + 0.1, arm_in + 1.3), (-0.7, 0.7), (8.4, 8.6 + hand_rows), mirror=True)


def hair_cap(b, top=21.6, brow=18.8, nape=15.6):
    """A cap of hair: top, back, sides and a fringe over the brow."""
    b.box("head", "hair", (-4.3, 4.3), (-3.8, 3.8), (19.6, top))
    b.box("head", "hair_shade", (-4.3, 4.3), (1.6, 3.8), (nape, 19.6))
    b.box("head", "hair", (3.6, 4.3), (-1.2, 1.6), (17.0, 19.6), mirror=True)
    b.box("head", "hair_shade", (-4.3, 4.3), (-3.8, -3.3), (brow, 19.6))


def joe():
    b = Body({"skin": "f0bd8c", "skin_shade": "dd8a70", "blush": "dd8a70", "eye": "222034",
              "hair": "c29e63", "hair_shade": "af8b51", "pants": "20243d",
              "shirt": "2c866b", "shirt_dark": "336556", "collar": "314035"})
    base_body(b, sleeve="shirt_dark")
    # green striped jumper: one box per sprite row
    for i, color in enumerate(["shirt_dark", "shirt", "shirt_dark", "shirt", "collar"]):
        b.box("spine", color, (-3, 3), (-1.7, 1.7), (8.5 + i, 9.5 + i))
    hair_cap(b)
    # the cowlick that flicks up in the idle
    b.box("hair", "hair", (-3.6, -1.6), (-2.4, 0.4), (21.6, 22.4))
    b.box("hair", "hair", (-4.8, -3.2), (-3.4, -1.6), (21.9, 23.0))
    return b


def matt():
    b = Body({"skin": "f0bd8c", "skin_shade": "dd8a70", "blush": "dd8a70", "eye": "222034",
              "hair": "4a5072", "hair_shade": "20243d", "pants": "20243d",
              "shirt": "cbdbfc", "shirt_shade": "96a4c0", "jacket": "d95763", "jacket_dark": "b13a45"})
    base_body(b, sleeve="jacket")
    b.box("spine", "shirt", (-3, 3), (-1.6, 1.6), (8.5, 12.6))
    b.box("spine", "shirt_shade", (-3, 3), (-1.6, 1.6), (12.6, 13.5))
    # open red jacket: back, sides and two front panels
    b.box("spine", "jacket", (-3.2, 3.2), (0.4, 1.9), (8.4, 13.6))
    b.box("spine", "jacket", (1.2, 3.2), (-1.9, 0.4), (8.4, 13.6), mirror=True)
    b.box("spine", "jacket_dark", (1.0, 1.7), (-1.95, -1.6), (10.4, 13.6), mirror=True)
    hair_cap(b, top=21.8, brow=18.6)
    # swept fringe and the spikes at the back
    b.box("head", "hair", (-4.6, 1.5), (-4.3, -3.6), (19.2, 20.8))
    b.box("hair", "hair", (-2.5, 4.0), (-1.0, 3.0), (21.8, 22.6))
    b.box("hair", "hair", (1.4, 3.4), (3.8, 5.0), (19.4, 21.0))
    b.box("hair", "hair", (-3.6, -1.4), (3.8, 4.8), (17.2, 18.8))
    b.box("hair", "hair_shade", (-1.2, 1.2), (3.8, 4.6), (15.4, 16.8))
    return b


def alex():
    b = Body({"skin": "ddbd9f", "skin_shade": "ce9488", "blush": "cd649e", "eye": "222034",
              "hair": "e8af3b", "hair_shade": "d99f2a", "pants": "3345b3", "shoes": "cbdbfc",
              "shirt": "e35a1e", "shirt_dark": "d24e13", "belt": "000000", "buckle": "663931"})
    base_body(b, torso_half=2.5, shoes="shoes", sleeve="shirt_dark")
    b.box("spine", "shirt", (-2.5, 2.5), (-1.6, 1.6), (9.4, 13.5))
    b.box("spine", "belt", (-2.6, 2.6), (-1.7, 1.7), (8.4, 9.4))
    b.box("spine", "buckle", (-0.7, 0.7), (-1.85, -1.6), (8.5, 9.3))
    hair_cap(b, top=21.8, brow=19.0, nape=14.4)
    # long hair: down the back and over the shoulders
    b.box("hair", "hair", (-4.4, 4.4), (2.2, 4.3), (11.0, 20.0))
    b.box("hair", "hair_shade", (-3.4, 3.4), (2.6, 4.0), (9.6, 11.0))
    b.box("hair", "hair", (3.5, 4.5), (-1.6, 2.2), (12.6, 19.6), mirror=True)
    b.box("head", "hair", (2.2, 4.3), (-3.9, -3.3), (17.6, 19.6), mirror=True)
    return b


def jon():
    b = Body({"skin": "f0bd8c", "skin_shade": "dd8a70", "blush": "dd8a70", "eye": "222034",
              "hair": "222034", "hair_shade": "20243d", "pants": "20243d", "shoes": "cbdbfc", "sole": "b13a45",
              "shirt": "0d7ac2", "shirt_dark": "1a699d", "collar": "084b77", "tee": "d9dee1",
              "frame": "5c5979", "lens": "cbdbfc"})
    base_body(b, shoes="shoes", sleeve="shirt_dark", hand_rows=2.0)
    b.box("leg_L", "sole", (1.2, 2.8), (-2.05, -1.2), (0, 0.6), mirror=True)
    b.box("spine", "shirt", (-3, 3), (-1.7, 1.7), (8.5, 13.5))
    b.box("spine", "shirt_dark", (-0.4, 0.4), (-1.8, -1.6), (8.5, 12.0))
    b.box("spine", "tee", (-1.4, 1.4), (-1.82, -1.6), (12.0, 13.5))
    b.box("spine", "collar", (1.4, 3.6), (-1.9, 1.9), (13.0, 14.0), mirror=True)
    hair_cap(b, top=21.6, brow=19.0)
    b.box("hair", "hair", (-0.8, 2.4), (3.8, 5.2), (20.4, 21.4))
    b.box("hair", "hair", (0.4, 1.6), (4.6, 5.6), (21.0, 22.2))
    # big glasses: frame, lenses, pupils, and the arms back to the ears
    b.box("head", "frame", (-4.1, 4.1), (-4.0, -3.5), (15.7, 18.7))
    b.box("head", "lens", (0.4, 3.6), (-4.1, -3.9), (16.1, 18.3), mirror=True)
    b.box("head", "eye", (1.0, 2.0), (-4.2, -4.0), (16.4, 17.8), mirror=True)
    b.box("head", "frame", (4.0, 4.4), (-3.9, 1.0), (17.2, 17.9), mirror=True)
    return b


HEROES = {"joe": joe, "matt": matt, "alex": alex, "jon": jon}


# ---------------------------------------------------------------- output

def render(arm, hero, shot, direction, pose):
    apply_pose(arm, pose)
    scene = bpy.context.scene
    cam = scene.camera
    target = Vector((0, 0, 11 * PX))
    cam.location = target + Vector(direction).normalized() * 6.0
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = os.path.join(PREVIEW_DIR, "%s_%s.png" % (hero, shot))
    bpy.ops.render.render(write_still=True)
    apply_pose(arm, {})


def build(hero):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.fps = FPS
    arm = build_armature(hero)
    mesh = HEROES[hero]().to_object(hero)
    mesh.parent = arm
    mesh.modifiers.new("Armature", "ARMATURE").object = arm

    if PREVIEW_DIR:
        cam_data = bpy.data.cameras.new("preview")
        cam_data.type = "ORTHO"
        cam_data.ortho_scale = 2.4
        scene.camera = bpy.data.objects.new("preview", cam_data)
        scene.collection.objects.link(scene.camera)
        scene.render.engine = "BLENDER_WORKBENCH"
        scene.display.shading.light = "STUDIO"
        scene.display.shading.color_type = "MATERIAL"
        scene.render.resolution_x = 420
        scene.render.resolution_y = 520
        scene.render.film_transparent = True
        render(arm, hero, "front", (0.45, -1, 0.25), {})
        render(arm, hero, "back", (-0.6, 1, 0.3), {})
        render(arm, hero, "run", (1, -0.35, 0.15), RUN_REACH)
        bpy.data.objects.remove(scene.camera)

    add_actions(arm)
    scene.frame_start = 0
    scene.frame_end = 48
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, hero + ".blend"))
    bpy.ops.export_scene.gltf(
        filepath=os.path.join(ROOT, "models", hero + ".glb"),
        export_format="GLB",
        export_animations=True,
        export_animation_mode="NLA_TRACKS",
        export_force_sampling=True,
        export_yup=True,
    )
    print("BUILT", hero)


for hero_name in HEROES:
    build(hero_name)
print("HEROES BUILT")
