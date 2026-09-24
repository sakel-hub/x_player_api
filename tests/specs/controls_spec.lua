-- Specs for Semantic Controls, State Evaluation, and Action Tracks

local mock_env = require("tests.mock_env")

describe("Controls & Semantic State Engine", function()
	local player

	before_each(function()
		player = mock_env.join_player("ControlsTester")
	end)

	it("recovers immediately on ground landing from jump or fall", function()
		core.get_node_or_nil = function() return {name = "default:dirt"} end
		core.registered_nodes["default:dirt"] = {walkable = true}
		player._pos = {x = 0, y = 0.5, z = 0}
		player.get_velocity = function() return {x = 0, y = 0.0, z = 0} end
		player.get_player_control = function() return {} end

		local landed_state = player_api.get_player_state(player)
		assert.is_false(landed_state.jumping)
		assert.is_false(landed_state.falling)
		assert.equal("stand", landed_state.locomotion)
	end)

	it("ensures shooting_bow returns a strict boolean", function()
		local pstate = player_api.controls.player_states[player:get_player_name()]
		local init_state = player_api.get_player_state(player)
		assert.equal("boolean", type(init_state.shooting_bow))
		assert.is_false(init_state.shooting_bow)

		pstate.bow_shoot_until = (core.get_us_time() / 1000000) + 1.0
		local active_state = player_api.get_player_state(player)
		assert.equal("boolean", type(active_state.shooting_bow))
		assert.is_true(active_state.shooting_bow)
		pstate.bow_shoot_until = nil
	end)

	it("blocks posture emotes while airborne and allows them when grounded", function()
		local pstate = player_api.controls.player_states[player:get_player_name()]
		pstate.eat_until = nil
		pstate.active_emote = "sit"
		pstate.emote_until = -1

		core.get_node_or_nil = function() return {name = "air"} end
		local air_state = player_api.get_player_state(player)
		assert.not_equal("sit", air_state.locomotion)

		core.registered_nodes["default:dirt"] = {walkable = true}
		core.get_node_or_nil = function() return {name = "default:dirt"} end
		local ground_state = player_api.get_player_state(player)
		assert.equal("sit", ground_state.locomotion)

		pstate.active_emote = nil
		pstate.emote_until = 0
	end)

	it("resolves play_action tracks when track name differs from action alias", function()
		player_api.register_model("test_action_model.glb", {
			is_multitrack = true,
			animation_speed = 30,
			animations_glb = {
				custom_kick = {
					track = "anim_kick_track",
					speed = 25,
					loop = false,
					priority = 2,
				},
				custom_punch = {
					track = "anim_punch_track",
					speed = 30,
					loop = false,
				},
			},
		})
		player_api.set_model(player, "test_action_model.glb")

		local proxies = player_api.get_visual_proxies(player)
		local glb = proxies.glb

		glb._played_animations = {}
		glb._stopped_animations = {}

		player_api.play_action(player, "custom_kick")
		assert.is_true(#glb._played_animations > 0)
		assert.equal("anim_kick_track", glb._played_animations[#glb._played_animations].track)

		player_api.play_action(player, "custom_punch")
		assert.is_true(#glb._stopped_animations > 0)
		assert.equal("anim_kick_track", glb._stopped_animations[#glb._stopped_animations])
		assert.equal("anim_punch_track", glb._played_animations[#glb._played_animations].track)

		player_api.play_action(player, nil)
		assert.equal("anim_punch_track", glb._stopped_animations[#glb._stopped_animations])
	end)

	it("triggers eating action when clicking LMB with food without falling through to mine", function()
		core.registered_items["test:bread"] = {
			description = "Bread",
			groups = {food = 1, eatable = 1},
		}
		player.get_wielded_item = function()
			return {
				get_name = function() return "test:bread" end,
				is_empty = function() return false end,
			}
		end

		-- In Luanti food is consumed by clicking LMB (dig), not RMB
		player.get_player_control = function()
			return {LMB = true, dig = true, RMB = false, place = false}
		end
		player.get_hp = function() return 20 end

		local state = player_api.get_player_state(player)
		assert.is_true(state.eating)
		assert.equal("eat", state.action)
	end)

	it("does not trigger eating when holding RMB with food", function()
		core.registered_items["test:bread_loaf"] = {
			description = "Bread Loaf",
			groups = {food = 1, eatable = 1},
		}
		player.get_wielded_item = function()
			return {
				get_name = function() return "test:bread_loaf" end,
				is_empty = function() return false end,
			}
		end

		-- Holding RMB with food in Luanti does not trigger eating
		player.get_player_control = function()
			return {RMB = true, place = true, LMB = false, dig = false}
		end
		local pstate = player_api.controls.player_states[player:get_player_name()]
		pstate.eat_until = 0

		local state = player_api.get_player_state(player)
		assert.is_false(state.eating)
	end)

	it("triggers mining when holding LMB with non-food item instead of eating", function()
		core.registered_items["default:pick_steel"] = {
			description = "Steel Pickaxe",
			groups = {tool = 1},
		}
		player.get_wielded_item = function()
			return {
				get_name = function() return "default:pick_steel" end,
				is_empty = function() return false end,
			}
		end

		player.get_player_control = function()
			return {LMB = true, dig = true}
		end

		local state = player_api.get_player_state(player)
		assert.is_false(state.eating)
		assert.equal("mine", state.action)
	end)

	it("detects airborne hovering when vertical velocity is near zero", function()
		core.get_node_or_nil = function() return {name = "air"} end
		player._pos = {x = 0, y = 50, z = 0}
		player.get_velocity = function() return {x = 0, y = 0.01, z = 0} end
		player.get_player_control = function() return {} end

		local state = player_api.get_player_state(player)
		assert.is_true(state.hovering)
	end)

	it("maintains hovering and prevents stand glitch during airborne flight deceleration", function()
		core.get_node_or_nil = function() return {name = "air"} end
		player._pos = {x = 0, y = 50, z = 0}
		-- Active forward flight at high speed
		player.get_velocity = function() return {x = 8.0, y = 0, z = 0} end
		player.get_player_control = function() return {up = true} end
		local state1 = player_api.get_player_state(player)
		assert.is_true(state1.flying)
		assert.equal("fly", state1.locomotion)

		-- Release keys, speed drops below fly threshold with minimal vertical velocity
		player.get_velocity = function() return {x = 2.0, y = 0.2, z = 0} end
		player.get_player_control = function() return {} end
		local state2 = player_api.get_player_state(player)
		assert.is_false(state2.flying)
		assert.is_true(state2.hovering)
		assert.equal("hover", state2.locomotion)

		-- Complete stop
		player.get_velocity = function() return {x = 0, y = 0, z = 0} end
		local state3 = player_api.get_player_state(player)
		assert.is_true(state3.hovering)
		assert.equal("hover", state3.locomotion)
	end)

	it("animates jump while ascending and transitions cleanly to hover on stop", function()
		core.get_node_or_nil = function() return {name = "air"} end
		player._pos = {x = 0, y = 50, z = 0}
		-- Ascending upward in mid-air (jump animation)
		player.get_velocity = function() return {x = 0, y = 4.5, z = 0} end
		player.get_player_control = function() return {jump = true} end
		local state1 = player_api.get_player_state(player)
		assert.is_true(state1.jumping)
		assert.is_false(state1.hovering)
		assert.equal("jump", state1.locomotion)

		-- Release jump key, decelerating upward (vel.y = 2.0 > 0.5 keeps jump)
		player.get_velocity = function() return {x = 0, y = 2.0, z = 0} end
		player.get_player_control = function() return {} end
		local state2 = player_api.get_player_state(player)
		assert.is_true(state2.jumping)
		assert.is_false(state2.hovering)
		assert.equal("jump", state2.locomotion)

		-- Upward velocity settles (|vel.y| <= 0.5 transitions cleanly to hover)
		player.get_velocity = function() return {x = 0, y = 0, z = 0} end
		local state3 = player_api.get_player_state(player)
		assert.is_true(state3.hovering)
		assert.is_false(state3.jumping)
		assert.equal("hover", state3.locomotion)
	end)

	it("animates fall while descending and transitions cleanly to hover or stand", function()
		core.get_node_or_nil = function() return {name = "air"} end
		player._pos = {x = 0, y = 50, z = 0}

		-- High-speed descent downward in flight (vel.y = -7.5 < -0.5 triggers fall animation)
		player.get_velocity = function() return {x = 0, y = -7.5, z = 0} end
		player.get_player_control = function() return {sneak = true} end
		local state1 = player_api.get_player_state(player)
		assert.is_true(state1.falling)
		assert.is_false(state1.hovering)
		assert.equal("fall", state1.locomotion)

		-- Release sneak key in mid-air with downward velocity (vel.y = -7.0 < -0.5 keeps fall)
		player.get_velocity = function() return {x = 0, y = -7.0, z = 0} end
		player.get_player_control = function() return {} end
		local state2 = player_api.get_player_state(player)
		assert.is_true(state2.falling)
		assert.is_false(state2.hovering)
		assert.equal("fall", state2.locomotion)

		-- Deceleration continues (vel.y = -2.0)
		player.get_velocity = function() return {x = 0, y = -2.0, z = 0} end
		local state2b = player_api.get_player_state(player)
		assert.is_true(state2b.falling)
		assert.is_false(state2b.hovering)
		assert.equal("fall", state2b.locomotion)

		-- Descending stops in mid-air (|vel.y| <= 0.5) transitions cleanly to hover
		player._pos = {x = 0, y = 1.0, z = 0}
		player.get_velocity = function() return {x = 0, y = -0.2, z = 0} end
		player.get_player_control = function() return {} end
		local state3 = player_api.get_player_state(player)
		assert.is_true(state3.hovering)
		assert.is_false(state3.falling)
		assert.equal("hover", state3.locomotion)

		-- Landing on solid ground resets to stand
		core.registered_nodes["default:stone"] = {walkable = true}
		core.get_node_or_nil = function() return {name = "default:stone"} end
		player._pos = {x = 0, y = 0.5, z = 0}
		player.get_velocity = function() return {x = 0, y = 0, z = 0} end
		local state4 = player_api.get_player_state(player)
		assert.is_false(state4.hovering)
		assert.is_false(state4.falling)
		assert.equal("stand", state4.locomotion)
	end)

	it("ensures ground jumps and cliff falls do not activate flight hovering", function()
		-- Ground jump
		core.get_node_or_nil = function() return {name = "default:dirt"} end
		player._pos = {x = 0, y = 1.0, z = 0}
		player.get_velocity = function() return {x = 0, y = 3.5, z = 0} end
		player.get_player_control = function() return {jump = true} end
		local jump_state = player_api.get_player_state(player)
		assert.is_true(jump_state.jumping)
		assert.is_false(jump_state.hovering)

		-- Cliff fall in survival (even if holding sneak while falling)
		core.get_node_or_nil = function() return {name = "air"} end
		player._pos = {x = 0, y = 50, z = 0}
		player.get_velocity = function() return {x = 0, y = -8.0, z = 0} end
		player.get_player_control = function() return {sneak = true} end
		local fall_state = player_api.get_player_state(player)
		assert.is_true(fall_state.falling)
		assert.is_false(fall_state.hovering)
		assert.equal("fall", fall_state.locomotion)
	end)

	it("animates jump during upward ascent and fall during descent across continuous jumps", function()
		core.registered_nodes["default:dirt"] = {walkable = true}
		core.get_node_or_nil = function(pos)
			if pos.y <= 0 then return {name = "default:dirt"} end
			return {name = "air"}
		end

		-- Initial jump takeoff (ascending upward vel.y = 6.5 > 0.5)
		player._pos = {x = 0, y = 0.8, z = 0}
		player.get_velocity = function() return {x = 0, y = 6.5, z = 0} end
		player.get_player_control = function() return {jump = true} end
		local jump1_takeoff = player_api.get_player_state(player)
		assert.is_true(jump1_takeoff.jumping)
		assert.is_false(jump1_takeoff.falling)
		assert.equal("jump", jump1_takeoff.locomotion)

		-- Rising phase of jump (ascending upward vel.y = 2.5 > 0.5)
		player._pos = {x = 0, y = 1.8, z = 0}
		player.get_velocity = function() return {x = 0, y = 2.5, z = 0} end
		local jump1_rising = player_api.get_player_state(player)
		assert.is_true(jump1_rising.jumping)
		assert.is_false(jump1_rising.falling)
		assert.equal("jump", jump1_rising.locomotion)

		-- Descent of jump (downward vel.y = -6.0 < -0.5 triggers fall)
		player._pos = {x = 0, y = 1.2, z = 0}
		player.get_velocity = function() return {x = 0, y = -6.0, z = 0} end
		local jump1_descent = player_api.get_player_state(player)
		assert.is_false(jump1_descent.jumping)
		assert.is_true(jump1_descent.falling)
		assert.equal("fall", jump1_descent.locomotion)

		-- Touchdown / landing resets jumping and falling
		player._pos = {x = 0, y = 0.5, z = 0}
		core.get_node_or_nil = function() return {name = "default:dirt"} end
		player.get_velocity = function() return {x = 0, y = 0.0, z = 0} end
		local landed = player_api.get_player_state(player)
		assert.is_false(landed.jumping)
		assert.is_false(landed.falling)
		assert.equal("stand", landed.locomotion)

		-- Subsequent bounce with jump key held continuously
		core.get_node_or_nil = function(pos)
			if pos.y <= 0 then return {name = "default:dirt"} end
			return {name = "air"}
		end
		player._pos = {x = 0, y = 0.8, z = 0}
		player.get_velocity = function() return {x = 0, y = 6.5, z = 0} end
		player.get_player_control = function() return {jump = true} end
		local jump2_takeoff = player_api.get_player_state(player)
		assert.is_true(jump2_takeoff.jumping)
		assert.is_false(jump2_takeoff.falling)
		assert.equal("jump", jump2_takeoff.locomotion)

		-- Descent of second bounce at high downward velocity
		player._pos = {x = 0, y = 1.2, z = 0}
		player.get_velocity = function() return {x = 0, y = -6.0, z = 0} end
		local jump2_descent = player_api.get_player_state(player)
		assert.is_false(jump2_descent.jumping)
		assert.is_true(jump2_descent.falling)
		assert.equal("fall", jump2_descent.locomotion)
	end)

	it("maintains falling animation during high cliff falls even as ground approaches at bottom", function()
		-- Falling from high cliff
		core.get_node_or_nil = function() return {name = "air"} end
		player._pos = {x = 0, y = 50.0, z = 0}
		player.get_velocity = function() return {x = 0, y = -10.0, z = 0} end
		player.get_player_control = function() return {} end
		local fall_high = player_api.get_player_state(player)
		assert.is_true(fall_high.falling)
		assert.equal("fall", fall_high.locomotion)

		-- Approaching ground at bottom of cliff (pos.y = 1.5, ground at 0) keeps falling
		core.get_node_or_nil = function(pos)
			if pos.y <= 0 then return {name = "default:dirt"} end
			return {name = "air"}
		end
		player._pos = {x = 0, y = 1.5, z = 0}
		player.get_velocity = function() return {x = 0, y = -10.0, z = 0} end
		local fall_near_ground = player_api.get_player_state(player)
		assert.is_true(fall_near_ground.falling)
		assert.equal("fall", fall_near_ground.locomotion)

		-- Impact on ground
		core.get_node_or_nil = function() return {name = "default:dirt"} end
		player._pos = {x = 0, y = 0.5, z = 0}
		player.get_velocity = function() return {x = 0, y = 0.0, z = 0} end
		local impact = player_api.get_player_state(player)
		assert.is_false(impact.falling)
		assert.equal("stand", impact.locomotion)
	end)

	it("smoothly turns over jump apex without inserting hover animation", function()
		core.registered_nodes["default:dirt"] = {walkable = true}
		core.get_node_or_nil = function(pos)
			if math.floor(pos.y + 0.5) <= 0 then return {name = "default:dirt"} end
			return {name = "air"}
		end

		-- Ascent phase
		player._pos = {x = 0, y = 1.5, z = 0}
		player.get_velocity = function() return {x = 0, y = 2.5, z = 0} end
		player.get_player_control = function() return {} end
		local rising = player_api.get_player_state(player)
		assert.is_true(rising.jumping)
		assert.is_false(rising.hovering)
		assert.equal("jump", rising.locomotion)

		-- Apex turnover ascent side
		player._pos = {x = 0, y = 1.9, z = 0}
		player.get_velocity = function() return {x = 0, y = 0.2, z = 0} end
		local apex_up = player_api.get_player_state(player)
		assert.is_true(apex_up.jumping)
		assert.is_false(apex_up.hovering)
		assert.equal("jump", apex_up.locomotion)

		-- Apex turnover descent side
		player._pos = {x = 0, y = 1.85, z = 0}
		player.get_velocity = function() return {x = 0, y = -0.2, z = 0} end
		local apex_down = player_api.get_player_state(player)
		assert.is_false(apex_down.jumping)
		assert.is_true(apex_down.falling)
		assert.is_false(apex_down.hovering)
		assert.equal("fall", apex_down.locomotion)

		-- Standard fall
		player._pos = {x = 0, y = 1.2, z = 0}
		player.get_velocity = function() return {x = 0, y = -2.5, z = 0} end
		local falling = player_api.get_player_state(player)
		assert.is_true(falling.falling)
		assert.is_false(falling.hovering)
		assert.equal("fall", falling.locomotion)

		-- Landing
		player._pos = {x = 0, y = 0.5, z = 0}
		player.get_velocity = function() return {x = 0, y = 0.0, z = 0} end
		local landed = player_api.get_player_state(player)
		assert.is_false(landed.jumping)
		assert.is_false(landed.falling)
		assert.is_false(landed.hovering)
		assert.equal("stand", landed.locomotion)
	end)

	it("ensures sprinting and jumping does not trigger fly animation", function()
		core.get_node_or_nil = function() return {name = "air"} end
		player._pos = {x = 0, y = 2.0, z = 0}

		-- Ascent phase of sprint jump (high horiz speed 8.0 m/s, upward vel.y 4.5 m/s, aux1 + jump)
		player.get_velocity = function() return {x = 8.0, y = 4.5, z = 0} end
		player.get_player_control = function() return {up = true, aux1 = true, jump = true} end
		local state1 = player_api.get_player_state(player)
		assert.is_false(state1.flying)
		assert.is_true(state1.jumping)
		assert.equal("jump", state1.locomotion)

		-- Peak turnover of sprint jump (vel.y = 0.2 m/s)
		player.get_velocity = function() return {x = 8.0, y = 0.2, z = 0} end
		local state2 = player_api.get_player_state(player)
		assert.is_false(state2.flying)
		assert.is_true(state2.jumping)
		assert.equal("jump", state2.locomotion)

		-- Descent phase of sprint jump (vel.y = -5.0 m/s)
		player.get_velocity = function() return {x = 8.0, y = -5.0, z = 0} end
		local state3 = player_api.get_player_state(player)
		assert.is_false(state3.flying)
		assert.is_true(state3.falling)
		assert.equal("fall", state3.locomotion)
	end)

	it("maintains walking locomotion without fall jitter when stepping down slopes", function()
		core.registered_nodes["default:dirt"] = {walkable = true}
		core.get_node_or_nil = function(pos)
			-- Ground sloped down at y = 0
			if math.floor(pos.y + 0.5) <= 0 then return {name = "default:dirt"} end
			return {name = "air"}
		end

		-- Walking horizontally on upper ledge
		player._pos = {x = 0, y = 0.5, z = 0}
		player.get_velocity = function() return {x = 4.0, y = 0.0, z = 0} end
		player.get_player_control = function() return {up = true} end
		local flat_walk = player_api.get_player_state(player)
		assert.is_true(flat_walk.moving)
		assert.is_false(flat_walk.falling)
		assert.equal("walk", flat_walk.locomotion)

		-- Transient drop while stepping down slope (ground 0.8 blocks below, vel.y = -2.5)
		player._pos = {x = 0.8, y = 0.8, z = 0}
		player.get_velocity = function() return {x = 4.0, y = -2.5, z = 0} end
		local slope_step = player_api.get_player_state(player)
		assert.is_true(slope_step.moving)
		assert.is_false(slope_step.falling)
		assert.equal("walk", slope_step.locomotion)
	end)

	it("supports extensible weapon categories via player_api.register_weapon_category", function()
		player_api.register_weapon_category("group:halberd", "attack_thrust")
		core.registered_items["test:halberd"] = {
			description = "Halberd",
			groups = {halberd = 1},
		}
		player.get_wielded_item = function()
			return {
				get_name = function() return "test:halberd" end,
				is_empty = function() return false end,
			}
		end
		player.get_player_control = function()
			return {LMB = true, dig = true}
		end

		local state = player_api.get_player_state(player)
		assert.equal("attack_thrust", state.action)
	end)

	it("registers custom gestures and postures with player_api.register_emote and chatcommands", function()
		-- Gesture emote
		player_api.register_emote("salute", {
			is_posture = false,
			duration = 1.5,
			description = "Perform a military salute",
			msg = "Saluting Commander",
		})
		assert.is_not_nil(core.chatcommands["salute"])
		local ok, msg = core.chatcommands["salute"].func("ControlsTester")
		assert.is_true(ok)
		assert.equal("Saluting Commander", msg)

		local pstate = player_api.controls.player_states["ControlsTester"]
		assert.equal("salute", pstate.active_emote)

		-- Posture emote with sit/stand toggle
		player_api.register_emote("kneel", {
			is_posture = true,
			duration = -1,
			description = "Kneel down",
			msg = "Kneeling down",
		})
		assert.is_not_nil(core.chatcommands["kneel"])
		local ok_kneel = core.chatcommands["kneel"].func("ControlsTester")
		assert.is_true(ok_kneel)
		assert.equal("kneel", pstate.active_emote)

		-- Calling again toggles stand up
		local ok_stand, msg_stand = core.chatcommands["kneel"].func("ControlsTester")
		assert.is_true(ok_stand)
		assert.equal("Standing up", msg_stand)
		assert.is_nil(pstate.active_emote)

		-- Posture emote cancels on movement
		core.chatcommands["kneel"].func("ControlsTester")
		assert.equal("kneel", pstate.active_emote)
		player.get_player_control = function() return {up = true} end
		player.get_velocity = function() return {x = 3.0, y = 0, z = 0} end
		local state = player_api.get_player_state(player)
		assert.is_nil(pstate.active_emote)
		assert.not_equal("kneel", state.locomotion)
	end)

	it("tracks get_player_control_bits and single-pass caches controls during update_player_controls", function()
		player._controls = {jump = true, up = true}
		player_api.controls.update_player_controls(player, 0.05)

		local pstate = player_api.controls.player_states["ControlsTester"]
		assert.is_not_nil(pstate.controls)
		assert.is_true(pstate.controls.jump)
		assert.is_true(pstate.controls.up)
		assert.equal(17, pstate.prev_control_bits)

		-- Calling get_player_state should reuse pstate.controls
		local called_control = false
		local orig_fn = player.get_player_control
		player.get_player_control = function(self)
			called_control = true
			return orig_fn(self)
		end

		local state = player_api.get_player_state(player)
		assert.is_false(called_control)
		assert.is_not_nil(state)
	end)

	it("triggers weapon equip montage when model defines equip animation", function()
		player_api.set_model(player, "character.glb")
		player._played_animations = {}

		local ok = player_api.trigger_equip(player)
		assert.is_true(ok)

		local pstate = player_api.controls.player_states["ControlsTester"]
		assert.is_not_nil(pstate.equip_until)
		assert.is_true(pstate.equip_until > (core.get_us_time() * 0.000001))

		player.get_player_control = function() return {} end
		local state = player_api.get_player_state(player)
		assert.is_true(state.equipping)
		assert.equal("equip", state.action)
	end)

	it("falls back to no-op when active model does not have an equip animation", function()
		player_api.register_model("legacy_model.b3d", {
			animations = {
				stand = {x = 0, y = 10},
				walk = {x = 11, y = 20},
			},
		})
		player_api.set_model(player, "legacy_model.b3d")

		local ok = player_api.trigger_equip(player)
		assert.is_false(ok)

		local pstate = player_api.controls.player_states["ControlsTester"]
		pstate.equip_until = 0

		player.get_player_control = function() return {} end
		local state = player_api.get_player_state(player)
		assert.is_false(state.equipping)
		assert.is_nil(state.action)

		-- Restore default model
		player_api.set_model(player, "character.glb")
	end)

	it("immediately interrupts equip montage when player attacks or mines", function()
		player_api.set_model(player, "character.glb")
		local ok = player_api.trigger_equip(player)
		assert.is_true(ok)

		-- Simulate player clicking LMB to mine / attack
		player.get_player_control = function()
			return {LMB = true, dig = true}
		end
		player_api.update_player_controls(player, 0.1)

		local state = player_api.get_player_state(player)
		assert.is_false(state.equipping)
		assert.equal("mine", state.action)

		local pstate = player_api.controls.player_states["ControlsTester"]
		assert.equal(0, pstate.equip_until)
	end)

	it("triggers equip montage on item swap via wield globalstep", function()
		player_api.set_model(player, "character.glb")
		player:set_wielded_item("default:pick_wood")
		player_api.attach_wield_item(player)
		local name = player:get_player_name()
		local data = player_api.wield_entities[name]
		assert.is_not_nil(data)
		data.last_wield_name = "default:pick_wood"

		-- Now switch item to a sword
		player:set_wielded_item("default:sword_steel")

		-- Run globalstep
		for _, step_fn in ipairs(core._globalsteps) do
			step_fn(0.01)
		end

		local pstate = player_api.controls.player_states[name]
		assert.is_true(pstate.equip_until > (core.get_us_time() * 0.000001))

		player.get_player_control = function() return {} end
		local state = player_api.get_player_state(player)
		assert.is_true(state.equipping)
		assert.equal("equip", state.action)
	end)

	it("does not trigger forward sprint when moving backward or purely lateral", function()
		core.get_node_or_nil = function() return {name = "default:dirt"} end
		core.registered_nodes["default:dirt"] = {walkable = true}
		player._pos = {x = 0, y = 0.5, z = 0}

		-- Moving backward with aux1 pressed (e.g. backpedaling)
		player.get_player_control = function()
			return {down = true, aux1 = true}
		end
		player.get_velocity = function()
			return {x = 0, y = 0, z = -4.0}
		end

		local state = player_api.get_player_state(player)
		assert.is_false(state.sprinting)
		assert.not_equal("run", state.locomotion)

		-- Purely strafing laterally with aux1 pressed
		player.get_player_control = function()
			return {left = true, aux1 = true}
		end
		player.get_velocity = function()
			return {x = -4.0, y = 0, z = 0}
		end

		state = player_api.get_player_state(player)
		assert.is_false(state.sprinting)
		assert.not_equal("run", state.locomotion)

		-- Moving forward with aux1 pressed triggers sprint
		player.get_player_control = function()
			return {up = true, aux1 = true}
		end
		player.get_velocity = function()
			return {x = 0, y = 0, z = 4.0}
		end

		state = player_api.get_player_state(player)
		assert.is_true(state.sprinting)
		assert.equal("sprint", state.locomotion)
	end)

	it("clears wield params cache on player_api.clear_item_cache", function()
		core.registered_items["test_mod:custom_sword"] = {
			type = "tool",
			groups = {sword = 1},
		}
		local _, pos1 = player_api.get_wield_attachment_params("test_mod:custom_sword")
		assert.is_not_nil(pos1)

		-- Clear cache via unified clear_item_cache
		player_api.clear_item_cache()

		-- Register an offset override and verify new value is returned rather than stale cache
		player_api.register_wield_item_offset("test_mod:custom_sword", {
			pos = {x = 1.0, y = 2.0, z = 3.0},
		})
		local _, pos2 = player_api.get_wield_attachment_params("test_mod:custom_sword")
		assert.not_equal(pos1.x, pos2.x)
	end)

	it("resets double-tap timestamp upon sprint activation", function()
		local name = player:get_player_name()
		local pstate = player_api.controls.player_states[name]

		-- Tap 1 at t=10.0
		player.get_player_control = function() return {up = true} end
		player_api.update_player_controls(player, 0.05, 10.0)
		assert.equal(10.0, pstate.last_press_time["up"])
		assert.is_false(pstate.double_tap_sprint)

		-- Release at t=10.1
		player.get_player_control = function() return {} end
		player_api.update_player_controls(player, 0.05, 10.1)

		-- Tap 2 at t=10.2 (within DOUBLE_TAP_TIME = 0.28) -> activates sprint
		player.get_player_control = function() return {up = true} end
		player_api.update_player_controls(player, 0.05, 10.2)
		assert.is_true(pstate.double_tap_sprint)
		-- Timestamp reset to 0 to prevent successive taps immediately re-triggering
		assert.equal(0, pstate.last_press_time["up"])
	end)

	it("prevents mid-air sneak from triggering sliding animation", function()
		local name = player:get_player_name()
		local pstate = player_api.controls.player_states[name]
		pstate.was_on_ground = false
		pstate.sliding_until = 0

		-- Airborne node
		core.get_node_or_nil = function() return {name = "air"} end
		player._pos = {x = 0, y = 50.0, z = 0}

		-- Press sneak while sprinting forward in mid-air
		player.get_player_control = function() return {up = true, aux1 = true, sneak = true} end
		player_api.update_player_controls(player, 0.05, 20.0)

		-- Should not trigger sliding_until
		assert.equal(0, pstate.sliding_until)

		-- Even if sliding_until was set, is_sliding is false while in air
		pstate.sliding_until = 99999
		local state = player_api.get_player_state(player, 20.0)
		assert.is_false(state.sliding)
	end)

	it("prevents crouch state when sneaking stationary in water or on ladders", function()
		-- In water
		core.get_node_or_nil = function() return {name = "default:water_source"} end
		core.registered_nodes["default:water_source"] = {liquidtype = "source", walkable = false}
		player.get_player_control = function() return {sneak = true} end
		player.get_velocity = function() return {x = 0, y = 0, z = 0} end

		local state = player_api.get_player_state(player)
		assert.is_false(state.crouching)
		assert.is_false(state.crouch_walking)
	end)

	it("overrides local client animation during /test_anim and restores on stop", function()
		player_api.set_model(player, "character.b3d")
		local ok = core.chatcommands["test_anim"].func("ControlsTester", "walk 4")
		assert.is_true(ok)

		local anim = player_api.get_animation(player)
		assert.equal("walk", anim.animation)
		assert.is_true(anim.override_local)

		-- Stop anim test
		core.chatcommands["test_anim"].func("ControlsTester", "stop")
		local anim_after = player_api.get_animation(player)
		assert.equal("stand", anim_after.animation)
		assert.is_false(anim_after.override_local)
	end)

	it("triggers equip montage on model defining only animations_glb.equip", function()
		player_api.register_model("glb_equip_only.glb", {
			mesh_glb = "glb_equip_only.glb",
			is_multitrack = true,
			animations_glb = {
				equip = {track = "equip", priority = 1, is_action = true, loop = false},
			},
		})
		player_api.set_model(player, "glb_equip_only.glb")
		local equip_ok = player_api.trigger_equip(player, "default:sword_steel")
		assert.is_true(equip_ok)

		local pstate = player_api.controls.player_states["ControlsTester"]
		assert.is_true(pstate.equip_until > (core.get_us_time() * 0.000001))
	end)

	it("detects potions and drinks via is_consumable and triggers eating on LMB", function()
		assert.is_true(player_api.is_consumable("potions:healing"))
		assert.is_true(player_api.is_consumable("mobs:glass_bottle"))
		assert.is_false(player_api.is_consumable("default:dirt"))

		player:set_wielded_item("potions:healing")
		player.get_player_control = function() return {LMB = true, dig = true} end
		player_api.update_player_controls(player, 0.1)

		local state = player_api.get_player_state(player)
		assert.is_true(state.eating)
		assert.equal("eat", state.action)
	end)

	it("preserves custom consumable action tracks like drink across ticks", function()
		player_api.register_consumable("magic:elixir", {
			action = "drink",
			duration = 1.2,
		})

		player_api.trigger_eat(player, 1.2, "magic:elixir")
		local state = player_api.get_player_state(player)
		assert.is_true(state.eating)
		assert.equal("drink", state.action)

		local pstate = player_api.controls.player_states[player:get_player_name()]
		pstate.eat_until = 0
	end)

	it("enforces sitting locomotion when player is attached in globalstep", function()
		player_api.set_model(player, "character.glb")
		player_api.set_animation(player, "stand")
		assert.equal("stand", player_api.get_animation(player).animation)

		local name = player:get_player_name()
		player_api.player_attached[name] = true
		player_api.globalstep(0.1)

		assert.equal("sit", player_api.get_animation(player).animation)
		player_api.player_attached[name] = false
	end)

	it("safely ignores nil or invalid ObjectRefs on public triggers and prevents emotes when dead", function()
		assert.is_nil(player_api.trigger_bow_shoot(nil))
		assert.is_nil(player_api.trigger_hurt(nil))
		assert.is_false(player_api.trigger_equip(nil))
		assert.is_nil(player_api.play_emote(nil, "wave"))
		assert.is_nil(player_api.stop_emote(nil))

		local fake_obj = {}
		assert.is_nil(player_api.trigger_bow_shoot(fake_obj))
		assert.is_nil(player_api.trigger_hurt(fake_obj))
		assert.is_false(player_api.trigger_equip(fake_obj))
		assert.is_nil(player_api.play_emote(fake_obj, "wave"))
		assert.is_nil(player_api.stop_emote(fake_obj))

		player:set_hp(0)
		player_api.play_emote(player, "wave")
		local pstate = player_api.controls.player_states[player:get_player_name()]
		assert.is_nil(pstate.active_emote)
		player:set_hp(20)
	end)

	it("allows eating and weapon actions while player is attached to mount or vehicle", function()
		player_api.set_model(player, "character.glb")
		local name = player:get_player_name()
		player_api.player_attached[name] = true

		core.registered_items["food:apple"] = {
			type = "craftitem",
			inventory_image = "food_apple.png",
			groups = {food = 1},
		}
		player:set_wielded_item("food:apple", 1)
		player_api.clear_item_cache()
		player._controls = {dig = true, LMB = true, place = false, RMB = false}

		local pstate = player_api.controls.player_states[name]
		pstate.eat_until = 0
		pstate.last_chew_particle_time = 0
		pstate.wield_name = nil
		pstate.item_info = nil
		local wield_data = player_api.wield_entities and player_api.wield_entities[name]
		if wield_data then
			wield_data.last_wield_name = "food:apple"
		end

		player_api.controls.update_player_controls(player, 0.1)
		local state = player_api.get_player_state(player)

		assert.equal("sit", state.locomotion, "Locomotion must remain sit while attached")
		assert.is_true(state.eating, "Attached player must be able to eat")
		assert.equal("eat", state.action, "Action must be eat")

		player_api.globalstep(0.1)
		assert.equal("sit", player_api.get_animation(player).animation)

		local proxies = player_api.get_visual_proxies(player)
		local glb = proxies.glb
		local last_action_anim = glb._played_animations[#glb._played_animations]
		assert.is_not_nil(last_action_anim)
		assert.equal("eat", last_action_anim.track)

		player_api.player_attached[name] = false
	end)

	it("detects climbable ladder at upper-body height (pos.y + 1.2)", function()
		core.registered_nodes["test:ladder"] = {
			climbable = true,
			walkable = false,
		}
		core.registered_nodes["test:air"] = {
			walkable = false,
		}

		-- Player at y = 0.8: waist (0.8 + 0.5 = 1.3) is in node 1 (air),
		-- head/torso (0.8 + 1.2 = 2.0) is in node 2 (ladder).
		player:set_pos({x = 0, y = 0.8, z = 0})
		core.get_node_or_nil = function(pos)
			local ny = math.floor(pos.y + 0.5)
			if ny == 2 then
				return {name = "test:ladder"}
			end
			return {name = "test:air"}
		end

		local state = player_api.get_player_state(player)
		assert.is_true(state.climbing, "Upper body contacting ladder must set climbing")
		assert.equal("climb", state.locomotion)

		core.get_node_or_nil = function() return {name = "default:dirt"} end
		player:set_pos({x = 0, y = 0, z = 0})
	end)

	it("prioritizes exact weapon category override over broad group match", function()
		player_api.register_weapon_category("group:test_blade", "attack_slash")
		player_api.register_weapon_category("test:thrust_blade", "attack_thrust")

		core.registered_items["test:thrust_blade"] = {
			description = "Thrust Blade",
			groups = {test_blade = 1},
		}
		player_api.clear_item_cache()

		player:set_wielded_item("test:thrust_blade", 1)
		player._controls = {dig = true, LMB = true}
		local pstate = player_api.controls.player_states[player:get_player_name()]
		pstate.wield_name = nil
		pstate.item_info = nil
		pstate.wielded_item = nil

		player_api.controls.update_player_controls(player, 0.1)
		local state = player_api.get_player_state(player)
		assert.equal("attack_thrust", state.action, "Exact weapon category match must take precedence")
	end)

	it("recognizes drink action in classify_item as consumable", function()
		core.registered_items["test:elixir"] = {
			description = "Magic Elixir",
			_consumable_action = "drink",
		}
		player_api.register_consumable("test:elixir", {
			action = "drink",
			duration = 1.0,
			particle_type = "liquid_drops",
		})
		player_api.clear_item_cache()

		player:set_wielded_item("test:elixir", 1)
		player._controls = {dig = true, LMB = true, place = false, RMB = false}
		local pstate = player_api.controls.player_states[player:get_player_name()]
		pstate.eat_until = 0
		pstate.wield_name = nil
		pstate.item_info = nil
		pstate.wielded_item = nil

		player_api.controls.update_player_controls(player, 0.1)
		local state = player_api.get_player_state(player)
		assert.is_true(state.eating)
		assert.equal("drink", state.action)
	end)

	it("initializes in stand locomotion and avoids false hover in unloaded chunks on join", function()
		core.get_node_or_nil = function() return {name = "ignore"} end
		player._pos = {x = 0, y = 10.5, z = 0}
		player.get_velocity = function() return {x = 0, y = 0, z = 0} end
		player.get_player_control = function() return {} end
		local pstate = player_api.controls.player_states[player:get_player_name()]
		pstate.was_on_ground = true

		local state = player_api.get_player_state(player)
		assert.is_false(state.hovering, "Unloaded chunk on join must not trigger hovering")
		assert.equal("stand", state.locomotion)
	end)

	it("detects ground and maintains stand locomotion when stationary on half-height slab", function()
		core.registered_nodes["stairs:slab_wood"] = {walkable = true}
		core.get_node_or_nil = function(pos)
			if math.floor(pos.y + 0.5) == 1 then
				return {name = "stairs:slab_wood"}
			end
			return {name = "air"}
		end
		player._pos = {x = 0, y = 1.0, z = 0}
		player.get_velocity = function() return {x = 0, y = 0, z = 0} end
		player.get_player_control = function() return {} end

		local state = player_api.get_player_state(player)
		assert.is_false(state.hovering, "Stationary player on slab must not hover")
		assert.equal("stand", state.locomotion)
	end)

	it("translates emote messages and chatcommand responses via get_translator", function()
		local wave_cmd = core.chatcommands["wave"]
		assert.is_not_nil(wave_cmd)
		assert.equal("Perform the wave gesture", wave_cmd.description)

		local ok, msg = wave_cmd.func(player:get_player_name())
		assert.is_true(ok)
		assert.equal("Playing gesture: wave", msg)

		local sit_cmd = core.chatcommands["sit"]
		assert.is_not_nil(sit_cmd)
		local ok_sit, sit_msg = sit_cmd.func(player:get_player_name())
		assert.is_true(ok_sit)
		assert.equal("Sitting down (move to stand up)", sit_msg)

		-- Stand up toggle
		local ok_stand, stand_msg = sit_cmd.func(player:get_player_name())
		assert.is_true(ok_stand)
		assert.equal("Standing up", stand_msg)
	end)

	it("recognizes group:armor_shield and triggers block posture on RMB", function()
		core.registered_items["shields:shield_wood"] = {
			description = "Wood Shield",
			groups = {armor_shield = 1}
		}
		player.get_wielded_item = function()
			return ItemStack("shields:shield_wood")
		end
		player.get_player_control = function()
			return {RMB = true}
		end

		local state = player_api.get_player_state(player)
		assert.is_true(state.blocking)
		assert.equal("block", state.action)
	end)

	it("allows blocking via register_blocking_predicate even with non-shield wielded item", function()
		core.registered_items["default:sword_steel"] = {
			description = "Steel Sword",
			groups = {sword = 1}
		}
		player.get_wielded_item = function()
			return ItemStack("default:sword_steel")
		end
		player.get_player_control = function()
			return {RMB = true}
		end

		local state_before = player_api.get_player_state(player)
		assert.is_false(state_before.blocking)

		local predicate_called = false
		x_player_api.register_blocking_predicate(function(p, wield_name)
			if p == player and wield_name == "default:sword_steel" then
				predicate_called = true
				return true
			end
			return false
		end)

		local state_after = player_api.get_player_state(player)
		assert.is_true(predicate_called)
		assert.is_true(state_after.blocking)
		assert.equal("block", state_after.action)
		x_player_api.blocking_predicates = {}
	end)

	it("animates upper body actions on B3D proxies and player entity when model_format is b3d", function()
		core.registered_nodes["default:dirt"] = {walkable = true}
		core.get_node_or_nil = function(pos)
			if math.floor(pos.y + 0.5) <= 0 then
				return {name = "default:dirt"}
			end
			return {name = "air"}
		end
		player._pos = {x = 0, y = 0.5, z = 0}

		player_api.set_model_format("b3d")
		player_api.set_model(player, "character.b3d")
		local proxies = x_player_api.get_visual_proxies(player)
		assert.is_not_nil(proxies.b3d)

		-- Stand still
		player.get_player_control = function() return {} end
		player.get_velocity = function() return {x = 0, y = 0, z = 0} end
		player.get_wielded_item = function() return ItemStack("default:pick_wood") end
		player_api.globalstep(0.05)
		assert.equal("stand", player_api.get_animation(player).animation)

		-- Mine (LMB)
		player.get_player_control = function() return {LMB = true} end
		player_api.globalstep(0.05)
		assert.equal("mine", player_api.get_animation(player).animation)
		assert.equal(190, player._last_animation.anim.x)
		assert.equal(200, player._last_animation.anim.y)

		-- Walk and mine
		player.get_player_control = function() return {LMB = true, up = true} end
		player.get_velocity = function() return {x = 0, y = 0, z = 2.0} end
		player_api.globalstep(0.05)
		assert.equal("walk_mine", player_api.get_animation(player).animation)
		assert.equal(201, player._last_animation.anim.x)
		assert.equal(220, player._last_animation.anim.y)

		-- Attack slash with sword
		player.get_wielded_item = function() return ItemStack("default:sword_steel") end
		player.get_player_control = function() return {LMB = true} end
		player.get_velocity = function() return {x = 0, y = 0, z = 0} end
		player_api.globalstep(0.05)
		assert.equal("attack_slash", player_api.get_animation(player).animation)
		assert.equal(405, player._last_animation.anim.x)
		assert.equal(415, player._last_animation.anim.y)

		-- Restore format
		player.get_player_control = function() return {} end
		player_api.set_model_format("glb")
	end)

	it("synchronizes single-timeline actions to B3D proxy and player in GLB mode", function()
		core.registered_nodes["default:dirt"] = {walkable = true}
		core.get_node_or_nil = function(pos)
			if math.floor(pos.y + 0.5) <= 0 then
				return {name = "default:dirt"}
			end
			return {name = "air"}
		end
		player._pos = {x = 0, y = 0.5, z = 0}

		player_api.set_model_format("glb")
		player_api.set_model(player, "character.b3d")

		-- Mine (LMB)
		player.get_player_control = function() return {LMB = true} end
		player.get_velocity = function() return {x = 0, y = 0, z = 0} end
		player.get_wielded_item = function() return ItemStack("default:pick_wood") end
		player_api.globalstep(0.05)

		-- Locomotion is stand for GLB, but B3D single-timeline receives mine!
		assert.equal("stand", player_api.get_animation(player).animation)
		assert.equal("mine", player_api.get_animation(player).animation_b3d)
		assert.equal(190, player._last_animation.anim.x)
		assert.equal(200, player._last_animation.anim.y)

		-- Restore
		player.get_player_control = function() return {} end
		player_api.globalstep(0.05)
	end)

	it("triggers default interaction animation when pressing RMB or place with weapon or tool", function()
		player.get_wielded_item = function() return ItemStack("default:sword_steel") end
		player.get_player_control = function() return {RMB = true, place = true} end
		local state = player_api.get_player_state(player)
		assert.equal("mine", state.action)
		assert.is_true(state.acting and state.action ~= nil)

		player.get_wielded_item = function() return ItemStack("default:pick_diamond") end
		player.get_player_control = function() return {RMB = true} end
		local state2 = player_api.get_player_state(player)
		assert.equal("mine", state2.action)
	end)

	it("verifies animations_glb does not contain legacy walk_mine track", function()
		local mdef = player_api.get_model("character.b3d")
		assert.is_not_nil(mdef)
		assert.is_not_nil(mdef.animations_glb)
		assert.is_nil(mdef.animations_glb.walk_mine)
	end)

	it("prioritizes animations_glb collisionbox and eye_height over b3d fallback", function()
		player_api.register_model("glb_precedence_test.glb", {
			mesh_glb = "glb_precedence_test.glb",
			mesh = "character.b3d",
			is_multitrack = true,
			animations = {
				crouch = {x = 315, y = 355, eye_height = 1.1, collisionbox = {-0.2, 0, -0.2, 0.2, 1.2, 0.2}},
			},
			animations_glb = {
				crouch = {track = "crouch", priority = 0, eye_height = 1.25,
					collisionbox = {-0.3, 0.0, -0.3, 0.3, 1.45, 0.3}},
			},
		})
		player_api.set_model(player, "glb_precedence_test.glb")
		player_api.set_animation(player, "crouch")

		local props = player:get_properties()
		assert.equal(1.25, props.eye_height)
		assert.equal(-0.3, props.collisionbox[1])
		assert.equal(1.45, props.collisionbox[5])

		-- Restore default model
		player_api.set_model(player, "character.glb")
	end)

	it("sustains action state across ticks during LMB action duration window", function()
		player_api.set_model(player, "character.b3d")
		player:set_wielded_item("default:pick_wood")
		player_api.globalstep(0.05)
		local pstate = player_api.controls.player_states[player:get_player_name()]
		pstate.equip_until = 0

		-- Tick 1: LMB tapped for 0.05s
		player.get_player_control = function() return {LMB = true} end
		player_api.globalstep(0.05)
		local state = player_api.get_player_state(player)
		assert.equal("mine", state.action)
		assert.is_true(state.acting)

		-- Tick 2: LMB released 0.05s later (transient tap) - action window must remain active
		player.get_player_control = function() return {} end
		core._mock_us_time = core._mock_us_time + 50000
		player_api.globalstep(0.05)
		state = player_api.get_player_state(player)
		assert.equal("mine", state.action)
		assert.is_true(state.acting)

		-- Tick 3: Advance past the 0.45s window expiration
		core._mock_us_time = core._mock_us_time + 450000
		player_api.globalstep(0.45)
		state = player_api.get_player_state(player)
		assert.is_nil(state.action)
	end)

	it("triggers action window via trigger_player_action for combat/punch events", function()
		player_api.set_model(player, "character.b3d")
		player:set_wielded_item("default:sword_steel")
		player_api.globalstep(0.05)
		local pstate = player_api.controls.player_states[player:get_player_name()]
		pstate.equip_until = 0
		pstate.lmb_action_until = 0

		player.get_player_control = function() return {} end
		player_api.trigger_player_action(player)

		local state = player_api.get_player_state(player)
		assert.equal("attack_slash", state.action)

		-- Advance past duration window (0.33s)
		core._mock_us_time = core._mock_us_time + 500000
		pstate.equip_until = 0
		player_api.globalstep(0.50)
		state = player_api.get_player_state(player)
		assert.is_nil(state.action)
	end)

	it("debounces hit contact events during in-flight swing and preserves continuous cycles on hold", function()
		player_api.set_model(player, "character.b3d")
		player:set_wielded_item("default:sword_steel")
		player_api.globalstep(0.05)
		local pstate = player_api.controls.player_states[player:get_player_name()]
		pstate.equip_until = 0
		pstate.lmb_action_until = 0
		pstate.lmb_cycle_count = 0

		-- 1. Click LMB once (tap)
		player.get_player_control = function() return {LMB = true} end
		player_api.globalstep(0.05)
		assert.equal("attack_slash", pstate.lmb_action)
		assert.equal(1, pstate.lmb_cycle_count)

		-- Release LMB immediately (tap)
		player.get_player_control = function() return {} end

		-- 2. Punch contact registers 50ms later (e.g. hitting node or mob)
		core._mock_us_time = core._mock_us_time + 50000
		player_api.trigger_player_action(player)
		-- Must NOT increment cycle count or restart in-flight swing
		assert.equal(1, pstate.lmb_cycle_count)

		-- 3. After 0.35s (single swing completes), action expires cleanly without 2nd swing
		core._mock_us_time = core._mock_us_time + 350000
		player_api.globalstep(0.35)
		local state = player_api.get_player_state(player)
		assert.is_nil(state.action)

		-- 4. Hold LMB down: must continuously cycle every ~0.33s
		player.get_player_control = function() return {LMB = true} end
		local initial_cycles = pstate.lmb_cycle_count
		for _ = 1, 20 do
			core._mock_us_time = core._mock_us_time + 50000
			player_api.globalstep(0.05)
		end
		-- In 1.0 second with 0.33s cycle duration, must have progressed at least 3 attack cycles
		assert.is_true(pstate.lmb_cycle_count >= initial_cycles + 3)
	end)

	it("resets transient action states and semantic flags on die and respawn", function()
		local name = player:get_player_name()
		local pstate = player_api.controls.player_states[name]
		assert.is_not_nil(pstate)

		-- Set up active transient actions
		pstate.double_tap_sprint = true
		pstate.sliding_until = 999999
		pstate.bow_shoot_until = 999999
		pstate.hurt_until = 999999
		pstate.lmb_action_until = 999999
		pstate.lmb_action = "attack_slash"
		pstate.eat_until = 999999
		pstate.active_emote = "wave"
		pstate.semantic_state.acting = true
		pstate.semantic_state.sliding = true
		pstate.semantic_state.hurt = true

		-- Trigger death callbacks
		for _, cb in ipairs(core._on_dieplayers) do
			cb(player)
		end

		assert.is_false(pstate.double_tap_sprint)
		assert.equal(0, pstate.sliding_until)
		assert.equal(0, pstate.bow_shoot_until)
		assert.equal(0, pstate.hurt_until)
		assert.equal(0, pstate.lmb_action_until)
		assert.is_nil(pstate.lmb_action)
		assert.equal(0, pstate.eat_until)
		assert.is_nil(pstate.active_emote)
		assert.is_false(pstate.semantic_state.acting)
		assert.is_false(pstate.semantic_state.sliding)
		assert.is_false(pstate.semantic_state.hurt)

		-- Set transient state again and verify respawn reset
		pstate.sliding_until = 999999
		pstate.hurt_until = 999999
		for _, cb in ipairs(core._on_respawnplayers) do
			cb(player)
		end
		assert.equal(0, pstate.sliding_until)
		assert.equal(0, pstate.hurt_until)
	end)
end)


