-- Specs for B3D Single-Timeline Legacy Animations
-- Tests dedicated legacy_b3d module functionality and isolation

local mock_env = require("tests.mock_env")

describe("B3D Legacy Single-Timeline Animation Subsystem", function()
	local player

	before_each(function()
		player = mock_env.join_player("B3DTester")
		core.registered_nodes["default:dirt"] = {walkable = true}
		core.get_node_or_nil = function(pos)
			if not pos or pos.y <= 0 then
				return {name = "default:dirt"}
			end
			return {name = "air"}
		end
		player._pos = {x = 0, y = 0.5, z = 0}
		player.get_velocity = function() return {x = 0, y = 0, z = 0} end
		player_api.set_model_format("b3d")
		player_api.set_model(player, "character.b3d")
	end)

	after_each(function()
		player_api.set_model_format("glb")
	end)

	it("animates attack_slash on B3D models when holding LMB with sword and walk_mine when moving", function()
		core.registered_items["default:sword_steel"] = {
			description = "Steel Sword",
			groups = {sword = 1},
		}
		player:set_wielded_item("default:sword_steel")
		local pstate = player_api.controls.player_states[player:get_player_name()]
		pstate.equip_until = 0

		-- Stationary with LMB: attack_slash
		player.get_player_control = function() return {LMB = true} end
		player.get_velocity = function() return {x = 0, y = 0, z = 0} end
		player_api.globalstep(0.05)
		local pdata = player_api.get_animation(player)
		assert.equal("attack_slash", pdata.animation_b3d)

		-- Moving with LMB: walk_mine composite
		player.get_player_control = function() return {up = true, LMB = true} end
		player.get_velocity = function() return {x = 0, y = 0, z = 4.0} end
		player_api.globalstep(0.05)
		pdata = player_api.get_animation(player)
		assert.equal("walk_mine", pdata.animation_b3d)

		-- Release LMB while stationary: returns to stand after action duration window expires
		player.get_player_control = function() return {} end
		player.get_velocity = function() return {x = 0, y = 0, z = 0} end
		core._mock_us_time = core._mock_us_time + 500000
		player_api.globalstep(0.50)
		pdata = player_api.get_animation(player)
		assert.equal("stand", pdata.animation_b3d)
	end)

	it("animates attack_thrust on B3D models when holding LMB with spear", function()
		core.registered_items["default:spear_steel"] = {
			description = "Steel Spear",
			groups = {spear = 1},
		}
		player:set_wielded_item("default:spear_steel")
		local pstate = player_api.controls.player_states[player:get_player_name()]
		pstate.equip_until = 0

		player.get_player_control = function() return {LMB = true} end
		player.get_velocity = function() return {x = 0, y = 0, z = 0} end
		player_api.globalstep(0.05)
		local pdata = player_api.get_animation(player)
		assert.equal("attack_thrust", pdata.animation_b3d)

		player.get_player_control = function() return {} end
		core._mock_us_time = core._mock_us_time + 500000
		player_api.globalstep(0.50)
		pdata = player_api.get_animation(player)
		assert.equal("stand", pdata.animation_b3d)
	end)

	it("animates mine on B3D models when holding LMB with tools or bare hands", function()
		player:set_wielded_item("default:pick_wood")
		local pstate = player_api.controls.player_states[player:get_player_name()]
		pstate.equip_until = 0

		-- Stationary mine
		player.get_player_control = function() return {LMB = true} end
		player.get_velocity = function() return {x = 0, y = 0, z = 0} end
		player_api.globalstep(0.05)
		local pdata = player_api.get_animation(player)
		assert.equal("mine", pdata.animation_b3d)

		-- Moving mine: walk_mine
		player.get_player_control = function() return {up = true, LMB = true} end
		player.get_velocity = function() return {x = 0, y = 0, z = 4.0} end
		player_api.globalstep(0.05)
		pdata = player_api.get_animation(player)
		assert.equal("walk_mine", pdata.animation_b3d)

		-- Release LMB: returns to walk when moving once action window completes
		player.get_player_control = function() return {up = true} end
		core._mock_us_time = core._mock_us_time + 500000
		player_api.globalstep(0.50)
		pdata = player_api.get_animation(player)
		assert.equal("walk", pdata.animation_b3d)
	end)

	it("animates eat when consuming food on B3D models", function()
		core.registered_items["default:apple"] = {
			description = "Apple",
			on_use = core.item_eat(2),
			groups = {food = 2, food_apple = 1},
		}
		player:set_wielded_item("default:apple")
		local pstate = player_api.controls.player_states[player:get_player_name()]
		pstate.equip_until = 0

		-- Stationary eating
		player.get_player_control = function() return {LMB = true} end
		player.get_velocity = function() return {x = 0, y = 0, z = 0} end
		player_api.globalstep(0.05)
		local pdata = player_api.get_animation(player)
		assert.equal("eat", pdata.animation_b3d)

		-- Moving while eating: walk_mine or walk_eat
		player.get_player_control = function() return {up = true, LMB = true} end
		player.get_velocity = function() return {x = 0, y = 0, z = 3} end
		player_api.globalstep(0.05)
		pdata = player_api.get_animation(player)
		assert.is_true(pdata.animation_b3d == "walk_eat" or pdata.animation_b3d == "walk_mine")
	end)

	it("ensures GLB models remain on multitrack and are completely decoupled from B3D logic", function()
		player_api.set_model_format("glb")
		player_api.set_model(player, "character.glb")

		player.get_player_control = function() return {} end
		player.get_velocity = function() return {x = 0, y = 0, z = 0} end
		player_api.globalstep(0.05)

		local pdata = player_api.get_animation(player)
		assert.equal("stand", pdata.animation)
	end)

	it("dynamically routes legacy client cohort to B3D single-timeline when server format is glb", function()
		player_api.set_model_format("glb")
		player_api.set_model(player, "character.glb")

		-- Simulate legacy client (e.g. Luanti 5.10.0)
		local name = player:get_player_name()
		x_player_api.modern_cohort[name] = nil
		x_player_api.legacy_cohort[name] = true
		assert.is_false(x_player_api.is_modern_client(name))

		core.registered_items["default:sword_steel"] = {
			description = "Steel Sword",
			groups = {sword = 1},
		}
		player:set_wielded_item("default:sword_steel")
		local pstate = player_api.controls.player_states[name]
		pstate.equip_until = 0

		-- Stationary with LMB on legacy client
		player.get_player_control = function() return {LMB = true} end
		player.get_velocity = function() return {x = 0, y = 0, z = 0} end
		player_api.globalstep(0.05)

		local pdata = player_api.get_animation(player)
		-- Must execute step_b3d_animation and resolve attack_slash on b3d timeline
		assert.equal("attack_slash", pdata.animation_b3d)

		-- Restore modern cohort
		x_player_api.legacy_cohort[name] = nil
		x_player_api.modern_cohort[name] = true
	end)

	it("verifies walk_eat animation starts at 746 and ends at 765 without start frame glitch", function()
		local model = player_api.registered_models["character.b3d"]
		assert.is_not_nil(model)
		assert.is_not_nil(model.animations.walk_eat)
		assert.equal(746, model.animations.walk_eat.x)
		assert.equal(765, model.animations.walk_eat.y)
	end)

	it("registers freeze animation consistently across b3d and glb models", function()
		local b3d_model = player_api.registered_models["character.b3d"]
		local glb_model = player_api.registered_models["character.glb"]
		assert.is_not_nil(b3d_model.animations.freeze)
		assert.equal(205, b3d_model.animations.freeze.x)
		assert.equal(205, b3d_model.animations.freeze.y)
		assert.is_false(b3d_model.animations.freeze.loop)

		assert.is_not_nil(glb_model.animations_glb.freeze)
		assert.equal("walk_mine", glb_model.animations_glb.freeze.track)
		assert.equal(0, glb_model.animations_glb.freeze.speed)
		assert.is_false(glb_model.animations_glb.freeze.loop)
	end)

	it("synchronizes play_action to b3d proxy and player object when action is active or cleared", function()
		player_api.set_model_format("b3d")
		player_api.set_model(player, "character.b3d")
		local proxies = player_api.get_visual_proxies(player)
		local b3d = proxies.b3d
		assert.is_not_nil(b3d)

		local anims = player_api.registered_models["character.b3d"].animations
		player_api.play_action(player, "attack_slash")
		local pdata = player_api.get_animation(player)
		assert.equal("attack_slash", pdata.animation_b3d)
		assert.equal(anims.attack_slash.x, player._last_animation.anim.x)
		assert.equal(anims.attack_slash.y, player._last_animation.anim.y)
		local last_call = b3d._animation_calls[#b3d._animation_calls]
		assert.is_not_nil(last_call)
		assert.equal(anims.attack_slash.x, last_call[1].x)
		assert.equal(anims.attack_slash.y, last_call[1].y)

		-- Clearing action restores locomotion state
		player_api.play_action(player, nil)
		pdata = player_api.get_animation(player)
		assert.equal("stand", pdata.animation_b3d)
		assert.equal(anims.stand.x, player._last_animation.anim.x)
		assert.equal(anims.stand.y, player._last_animation.anim.y)
		last_call = b3d._animation_calls[#b3d._animation_calls]
		assert.equal(anims.stand.x, last_call[1].x)
		assert.equal(anims.stand.y, last_call[1].y)
	end)

	it("maintains cross-cohort animation parity and walk_mine preservation on modern player", function()
		player_api.set_model_format("glb")
		player_api.set_model(player, "character.glb")
		local name = player:get_player_name()
		x_player_api.modern_cohort[name] = true
		x_player_api.legacy_cohort[name] = nil

		local proxies = player_api.get_visual_proxies(player)
		local b3d = proxies.b3d
		local glb = proxies.glb
		assert.is_not_nil(b3d)
		assert.is_not_nil(glb)

		-- Moving and mining: walk_mine composite must not be overwritten by mine
		player.get_player_control = function() return {up = true, LMB = true} end
		player.get_velocity = function() return {x = 0, y = 0, z = 4.0} end
		b3d._animation_calls = {}
		glb._played_animations = {}

		player_api.globalstep(0.05)
		local last_call = b3d._animation_calls[#b3d._animation_calls]
		assert.is_not_nil(last_call)
		local b3d_model = player_api.registered_models["character.b3d"]
		assert.equal(b3d_model.animations.walk_mine.x, last_call[1].x)
		assert.equal(b3d_model.animations.walk_mine.y, last_call[1].y)
	end)

	it("animates continuous combat attacks smoothly on B3D and GLB proxies during LMB hold", function()
		player_api.set_model_format("glb")
		player_api.set_model(player, "character.glb")
		local name = player:get_player_name()
		x_player_api.modern_cohort[name] = true

		core.registered_items["default:sword_steel"] = { groups = {sword = 1} }
		player:set_wielded_item("default:sword_steel")
		local pstate = player_api.controls.player_states[name]
		pstate.equip_until = 0

		player.get_player_control = function() return {LMB = true} end
		player.get_velocity = function() return {x = 0, y = 0, z = 0} end

		local proxies = player_api.get_visual_proxies(player)
		proxies.b3d._animation_calls = {}
		proxies.glb._played_animations = {}

		-- Advance 30 ticks (1.5 seconds)
		for _ = 1, 30 do
			core._mock_us_time = core._mock_us_time + 50000
			player_api.globalstep(0.05)
		end

		-- B3D proxy receives attack_slash frame range with loop = false (discrete swing retriggered per cycle)
		local b3d_model = player_api.registered_models["character.b3d"]
		local last_call = proxies.b3d._animation_calls[#proxies.b3d._animation_calls]
		assert.is_not_nil(last_call)
		assert.equal(b3d_model.animations.attack_slash.x, last_call[1].x)
		assert.equal(b3d_model.animations.attack_slash.y, last_call[1].y)
		assert.is_false(last_call[4]) -- loop mode must be false for discrete combat attacks on B3D
		assert.is_true(#proxies.b3d._animation_calls >= 3) -- sustained combat through discrete cycle retriggers

		-- GLB proxy plays attack_slash with loop = true without freezing or interruption
		assert.is_true(#proxies.glb._played_animations >= 1)
		local last_glb = proxies.glb._played_animations[#proxies.glb._played_animations]
		assert.equal("attack_slash", last_glb.track)
		assert.is_true(last_glb.params.loop)

		-- Release LMB: returns to stand after action duration window expires
		player.get_player_control = function() return {} end
		core._mock_us_time = core._mock_us_time + 500000
		player_api.globalstep(0.50)
		local pdata = player_api.get_animation(player)
		assert.equal("stand", pdata.animation_b3d)
	end)

	it("does not jitter or repeatedly reset continuous actions like eat and block during sustained hold", function()
		player_api.set_model_format("glb")
		player_api.set_model(player, "character.glb")
		local name = player:get_player_name()
		x_player_api.modern_cohort[name] = true

		local proxies = player_api.get_visual_proxies(player)
		local b3d = proxies.b3d
		local b3d_model = player_api.registered_models["character.b3d"]

		-- Verify block does not reset repeatedly during 1.5s RMB hold
		core.registered_items["shields:shield_wood"] = { groups = {armor_shield = 1} }
		player:set_wielded_item("shields:shield_wood")
		player.get_player_control = function() return {RMB = true} end
		b3d._animation_calls = {}

		for _ = 1, 30 do
			core._mock_us_time = core._mock_us_time + 50000
			player_api.globalstep(0.05)
		end

		-- Blocking must be triggered once and held without multiple resets per second
		assert.equal(1, #b3d._animation_calls)
		assert.equal(b3d_model.animations.block.x, b3d._animation_calls[1][1].x)
		assert.equal(b3d_model.animations.block.y, b3d._animation_calls[1][1].y)
		assert.is_false(b3d._animation_calls[1][4]) -- loop must be false

		-- Verify eat does not reset repeatedly during consumption
		b3d._animation_calls = {}
		player:set_wielded_item("default:apple")
		x_player_api.trigger_eat(player, 1.2, "default:apple")
		player.get_player_control = function() return {LMB = true} end

		for _ = 1, 20 do
			core._mock_us_time = core._mock_us_time + 50000
			player_api.globalstep(0.05)
		end

		-- Eating should have played once from trigger_eat without being clobbered every 0.45s
		assert.equal(1, #b3d._animation_calls)
		assert.equal(b3d_model.animations.eat.x, b3d._animation_calls[1][1].x)
		assert.equal(b3d_model.animations.eat.y, b3d._animation_calls[1][1].y)
	end)

	it("ensures all 12 action animations set proxies.b3d frame ranges during test_anim without being clobbered", function()
		player_api.set_model_format("glb")
		player_api.set_model(player, "character.glb")
		local name = player:get_player_name()
		x_player_api.modern_cohort[name] = true

		local proxies = player_api.get_visual_proxies(player)
		local b3d = proxies.b3d
		local b3d_model = player_api.registered_models["character.b3d"]
		assert.is_not_nil(b3d)
		assert.is_not_nil(b3d_model)

		local action_list = {
			"mine", "block", "attack_slash", "attack_thrust", "eat",
			"bow_aim", "bow_shoot", "hurt", "equip", "wave", "point", "cheer",
		}

		for _, action_name in ipairs(action_list) do
			b3d._animation_calls = {}
			local started = x_player_api.start_anim_test(player, 4.0, action_name)
			assert.is_true(started, "Failed to start test_anim for " .. action_name)

			-- Run 5 globalstep ticks (0.25s)
			for _ = 1, 5 do
				core._mock_us_time = core._mock_us_time + 50000
				mock_env.step_timers(0.05)
				player_api.globalstep(0.05)
			end

			local last_call = b3d._animation_calls[#b3d._animation_calls]
			assert.is_not_nil(last_call, "No b3d animation calls recorded for " .. action_name)

			local exp = b3d_model.animations[action_name]
			assert.is_not_nil(exp, "No b3d definition for " .. action_name)
			assert.equal(exp.x, last_call[1].x, "Action " .. action_name .. " start frame mismatch")
			assert.equal(exp.y, last_call[1].y, "Action " .. action_name .. " end frame mismatch")
			-- Ensure not clobbered back to stand (1..79)
			assert.not_equal(b3d_model.animations.stand.x, last_call[1].x, "Action " .. action_name .. " clobbered to stand")

			x_player_api.stop_anim_test(name, true)
		end
	end)

	it("retriggers one-shot action animations repeatedly on proxies.b3d during sustained test_anim", function()
		player_api.set_model_format("glb")
		player_api.set_model(player, "character.glb")
		local name = player:get_player_name()
		x_player_api.modern_cohort[name] = true

		local proxies = player_api.get_visual_proxies(player)
		local b3d = proxies.b3d
		local b3d_model = player_api.registered_models["character.b3d"]

		local oneshot_actions = {
			"bow_shoot", "hurt", "equip"
		}

		for _, anim_name in ipairs(oneshot_actions) do
			b3d._animation_calls = {}
			local started = x_player_api.start_anim_test(player, 2.0, anim_name)
			assert.is_true(started, "Failed to start test_anim for " .. anim_name)

			-- Advance 1.5 seconds in 0.05s increments (before 2.0s session expiry)
			for _ = 1, 30 do
				core._mock_us_time = core._mock_us_time + 50000
				mock_env.step_timers(0.05)
				player_api.globalstep(0.05)
			end

			-- With 2.0s duration and 0.8s repeat interval, 1.5s must trigger at least 2 times (at t=0 and t=0.8s)
			assert.is_true(#b3d._animation_calls >= 2,
				"Expected >= 2 animation triggers for oneshot " .. anim_name .. ", got " .. #b3d._animation_calls)

			local exp = b3d_model.animations[anim_name]
			local last_call = b3d._animation_calls[#b3d._animation_calls]
			assert.equal(exp.x, last_call[1].x, "Oneshot " .. anim_name .. " final start frame mismatch")
			assert.equal(exp.y, last_call[1].y, "Oneshot " .. anim_name .. " final end frame mismatch")

			x_player_api.stop_anim_test(name, true)
		end
	end)

	it("holds sustained postures and continuous actions smoothly without resets during test_anim showcase", function()
		player_api.set_model_format("glb")
		player_api.set_model(player, "character.glb")
		local name = player:get_player_name()
		x_player_api.modern_cohort[name] = true

		local proxies = player_api.get_visual_proxies(player)
		local b3d = proxies.b3d
		local b3d_model = player_api.registered_models["character.b3d"]

		local sustained_actions = {
			"mine", "attack_slash", "attack_thrust", "block", "bow_aim", "eat", "wave", "point", "cheer"
		}

		for _, anim_name in ipairs(sustained_actions) do
			b3d._animation_calls = {}
			local started = x_player_api.start_anim_test(player, 2.0, anim_name)
			assert.is_true(started, "Failed to start test_anim for " .. anim_name)

			-- Advance 1.5 seconds in 0.05s increments (30 ticks)
			for _ = 1, 30 do
				core._mock_us_time = core._mock_us_time + 50000
				mock_env.step_timers(0.05)
				player_api.globalstep(0.05)
			end

			-- Must have been set once (or at most once on start) without repeated resets
			assert.is_true(#b3d._animation_calls <= 2,
				"Expected <= 2 animation calls (no jitter/resets) for sustained " .. anim_name .. ", got " .. #b3d._animation_calls)

			local exp = b3d_model.animations[anim_name]
			local last_call = b3d._animation_calls[#b3d._animation_calls]
			assert.equal(exp.x, last_call[1].x, "Sustained " .. anim_name .. " start frame mismatch")
			assert.equal(exp.y, last_call[1].y, "Sustained " .. anim_name .. " end frame mismatch")

			x_player_api.stop_anim_test(name, true)
		end
	end)

	it("classifies 5.10.0 clients into legacy cohort and synchronizes B3D animations", function()
		player_api.set_model_format("glb")
		player_api.set_model(player, "character.glb")
		local modern_name = player:get_player_name()

		local old_get_info = core.get_player_information
		core.get_player_information = function(pname)
			if pname == "LegacyUser" then
				return { protocol_version = 46, version_string = "5.10.0" }
			end
			return { protocol_version = 49, version_string = "5.17.0" }
		end

		x_player_api.modern_cohort[modern_name] = nil
		x_player_api.legacy_cohort[modern_name] = nil
		x_player_api.ensure_player_cohort(modern_name)
		assert.is_true(x_player_api.is_modern_client(modern_name))

		local legacy_player = mock_env.join_player("LegacyUser")
		local legacy_name = legacy_player:get_player_name()
		player_api.set_model(legacy_player, "character.glb")

		assert.is_false(x_player_api.is_modern_client(legacy_name))
		assert.is_true(x_player_api.get_legacy_observers()[legacy_name])

		x_player_api.refresh_observers()

		local modern_proxies = player_api.get_visual_proxies(player)
		local legacy_proxies = player_api.get_visual_proxies(legacy_player)

		assert.is_not_nil(modern_proxies.b3d:get_observers()[legacy_name])
		assert.is_not_nil(legacy_proxies.b3d:get_observers()[legacy_name])
		assert.is_not_nil(modern_proxies.glb:get_observers()[modern_name])
		assert.is_not_nil(legacy_proxies.glb:get_observers()[modern_name])

		-- Legacy player swings sword (attack_slash)
		legacy_player.get_wielded_item = function() return ItemStack("default:sword_steel") end
		legacy_player.get_player_control = function() return {LMB = true} end
		legacy_player.get_velocity = function() return {x = 0, y = 0, z = 0} end

		player_api.globalstep(0.05)

		local b3d_model = player_api.registered_models["character.b3d"]
		local exp_slash = b3d_model.animations.attack_slash
		assert.equal(exp_slash.x, legacy_player._last_animation.anim.x)
		assert.equal(exp_slash.y, legacy_player._last_animation.anim.y)
		local last_slash = legacy_proxies.b3d._animation_calls[#legacy_proxies.b3d._animation_calls]
		assert.is_not_nil(last_slash)
		assert.equal(exp_slash.x, last_slash[1].x)
		assert.equal(exp_slash.y, last_slash[1].y)

		-- Modern player eats bread
		player.get_wielded_item = function() return ItemStack("default:bread") end
		player.get_player_control = function() return {RMB = true} end
		player.get_velocity = function() return {x = 0, y = 0, z = 0} end
		core.item_eat(2)(ItemStack("default:bread"), player, {type="nothing"})

		player_api.globalstep(0.05)

		local exp_eat = b3d_model.animations.eat
		assert.equal(exp_eat.x, player._last_animation.anim.x)
		assert.equal(exp_eat.y, player._last_animation.anim.y)
		local last_eat = modern_proxies.b3d._animation_calls[#modern_proxies.b3d._animation_calls]
		assert.is_not_nil(last_eat)
		assert.equal(exp_eat.x, last_eat[1].x)
		assert.equal(exp_eat.y, last_eat[1].y)

		mock_env.leave_player(legacy_player)
		core.get_player_information = old_get_info
	end)

	it("applies seamless frame boundaries with blend = 0 on B3D actions to eliminate jitter and drag-down", function()
		player_api.set_model_format("b3d")
		player_api.set_model(player, "character.b3d")
		local proxies = player_api.get_visual_proxies(player)
		assert.is_not_nil(proxies and proxies.b3d)

		-- Mine (190..200 with blend = 0)
		player.get_player_control = function() return {LMB = true} end
		player.get_velocity = function() return {x = 0, y = 0, z = 0} end
		player_api.globalstep(0.05)

		assert.equal("mine", player_api.get_animation(player).animation_b3d)
		assert.equal(190, player._last_animation.anim.x)
		assert.equal(200, player._last_animation.anim.y)
		assert.equal(0, player._last_animation.blend)
		local b3d_calls = proxies.b3d._animation_calls
		local last_call = b3d_calls[#b3d_calls]
		assert.equal(190, last_call[1].x)
		assert.equal(200, last_call[1].y)
		assert.equal(0, last_call[3]) -- blend parameter

		-- Walk and mine (201..220 with blend = 0)
		player.get_player_control = function() return {LMB = true, up = true} end
		player.get_velocity = function() return {x = 0, y = 0, z = 3.0} end
		player_api.globalstep(0.05)

		assert.equal("walk_mine", player_api.get_animation(player).animation_b3d)
		assert.equal(201, player._last_animation.anim.x)
		assert.equal(220, player._last_animation.anim.y)
		assert.equal(0, player._last_animation.blend)
		last_call = b3d_calls[#b3d_calls]
		assert.equal(201, last_call[1].x)
		assert.equal(220, last_call[1].y)
		assert.equal(0, last_call[3]) -- blend parameter

		-- Restore format
		player.get_player_control = function() return {} end
		player_api.set_model_format("glb")
	end)
end)
