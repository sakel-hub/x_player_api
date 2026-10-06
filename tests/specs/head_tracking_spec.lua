-- tests/specs/head_tracking_spec.lua
-- Unit tests for natural and smooth head bone look direction tracking in x_player_api

local mock_env = require("tests.mock_env")

describe("Head Bone Look Tracking Subsystem", function()
	local player
	local name

	before_each(function()
		x_player_api.head_tracking.config.enable = true
		x_player_api.head_tracking.modifiers = {}
		player = mock_env.join_player("test_player")
		name = player:get_player_name()
		x_player_api.set_model(player, "character.b3d")
	end)

	after_each(function()
		if player and player:is_valid() then
			mock_env.leave_player(player)
		end
	end)

	it("initializes head tracking state on player join", function()
		local state = x_player_api.head_tracking.states[name]
		assert.is_not_nil(state, "Player head state must be initialized on join")
		assert.is_true(state.enabled)
		assert.is_true(state.sleeping)
		assert.equal(0, state.current.x)
		assert.equal(0, state.current.y)
		assert.equal(0, state.current.z)
	end)

	it("naturally maps negative look vertical (looking up) to negative head bone pitch", function()
		-- Looking up at 30 degrees (-pi/6 rad)
		local look_up = -math.rad(30)
		player:set_look_vertical(look_up)

		local sem_state = {locomotion = "stand", moving = false}
		-- Step multiple frames to allow smooth convergence
		for _ = 1, 20 do
			x_player_api.step_head_tracking(player, 0.05, sem_state)
		end

		local rot = x_player_api.head_tracking.get_head_rotation(player)
		assert.is_not_nil(rot)
		assert.near(-math.rad(30), rot.x, 0.02, "Head bone pitch must rotate upward (-X) when looking up")

		local proxies = x_player_api.get_visual_proxies(player)
		local ov = proxies.glb:get_bone_override("Head")
		assert.is_not_nil(ov)
		assert.near(-math.rad(30), ov.rotation.vec.x, 0.02)
	end)

	it("naturally maps positive look vertical (looking down) to positive head bone pitch", function()
		-- Looking down at 45 degrees (+pi/4 rad)
		local look_down = math.rad(45)
		player:set_look_vertical(look_down)

		local sem_state = {locomotion = "stand", moving = false}
		for _ = 1, 20 do
			x_player_api.step_head_tracking(player, 0.05, sem_state)
		end

		local rot = x_player_api.head_tracking.get_head_rotation(player)
		assert.is_not_nil(rot)
		assert.near(math.rad(45), rot.x, 0.02, "Head bone pitch must rotate downward (+X) when looking down")

		local proxies = x_player_api.get_visual_proxies(player)
		local ov = proxies.glb:get_bone_override("Head")
		assert.is_not_nil(ov)
		assert.near(math.rad(45), ov.rotation.vec.x, 0.02)
	end)

	it("clamps pitch to anatomical zenith and nadir limits", function()
		local cfg = x_player_api.head_tracking.config
		local sem_state = {locomotion = "stand", moving = false}

		-- Extreme look up (-90 deg / zenith)
		player:set_look_vertical(-math.rad(90))
		for _ = 1, 25 do
			x_player_api.step_head_tracking(player, 0.05, sem_state)
		end
		local rot_up = x_player_api.head_tracking.get_head_rotation(player)
		assert.near(-cfg.pitch_up_max, rot_up.x, 0.01, "Pitch must not exceed anatomical upward limit (-75 deg)")

		-- Extreme look down (+90 deg / nadir)
		player:set_look_vertical(math.rad(90))
		for _ = 1, 25 do
			x_player_api.step_head_tracking(player, 0.05, sem_state)
		end
		local rot_down = x_player_api.head_tracking.get_head_rotation(player)
		assert.near(cfg.pitch_down_max, rot_down.x, 0.01, "Pitch must not exceed anatomical downward limit (70 deg)")
	end)

	it("calculates relative horizontal yaw when attached to a parent entity", function()
		-- Create a parent vehicle entity (facing North / yaw 0)
		local parent = mock_env.join_player("vehicle_entity")
		parent:set_yaw(0)
		player:set_attach(parent, "", {x=0, y=0, z=0}, {x=0, y=0, z=0})

		-- Player looks 45 degrees to the left (yaw = math.rad(45))
		player:set_look_horizontal(math.rad(45))
		player:set_look_vertical(0)

		local sem_state = {locomotion = "sit", moving = false}
		for _ = 1, 25 do
			x_player_api.step_head_tracking(player, 0.05, sem_state)
		end

		local rot = x_player_api.head_tracking.get_head_rotation(player)
		assert.near(-math.rad(45), rot.y, 0.02, "Head bone must turn horizontally relative to vehicle parent")
	end)

	it("clamps attached relative yaw within anatomical limits", function()
		local cfg = x_player_api.head_tracking.config
		local parent = mock_env.join_player("vehicle_entity")
		parent:set_yaw(0)
		player:set_attach(parent, "", {x=0, y=0, z=0}, {x=0, y=0, z=0})

		-- Player looks 120 degrees behind
		player:set_look_horizontal(math.rad(120))
		player:set_look_vertical(0)

		local sem_state = {locomotion = "sit", moving = false}
		for _ = 1, 25 do
			x_player_api.step_head_tracking(player, 0.05, sem_state)
		end

		local rot = x_player_api.head_tracking.get_head_rotation(player)
		assert.near(-cfg.yaw_limit_attached, rot.y, 0.02, "Attached yaw must be clamped to -75 degrees")
	end)

	it("applies smooth exponential decay interpolation over multiple steps", function()
		player:set_look_vertical(-math.rad(40)) -- Target pitch = -40 deg
		local sem_state = {locomotion = "stand", moving = false}

		-- Step 1 (dt = 0.02s): initial displacement should be partial
		x_player_api.step_head_tracking(player, 0.02, sem_state)
		local rot1 = x_player_api.head_tracking.get_head_rotation(player).x
		assert.is_true(rot1 < 0, "Head must begin rotating towards target")
		assert.is_true(rot1 > -math.rad(40), "Head must not jump instantaneously to target")

		-- Step 2: progressive advancement
		x_player_api.step_head_tracking(player, 0.03, sem_state)
		local rot2 = x_player_api.head_tracking.get_head_rotation(player).x
		assert.is_true(rot2 < rot1, "Head must progressively advance each step")
	end)

	it("enters quiescence sleep state once converged and suppresses redundant packet dispatch", function()
		player:set_look_vertical(-math.rad(30))
		local sem_state = {locomotion = "stand", moving = false}

		for _ = 1, 30 do
			x_player_api.step_head_tracking(player, 0.05, sem_state)
		end

		local pstate = x_player_api.head_tracking.states[name]
		assert.is_true(pstate.sleeping, "Tracking must enter sleeping state once converged")

		-- Clear proxy override calls counter to measure quiescence
		local proxies = x_player_api.get_visual_proxies(player)
		proxies.glb._bone_overrides = {}

		-- Next 5 steps while camera is stationary should produce 0 dispatches
		for _ = 1, 5 do
			x_player_api.step_head_tracking(player, 0.05, sem_state)
		end

		assert.is_nil(proxies.glb._bone_overrides["Head"], "Quiescent sleep must dispatch zero bone overrides")
	end)

	it("wakes up from sleep when camera rotation delta exceeds angular deadband", function()
		player:set_look_vertical(0)
		local sem_state = {locomotion = "stand", moving = false}

		-- Settle to sleep at horizon
		for _ = 1, 20 do
			x_player_api.step_head_tracking(player, 0.05, sem_state)
		end
		local pstate = x_player_api.head_tracking.states[name]
		assert.is_true(pstate.sleeping)

		-- Small change below deadband (0.02 < 0.05 rad) -> remains sleeping
		player:set_look_vertical(-0.02)
		x_player_api.step_head_tracking(player, 0.05, sem_state)
		assert.is_true(pstate.sleeping, "Must remain sleeping when delta is under deadband threshold")

		-- Large change exceeding deadband (0.2 rad) -> wakes up
		player:set_look_vertical(-0.2)
		x_player_api.step_head_tracking(player, 0.05, sem_state)
		assert.is_false(pstate.sleeping, "Must wake up from sleep when delta exceeds deadband")
	end)

	it("suppresses head tracking smoothly during lay and freeze postures", function()
		player:set_look_vertical(-math.rad(45))
		local sem_state = {locomotion = "stand", moving = false}

		-- First converge in standing posture
		for _ = 1, 20 do
			x_player_api.step_head_tracking(player, 0.05, sem_state)
		end
		assert.near(-math.rad(45), x_player_api.head_tracking.get_head_rotation(player).x, 0.02)

		-- Transition to lay posture (sleeping in bed)
		sem_state.locomotion = "lay"
		for _ = 1, 25 do
			x_player_api.step_head_tracking(player, 0.05, sem_state)
		end

		local rot_lay = x_player_api.head_tracking.get_head_rotation(player)
		assert.near(0, rot_lay.x, 0.02, "Head tracking must return to rest pose during lay posture")
	end)

	it("reduces head tracking weight during hurt flinch", function()
		player:set_look_vertical(-math.rad(40))
		local sem_state = {locomotion = "stand", action = "hurt"}

		for _ = 1, 25 do
			x_player_api.step_head_tracking(player, 0.05, sem_state)
		end

		local rot = x_player_api.head_tracking.get_head_rotation(player)
		-- Hurt flinch applies 0.5 weight factor -> -40 deg * 0.5 = -20 deg
		assert.near(-math.rad(20), rot.x, 0.02, "Head tracking weight must be scaled down during hurt action")
	end)

	it("resets head orientation to bind pose on reset or respawn", function()
		player:set_look_vertical(-math.rad(45))
		local sem_state = {locomotion = "stand", moving = false}
		for _ = 1, 20 do
			x_player_api.step_head_tracking(player, 0.05, sem_state)
		end

		x_player_api.reset_head_tracking(player)

		local rot = x_player_api.head_tracking.get_head_rotation(player)
		assert.equal(0, rot.x)
		assert.equal(0, rot.y)
		assert.equal(0, rot.z)

		local proxies = x_player_api.get_visual_proxies(player)
		local ov = proxies.glb:get_bone_override("Head")
		assert.equal(0, ov.rotation.vec.x)
	end)

	it("allows custom head tracking modifiers to override rotation and weight (Open/Closed Principle)", function()
		-- Register a custom modifier that forces a specific roll tilt
		x_player_api.register_head_tracking_modifier("custom_tilt", function(_, _, _)
			return {z = math.rad(15)}, 0.8
		end)

		player:set_look_vertical(-math.rad(30))
		local sem_state = {locomotion = "stand", moving = false}
		for _ = 1, 25 do
			x_player_api.step_head_tracking(player, 0.05, sem_state)
		end

		local rot = x_player_api.head_tracking.get_head_rotation(player)
		assert.near(math.rad(15) * 0.8, rot.z, 0.02, "Custom modifier roll rotation must be applied")
		assert.near(-math.rad(30) * 0.8, rot.x, 0.02, "Custom modifier weight multiplier must scale pitch")

		x_player_api.unregister_head_tracking_modifier("custom_tilt")
	end)

	it("cleans up player head state cleanly on player leave", function()
		assert.is_not_nil(x_player_api.head_tracking.states[name])
		mock_env.leave_player(player)
		assert.is_nil(x_player_api.head_tracking.states[name], "Player head state must be purged on disconnect")
	end)

	it("allows disabling head tracking per-player and globally", function()
		-- Per-player disable
		x_player_api.set_head_tracking_enabled(player, false)
		assert.is_false(x_player_api.is_head_tracking_enabled(player))

		player:set_look_vertical(-math.rad(45))
		local sem_state = {locomotion = "stand"}
		x_player_api.step_head_tracking(player, 0.05, sem_state)

		local rot = x_player_api.head_tracking.get_head_rotation(player)
		assert.equal(0, rot.x, "Disabled player must not update head rotation")

		-- Re-enable per-player
		x_player_api.set_head_tracking_enabled(player, true)
		assert.is_true(x_player_api.is_head_tracking_enabled(player))

		-- Global disable
		x_player_api.head_tracking.config.enable = false
		assert.is_false(x_player_api.is_head_tracking_enabled(player))
		x_player_api.step_head_tracking(player, 0.05, sem_state)
		assert.equal(0, rot.x, "Globally disabled subsystem must not update head rotation")
	end)

	it("mutates state vectors in-place with zero memory allocation in hot loop", function()
		local pstate = x_player_api.head_tracking.states[name]
		local orig_current = pstate.current
		local orig_target = pstate.target
		local orig_last_sent = pstate.last_sent

		player:set_look_vertical(-math.rad(30))
		local sem_state = {locomotion = "stand"}
		x_player_api.step_head_tracking(player, 0.05, sem_state)

		assert.equal(orig_current, pstate.current, "Current vector table must be mutated in-place")
		assert.equal(orig_target, pstate.target, "Target vector table must be mutated in-place")
		assert.equal(orig_last_sent, pstate.last_sent, "Last sent vector table must be mutated in-place")
	end)

	it("omits bone position from override when position is nil to prevent head collapsing into torso", function()
		player:set_look_vertical(-math.rad(30))
		local sem_state = {locomotion = "stand"}
		for _ = 1, 15 do
			x_player_api.step_head_tracking(player, 0.05, sem_state)
		end

		local proxies = x_player_api.get_visual_proxies(player)
		local ov = proxies.glb:get_bone_override("Head")
		assert.is_not_nil(ov, "Head bone override must be registered on proxy")
		assert.is_nil(ov.position, "Position must be omitted from override when nil to preserve bind height")
		assert.is_not_nil(ov.rotation, "Rotation must be present in override")
	end)

	it("includes client interpolation duration in bone override payload", function()
		player:set_look_vertical(-math.rad(25))
		local sem_state = {locomotion = "stand"}
		for _ = 1, 15 do
			x_player_api.step_head_tracking(player, 0.05, sem_state)
		end

		local proxies = x_player_api.get_visual_proxies(player)
		local ov = proxies.glb:get_bone_override("Head")
		assert.is_not_nil(ov)
		assert.near(0.1, ov.rotation.interpolation, 1e-4, "Client interpolation duration must be included")
	end)

	it("naturally turns head left/right with body turn lag during free-standing look changes", function()
		-- Player rapidly turns camera 30 degrees to the left
		player:set_look_horizontal(math.rad(30))
		player:set_look_vertical(0)

		local sem_state = {locomotion = "stand"}
		-- Step a small time slice where body is still lagging behind
		x_player_api.step_head_tracking(player, 0.02, sem_state)

		local rot = x_player_api.head_tracking.get_head_rotation(player)
		assert.is_true(rot.y < 0, "Head must turn left (< 0) into the horizontal turn")
		assert.is_true(rot.z > 0, "Head must slightly roll into the turn (+Z roll for -Y yaw)")

		-- After settling, body catches up and head smoothly re-centers
		for _ = 1, 30 do
			x_player_api.step_head_tracking(player, 0.05, sem_state)
		end
		local settled_rot = x_player_api.head_tracking.get_head_rotation(player)
		assert.near(0, settled_rot.y, 0.02, "Head yaw must smoothly re-center once turn settles")
	end)

	it("naturally elevates both arms (-X) on looking up and depresses both arms (+X) on looking down", function()
		-- Look up at 30 degrees (-pi/6 rad)
		player:set_look_vertical(-math.rad(30))
		local sem_state = {locomotion = "stand"}
		for _ = 1, 20 do
			x_player_api.step_head_tracking(player, 0.05, sem_state)
		end

		local rot_r, rot_l = x_player_api.get_head_tracking_arm_rotations(player)
		assert.is_not_nil(rot_r)
		assert.is_not_nil(rot_l)
		-- Idle weight is 0.35; negative X elevates arms forward/up matching head
		local expected_idle_up = -math.rad(30) * 0.35
		assert.near(expected_idle_up, rot_r.x, 0.02, "Right arm must elevate (-X) when looking up")
		assert.near(expected_idle_up, rot_l.x, 0.02, "Left arm must elevate (-X) when looking up")

		local proxies = x_player_api.get_visual_proxies(player)
		local ov_r = proxies.glb:get_bone_override("Arm_Right")
		local ov_l = proxies.glb:get_bone_override("Arm_Left")
		assert.is_not_nil(ov_r)
		assert.is_not_nil(ov_l)
		assert.is_false(ov_r.rotation.absolute, "Arm overrides must be relative (absolute = false)")
		assert.is_false(ov_l.rotation.absolute, "Arm overrides must be relative (absolute = false)")

		-- Look down at 40 degrees (+40 deg rad)
		player:set_look_vertical(math.rad(40))
		for _ = 1, 20 do
			x_player_api.step_head_tracking(player, 0.05, sem_state)
		end
		local rot_r_down, rot_l_down = x_player_api.get_head_tracking_arm_rotations(player)
		local expected_idle_down = math.rad(40) * 0.35
		assert.near(expected_idle_down, rot_r_down.x, 0.02, "Right arm must depress (+X) when looking down")
		assert.near(expected_idle_down, rot_l_down.x, 0.02, "Left arm must depress (+X) when looking down")
	end)

	it("synchronizes dual-arm pitch and compensates Arm_Left bow aim kinematics", function()
		-- 1. Aiming up at 45 degrees
		player:set_look_vertical(-math.rad(45))
		local sem_state = {locomotion = "stand", aiming_bow = true}

		for _ = 1, 25 do
			x_player_api.step_head_tracking(player, 0.05, sem_state)
		end

		local rot_r, rot_l = x_player_api.get_head_tracking_arm_rotations(player)
		assert.near(-math.rad(45), rot_r.x, 0.02, "Right arm must pitch up (-X) with look angle during bow aim")
		assert.near(-math.rad(45) * 0.78, rot_l.x, 0.02, "Left arm must coordinate upward elevation")
		assert.near(math.rad(45) * 0.20, rot_l.y, 0.02, "Left arm yaw compensation for upward aim")

		local proxies = x_player_api.get_visual_proxies(player)
		local ov_r = proxies.glb:get_bone_override("Arm_Right")
		local ov_l = proxies.glb:get_bone_override("Arm_Left")
		assert.near(-math.rad(45), ov_r.rotation.vec.x, 0.02)
		assert.near(-math.rad(45) * 0.78, ov_l.rotation.vec.x, 0.02)

		local b3d_r_up = proxies.b3d:get_bone_override("Arm_Right")
		local b3d_l_up = proxies.b3d:get_bone_override("Arm_Left")
		assert.near(math.rad(45), b3d_r_up.rotation.vec.x, 0.02, "B3D right arm elevates up (+X)")
		assert.is_true(b3d_l_up.rotation.vec.x > 0, "B3D left arm elevates up (+X)")
		assert.is_true(b3d_l_up.rotation.vec.y <= 0, "B3D left arm yaw up is negative or zero")

		-- 2. Aiming down at 40 degrees: verify Arm_Left compensates and does not drop to body
		player:set_look_vertical(math.rad(40))
		for _ = 1, 30 do
			x_player_api.step_head_tracking(player, 0.05, sem_state)
		end
		local rot_r_down, rot_l_down = x_player_api.get_head_tracking_arm_rotations(player)
		assert.near(math.rad(40), rot_r_down.x, 0.02, "Right arm pitches down (+X)")
		assert.near(math.rad(40) * 0.50, rot_l_down.x, 0.02, "Left arm pitch maintains forward extension")
		assert.near(math.rad(40) * 0.26, rot_l_down.y, 0.02, "Left arm inward yaw draws hand onto bow grip")
		assert.near(-math.rad(40) * 0.08, rot_l_down.z, 0.02, "Left arm roll prevents outward flare")

		local b3d_r_down = proxies.b3d:get_bone_override("Arm_Right")
		local b3d_l_down = proxies.b3d:get_bone_override("Arm_Left")
		assert.near(-math.rad(40), b3d_r_down.rotation.vec.x, 0.02, "B3D right arm pitches down (-X)")
		assert.is_true(b3d_l_down.rotation.vec.x < 0, "B3D left arm pitches down (-X)")
		assert.is_true(b3d_l_down.rotation.vec.y > 0, "B3D left arm yaw MUST be positive to draw inward onto bow grip")
	end)

	it("prioritizes dominant right arm during mining and attacking with reduced left arm pitch", function()
		player:set_look_vertical(math.rad(40))
		local sem_state = {locomotion = "stand", action = "mine"}

		for _ = 1, 25 do
			x_player_api.step_head_tracking(player, 0.05, sem_state)
		end

		local rot_r, rot_l = x_player_api.get_head_tracking_arm_rotations(player)
		local expected_action_r = math.rad(40) * 0.85
		local expected_subtle_l = math.rad(40) * (0.35 * 0.5)

		assert.near(expected_action_r, rot_r.x, 0.02, "Dominant right arm must receive 0.85 action weight")
		assert.near(expected_subtle_l, rot_l.x, 0.02, "Left arm must receive halved subtle weight")
		assert.is_true(math.abs(rot_r.x) > math.abs(rot_l.x) * 4)
	end)

	it("prioritizes shield block on left arm while reducing right arm pitch", function()
		player:set_look_vertical(-math.rad(30))
		local sem_state = {locomotion = "stand", action = "block"}

		for _ = 1, 25 do
			x_player_api.step_head_tracking(player, 0.05, sem_state)
		end

		local rot_r, rot_l = x_player_api.get_head_tracking_arm_rotations(player)
		local expected_action_l = -math.rad(30) * 0.85
		local expected_subtle_r = -math.rad(30) * (0.35 * 0.5)

		assert.near(expected_action_l, rot_l.x, 0.02, "Shield left arm must receive 0.85 action weight")
		assert.near(expected_subtle_r, rot_r.x, 0.02, "Right arm must receive halved subtle weight")
		assert.is_true(math.abs(rot_l.x) > math.abs(rot_r.x) * 4)
	end)

	it("suppresses arm pitch during lay posture and scales down during hurt", function()
		player:set_look_vertical(-math.rad(40))
		local sem_state = {locomotion = "lay"}

		for _ = 1, 25 do
			x_player_api.step_head_tracking(player, 0.05, sem_state)
		end

		local rot_r_lay, rot_l_lay = x_player_api.get_head_tracking_arm_rotations(player)
		assert.near(0, rot_r_lay.x, 0.02, "Arm pitch must be suppressed in lay posture")
		assert.near(0, rot_l_lay.x, 0.02, "Arm pitch must be suppressed in lay posture")

		-- Hurt flinch halves tracking weight (0.5)
		local sem_hurt = {locomotion = "stand", action = "hurt"}
		for _ = 1, 25 do
			x_player_api.step_head_tracking(player, 0.05, sem_hurt)
		end

		local rot_r_hurt, _ = x_player_api.get_head_tracking_arm_rotations(player)
		local expected_hurt = (-math.rad(40) * 0.35) * 0.5
		assert.near(expected_hurt, rot_r_hurt.x, 0.02, "Arm pitch must be halved during hurt action")
	end)

	it("resets both arms to 0 bind pose on reset_head_tracking", function()
		player:set_look_vertical(-math.rad(45))
		local sem_state = {locomotion = "stand", aiming_bow = true}

		for _ = 1, 20 do
			x_player_api.step_head_tracking(player, 0.05, sem_state)
		end

		x_player_api.reset_head_tracking(player)

		local rot_r, rot_l = x_player_api.get_head_tracking_arm_rotations(player)
		assert.equal(0, rot_r.x)
		assert.equal(0, rot_l.x)

		local proxies = x_player_api.get_visual_proxies(player)
		local ov_r = proxies.glb:get_bone_override("Arm_Right")
		local ov_l = proxies.glb:get_bone_override("Arm_Left")
		assert.equal(0, ov_r.rotation.vec.x)
		assert.equal(0, ov_l.rotation.vec.x)
		assert.is_false(ov_r.rotation.absolute)
		assert.is_false(ov_l.rotation.absolute)
	end)

	it("disables arm pitch tracking when enable_arm_tracking config is false", function()
		x_player_api.head_tracking.config.enable_arm_tracking = false

		player:set_look_vertical(-math.rad(40))
		local sem_state = {locomotion = "stand"}
		for _ = 1, 20 do
			x_player_api.step_head_tracking(player, 0.05, sem_state)
		end

		local rot_r, rot_l = x_player_api.get_head_tracking_arm_rotations(player)
		assert.equal(0, rot_r.x, "Arm pitch tracking must be disabled")
		assert.equal(0, rot_l.x, "Arm pitch tracking must be disabled")

		-- Head tracking continues to function
		local rot_head = x_player_api.head_tracking.get_head_rotation(player)
		assert.near(-math.rad(40), rot_head.x, 0.02, "Head tracking must remain active")

		x_player_api.head_tracking.config.enable_arm_tracking = true
	end)

	it("quiescence sleep wakes up when semantic action changes arm targets", function()
		player:set_look_vertical(-math.rad(30))
		local sem_state = {locomotion = "stand"}
		for _ = 1, 25 do
			x_player_api.step_head_tracking(player, 0.05, sem_state)
		end

		local pstate = x_player_api.head_tracking.states[name]
		assert.is_true(pstate.sleeping, "Tracking must enter sleep once converged")

		-- Transition to bow aim without moving camera: arm target changes from 0.35 to 1.0
		sem_state.aiming_bow = true
		x_player_api.step_head_tracking(player, 0.05, sem_state)
		assert.is_false(pstate.sleeping, "Tracking must wake up when arm targets diverge")
	end)

	it("naturally offsets head pitch in flight so head looks forward along flight path", function()
		-- Level flight with horizontal camera (look_vertical = 0)
		player:set_look_vertical(0)
		local sem_state = {locomotion = "fly"}

		for _ = 1, 25 do
			x_player_api.step_head_tracking(player, 0.05, sem_state)
		end

		local rot = x_player_api.get_head_rotation(player)
		assert.is_not_nil(rot)
		-- Head must be pitched upward relative to horizontal torso by -75 deg to look forward
		assert.near(-math.rad(75), rot.x, 0.02, "Head must offset to -75 deg in level flight")

		-- Looking up by 30 deg in flight: cranes up towards zenith clamp (-85 deg)
		player:set_look_vertical(-math.rad(30))
		for _ = 1, 25 do
			x_player_api.step_head_tracking(player, 0.05, sem_state)
		end
		local rot_up = x_player_api.get_head_rotation(player)
		local expected_up = math.max(-math.rad(85), -math.rad(75) - math.rad(30) * 0.75)
		assert.near(expected_up, rot_up.x, 0.02, "Head pitch must track upward gaze within zenith limit")

		-- Looking down by 60 deg in flight: relaxes forward to scan ground below
		player:set_look_vertical(math.rad(60))
		for _ = 1, 25 do
			x_player_api.step_head_tracking(player, 0.05, sem_state)
		end
		local rot_down = x_player_api.get_head_rotation(player)
		local expected_down = -math.rad(75) + math.rad(60) * 0.75
		assert.near(expected_down, rot_down.x, 0.02, "Head pitch must track downward to scan terrain")
	end)

	it("naturally offsets head pitch in swimming so head looks forward along swim path", function()
		-- Level swimming with horizontal camera (look_vertical = 0)
		player:set_look_vertical(0)
		local sem_state = {locomotion = "swim"}

		for _ = 1, 25 do
			x_player_api.step_head_tracking(player, 0.05, sem_state)
		end

		local rot = x_player_api.get_head_rotation(player)
		assert.is_not_nil(rot)
		-- Head must be pitched upward relative to horizontal torso by -75 deg to look forward
		assert.near(-math.rad(75), rot.x, 0.02, "Head must offset to -75 deg in level swim")

		-- Looking up by 30 deg while swimming: cranes up towards zenith clamp (-85 deg)
		player:set_look_vertical(-math.rad(30))
		for _ = 1, 25 do
			x_player_api.step_head_tracking(player, 0.05, sem_state)
		end
		local rot_up = x_player_api.get_head_rotation(player)
		local expected_up = math.max(-math.rad(85), -math.rad(75) - math.rad(30) * 0.75)
		assert.near(expected_up, rot_up.x, 0.02, "Head pitch must track upward gaze within zenith limit")

		-- Looking down by 60 deg while swimming: relaxes forward to scan seabed
		player:set_look_vertical(math.rad(60))
		for _ = 1, 25 do
			x_player_api.step_head_tracking(player, 0.05, sem_state)
		end
		local rot_down = x_player_api.get_head_rotation(player)
		local expected_down = -math.rad(75) + math.rad(60) * 0.75
		assert.near(expected_down, rot_down.x, 0.02, "Head pitch must track downward to scan seabed")
	end)

	it("applies standard upright head tracking when stationary in water", function()
		-- Standing still in water (in water, but locomotion is stand)
		player:set_look_vertical(math.rad(25))
		local sem_state = {locomotion = "stand", swimming = true}

		for _ = 1, 25 do
			x_player_api.step_head_tracking(player, 0.05, sem_state)
		end

		local rot = x_player_api.get_head_rotation(player)
		assert.is_not_nil(rot)
		-- Normal upright tracking without -75 deg offset
		assert.near(math.rad(25), rot.x, 0.02, "Stationary water idling must not apply prone offset")
	end)

	it("respects custom swim_pitch_offset and pitch limits when configured", function()
		local cfg = x_player_api.head_tracking.config
		local orig_offset = cfg.swim_pitch_offset
		local orig_up = cfg.swim_pitch_up_max
		local orig_down = cfg.swim_pitch_down_max

		cfg.swim_pitch_offset = -math.rad(60)
		cfg.swim_pitch_up_max = math.rad(70)
		cfg.swim_pitch_down_max = math.rad(20)

		player:set_look_vertical(0)
		local sem_state = {locomotion = "swim"}

		for _ = 1, 25 do
			x_player_api.step_head_tracking(player, 0.05, sem_state)
		end

		local rot = x_player_api.get_head_rotation(player)
		assert.near(-math.rad(60), rot.x, 0.02, "Custom swim offset must be applied")

		-- Restore config
		cfg.swim_pitch_offset = orig_offset
		cfg.swim_pitch_up_max = orig_up
		cfg.swim_pitch_down_max = orig_down
	end)

	it("refreshes bone overrides immediately on refresh_head_tracking", function()
		player:set_look_vertical(math.rad(30))
		for _ = 1, 20 do
			x_player_api.step_head_tracking(player, 0.05, nil)
		end

		local proxies = x_player_api.get_visual_proxies(player)
		local ov_glb = proxies.glb:get_bone_override("Head")
		local ov_b3d = proxies.b3d:get_bone_override("Head")
		assert.is_not_nil(ov_glb)
		assert.is_not_nil(ov_b3d)
		assert.near(math.rad(30), ov_glb.rotation.vec.x, 0.02)
		assert.near(-math.rad(30), ov_b3d.rotation.vec.x, 0.02)

		-- Switching model format triggers refresh_head_tracking across connected players
		player_api.set_model_format("b3d")
		local refreshed_b3d = proxies.b3d:get_bone_override("Head")
		assert.near(-math.rad(30), refreshed_b3d.rotation.vec.x, 0.02)

		player_api.set_model_format("glb")
	end)
end)
