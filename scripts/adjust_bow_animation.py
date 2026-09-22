import bpy
import os

def adjust_bow():
    blend_path = os.path.abspath("mods/x_player_api/assets/character.blend")
    print(f"Loading {blend_path}...")
    bpy.ops.wm.open_mainfile(filepath=blend_path)

    arm = bpy.data.objects.get("Armature")
    if not arm:
        raise RuntimeError("Armature object not found in character.blend")

    act = bpy.data.actions.get("bow")
    if not act:
        raise RuntimeError("Action 'bow' not found in character.blend")

    arm.animation_data.action = act

    body = arm.pose.bones["Body"]
    leg_r = arm.pose.bones["Leg_Right"]
    leg_l = arm.pose.bones["Leg_Left"]

    # Keyframes definition for bow
    # Body bends forward 30 degrees (rot_x = -30 deg) with ZERO translation (hip pivot remains anchored)
    # Legs counter-rotate 30 degrees (rot_x = +30 deg) so feet stay completely locked to the floor (0.0000)
    keyframes = {
        0: {
            "body_loc": (0.0, 0.0, 0.0),
            "body_rot": (1.0, 0.0, 0.0, 0.0),
            "leg_rot": (1.0, 0.0, 0.0, 0.0),
        },
        20: {
            "body_loc": (0.0, 0.0, 0.0),
            "body_rot": (0.9659258, -0.2588190, 0.0, 0.0),
            "leg_rot": (0.9659258, 0.2588190, 0.0, 0.0),
        },
        35: {
            "body_loc": (0.0, 0.0, 0.0),
            "body_rot": (0.9659258, -0.2588190, 0.0, 0.0),
            "leg_rot": (0.9659258, 0.2588190, 0.0, 0.0),
        },
        60: {
            "body_loc": (0.0, 0.0, 0.0),
            "body_rot": (1.0, 0.0, 0.0, 0.0),
            "leg_rot": (1.0, 0.0, 0.0, 0.0),
        },
    }

    for frame, vals in keyframes.items():
        bpy.context.scene.frame_set(frame)
        body.location = vals["body_loc"]
        body.rotation_quaternion = vals["body_rot"]
        leg_r.rotation_quaternion = vals["leg_rot"]
        leg_l.rotation_quaternion = vals["leg_rot"]

        body.keyframe_insert("location", frame=frame)
        body.keyframe_insert("rotation_quaternion", frame=frame)
        leg_r.keyframe_insert("rotation_quaternion", frame=frame)
        leg_l.keyframe_insert("rotation_quaternion", frame=frame)

    # Set LINEAR interpolation for all curves in bow
    for l in act.layers:
        for s in l.strips:
            for cb in s.channelbags:
                for fc in cb.fcurves:
                    for kp in fc.keyframe_points:
                        kp.interpolation = "LINEAR"

    # Verify foot positions at all frames
    print("\n--- FOOT MOTION VERIFICATION ---")
    max_foot_err = 0.0
    for f in range(0, 61):
        bpy.context.scene.frame_set(f)
        bpy.context.view_layer.update()
        err_r = abs(leg_r.tail.x - 1.05) + abs(leg_r.tail.y) + abs(leg_r.tail.z)
        err_l = abs(leg_l.tail.x - (-1.05)) + abs(leg_l.tail.y) + abs(leg_l.tail.z)
        max_foot_err = max(max_foot_err, err_r, err_l)
        if f in (0, 20, 35, 60):
            print(f"Frame {f:2d}: Body.tail.z={round(body.tail.z, 4)}, Leg_R.tail={leg_r.tail}, Leg_L.tail={leg_l.tail}")

    print(f"Maximum foot displacement across all 60 frames: {max_foot_err:.6f}")
    assert max_foot_err < 1e-4, f"Foot moved! Error: {max_foot_err}"

    # Reset pose bones to rest pose and restore active action to stand
    for pb in arm.pose.bones:
        pb.location = (0, 0, 0)
        pb.rotation_euler = (0, 0, 0)
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.scale = (1, 1, 1)

    act_stand = bpy.data.actions.get("stand")
    if act_stand:
        arm.animation_data.action = act_stand

    # Save character.blend
    print(f"\nSaving updated {blend_path}...")
    bpy.ops.wm.save_as_mainfile(filepath=blend_path)
    print("character.blend saved successfully!")

    # Export character.glb
    glb_path = os.path.abspath("mods/x_player_api/models/character.glb")
    print(f"Exporting multi-track glTF to {glb_path}...")
    bpy.ops.export_scene.gltf(
        filepath=glb_path,
        export_format="GLB",
        export_animations=True,
        export_force_sampling=False,
        export_optimize_animation_keep_anim_armature=False,
    )
    print(f"character.glb exported successfully! File size: {os.path.getsize(glb_path)} bytes.")

if __name__ == "__main__":
    adjust_bow()
