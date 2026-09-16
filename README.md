# Luanti mod: x_player_api

Provides a high-performance, next-generation Player API for Luanti, featuring full support for **glTF multi-track animations** (Luanti 5.17+), realistic biomechanical locomotion, kinematic action layers, eating animation and crumb simulation (`eating.lua`), and 3D wield items (`wield.lua`).

Fully backward compatible with classic `.b3d` single-track models and standard mods (`3d_armor`, `skinsdb`, `simple_skins`).

---

## Architecture: Multi-Track Animations

`x_player_api` leverages Luanti's glTF multi-track animation capabilities to decouple whole-body locomotion from upper-body interactions using bone-masked priority layers:

```
┌────────────────────────────────────────────────────────────────────────┐
│                        Action Layer (Priority 1)                       │
│    Bones: Arm_Right, Arm_Left, Head (Zero influence on Pelvis/Legs)    │
│    Tracks: mine, attack_slash, attack_thrust, block, eat, bow, emotes  │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │ Blended simultaneously
┌───────────────────────────────────▼────────────────────────────────────┐
│                      Locomotion Layer (Priority 0)                     │
│    Bones: Pelvis, Spine, Torso, Hips, Thighs, Calves, Feet             │
│    Tracks: stand, walk, sprint, crouch, crouch_walk, slide, jump, etc. │
└────────────────────────────────────────────────────────────────────────┘
```

### Why Bone Masking Matters
In traditional single-track models (`.b3d`), digging while walking requires a separately baked hybrid animation (`walk_mine`). If you sprint while digging, the engine either cancels sprinting or slides the feet unnaturally.

With glTF multi-track:
- **Zero Foot-Sliding**: Locomotion tracks drive the pelvis and legs according to actual physics and velocity.
- **Simultaneous Action**: Action tracks animate the arms and head without overwriting leg keyframes.
- **Natural Gaze & Breathing**: Idle breathing and walking gait sway continue uninterrupted while swinging tools or raising shields.

---

## Controls & Animation States

### Locomotion Layer

| State | Controls / Trigger | Collisionbox (x1, y1, z1, x2, y2, z2) | Eye Height | Description |
| :--- | :--- | :--- | :--- | :--- |
| **`stand`** | Stationary on solid ground | `{-0.3, 0.0, -0.3, 0.3, 1.7, 0.3}` | 1.47 m | Grounded idle stance with contrapposto weight balance and thoracic breathing. |
| **`walk`** | Move keys (`W`, `A`, `S`, `D`) or Auto-forward (`F` key) | `{-0.3, 0.0, -0.3, 0.3, 1.7, 0.3}` | 1.47 m | Athletic 4-phase walking gait with pelvic twist and gaze stabilization. Seamlessly triggered by the `F` auto-forward key, analog sticks, or velocity. |
| **`sprint`** | Hold `aux1` (`E`) or double-tap `W` while moving forward | `{-0.3, 0.0, -0.3, 0.3, 1.7, 0.3}` | 1.47 m | High-knee forward sprint stride with dynamic forward torso lean. |
| **`crouch`** | Hold `sneak` (`Shift`) while stationary | `{-0.3, 0.0, -0.3, 0.3, 1.45, 0.3}` | 1.25 m | Low stealth crouch with bent knees; lowered hitbox and eye height. |
| **`crouch_walk`** | Hold `sneak` (`Shift`) + move | `{-0.3, 0.0, -0.3, 0.3, 1.45, 0.3}` | 1.25 m | Cautious stealth stride; lets you sneak through 1.5m high spaces. |
| **`slide`** | Tap `sneak` (`Shift`) while sprinting | `{-0.4, 0.0, -0.4, 0.4, 1.1, 0.4}` | 0.90 m | Knee ground-slide under low obstacles. |
| **`jump`** | Press `Space` or moving upward in air | `{-0.3, 0.0, -0.3, 0.3, 1.7, 0.3}` | 1.47 m | Dynamic leap with mid-air knee tuck and apex stretch. |
| **`fall`** | Air descent (`velocity.y < -5.5`) | `{-0.3, 0.0, -0.3, 0.3, 1.7, 0.3}` | 1.47 m | Aerodynamic downward fall with arms stabilized outward. |
| **`swim`** | Submerged in water / liquid | `{-0.3, 0.0, -0.3, 0.3, 1.7, 0.3}` | 1.47 m | Horizontal breaststroke swimming cycle with scissor leg kicks. |
| **`climb`** | On ladder or vines | `{-0.3, 0.0, -0.3, 0.3, 1.7, 0.3}` | 1.47 m | Hand-over-hand ladder climbing while ascending (`Space`/`W`) or descending (`Shift`/`S`). When stationary on a ladder, automatically holds rungs with animation speed paused at 0. |
| **`fly`** | Airborne moving fast with `W`/`A`/`S`/`D` at high speed ($\ge 6.5$ m/s, sprint in air, or fast mode) | `{-0.4, 0.0, -0.4, 0.4, 1.2, 0.4}` | 1.25 m | Dynamic superhero horizontal flight glide with streamlined arms, head looking ahead, and trailing legs. Automatically transitions to hovering when stopping or navigating below speed limit. Ground jumps always retain the jump animation. |
| **`hover`** | Airborne stationary or navigating below flight speed ($< 6.5$ m/s) | `{-0.35, 0.0, -0.35, 0.35, 1.6, 0.35}` | 1.35 m | Gentle levitating hover with upright posture, rhythmic vertical buoyancy, stabilizing arms, and relaxed dangling legs. Automatically engages when stopped or drifting/navigating slowly in the air. |
| **`sit`** | Chat command `/sit` or sitting node | `{-0.3, 0.0, -0.3, 0.3, 1.0, 0.3}` | 0.80 m | Relaxed seated posture with legs locked flat on the ground and subtle upper body breathing; automatically cancels when moving. |
| **`lay`** | Chat command `/lay` or zero HP (death) | `{-0.6, 0.0, -0.6, 0.6, 0.3, 0.6}` | 0.30 m | Flat resting posture on back facing skyward, flush to the ground with gentle 80-frame sleeping breathing cycle; automatically cancels when moving. |

### Action & Interaction Layer (Simultaneous with Any Locomotion)

| State | Controls / Trigger | Description |
| :--- | :--- | :--- |
| **`mine`** | Click / hold `LMB` (`dig`) with tools or bare hands | Kinetic downward tool swing with anticipation wind-up and elastic recoil snap. |
| **`attack_slash`** | Click / hold `LMB` while wielding a sword, blade, or saber | Clean high-to-low diagonal sword cleave across the torso with 0 awkward arm roll. |
| **`attack_thrust`** | Click / hold `LMB` while wielding a spear, pike, or javelin | Explosive forward thrust/jab. |
| **`block`** | Hold `RMB` / `place` while holding a shield or guard item | Raises shield into active defensive guard stance. |
| **`eat`** | Click / hold `LMB` (`dig`) or `RMB` (`place`) while holding food | Brings consumable directly to the mouth with rhythmic chewing motion. |
| **`bow_aim`** | Hold `RMB` / `place` to charge bow, or wield a charged bow (`x_bows`) | Both arms angled inward in front of the chest with hands held closely together along the centerline. |
| **`bow_shoot`** | Release drawn string or click `LMB` with charged bow | Dynamic string release snap and right arm recoil follow-through. |
| **`hurt`** | Damaged / HP decrease (`on_player_hpchange`), or `player_api.trigger_hurt` | Defensive impact flinch snapping the head back and drawing arms inward protectively (~0.33s). |

### Social Gestures & Emotes

| Command | Gesture | Description |
| :--- | :--- | :--- |
| `/wave` | **Wave** | Raises right arm high above the right shoulder clear of the face, waving left and right. |
| `/point` | **Point** | Extends right arm forward, pointing in target direction. |
| `/cheer` | **Cheer** | Pumps both arms overhead in a wide celebratory V-shape with hands held wide from the head. |
| `/bow` | **Bow** | Single graceful courtly bow: right hand over heart/chest, left arm swept back, bowing respectfully with a smooth hold and recovery. Cancels automatically on movement. |
| `/sit` | **Sit** | Sits down on the spot; move in any direction to stand back up. |
| `/lay` | **Lay** | Lies down flat on the spot facing skyward; move in any direction to stand back up. |
| `/hurt` | **Hurt** | Triggers the hurt flinch animation immediately (for testing & inspection). |

### Animation Testing & Debug Showcase (Admin Command)

| Command | Privs | Description |
| :--- | :--- | :--- |
| `/test_anim` | `server` | Runs a continuous slideshow showcasing all 27 registered animations for 4.0s each. Each animation is announced in private chat with track and looping details. |
| `/test_anim <seconds>` | `server` | Runs the full slideshow with custom duration per animation (e.g. `/test_anim 2` or `/test_anim 5`). |
| `/test_anim <anim_name> [sec]` | `server` | Previews a single specific animation on your character (e.g. `/test_anim hurt 3` or `/test_anim bow_aim 6`). |
| `/test_anim stop` | `server` | Instantly cancels any active animation slideshow or single-anim preview, restoring normal gameplay animations. |
| `/test_anim list` | `server` | Prints a sorted list of all available animations registered on the current player model. |

> [!TIP]
> While `/test_anim` is active, you can switch camera views (`F7`) or rotate around your character to inspect bone orientations, limb movements, and ground alignment from any angle. When moving, gestures and actions seamlessly play on the upper body while your legs continue walking or running!

---

## Developer Guide & Key Examples

> [!NOTE]
> For the complete, exhaustive API reference including all class definitions, type aliases, method signatures, parameter tables, and return types, please consult **[`API.md`](API.md)**.

`x_player_api` is designed around decoupled modules, zero external game dependencies, and extensible registries. Below are practical examples showcasing the most important and commonly used methods for extending player animations, weapons, consumables, and reactive events.

---

### Custom Animations & Model Tweaks

External mods can register custom animation tracks on character models or adjust playback parameters on existing tracks.

```lua
-- Register a custom action track on character.glb (glTF multi-track)
player_api.register_model_animation("character.glb", "cast_spell", {
    track = "cast_spell",
    fps = 30,
    loop = false,
    blend = 0.15,
})

-- Register single-track frame boundaries on classic character.b3d
player_api.register_model_animation("character.b3d", "cast_spell", {
    x = 240,
    y = 265,
    fps = 30,
    loop = false,
    blend = 0.15,
})

-- Fine-tune playback speed on an existing animation track
player_api.edit_model_animation("character.glb", "walk", {
    fps = 36,
})
```

*See [Core & Model API in API.md](API.md#core--model-api) for all model methods and [AnimationDefinition](API.md#animationdefinition).*

---

### Weapons & Combat Action Mapping

The item action classifier automatically routes client click and hold inputs to upper-body action tracks (`attack_slash`, `attack_thrust`, `block`, `bow_aim`, `bow_shoot`). Mods can map actions by exact item name or item group:

```lua
-- Bind an entire item group to a combat animation
player_api.register_item_action("group:halberd", "attack_slash")

-- Register advanced weapon behaviors (e.g. primary slash and secondary defensive guard)
player_api.register_item_action("my_rpg:dual_daggers", {
    action = "attack_slash",
    alt_action = "block",
})

-- Register a custom bow with aim and release actions
player_api.register_item_action("my_mod:crystal_bow", {
    is_bow = true,
    action = "bow_shoot",
    alt_action = "bow_aim",
})
```

*See [player_api.register_item_action](API.md#player_apiregister_item_action) and [ItemActionDefinition](API.md#itemactiondefinition) in API.md.*

---

### Consumables & Custom Particle Effects

The eating system (`eating.lua`) decouples eating animations, sound triggers, and visual particle feedback. Mods can register custom particle spawners and attach them to items or groups:

```lua
-- Register a custom particle generator (e.g. magical sparkles)
player_api.register_particle_generator("magic_sparkles", function(player, item_name, duration, def)
    local ppos = player:get_pos()
    ppos.y = ppos.y + 1.5
    core.add_particlespawner({
        amount = 15,
        time = duration or 0.8,
        minpos = vector.add(ppos, {x = -0.2, y = -0.1, z = -0.2}),
        maxpos = vector.add(ppos, {x = 0.2, y = 0.2, z = 0.2}),
        minvel = {x = -0.5, y = 0.5, z = -0.5},
        maxvel = {x = 0.5, y = 1.5, z = 0.5},
        texture = "magic_sparkle_particle.png",
        glow = 12,
    })
end)

-- Register potion items with liquid droplets and custom drink sounds
player_api.register_consumable("group:potion", {
    particle_type = "liquid_drops",
    sound = "potion_drink",
    duration = 1.0,
})

-- Register a magical elixir with custom sparkles
player_api.register_consumable("my_magic:elixir_of_life", {
    particle_type = "magic_sparkles",
    sound = "magic_chime",
    duration = 1.2,
})
```

#### Configuration & Runtime Toggling
Eating simulation, sounds, and particle emission can be toggled via settings (`luanti.conf` or the in-game Settings menu under **Mods -> x_player_api**):
```ini
# Enable eating animation, sounds, and crumb / droplet particle effects (default: true)
x_player_api.enable_eating = true
```
Or dynamically in Lua via `player_api.set_eating_enabled(boolean)`.

*See [Eating & Consumables API in API.md](API.md#eating--consumables-api) for generator types and [ConsumableDefinition](API.md#consumabledefinition).*

---

### Reactive State Observers (Zero-Polling)

Instead of polling player state in a server `globalstep`, external mods can register reactive callbacks to listen for locomotion and action transitions:

```lua
-- Listen reactively for state changes (e.g. sound effects, footsteps, weapon swooshes)
player_api.register_on_state_change(function(player, state, prev_loco, prev_action)
    local name = player:get_player_name()

    -- Trigger custom sounds on locomotion state transition
    if state.locomotion ~= prev_loco then
        if state.locomotion == "slide" then
            core.sound_play("player_slide_whoosh", {to_player = name, gain = 0.8})
        elseif prev_loco == "fall" and state.locomotion == "stand" then
            core.sound_play("player_land_thud", {pos = player:get_pos(), gain = 1.0})
        end
    end

    -- Trigger weapon swing whoosh on action change
    if state.action ~= prev_action and state.action == "attack_slash" then
        core.sound_play("sword_swing", {pos = player:get_pos(), gain = 0.5})
    end
end)

-- Query player state at any time
local state = player_api.get_player_state(player)
if state.sprinting and state.moving then
    -- Player is actively sprinting
end
```

*See [player_api.register_on_state_change](API.md#player_apiregister_on_state_change) and the complete [PlayerSemanticState](API.md#playersemanticstate) field specification in API.md.*

---

### Programmatic Action & Impact Triggers

Mods can trigger action animations manually to simulate environmental reactions, combat impacts, or abilities:

```lua
-- Trigger hurt impact flinch (e.g. from poison, spells, or environmental hazards)
player_api.trigger_hurt(player, 0.35)

-- Trigger bow string release snap
player_api.trigger_bow_shoot(player, 0.35)

-- Trigger eating animation and particle simulation programmatically
player_api.trigger_eat(player, 1.2, "default:apple")

-- Directly play or stop any action track (force=true restarts if already active)
player_api.play_action(player, "hurt", true)
player_api.play_action(player, nil) -- Stops active action track
```

*See [Locomotion & Action Controls API in API.md](API.md#locomotion--action-controls-api).*

---

### Model Redirection & Armor / Skin Mods

Instead of monkey-patching `player_api.set_model` (which causes fragile load-order bugs), mods register clean redirection rules:

```lua
if core.get_modpath("x_player_api") then
    -- Direct alias redirection (e.g. 3d_armor or equipment meshes)
    player_api.register_model_redirect("character.glb", "3d_armor_character.glb")
    player_api.register_model_redirect("character.b3d", "3d_armor_character.b3d")

    -- Dynamic pattern redirection (matches any skin model request)
    player_api.register_model_redirect("*", function(player, model_name)
        if model_name:find("^custom_skin_") then
            return "custom_mesh.glb"
        end
    end)
end
```

*See [player_api.register_model_redirect](API.md#player_apiregister_model_redirect) in API.md.*

---

### Custom Locomotion & Action Evaluators

Mods can inject custom movement logic into the priority evaluator pipeline with zero garbage collection overhead:

```lua
-- Custom locomotion evaluator (priority 50 executes ahead of default walk/stand logic)
player_api.register_locomotion_evaluator(50, function(player, ctx)
    -- If player is wearing a glider or flight harness, trigger flight animation
    if ctx.in_air and player:get_meta():get_string("has_glider") == "true" then
        return "fly"
    end
    -- Return nil to fall through to standard movement evaluation
    return nil
end)
```

*See [StateEvaluationContext](API.md#stateevaluationcontext) in API.md for all pre-allocated context fields.*

---

### Client Input & Control Events

Intercept raw client inputs without polling:

```lua
-- Key Press
player_api.register_on_control_press(function(player, key)
    if key == "aux1" then
        -- Handle ability activation
    end
end)

-- Key Hold (fired every frame key remains depressed)
player_api.register_on_control_hold(function(player, key, duration)
    if key == "sneak" and duration > 3.0 then
        -- Charged stealth mechanic
    end
end)

-- Key Release
player_api.register_on_control_release(function(player, key, duration)
    -- duration in seconds
end)
```

*See [Type Aliases & Callbacks in API.md](API.md#type-aliases--callbacks).*

---

## Performance & Server Scalability Architecture

`x_player_api` is engineered for 60 FPS client responsiveness and high-population dedicated servers ($N = 50+$):

* **Zero-GC Hot Loop**: All per-player semantic states are pre-allocated on join and mutated in-place. The globalstep produces **0 temporary table allocations** per frame.
* **$O(1)$ Memoized Item Classification**: Wielded item groups (`food`, `shield`, `bow`, `eatable`) and weapon action substrings (`sword`, `blade`, `spear`) are evaluated once on first encounter and stored in `ITEM_CACHE`.
* **Center-First Short-Circuiting**: Ground collision checks probe `{x = 0, z = 0}` first. Because ground terrain is solid over 95% of the time, the outer 4 corner probes are skipped, eliminating ~80% of `core.get_node_or_nil` queries.
* **Attached Entity Fast-Path**: Players riding carts, boats, mounts, or airships immediately exit terrain checks, avoiding redundant raycasts.

---

## Debugging & Administration Commands

* `/controls_debug`: Display current player control and semantic locomotion state in real time.
* `/model_format [glb|b3d|toggle|status]`: Query or instantly switch the active player model format between modern GLB (multi-track) and classic B3D (single-track) on the fly.
* `/toggle_model`: Quick shortcut to toggle between GLB and B3D formats without restarting the server.
* `/test_anim [anim_name|duration|list|stop]`: Run an in-game animated slideshow or test a specific animation.

---

## Model Format Selection (GLB vs. B3D)

`x_player_api` provides full dual-format support for both **GLB (glTF 2.0 binary)** and **B3D (Blitz3D)** player character models.

#### Configuration (`luanti.conf`)

You can set the default model format globally:
```ini
# Choose 'glb' (default) for multi-track skeletal animation or 'b3d' for classic single-track timeline
x_player_api.model_format = b3d
```
*(Also accessible graphically in the Luanti Settings tab under **Mods -> x_player_api**).*

#### Runtime Switching (Lua API)

```lua
-- Query the active format ("glb" or "b3d")
local current_format = player_api.get_model_format()

-- Switch active format and re-apply mesh to all connected players (or a specific player)
player_api.set_model_format("b3d") -- Switches to character.b3d / 3d_armor_character.b3d
player_api.set_model_format("glb") -- Switches to character.glb / 3d_armor_character.glb
```

---

## 3D Wield Items

`x_player_api` provides native 3D wielded item rendering via an ephemeral child `LuaEntity` attached to the standard `Arm_Right` bone.

### Key Technical Features

* **Native 3D Extrusion & Mesh Rendering**: Uses Luanti's built-in `visual = "wielditem"`, automatically extruding 2D inventory sprites into 3D voxel items and rendering registered node boxes and 3D meshes natively.
* **Zero Rig Alteration**: Attached directly to the canonical `Arm_Right` bone. Syncs seamlessly with all walking, sprinting, mining, attacking, and emote animations across both `character.glb` and `character.b3d`.
* **Server Performance (`static_save = false`)**: Child entities are never saved to mapblocks. In the event of a server shutdown or restart, entities vanish cleanly without database pollution or orphaned items.
* **Physics & Raycast Isolation (`pointable = false`)**: Attached items never block user crosshairs, node digging, or projectile raycasts.
* **Throttled Updates (0.2s Interval)**: Item checks are decoupled from frame step intervals. Property updates are pushed to clients only when the held item string changes.
* **Natural Forward Alignment & Proportionate Scale**: Calibrated with canonical forward bone orientation (`rot = {x = -90, y = 45, z = 90}`, `pos = {x = 0, y = 5.2, z = -3.5}`) and calculated dynamically from the held item's `wield_scale`, preventing oversized models, backward fin-stretching, and double-scaling.
* **Smart Category & Group Orientations**: Includes built-in angle compensation for upright items (torches, saplings, plants at 180°), reverse-diagonal tools (shovels, screwdrivers, vessels at 135°), and nodes (compact 0.75x mini-blocks).
* **Pivot Translation Drift Compensation**: Automatically compensates for origin expansion on elongated weapons, keeping handles firmly positioned in the palm grip.
* **Ecosystem Compatibility**: Automatically disables legacy 2D texture compositing from `3d_armor` / `wieldview` to prevent z-fighting and duplicate items.

### 3D Wield Item Customization & Extensibility

`x_player_api` provides four decoupled mechanisms for mods to customize held item positioning, rotation, scale, and luminescence without touching core mod files:

#### Direct Item & Node Definition Properties (Flat Prefixes)

In accordance with [Luanti engine guidelines (`lua_api.md`)](https://github.com/luanti-org/luanti/blob/master/doc/lua_api.md), custom fields added to item or node definitions must start with an underscore (`_`) to avoid collisions with future engine properties. Non-prefixed attributes (like `wield_offset`) are ignored.

Any mod registering a craftitem, tool, or node can declare custom wield transforms directly using flat prefixed fields:

```lua
core.register_tool("weapons:halberd", {
    description = "Steel Halberd",
    inventory_image = "weapons_halberd.png",
    _wield_offset = {x = 0, y = 0.8, z = -0.4},   -- Hand bone translation offset {x, y, z}
    _wield_rotation = {x = -80, y = 30, z = 85},   -- Local Euler rotation in degrees
    _wield_scale = 1.8,                           -- Scalar visual scale multiplier (or Vector3)
    _wield_glow = 8,                              -- Explicit entity glow brightness (0-14)
})
```

#### Generic Item Groups (`group:*`)

Items belonging to specific item groups automatically receive calibrated transforms without requiring item-specific configurations:

| Group | Hand Alignment | Intended Items |
| :--- | :--- | :--- |
| `group:torch` | Upright forward, angled handle | Torches, lanterns, lit candles |
| `group:bucket` | Upright centered in hand grip | Buckets, pails, large containers |
| `group:vessel` | Upright centered in hand grip | Glass bottles, drinking cups, flasks |
| `group:shovel` | Forward reverse-diagonal | Shovels, spades |
| `group:bow` | Centered bow charging grip | Bows, crossbows |
| `group:screwdriver` | Forward working tip | Screwdrivers, wands, styluses |
| `group:sapling` / `group:flower` / `group:plant` | Upright natural foliage | Flowers, seedlings, crops, bushes |

Any item declaring `groups = {bucket = 1}` or `groups = {vessel = 1}` inherits the group position automatically. Disabled groups (`rating = 0`) are ignored.

#### Runtime API Registration (`player_api.register_wield_item_offset`)

External mods can register or override transforms dynamically at load time:

```lua
-- Get the active wield entity for a player
local entity = player_api.get_wield_entity(player)

-- Set visibility of a player's held item
player_api.set_wield_item_visibility(player, false)

-- Register offset for an entire item group
player_api.register_wield_item_offset("group:bucket", {
    pos = {x = 0, y = 0, z = 0.2},
    rot = {x = 180, y = 0, z = 0},
})

-- Register offset for a specific third-party item
player_api.register_wield_item_offset("weapons:greatsword", {
    pos = {x = 0, y = 5.0, z = 2.4},
    scale = {x = 1.2, y = 2.0, z = 1.2},
})
```

#### Base Type Fallbacks

Any item without custom definitions or groups automatically falls back to its engine type (`type:node`, `type:tool`, or `type:craftitem`), ensuring full 3D nodes, diagonal tools, and upright 2D craftitems render consistently with zero manual setup.

#### Configuration & Runtime Toggling

3D wielded item rendering can be enabled or disabled via settings (`luanti.conf` or the in-game Settings menu under **Mods -> x_player_api**):

```ini
# Enable 3D wielded item rendering attached to the player hand (default: true)
x_player_api.enable_wield_item = true
```

Or dynamically in Lua via `player_api.set_wield_item_enabled(boolean)`.

*See [3D Wield Item API in API.md](API.md#3d-wield-item-api) for full method signatures, transforms, and [WieldItemCustomDef](API.md#wielditemcustomdef).*

---

## Testing Framework

`x_player_api` includes a zero-dependency, modular BDD (Behavior-Driven Development) test framework designed for testing Luanti mods without requiring the Luanti engine or graphical client to be running. It is compatible with standard BDD runners like Busted and Mineunit.

### Running Tests

Run the complete test suite directly with Lua (compatible with Lua 5.1 / LuaJIT):

```bash
lua test.lua
```

Static analysis and lint checks are run via `luacheck`:

```bash
luacheck .
```

Workspace code style and type diagnostics are run via `lua-language-server`:

```bash
lua-language-server --check=.
```

### Test Suite Structure

The test architecture is organized under the `tests/` directory:

```
tests/
├── framework.lua         # Lightweight BDD test runner and assertion library
├── mock_env.lua          # Mock Luanti engine environment (core.*, ItemStack, vector, Player SAO)
└── specs/                # Modular test specifications
    ├── controls_spec.lua        # Semantic state engine, recovery, posture & airborne gating
    ├── eating_spec.lua          # Consumable registry, node/craftitem crumbs, eating action
    ├── model_spec.lua           # Format switching (GLB/B3D), B3D binary validation, aliases
    ├── wield_entity_spec.lua    # 3D child entity lifecycle, delta updates, death/respawn
    ├── wield_offsets_spec.lua   # Attachment math, flat prefix attributes, scale normalization
    └── wield_settings_spec.lua  # Dynamic runtime settings enablement & cleanup
```

- **[`test.lua`](test.lua)**: The clean entrypoint runner that initializes the mock environment, exposes BDD test globals, requires spec suites, and reports aggregate results.
- **[`tests/framework.lua`](tests/framework.lua)**: Implements `describe`, `it`, `before_each`, and `after_each` lifecycle blocks, deep table equality assertions, colorized ANSI output, execution timing, and failure summaries without fail-stop execution.
- **[`tests/mock_env.lua`](tests/mock_env.lua)**: Pure Lua implementation of Luanti engine globals (`core.*`), vector math, item stacks with metadata serialization, particle spawner tracking, timers, and simulated player objects.

### Writing New Tests

Create a new specification file under `tests/specs/<feature>_spec.lua` or add to existing spec files.

#### 1. Anatomy of a Spec File

```lua
-- tests/specs/my_feature_spec.lua
local mock_env = require("tests.mock_env")

describe("My Feature Subsystem", function()
	local player

	before_each(function()
		-- Set up fresh player or reset state before each test case
		player = mock_env.join_player("Tester")
	end)

	after_each(function()
		-- Optional clean-up after each test
	end)

	it("evaluates expected behavior", function()
		player:set_wielded_item("default:sword_steel", 1)
		player_api.update_wield_item(player, true)

		local entity = player_api.get_wield_entity(player)
		assert.is_not_nil(entity, "Wield entity should be attached")
		assert.equal(true, entity:get_properties().is_visible)
	end)

	it("verifies numerical precision with tolerances", function()
		local pos = player:get_pos()
		assert.near(0.0, pos.x, 1e-4, "Position X should be near zero")
	end)
end)
```

#### 2. Registering the Spec in `test.lua`

Add your new spec file to [`test.lua`](test.lua):

```lua
require("tests.specs.my_feature_spec")
```

#### 3. Available Assertions

The built-in assertion library (`assert.*`) provides:

| Assertion | Description |
| :--- | :--- |
| `assert.equal(expected, actual, [msg])` | Exact value equality or deep table comparison with key-level diffs |
| `assert.not_equal(unexpected, actual, [msg])` | Ensures values or tables are not equal |
| `assert.near(expected, actual, [epsilon], [msg])` | Floating point comparison within an epsilon tolerance (default: `1e-5`) |
| `assert.is_true(condition, [msg])` | Asserts condition is strictly `true` |
| `assert.is_false(condition, [msg])` | Asserts condition is strictly `false` |
| `assert.is_nil(val, [msg])` | Asserts value is `nil` |
| `assert.is_not_nil(val, [msg])` | Asserts value is not `nil` |
| `assert.table_equal(expected, actual, [msg])` | Deep recursive comparison of table contents with detailed field diffs |
| `assert.error(func, [msg])` | Verifies that executing `func()` raises an error |

#### 4. Working with Mock Objects

The mock environment provides helpers to simulate Luanti engine behaviors:

* `mock_env.join_player(name)`: Creates a mock player object, registers it in `core.get_connected_players()`, triggers `core.register_on_joinplayer` callbacks, and resolves any immediate attachment timers.
* `mock_env.create_player(name)`: Instantiates a standalone mock player object without triggering join callbacks.
* `player:set_wielded_item(item_name, count, meta)`: Simulates player holding an item with optional metadata (e.g. `meta = {color = "#FF0000"}`).
* `player:set_hp(hp)`: Adjusts player health points (e.g. `0` to test death handlers).
* `core._after_timers`: Inspect or execute queued timers created by `core.after(delay, fn)`.
* `core._particlespawners`: Inspect active particle spawners created by `core.add_particlespawner`.
* `core._sounds_played`: Inspect sounds triggered via `core.sound_play`.

---

## Compiling API Documentation with lua-language-server

All public API methods, configuration registries, types, classes, and callback signatures in `x_player_api` are thoroughly annotated using standard [LuaLS Annotations](https://github.com/LuaLS/lua-language-server/wiki/Annotations) (`@class`, `@type`, `@param`, `@return`, `@nodiscard`, `@alias`).

A fully compiled, exhaustive API reference is maintained in [`API.md`](API.md).

### Prerequisites
Install `lua-language-server`:
* **macOS** (Homebrew): `brew install lua-language-server`
* **Linux** (Arch/Debian/Fedora/pip): Package manager or release binary from [LuaLS GitHub releases](https://github.com/LuaLS/lua-language-server/releases).

### Compilation Command
To recompile `API.md` from the Lua source code annotations:

```bash
mkdir -p doc_build && lua-language-server --doc=. --doc_out_path=doc_build --doc_format_path=scripts/doc_format.lua && cp doc_build/doc.md API.md && rm -rf doc_build
```

### Configuration (`.luarc.json`)
The export behavior and workspace settings are configured in [`.luarc.json`](.luarc.json):
* Targets `Lua 5.1` runtime.
* Pre-defines global engine types (`core`, `player_api`, `x_player_api`, `vector`, `ItemStack`).
* Excludes asset directories, test harnesses, and scratch scripts from documentation output.
* Sets package export namespace to `x_player_api`.

---

## Authors & License

See `license.txt` for license details (LGPLv2.1+ / CC BY-SA 3.0).

