#!/usr/bin/env python3
"""
Build assets/character_b3d.blend and export models/character.b3d
Features:
- Single contiguous timeline for Blitz3D export (non multi-track engine support).
- Unreal Engine Mannequin-style full body kinematics (torso, head, arms, legs in natural harmony).
- 100% backwards compatibility with canonical Luanti frame ranges (0..219):
    stand     = 0..79
    sit       = 81..160
    lay       = 162..166
    walk      = 168..187
    mine      = 189..198
    walk_mine = 200..219
- Extended full-body animations (221..725):
    sprint        = 221..237
    jump          = 240..250
    fall          = 251..261
    swim          = 265..285
    climb         = 290..310
    crouch        = 315..355
    crouch_walk   = 360..380
    slide         = 385..400
    attack_slash  = 405..415
    attack_thrust = 420..430
    block         = 435..445
    bow_aim       = 450..465
    bow_shoot     = 466..474
    eat           = 475..495
    hurt          = 500..510
    wave          = 515..535
    point         = 540..555
    cheer         = 560..580
    bow           = 585..645
    fly           = 650..660
    hover         = 665..725
"""

import bpy
import mathutils
import math
import sys
import os

# Helper to convert degrees to radians
def deg2rad(d):
    return math.radians(d)

def euler_quat(x_deg, y_deg, z_deg):
    e = mathutils.Euler((deg2rad(x_deg), deg2rad(y_deg), deg2rad(z_deg)), 'XYZ')
    return e.to_quaternion()

def clamp(val, min_v, max_v):
    return max(min_v, min(max_v, val))

def lerp(a, b, t):
    return a + (b - a) * t

# Dictionary of frame generators for each animation
# Each generator takes local frame `t` (from 0 to duration) and returns:
# { bone_name: { 'loc': (x, y, z), 'rot': (x_deg, y_deg, z_deg) } }
ANIM_DEFS = {}

def register_anim(name, start, end, fn):
    ANIM_DEFS[name] = {
        'start': start,
        'end': end,
        'duration': end - start,
        'fn': fn,
    }

# 1. STAND (0..79, duration 80) - UE Mannequin Relaxed Idle
def eval_stand(t, dur):
    phase = 2.0 * math.pi * (t / dur)
    breath = math.sin(phase)
    sway = math.sin(phase * 0.5)
    
    return {
        'Body': {
            'loc': (0.0, 0.04 * breath, 0.0),
            'rot': (-0.6 + 0.5 * breath, 0.0, 0.4 * sway),
        },
        'Head': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (0.5 - 0.4 * breath, 0.0, -0.3 * sway),
        },
        'Arm_Right': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (1.0 * breath, 0.0, -8.0 - 0.6 * breath),
        },
        'Arm_Left': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (1.0 * breath, 0.0, 8.0 + 0.6 * breath),
        },
        'Leg_Right': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (0.0, 0.0, 1.0),
        },
        'Leg_Left': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (0.0, 0.0, -1.0),
        },
    }
register_anim('stand', 0, 79, eval_stand)

# 2. SIT (81..160, duration 80) - Seated full body
def eval_sit(t, dur):
    phase = 2.0 * math.pi * (t / dur)
    breath = math.sin(phase)
    return {
        'Body': {
            'loc': (0.0, -5.4 + 0.02 * breath, 0.0),
            'rot': (0.0, 0.0, 0.0),
        },
        'Head': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (1.0 * breath, 0.0, 0.0),
        },
        'Arm_Right': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (25.0 + 1.0 * breath, 0.0, -8.0),
        },
        'Arm_Left': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (25.0 + 1.0 * breath, 0.0, 8.0),
        },
        'Leg_Right': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (90.0, 0.0, 4.0),
        },
        'Leg_Left': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (90.0, 0.0, -4.0),
        },
    }
register_anim('sit', 81, 160, eval_sit)

# 3. LAY (162..166, duration 5) - Lying flat
def eval_lay(t, dur):
    return {
        'Body': {
            'loc': (0.0, -5.25, 0.0),
            'rot': (90.0, 0.0, 0.0),
        },
        'Head': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (0.0, 0.0, 0.0),
        },
        'Arm_Right': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (0.0, 0.0, -6.5),
        },
        'Arm_Left': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (0.0, 0.0, 6.5),
        },
        'Leg_Right': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (0.0, 0.0, 2.0),
        },
        'Leg_Left': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (0.0, 0.0, -2.0),
        },
    }
register_anim('lay', 162, 166, eval_lay)

# 4. WALK (168..187, duration 20) - UE Mannequin Natural Walk Cycle
def eval_walk(t, dur):
    phase = 2.0 * math.pi * (t / dur)
    s = math.sin(phase)
    c = math.cos(phase)
    
    return {
        'Body': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (-4.0, 1.0 * s, -1.5 * s),
        },
        'Head': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (4.0, -0.8 * s, 1.2 * s),
        },
        'Arm_Right': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (-38.0 * s, 0.0, -9.0 - 3.0 * c),
        },
        'Arm_Left': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (38.0 * s, 0.0, 9.0 + 3.0 * c),
        },
        'Leg_Right': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (48.0 * s, 0.0, 2.0),
        },
        'Leg_Left': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (-48.0 * s, 0.0, -2.0),
        },
    }
register_anim('walk', 168, 187, eval_walk)

# 5. MINE (189..198, duration 10) - Full-Body Tool Strike
def eval_mine(t, dur):
    # Normalized strike progression
    prog = (t / dur) % 1.0
    if prog < 0.35:
        # Wind up
        sub = prog / 0.35
        arm_r_pitch = lerp(60.0, 115.0, sub)
        torso_pitch = lerp(-2.0, 0.0, sub)
        arm_l_pitch = lerp(5.0, 12.0, sub)
    elif prog < 0.75:
        # Powerful strike down
        sub = (prog - 0.35) / 0.40
        arm_r_pitch = lerp(115.0, 40.0, sub)
        torso_pitch = lerp(0.0, -8.0, sub)
        arm_l_pitch = lerp(12.0, -6.0, sub)
    else:
        # Recovery
        sub = (prog - 0.75) / 0.25
        arm_r_pitch = lerp(40.0, 60.0, sub)
        torso_pitch = lerp(-8.0, -2.0, sub)
        arm_l_pitch = lerp(-6.0, 5.0, sub)
        
    return {
        'Body': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (torso_pitch, 0.0, 0.0),
        },
        'Head': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (-torso_pitch * 0.4, 0.0, 0.0),
        },
        'Arm_Right': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (arm_r_pitch, -3.0, -8.0),
        },
        'Arm_Left': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (arm_l_pitch, 0.0, 9.0),
        },
        'Leg_Right': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (0.0, 0.0, 1.0),
        },
        'Leg_Left': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (0.0, 0.0, -1.0),
        },
    }
register_anim('mine', 189, 198, eval_mine)

# 6. WALK_MINE (200..219, duration 20) - Walk Cycle while Actively Mining
def eval_walk_mine(t, dur):
    # Walk base
    walk_data = eval_walk(t, dur)
    # 2 mining strikes over the 20-frame stride
    strike_prog = ((t % 10) / 10.0)
    if strike_prog < 0.35:
        sub = strike_prog / 0.35
        arm_r_pitch = lerp(60.0, 115.0, sub)
    elif strike_prog < 0.75:
        sub = (strike_prog - 0.35) / 0.40
        arm_r_pitch = lerp(115.0, 45.0, sub)
    else:
        sub = (strike_prog - 0.75) / 0.25
        arm_r_pitch = lerp(45.0, 60.0, sub)
        
    walk_data['Arm_Right'] = {
        'loc': (0.0, 0.0, 0.0),
        'rot': (arm_r_pitch, -2.5, -8.0),
    }
    return walk_data
register_anim('walk_mine', 200, 219, eval_walk_mine)

# 7. SPRINT (221..237, duration 16) - UE Mannequin Athletic Sprint
def eval_sprint(t, dur):
    phase = 2.0 * math.pi * (t / dur)
    s = math.sin(phase)
    c = math.cos(phase)
    
    return {
        'Body': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (-14.0, 1.5 * s, -3.0 * s),
        },
        'Head': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (12.0, -1.0 * s, 2.0 * s),
        },
        'Arm_Right': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (-65.0 * s + 12.0, 0.0, -14.0 - 4.0 * c),
        },
        'Arm_Left': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (65.0 * s + 12.0, 0.0, 14.0 + 4.0 * c),
        },
        'Leg_Right': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (60.0 * s, 0.0, 2.5),
        },
        'Leg_Left': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (-60.0 * s, 0.0, -2.5),
        },
    }
register_anim('sprint', 221, 237, eval_sprint)

# 8. JUMP (240..250, duration 10) - Upward Launch & Float
def eval_jump(t, dur):
    prog = t / dur
    y_off = 0.8 * math.sin(math.pi * prog)
    return {
        'Body': {
            'loc': (0.0, y_off, 0.0),
            'rot': (-8.0, 0.0, 0.0),
        },
        'Head': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (-10.0, 0.0, 0.0),
        },
        'Arm_Right': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (-32.0, 0.0, -18.0),
        },
        'Arm_Left': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (-32.0, 0.0, 18.0),
        },
        'Leg_Right': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (-22.0, 0.0, 4.0),
        },
        'Leg_Left': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (-22.0, 0.0, -4.0),
        },
    }
register_anim('jump', 240, 250, eval_jump)

# 9. FALL (251..261, duration 10) - Airborne Balance Fall
def eval_fall(t, dur):
    phase = 2.0 * math.pi * (t / dur)
    flair = math.sin(phase)
    return {
        'Body': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (4.0, 0.0, 0.0),
        },
        'Head': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (15.0, 0.0, 0.0),
        },
        'Arm_Right': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (35.0 + 5.0 * flair, 0.0, -32.0),
        },
        'Arm_Left': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (35.0 - 5.0 * flair, 0.0, 32.0),
        },
        'Leg_Right': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (-12.0 + 4.0 * flair, 0.0, 6.0),
        },
        'Leg_Left': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (-12.0 - 4.0 * flair, 0.0, -6.0),
        },
    }
register_anim('fall', 251, 261, eval_fall)

# 10. SWIM (265..285, duration 20) - Full Body Swimming Stroke
def eval_swim(t, dur):
    phase = 2.0 * math.pi * (t / dur)
    s = math.sin(phase)
    c = math.cos(phase)
    # Stroke: arms pull back, legs flutter kick
    arm_stroke = 80.0 + 65.0 * s
    arm_spread = 20.0 + 35.0 * abs(c)
    leg_kick = 25.0 * math.sin(phase * 2.0)
    
    return {
        'Body': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (-85.0, 0.0, 0.0),
        },
        'Head': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (55.0, 0.0, 0.0),
        },
        'Arm_Right': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (arm_stroke, 0.0, -arm_spread),
        },
        'Arm_Left': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (arm_stroke, 0.0, arm_spread),
        },
        'Leg_Right': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (leg_kick, 0.0, 3.0),
        },
        'Leg_Left': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (-leg_kick, 0.0, -3.0),
        },
        'Cape': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (0.0, -1.0 + 0.2 * s, 0.0),
        },
    }
register_anim('swim', 265, 285, eval_swim)

# 11. CLIMB (290..310, duration 20) - Alternating Ladder Climb
def eval_climb(t, dur):
    phase = 2.0 * math.pi * (t / dur)
    s = math.sin(phase)
    arm_r_reach = 80.0 + 45.0 * s
    arm_l_reach = 80.0 - 45.0 * s
    leg_r_step = 25.0 - 30.0 * s
    leg_l_step = 25.0 + 30.0 * s
    
    return {
        'Body': {
            'loc': (0.08 * s, 0.0, 0.0),
            'rot': (0.0, 0.0, 1.5 * s),
        },
        'Head': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (-25.0, 0.0, 0.0),
        },
        'Arm_Right': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (arm_r_reach, 0.0, -12.0),
        },
        'Arm_Left': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (arm_l_reach, 0.0, 12.0),
        },
        'Leg_Right': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (leg_r_step, 0.0, 2.0),
        },
        'Leg_Left': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (leg_l_step, 0.0, -2.0),
        },
    }
register_anim('climb', 290, 310, eval_climb)

# 12. CROUCH (315..355, duration 40) - Stealth Crouch Idle
def eval_crouch(t, dur):
    phase = 2.0 * math.pi * (t / dur)
    breath = math.sin(phase)
    return {
        'Body': {
            'loc': (0.0, -1.1 + 0.02 * breath, 0.0),
            'rot': (-10.0 + 0.5 * breath, 0.0, 0.0),
        },
        'Head': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (10.0 - 0.5 * breath, 0.0, 0.0),
        },
        'Arm_Right': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (24.0 + 1.0 * breath, 0.0, -9.0),
        },
        'Arm_Left': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (24.0 + 1.0 * breath, 0.0, 9.0),
        },
        'Leg_Right': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (35.0, 0.0, 3.5),
        },
        'Leg_Left': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (35.0, 0.0, -3.5),
        },
    }
register_anim('crouch', 315, 355, eval_crouch)

# 13. CROUCH_WALK (360..380, duration 20) - Low Stealth Sneak Walk
def eval_crouch_walk(t, dur):
    phase = 2.0 * math.pi * (t / dur)
    s = math.sin(phase)
    c = math.cos(phase)
    return {
        'Body': {
            'loc': (0.1 * s, -1.1, 0.0),
            'rot': (-12.0, 1.0 * s, -2.0 * s),
        },
        'Head': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (12.0, 0.0, 0.0),
        },
        'Arm_Right': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (-20.0 * s + 22.0, 0.0, -10.0),
        },
        'Arm_Left': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (20.0 * s + 22.0, 0.0, 10.0),
        },
        'Leg_Right': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (25.0 * s + 35.0, 0.0, 3.5),
        },
        'Leg_Left': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (-25.0 * s + 35.0, 0.0, -3.5),
        },
    }
register_anim('crouch_walk', 360, 380, eval_crouch_walk)

# 14. SLIDE (385..400, duration 15) - Combat Power Slide
def eval_slide(t, dur):
    prog = t / dur
    dip = 0.5 * math.sin(math.pi * prog)
    return {
        'Body': {
            'loc': (0.0, -3.0 - dip, 0.0),
            'rot': (22.0 + 3.0 * dip, 0.0, -8.0),
        },
        'Head': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (-16.0 - 4.0 * dip, 0.0, 8.0),
        },
        'Arm_Right': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (-35.0 - 5.0 * dip, 0.0, -22.0),
        },
        'Arm_Left': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (-22.0 - 5.0 * dip, 0.0, 32.0),
        },
        'Leg_Right': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (75.0 + 5.0 * dip, 0.0, 4.0),
        },
        'Leg_Left': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (-16.0 - 4.0 * dip, 0.0, -12.0),
        },
    }
register_anim('slide', 385, 400, eval_slide)

# 15. ATTACK_SLASH (405..415, duration 10) - Sword Slash (Subtle, Firm Footing)
def eval_attack_slash(t, dur):
    prog = t / dur
    if prog < 0.35:
        # Wind up high right
        sub = prog / 0.35
        arm_p = lerp(20.0, 75.0, sub)
        arm_r = lerp(-8.0, 30.0, sub)
        body_pitch = lerp(-2.0, -1.0, sub)
    elif prog < 0.75:
        # Powerful slash across left
        sub = (prog - 0.35) / 0.40
        arm_p = lerp(75.0, 48.0, sub)
        arm_r = lerp(30.0, -42.0, sub)
        body_pitch = lerp(-1.0, -6.0, sub)
    else:
        # Recovery
        sub = (prog - 0.75) / 0.25
        arm_p = lerp(48.0, 20.0, sub)
        arm_r = lerp(-42.0, -8.0, sub)
        body_pitch = lerp(-6.0, -2.0, sub)
        
    return {
        'Body': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (body_pitch, 0.0, 0.0),
        },
        'Head': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (-body_pitch * 0.5, 0.0, 0.0),
        },
        'Arm_Right': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (arm_p, 0.0, arm_r),
        },
        'Arm_Left': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (-arm_p * 0.25, 0.0, 12.0),
        },
        'Leg_Right': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (0.0, 0.0, 1.0),
        },
        'Leg_Left': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (0.0, 0.0, -1.0),
        },
    }
register_anim('attack_slash', 405, 415, eval_attack_slash)

# 16. ATTACK_THRUST (420..430, duration 10) - Deep Spear Lunge
def eval_attack_thrust(t, dur):
    prog = t / dur
    if prog < 0.35:
        sub = prog / 0.35
        thrust = lerp(0.0, -15.0, sub)
        arm_p = lerp(20.0, 35.0, sub)
    elif prog < 0.70:
        sub = (prog - 0.35) / 0.35
        thrust = lerp(-15.0, 85.0, sub)
        arm_p = lerp(35.0, 88.0, sub)
    else:
        sub = (prog - 0.70) / 0.30
        thrust = lerp(85.0, 20.0, sub)
        arm_p = lerp(88.0, 20.0, sub)
        
    return {
        'Body': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (-12.0, 0.0, 0.0),
        },
        'Head': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (10.0, 0.0, 0.0),
        },
        'Arm_Right': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (arm_p, 0.0, -6.0),
        },
        'Arm_Left': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (-25.0, 0.0, 14.0),
        },
        'Leg_Right': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (28.0, 0.0, 3.0),
        },
        'Leg_Left': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (-22.0, 0.0, -3.0),
        },
    }
register_anim('attack_thrust', 420, 430, eval_attack_thrust)

# 17. BLOCK (435..445, duration 10) - Defensive Shield Guard
def eval_block(t, dur):
    return {
        'Body': {
            'loc': (0.0, -0.4, 0.0),
            'rot': (-8.0, 0.0, 12.0),
        },
        'Head': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (6.0, 0.0, -10.0),
        },
        'Arm_Right': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (48.0, 0.0, -16.0),
        },
        'Arm_Left': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (65.0, 20.0, 18.0),
        },
        'Leg_Right': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (15.0, 0.0, 5.0),
        },
        'Leg_Left': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (-12.0, 0.0, -5.0),
        },
    }
register_anim('block', 435, 445, eval_block)

# 18. BOW_AIM (450..465, duration 15) - Focused Archer Aim (Pristine Forward Posture)
def eval_bow_aim(t, dur):
    # Matches original character.blend1: Left arm holds bow forward, Right arm pulls string back,
    # Head focused forward, Body and Legs aligned forward with zero lateral twist.
    phase = math.sin(math.pi * (t / dur))
    return {
        'Body': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (0.0, 0.0, 0.0),
        },
        'Head': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (0.0, 8.0 + 1.0 * phase, 0.0),
        },
        'Arm_Right': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (80.0 + 1.0 * phase, -10.0 + 1.0 * phase, 5.0 - 0.5 * phase),
        },
        'Arm_Left': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (75.0 + 1.0 * phase, 35.0 + 1.0 * phase, 30.0 + 1.0 * phase),
        },
        'Leg_Right': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (0.0, 0.0, 1.0),
        },
        'Leg_Left': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (0.0, 0.0, -1.0),
        },
    }
register_anim('bow_aim', 450, 465, eval_bow_aim)

# 19. BOW_SHOOT (466..474, duration 8) - Bow String Release & Recoil (Pristine Animation)
def eval_bow_shoot(t, dur):
    # Matches original character.blend1 keyframe milestones: t=0, 2, 5, 8
    if t <= 2:
        factor = t / 2.0
        head_rot = (0.0, lerp(8.0, 4.0, factor), 0.0)
        arm_r_rot = (lerp(80.0, 82.0, factor), lerp(-10.0, -8.0, factor), lerp(5.0, 4.0, factor))
        arm_l_rot = (lerp(75.0, 45.0, factor), lerp(35.0, 15.0, factor), lerp(30.0, 15.0, factor))
    elif t <= 5:
        factor = (t - 2.0) / 3.0
        head_rot = (0.0, lerp(4.0, 2.0, factor), 0.0)
        arm_r_rot = (lerp(82.0, 78.0, factor), lerp(-8.0, -5.0, factor), lerp(4.0, 2.0, factor))
        arm_l_rot = (lerp(45.0, 25.0, factor), lerp(15.0, 5.0, factor), lerp(15.0, 10.0, factor))
    else:
        factor = min(1.0, (t - 5.0) / 3.0)
        head_rot = (0.0, lerp(2.0, 0.0, factor), 0.0)
        arm_r_rot = (lerp(78.0, 70.0, factor), lerp(-5.0, 0.0, factor), lerp(2.0, -8.0, factor))
        arm_l_rot = (lerp(25.0, 0.0, factor), lerp(5.0, 0.0, factor), lerp(10.0, 8.0, factor))
    
    return {
        'Body': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (0.0, 0.0, 0.0),
        },
        'Head': {
            'loc': (0.0, 0.0, 0.0),
            'rot': head_rot,
        },
        'Arm_Right': {
            'loc': (0.0, 0.0, 0.0),
            'rot': arm_r_rot,
        },
        'Arm_Left': {
            'loc': (0.0, 0.0, 0.0),
            'rot': arm_l_rot,
        },
        'Leg_Right': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (0.0, 0.0, 1.0),
        },
        'Leg_Left': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (0.0, 0.0, -1.0),
        },
    }
register_anim('bow_shoot', 466, 474, eval_bow_shoot)


# 20. EAT (475..495, duration 20) - Eating / Drinking
def eval_eat(t, dur):
    # Matches the GLB animation in character.blend:
    # 2 gentle, smooth chewing nods across 20 frames (10 frames per cycle).
    # t=0, 10, 20: Head=8.0 deg, Arm_Right=(145.0, 0.0, -65.0)
    # t=5, 15:     Head=14.0 deg, Arm_Right=(152.0, 0.0, -68.0)
    phase = 2.0 * math.pi * (t / 10.0)
    chew_factor = 0.5 * (1.0 - math.cos(phase))
    return {
        'Body': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (0.0, 0.0, 0.0),
        },
        'Head': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (8.0 + 6.0 * chew_factor, 0.0, 0.0),
        },
        'Arm_Right': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (145.0 + 7.0 * chew_factor, 0.0, -65.0 - 3.0 * chew_factor),
        },
        'Arm_Left': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (10.0, 0.0, 8.5),
        },
        'Leg_Right': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (0.0, 0.0, 0.0),
        },
        'Leg_Left': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (0.0, 0.0, 0.0),
        },
    }
register_anim('eat', 475, 495, eval_eat)

# 21. HURT (500..510, duration 10) - Impact Flinch
def eval_hurt(t, dur):
    prog = t / dur
    flinch = math.sin(math.pi * prog)
    return {
        'Body': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (14.0 * flinch, 0.0, 0.0),
        },
        'Head': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (-18.0 * flinch, 0.0, -5.0 * flinch),
        },
        'Arm_Right': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (25.0 * flinch, 0.0, -22.0 * flinch - 8.0),
        },
        'Arm_Left': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (25.0 * flinch, 0.0, 22.0 * flinch + 8.0),
        },
        'Leg_Right': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (-10.0 * flinch, 0.0, 4.0),
        },
        'Leg_Left': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (-10.0 * flinch, 0.0, -4.0),
        },
    }
register_anim('hurt', 500, 510, eval_hurt)

# 22. WAVE (515..535, duration 20) - Natural Friendly Wave (Original Cadence)
def eval_wave(t, dur):
    # Match original wave animation timing and cadence (1 gentle wave cycle over 20 frames):
    # f=0: center (-150°), f=5: right (-135°), f=10: left (-165°), f=15: right (-135°), f=20: center (-150°)
    if t <= 5.0:
        frac = t / 5.0
        rz = -150.0 + 15.0 * frac
        head_z = -5.0 + 2.0 * frac
    elif t <= 10.0:
        frac = (t - 5.0) / 5.0
        rz = -135.0 - 30.0 * frac
        head_z = -3.0 - 4.0 * frac
    elif t <= 15.0:
        frac = (t - 10.0) / 5.0
        rz = -165.0 + 30.0 * frac
        head_z = -7.0 + 4.0 * frac
    else:
        frac = (t - 15.0) / 5.0
        rz = -135.0 - 15.0 * frac
        head_z = -3.0 - 2.0 * frac

    return {
        'Body': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (0.0, 0.0, 0.0),
        },
        'Head': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (0.0, 0.0, head_z),
        },
        'Arm_Right': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (0.0, 0.0, rz),
        },
        'Arm_Left': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (5.0, 0.0, 8.0),
        },
        'Leg_Right': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (0.0, 0.0, 1.0),
        },
        'Leg_Left': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (0.0, 0.0, -1.0),
        },
    }
register_anim('wave', 515, 535, eval_wave)

# 23. POINT (540..555, duration 15) - Directing Attention
def eval_point(t, dur):
    return {
        'Body': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (-4.0, 0.0, 0.0),
        },
        'Head': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (2.0, 0.0, 0.0),
        },
        'Arm_Right': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (88.0, 0.0, -4.0),
        },
        'Arm_Left': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (5.0, 0.0, 10.0),
        },
        'Leg_Right': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (0.0, 0.0, 1.0),
        },
        'Leg_Left': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (0.0, 0.0, -1.0),
        },
    }
register_anim('point', 540, 555, eval_point)

# 24. CHEER (560..580, duration 20) - Victory Celebration (Wide V, Grounded)
def eval_cheer(t, dur):
    phase = 2.0 * math.pi * (t / 10.0) # 2 pulse waves
    pulse = math.sin(phase)
    return {
        'Body': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (-4.0, 0.0, 0.0),
        },
        'Head': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (-12.0, 0.0, 0.0),
        },
        'Arm_Right': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (145.0 + 8.0 * pulse, 0.0, -46.0),
        },
        'Arm_Left': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (145.0 + 8.0 * pulse, 0.0, 46.0),
        },
        'Leg_Right': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (0.0, 0.0, 1.5),
        },
        'Leg_Left': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (0.0, 0.0, -1.5),
        },
    }
register_anim('cheer', 560, 580, eval_cheer)

# 25. BOW (585..645, duration 60) - Formal Courtly Bow (Grounded Legs)
def eval_bow(t, dur):
    prog = t / dur
    bend = math.sin(math.pi * prog)
    # Upper body bends forward by 20 deg
    body_pitch = -20.0 * bend
    # Child legs counter-rotate by +20 deg so world rotation remains 0 (firmly grounded)
    leg_pitch = 20.0 * bend
    return {
        'Body': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (body_pitch, 0.0, 0.0),
        },
        'Head': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (-14.0 * bend, 0.0, 0.0),
        },
        'Arm_Right': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (50.0 * bend, -15.0 * bend, -30.0 * bend),
        },
        'Arm_Left': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (-18.0 * bend, 0.0, 10.0),
        },
        'Leg_Right': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (leg_pitch, 0.0, 1.0),
        },
        'Leg_Left': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (leg_pitch, 0.0, -1.0),
        },
    }
register_anim('bow', 585, 645, eval_bow)

# 26. FLY (650..660, duration 10) - Superhero Flight
def eval_fly(t, dur):
    return {
        'Body': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (-80.0, 0.0, 0.0),
        },
        'Head': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (65.0, 0.0, 0.0),
        },
        'Arm_Right': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (16.0, 0.0, -13.0),
        },
        'Arm_Left': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (16.0, 0.0, 13.0),
        },
        'Leg_Right': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (6.0, 0.0, 3.0),
        },
        'Leg_Left': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (6.0, 0.0, -3.0),
        },
    }
register_anim('fly', 650, 660, eval_fly)

# 27. HOVER (665..725, duration 60) - Aerial Float Idle
def eval_hover(t, dur):
    phase = 2.0 * math.pi * (t / dur)
    drift = math.sin(phase)
    return {
        'Body': {
            'loc': (0.0, 0.4 * drift, 0.0),
            'rot': (2.0 + 2.0 * drift, 0.0, 0.0),
        },
        'Head': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (-1.0 - 1.0 * drift, 0.0, 0.0),
        },
        'Arm_Right': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (16.0 + 6.0 * drift, 0.0, -22.0),
        },
        'Arm_Left': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (16.0 + 6.0 * drift, 0.0, 22.0),
        },
        'Leg_Right': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (16.0 + 5.0 * drift, 0.0, 5.0),
        },
        'Leg_Left': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (10.0 + 5.0 * drift, 0.0, -5.0),
        },
    }
register_anim('hover', 665, 725, eval_hover)

# 28. EQUIP (730..740, duration 10) - Unreal Engine Mannequin Weapon Draw / Equip Montage
def eval_equip(t, dur):
    prog = t / dur
    if prog < 0.40:
        sub = prog / 0.40
        # Phase 1: Rapid reach down to hip/belt holster
        arm_p = lerp(0.0, -28.0, sub)
        arm_r = lerp(-8.0, -16.0, sub)
        body_p = lerp(0.0, -2.5, sub)
        body_y = lerp(0.0, 1.8, sub)
        head_p = lerp(0.0, 1.2, sub)
        left_arm_p = lerp(0.0, 3.0, sub)
        left_arm_r = lerp(8.0, 11.0, sub)
    else:
        sub = (prog - 0.40) / 0.60
        # Phase 2: Crisp draw & raise with punchy ease-out settle
        if sub < 0.55:
            # Snap up into ready presentation
            sub2 = sub / 0.55
            sub_ease = 1.0 - (1.0 - sub2) ** 3
            arm_p = lerp(-28.0, 18.0, sub_ease)
            arm_r = lerp(-16.0, -6.0, sub_ease)
            body_p = lerp(-2.5, 0.8, sub_ease)
            body_y = lerp(1.8, -0.5, sub_ease)
            head_p = lerp(1.2, -0.4, sub_ease)
            left_arm_p = lerp(3.0, -1.0, sub_ease)
            left_arm_r = lerp(11.0, 7.5, sub_ease)
        else:
            # Smooth settle back to neutral stance
            sub2 = (sub - 0.55) / 0.45
            sub_ease = sub2 * sub2 * (3.0 - 2.0 * sub2)
            arm_p = lerp(18.0, 0.0, sub_ease)
            arm_r = lerp(-6.0, -8.0, sub_ease)
            body_p = lerp(0.8, 0.0, sub_ease)
            body_y = lerp(-0.5, 0.0, sub_ease)
            head_p = lerp(-0.4, 0.0, sub_ease)
            left_arm_p = lerp(-1.0, 0.0, sub_ease)
            left_arm_r = lerp(7.5, 8.0, sub_ease)

    return {
        'Body': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (body_p, 0.0, body_y),
        },
        'Head': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (head_p, 0.0, 0.0),
        },
        'Arm_Right': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (arm_p, 0.0, arm_r),
        },
        'Arm_Left': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (left_arm_p, 0.0, left_arm_r),
        },
        'Leg_Right': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (0.0, 0.0, 1.0),
        },
        'Leg_Left': {
            'loc': (0.0, 0.0, 0.0),
            'rot': (0.0, 0.0, -1.0),
        },
    }
register_anim('equip', 730, 740, eval_equip)


UPPER_BODY_ACTIONS = {
    'attack_slash',
    'attack_thrust',
    'block',
    'bow_aim',
    'bow_shoot',
    'cheer',
    'eat',
    'hurt',
    'mine',
    'point',
    'wave',
    'equip',
}


def update_swim_action(arm):
    """
    Ensure 'swim' action clip matches the high-quality B3D eval_swim animation:
    Horizontal streamlined body (-85 deg pitch), raised head (+55 deg),
    breaststroke arm sweep and pull, alternating flutter kicks, and trailing cape.
    """
    act_swim = bpy.data.actions.get("swim")
    if act_swim:
        bpy.data.actions.remove(act_swim)
    act_swim = bpy.data.actions.new(name="swim")
    act_swim.use_fake_user = True
    arm.animation_data.action = act_swim
    dur = 20
    for local_frame in range(0, dur + 1):
        pose = eval_swim(local_frame, dur)
        for bname, xf in pose.items():
            bone = arm.pose.bones.get(bname)
            if not bone:
                continue
            if bname == "Body":
                bone.location = mathutils.Vector(xf["loc"])
                bone.keyframe_insert("location", frame=local_frame)
            bone.rotation_quaternion = euler_quat(*xf["rot"])
            bone.keyframe_insert("rotation_quaternion", frame=local_frame)


def update_wave_action(arm):
    """
    Ensure 'wave' action clip matches the friendly B3D eval_wave animation:
    Right arm raised high beside the head (Z > 14, X > 3.5), palm facing
    directly forward (+Y towards the viewer/other players), waving left-to-right.
    Only keys upper-body bones (Arm_Right, Arm_Left, Head) so lower-body
    locomotion (walk, sprint, stand) continues smoothly on track 0.
    """
    act_wave = bpy.data.actions.get("wave")
    if act_wave:
        bpy.data.actions.remove(act_wave)
    act_wave = bpy.data.actions.new(name="wave")
    act_wave.use_fake_user = True
    arm.animation_data.action = act_wave
    dur = 20
    for local_frame in [0, 5, 10, 15, 20]:
        pose = eval_wave(local_frame, dur)
        for bname in ['Head', 'Arm_Right', 'Arm_Left']:
            bone = arm.pose.bones.get(bname)
            if not bone:
                continue
            bone.rotation_quaternion = euler_quat(*pose[bname]['rot'])
            bone.keyframe_insert("rotation_quaternion", frame=local_frame)


def isolate_upper_body_actions(arm):
    """
    Ensure all upper-body action clips in the blend only keyframe upper-body bones
    (Arm_Right, Arm_Left, Head) with rotation_quaternion.
    Strips any Body, Leg_Left, Leg_Right, or location curves so that track 0
    locomotion (walk, sprint) continues to drive the lower body simultaneously.
    Also synchronizes full-body locomotion actions like 'swim' with B3D.
    """
    # 1. Ensure 'equip' action exists with pure upper-body keyframes
    act_equip = bpy.data.actions.get("equip")
    if not act_equip:
        act_equip = bpy.data.actions.new(name="equip")
    act_equip.use_fake_user = True
    arm.animation_data.action = act_equip
    dur = 10
    for local_frame in range(0, dur + 1):
        pose = eval_equip(local_frame, dur)
        for bname in ['Head', 'Arm_Right', 'Arm_Left']:
            bone = arm.pose.bones.get(bname)
            if not bone:
                continue
            bone.rotation_quaternion = euler_quat(*pose[bname]['rot'])
            bone.keyframe_insert("rotation_quaternion", frame=local_frame)

    # 2. Update 'swim' action clip to match the B3D eval_swim animation
    update_swim_action(arm)

    # 3. Update 'wave' action clip to match the B3D eval_wave animation (palm facing forward +Y)
    update_wave_action(arm)

    # 3. For all upper-body actions, purge any curves outside allowed bones or non-rotation curves
    allowed_bones = {'Head', 'Arm_Right', 'Arm_Left'}
    for act_name in UPPER_BODY_ACTIONS:
        act = bpy.data.actions.get(act_name)
        if not act:
            continue
        if hasattr(act, "layers"):
            for layer in act.layers:
                for strip in layer.strips:
                    for channelbag in strip.channelbags:
                        for fcurve in list(channelbag.fcurves):
                            dp = fcurve.data_path
                            bname = dp.split('["')[1].split('"]')[0] if '["' in dp else None
                            prop = dp.split(".")[-1]
                            if bname not in allowed_bones or prop != "rotation_quaternion":
                                channelbag.fcurves.remove(fcurve)
        if hasattr(act, "fcurves"):
            for fcurve in list(act.fcurves):
                dp = fcurve.data_path
                bname = dp.split('["')[1].split('"]')[0] if '["' in dp else None
                prop = dp.split(".")[-1]
                if bname not in allowed_bones or prop != "rotation_quaternion":
                    act.fcurves.remove(fcurve)

    # 3. Ensure all keyframe points use LINEAR interpolation for Irrlicht glTF compatibility
    # (Irrlicht loader error: 'Only STEP and LINEAR keyframe interpolation are supported')
    for act in bpy.data.actions:
        if hasattr(act, "layers"):
            for layer in act.layers:
                for strip in layer.strips:
                    for channelbag in strip.channelbags:
                        for fcurve in channelbag.fcurves:
                            for kp in fcurve.keyframe_points:
                                kp.interpolation = 'LINEAR'
        if hasattr(act, "fcurves"):
            for fcurve in act.fcurves:
                for kp in fcurve.keyframe_points:
                    kp.interpolation = 'LINEAR'

    # 5. Reset all pose bones to clean rest pose and set active action to stand
    for pb in arm.pose.bones:
        pb.location = (0, 0, 0)
        pb.rotation_euler = (0, 0, 0)
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.scale = (1, 1, 1)
    act_stand = bpy.data.actions.get("stand")
    if act_stand:
        arm.animation_data.action = act_stand


def bake_b3d_contiguous_timeline(arm):
    """
    Bake master contiguous timeline for B3D export by sampling directly from
    the Blender actions in bpy.data.actions, ensuring 100% identical animation
    motion and poses between the B3D single-track model and GLB multi-track model.
    """
    print("Baking master contiguous timeline directly from Blender actions...")

    # 1. Pre-sample stand pose at frame 0 as neutral base pose for unkeyed bones
    act_stand = bpy.data.actions.get("stand")
    if act_stand:
        arm.animation_data.action = act_stand
        bpy.context.scene.frame_set(0)
    base_pose = {}
    for b in arm.pose.bones:
        base_pose[b.name] = {
            "loc": mathutils.Vector(b.location),
            "rot": mathutils.Quaternion(b.rotation_quaternion),
        }

    # Helper to discover which bones an action actually animates
    def get_action_animated_bones(act):
        bones = set()
        fcurves = []
        if hasattr(act, "fcurves") and len(act.fcurves) > 0:
            fcurves.extend(act.fcurves)
        if hasattr(act, "layers"):
            for l in act.layers:
                for s in l.strips:
                    for cb in s.channelbags:
                        fcurves.extend(cb.fcurves)
        for fc in fcurves:
            dp = fc.data_path
            if '["' in dp and '"]' in dp:
                bname = dp.split('["')[1].split('"]')[0]
                bones.add(bname)
        return bones

    # Sample each animation frame from the Blender actions
    baked_frames = {}
    for anim_name, info in sorted(ANIM_DEFS.items(), key=lambda item: item[1]["start"]):
        start = info["start"]
        end = info["end"]
        act = bpy.data.actions.get(anim_name)
        if not act:
            print(f"Warning: action '{anim_name}' not found in blend, using fallback formula")
            for g_frame in range(start, end + 1):
                local_frame = g_frame - start
                baked_frames[g_frame] = {}
                pose_dict = info["fn"](local_frame, end - start)
                for bname, xf in pose_dict.items():
                    baked_frames[g_frame][bname] = {
                        "loc": mathutils.Vector(xf["loc"]),
                        "rot": euler_quat(*xf["rot"]),
                    }
            continue

        act_bones = get_action_animated_bones(act)
        arm.animation_data.action = act
        act_start, act_end = act.frame_range

        for g_frame in range(start, end + 1):
            baked_frames[g_frame] = {}
            if anim_name == "lay":
                local_frame = 0
            else:
                local_frame = g_frame - start
                local_frame = min(max(local_frame, act_start), act_end)

            bpy.context.scene.frame_set(int(local_frame))

            for b in arm.pose.bones:
                bname = b.name
                if bname in act_bones:
                    loc = mathutils.Vector(b.location)
                    rot = mathutils.Quaternion(b.rotation_quaternion)
                else:
                    loc = mathutils.Vector(base_pose[bname]["loc"])
                    rot = mathutils.Quaternion(base_pose[bname]["rot"])
                baked_frames[g_frame][bname] = {"loc": loc, "rot": rot}

    # 2. Assign master action and insert keyframes
    master_act = bpy.data.actions.get("character_b3d_timeline")
    if not master_act:
        master_act = bpy.data.actions.new(name="character_b3d_timeline")
    master_act.use_fake_user = True

    # Clear existing curves/layers in master_act
    if hasattr(master_act, "fcurves"):
        for fc in list(master_act.fcurves):
            master_act.fcurves.remove(fc)
    if hasattr(master_act, "layers"):
        for l in list(master_act.layers):
            master_act.layers.remove(l)

    arm.animation_data.action = master_act

    max_global_frame = max(info["end"] for info in ANIM_DEFS.values())
    for g_frame in range(0, max_global_frame + 1):
        frame_data = baked_frames.get(g_frame)
        if not frame_data:
            continue
        for bname, xf in frame_data.items():
            bone = arm.pose.bones.get(bname)
            if not bone:
                continue
            bone.location = xf["loc"]
            bone.rotation_quaternion = xf["rot"]
            bone.keyframe_insert("location", frame=g_frame)
            bone.keyframe_insert("rotation_quaternion", frame=g_frame)

    # Set LINEAR interpolation on master action
    if hasattr(master_act, "fcurves"):
        for fc in master_act.fcurves:
            for kp in fc.keyframe_points:
                kp.interpolation = 'LINEAR'
    if hasattr(master_act, "layers"):
        for l in master_act.layers:
            for s in l.strips:
                for cb in s.channelbags:
                    for fc in cb.fcurves:
                        for kp in fc.keyframe_points:
                            kp.interpolation = 'LINEAR'

    bpy.context.scene.frame_start = 0
    bpy.context.scene.frame_end = max_global_frame
    print(f"Master contiguous timeline baked successfully (frames 0..{max_global_frame})!")


def process_blend(source_blend, output_blend, output_b3d, output_glb=None):
    print(f"\n==================================================")
    print(f"Loading source blend: {source_blend}")
    bpy.ops.wm.open_mainfile(filepath=source_blend)

    arm = bpy.data.objects.get("Armature")
    if not arm:
        raise RuntimeError(f"Armature object not found in {source_blend}")

    if not arm.animation_data:
        arm.animation_data_create()

    # GLB export (only if explicitly requested; source blend is NOT overwritten)
    if output_glb:
        isolate_upper_body_actions(arm)
        print(f"Exporting multi-track glTF: {output_glb}")
        bpy.ops.export_scene.gltf(
            filepath=output_glb,
            export_format='GLB',
            export_animations=True,
            export_force_sampling=False,
            export_optimize_animation_keep_anim_armature=False,
        )
        print(f"GLB export completed! File size: {os.path.getsize(output_glb)} bytes.")

    # Create master contiguous timeline action for B3D export
    bake_b3d_contiguous_timeline(arm)

    if output_blend:
        print(f"Saving {output_blend}...")
        bpy.ops.wm.save_as_mainfile(filepath=output_blend)

    # Export B3D
    if output_b3d:
        print(f"Exporting to {output_b3d}...")
        sys.path.append(os.path.abspath("assets"))
        import export_b3d

        settings = {
            'use_local_transform': False,
            'export_ambient': False,
            'enable_mipmaps': False,
            'use_selection': False,
            'use_visible': True,
            'use_collection': False,
            'object_mesh': True,
            'object_armature': True,
            'object_light': False,
            'object_camera': False,
            'export_texcoords': True,
            'export_materials': True,
            'export_normals': True,
        }
        export_b3d.save(None, bpy.context, output_b3d, settings)
        print(f"B3D export completed! File size: {os.path.getsize(output_b3d)} bytes.")


def main():
    # Process base character models (B3D export only - GLB and source blend remain untouched)
    process_blend(
        source_blend="assets/character.blend",
        output_blend="assets/character_b3d.blend",
        output_b3d="models/character.b3d",
        output_glb=None,
    )


if __name__ == "__main__":
    main()

