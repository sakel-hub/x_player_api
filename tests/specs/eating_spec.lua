-- Specs for Consumables, Eating Animations, Particles, and Settings

local mock_env = require("tests.mock_env")

describe("Eating & Consumables System", function()
	local player

	before_each(function()
		player = mock_env.join_player("EatingTester")
		core._particlespawners = {}
		core._sounds_played = {}
		player_api.set_eating_enabled(true)
	end)

	after_each(function()
		player_api.set_eating_enabled(true)
	end)

	it("registers and retrieves custom consumable definitions", function()
		player_api.register_consumable("mod:honey_pot", {
			sound = "item_honey_slurp",
			duration = 2.5,
			particles = true,
		})
		local cdef = player_api.get_consumable_definition("mod:honey_pot")
		assert.is_not_nil(cdef)
		assert.equal("item_honey_slurp", cdef.sound)
		assert.equal(2.5, cdef.duration)
	end)

	it("retrieves correct item texture for nodes, craftitems, and tools", function()
		core.registered_items["food:cake"] = {
			type = "craftitem",
			inventory_image = "food_cake.png",
		}
		assert.equal("food_cake.png", player_api.get_item_texture("food:cake"))

		core.registered_items["tools:dagger"] = {
			type = "tool",
			wield_image = "tools_dagger_wield.png",
		}
		assert.equal("tools_dagger_wield.png", player_api.get_item_texture("tools:dagger"))
		assert.is_nil(player_api.get_item_texture("nonexistent:none"))
	end)

	it("spawns node crumb particles for food nodes", function()
		core.registered_nodes["default:apple"] = {
			description = "Apple",
			tiles = {"default_apple.png"},
		}
		local id = player_api.spawn_eat_particles(player, "default:apple", 0.8)
		assert.is_not_nil(id)
		local spawner = core._particlespawners[id]
		assert.is_not_nil(spawner)
		assert.equal("default:apple", spawner.node.name)
		assert.is_true(spawner.collisiondetection)
		assert.equal(-9.81, spawner.acc.min.y)
	end)

	it("spawns sliced crumb texture pool for craftitems to avoid unknown node crashes", function()
		core.registered_nodes["food:bread"] = nil
		core.registered_items["food:bread"] = {
			type = "craftitem",
			inventory_image = "food_bread.png",
		}
		local id = player_api.spawn_eat_particles(player, "food:bread", 0.8)
		assert.is_not_nil(id)
		local spawner = core._particlespawners[id]
		assert.is_nil(spawner.node)
		assert.equal(16, #spawner.texpool)
		assert.equal("clip", spawner.texpool[1].blend)
	end)

	it("spawns liquid drop particles using x_player_api_bubble.png for drinks/potions", function()
		local id = player_api.spawn_eat_particles(player, "potions:water", 0.8, "liquid_drops")
		assert.is_not_nil(id)
		local spawner = core._particlespawners[id]
		assert.equal("x_player_api_bubble.png", spawner.texture)
		assert.equal("x_player_api_bubble.png", spawner.texpool[1])
	end)

	it("triggers eating action, duration, and sound on trigger_eat", function()
		player_api.register_consumable("mod:potion", {
			sound = "item_potion_drink",
			duration = 1.8,
		})
		player_api.trigger_eat(player, 1.8, "mod:potion")

		local state = player_api.get_player_state(player)
		assert.equal("eat", state.action)
		assert.is_true(state.eating)
		assert.is_true(#core._sounds_played > 0)
		assert.equal("item_potion_drink", core._sounds_played[#core._sounds_played].spec)
	end)

	it("handles saturated food eating via on_item_eat hook without fallthrough to mine", function()
		core.registered_items["farming:bread_loaf"] = {type = "craftitem"}
		player:set_wielded_item("farming:bread_loaf", 1)
		player:set_hp(20)

		local fake_bread_stack = {
			is_empty = function() return false end,
			get_name = function() return "farming:bread_loaf" end,
		}
		for _, cb in ipairs(core._on_item_eat) do
			cb(0, nil, fake_bread_stack, player, nil)
		end

		local state = player_api.get_player_state(player)
		assert.is_true(state.eating)
		assert.equal("eat", state.action)
	end)

	it("respects enable_eating setting and suppresses operations when disabled", function()
		player_api.set_eating_enabled(false)
		assert.is_false(player_api.enable_eating)

		local pstate = player_api.controls.player_states[player:get_player_name()]
		pstate.eat_until = 0
		player_api.trigger_eat(player, 1.2, "default:apple")
		assert.equal(0, pstate.eat_until)

		local spawner = player_api.spawn_eat_particles(player, "default:apple", 1.2)
		assert.is_nil(spawner)

		player_api.set_eating_enabled(true)
		assert.is_true(player_api.enable_eating)
		player_api.trigger_eat(player, 1.2, "default:apple")
		assert.is_true(pstate.eat_until > 0)
	end)

	it("gracefully handles nil player:get_pos() during trigger_eat sound playback", function()
		player_api.register_consumable("test:soup", {
			action = "eat",
			sound = "soup_slurp",
		})
		player.get_pos = function() return nil end

		local initial_sounds = #core._sounds_played
		player_api.trigger_eat(player, 1.2, "test:soup")

		-- No crash, and no sound played because pos was nil
		assert.equal(initial_sounds, #core._sounds_played)
	end)

	it("exposes clear_consumable_cache and is cleared by clear_item_cache", function()
		assert.is_not_nil(player_api.clear_consumable_cache)
		local def1 = player_api.get_consumable_definition("default:apple")
		assert.is_not_nil(def1)

		player_api.clear_consumable_cache()
		local def2 = player_api.get_consumable_definition("default:apple")
		assert.equal(def1.action, def2.action)

		-- Calling clear_item_cache also flushes consumable cache
		player_api.clear_item_cache()
	end)

	it("synchronizes particle velocity with player velocity when standing still", function()
		player:set_velocity({x = 0, y = 0, z = 0})
		player:set_look_horizontal(0)

		local id = player_api.spawn_eat_particles(player, "default:apple", 0.25)
		assert.is_not_nil(id)
		local spawner = core._particlespawners[id]
		assert.is_not_nil(spawner)
		assert.equal(player, spawner.attached)

		-- Particles originate at mouth height (~1.29m) and in front of the body (> 0.35m)
		assert.is_true(spawner.pos.min.y >= 1.2)
		assert.is_true(spawner.pos.max.y <= 1.4)
		assert.is_true(spawner.pos.min.z >= 0.35)
		assert.is_true(spawner.pos.max.z <= 0.50)

		-- Downward drop and slight forward tumble
		assert.is_true(spawner.vel.min.y < 0)
		assert.is_true(spawner.vel.max.y < 0)
		assert.is_true(spawner.vel.min.z > 0)
		assert.is_true(spawner.vel.max.z > 0)
	end)

	it("synchronizes particle forward velocity when player is sprinting forward", function()
		-- Facing North (yaw = 0): forward is +Z
		player:set_look_horizontal(0)
		player:set_velocity({x = 0, y = 0, z = 6.5})

		local id = player_api.spawn_eat_particles(player, "default:apple", 0.25)
		local spawner = core._particlespawners[id]
		assert.is_not_nil(spawner)
		assert.equal(player, spawner.attached)

		-- Forward velocity in player-local frame (+Z) inherits 6.5 m/s sprint speed
		assert.is_true(spawner.vel.min.z >= 6.3)
		assert.is_true(spawner.vel.max.z >= 6.8)

		-- Facing East (yaw = -pi/2): forward in world space is +X
		local yaw_east = -math.pi / 2
		player:set_look_horizontal(yaw_east)
		player:set_velocity({x = 6.5, y = 0, z = 0})

		local id2 = player_api.spawn_eat_particles(player, "default:apple", 0.25)
		local spawner2 = core._particlespawners[id2]
		assert.is_not_nil(spawner2)
		assert.is_true(spawner2.vel.min.z >= 6.3)
		assert.is_true(spawner2.vel.max.z >= 6.8)
	end)

	it("synchronizes upward particle velocity when player jumps", function()
		player:set_look_horizontal(0)
		player:set_velocity({x = 0, y = 7.5, z = 0})

		local id = player_api.spawn_eat_particles(player, "default:apple", 0.25)
		local spawner = core._particlespawners[id]
		assert.is_not_nil(spawner)

		-- Vertical velocity is upward (> 6.0 m/s)
		assert.is_true(spawner.vel.min.y >= 6.5)
		assert.is_true(spawner.vel.max.y >= 7.0)
	end)

	it("synchronizes downward particle velocity when player falls", function()
		player:set_look_horizontal(0)
		player:set_velocity({x = 0, y = -10.0, z = 0})

		local id = player_api.spawn_eat_particles(player, "default:apple", 0.25)
		local spawner = core._particlespawners[id]
		assert.is_not_nil(spawner)

		-- Downward velocity drops with player (< -10.0 m/s)
		assert.is_true(spawner.vel.min.y <= -10.5)
		assert.is_true(spawner.vel.max.y <= -10.0)
	end)

	it("inherits vehicle or mount velocity when player is attached", function()
		player:set_look_horizontal(0)
		player:set_velocity({x = 0, y = 0, z = 0})

		local mount = {
			get_velocity = function() return {x = 0, y = 0, z = 8.0} end,
		}
		player:set_attach(mount, "body", {x = 0, y = 0, z = 0}, {x = 0, y = 0, z = 0}, true)

		local id = player_api.spawn_eat_particles(player, "default:apple", 0.25)
		local spawner = core._particlespawners[id]
		assert.is_not_nil(spawner)
		assert.is_true(spawner.vel.min.z >= 7.8)

		player:set_detach()
	end)

	it("schedules successive micro-bursts for eating durations greater than 0.25s", function()
		core._after_timers = {}
		player:set_velocity({x = 0, y = 0, z = 0})

		local id = player_api.spawn_eat_particles(player, "default:apple", 1.0)
		assert.is_not_nil(id)
		-- Duration 1.0s with 0.25s intervals schedules 3 subsequent timer bursts
		assert.equal(3, #core._after_timers)
		assert.equal(0.25, core._after_timers[1].delay)
		assert.equal(0.50, core._after_timers[2].delay)
		assert.equal(0.75, core._after_timers[3].delay)
	end)

	it("triggers eating via on_item_eat hook when food is consumed", function()
		core.registered_items["farming:apple_slice"] = {type = "craftitem"}
		player:set_wielded_item("farming:apple_slice", 1)

		local fake_apple_stack = {
			is_empty = function() return false end,
			get_name = function() return "farming:apple_slice" end,
		}

		-- In Luanti food consumption occurs via LMB click (dig = true)
		player._controls = {dig = true, LMB = true, place = false, RMB = false}
		local pstate = player_api.controls.player_states[player:get_player_name()]
		pstate.eat_until = 0

		for _, cb in ipairs(core._on_item_eat) do
			cb(0, nil, fake_apple_stack, player, nil)
		end
		-- In Luanti food consumption triggers eat animation
		assert.is_true(pstate.eat_until > 0)
	end)

	it("synchronizes liquid drop velocity when moving with drink", function()
		player:set_look_horizontal(0)
		player:set_velocity({x = 0, y = 0, z = 4.0})

		local id = player_api.spawn_eat_particles(player, "potions:water", 0.25, "liquid_drops")
		local spawner = core._particlespawners[id]
		assert.is_not_nil(spawner)
		assert.equal(player, spawner.attached)
		assert.is_true(spawner.vel.min.z >= 3.8)
		assert.is_true(spawner.vel.min.y <= -1.0)
	end)

	it("spawns chewing particle bursts during continuous LMB hold on food in controls loop", function()
		core.registered_items["food:cookie"] = {
			type = "craftitem",
			inventory_image = "food_cookie.png",
			groups = {food = 1},
		}
		player:set_wielded_item("food:cookie", 1)
		player_api.clear_item_cache()
		player._controls = {dig = true, LMB = true, place = false, RMB = false}
		local pstate = player_api.controls.player_states[player:get_player_name()]
		pstate.eat_until = 0
		pstate.last_chew_particle_time = 0
		pstate.wield_name = nil
		pstate.item_info = nil
		pstate.wielded_item = nil

		core._particlespawners = {}
		player_api.controls.update_player_controls(player, 0.1)
		player_api.get_player_state(player)

		local count = 0
		for _ in pairs(core._particlespawners) do
			count = count + 1
		end
		assert.is_true(count > 0)
		assert.is_true(pstate.last_chew_particle_time > 0)
	end)

	it("recognizes Luanti game food and drink groups in is_consumable", function()
		core.registered_items["default:apple"] = {
			type = "craftitem",
			groups = {food_apple = 1, eatable = 2},
		}
		core.registered_items["farming:bread"] = {
			type = "craftitem",
			groups = {food_bread = 1},
		}
		core.registered_items["farming:juice"] = {
			type = "craftitem",
			groups = {drink_juice = 1},
		}
		core.registered_items["default:pick_steel"] = {
			type = "tool",
			groups = {pickaxe = 1},
		}
		assert.is_true(player_api.is_consumable("default:apple"))
		assert.is_true(player_api.is_consumable("farming:bread"))
		assert.is_true(player_api.is_consumable("farming:juice"))
		assert.is_false(player_api.is_consumable("default:pick_steel"))
	end)

	it("recognizes items configured with engine item_eat closures", function()
		local eat_fn = core.item_eat(4)
		core.registered_items["test_mod:custom_ration"] = {
			type = "craftitem",
			on_use = eat_fn,
		}
		assert.is_true(player_api.is_consumable("test_mod:custom_ration"))
	end)

	it("preserves item technical name and spawns crumbs when eating the last item in a stack", function()
		core.registered_items["farming:cookie"] = {
			type = "craftitem",
			inventory_image = "farming_cookie.png",
			groups = {food = 1},
		}
		core._particlespawners = {}
		player:set_wielded_item("farming:cookie", 1)
		local stack = ItemStack("farming:cookie 1")

		player._controls = {dig = true, LMB = true, place = false, RMB = false}
		core.do_item_eat(2, nil, stack, player, nil)

		assert.is_true(stack:is_empty())
		local spawner_found = false
		for _, spawner in pairs(core._particlespawners) do
			if spawner.texture and spawner.texture:find("farming_cookie%.png") then
				spawner_found = true
				break
			end
		end
		assert.is_true(spawner_found)
	end)

	it("extends eating duration without restarting action playback when already eating", function()
		local play_action_calls = 0
		local orig_play = player_api.play_action
		player_api.play_action = function(p, act, force)
			if act == "eat" and force == true then
				play_action_calls = play_action_calls + 1
			end
			return orig_play(p, act, force)
		end

		local pstate = player_api.controls.player_states[player:get_player_name()]
		pstate.eat_until = 0
		pstate.eat_action = nil

		player_api.trigger_eat(player, 1.34, "farming:bread")
		local first_eat_until = pstate.eat_until
		assert.equal(1, play_action_calls)

		-- Repeat trigger while still eating
		player_api.trigger_eat(player, 1.34, "farming:bread")
		assert.equal(1, play_action_calls)
		assert.is_true(pstate.eat_until >= first_eat_until)

		player_api.play_action = orig_play
	end)

	it("verifies crumb particles have sufficient lifetime and gravity to reach ground", function()
		local id = player_api.spawn_eat_particles(player, "default:apple", 0.25)
		local spawner = core._particlespawners[id]
		assert.is_not_nil(spawner)
		assert.is_true(spawner.exptime.min >= 0.85)
		assert.is_true(spawner.exptime.max >= 1.45)
		assert.equal(-9.81, spawner.acc.min.y)
	end)

	it("sustains eating cycle for 1.34s completion when clicking LMB on food", function()
		core.registered_items["default:apple"] = {
			type = "craftitem",
			groups = {food_apple = 1},
		}
		player:set_wielded_item("default:apple", 1)
		player_api.clear_item_cache()
		player._controls = {dig = true, LMB = true, place = false, RMB = false}

		local pstate = player_api.controls.player_states[player:get_player_name()]
		pstate.eat_until = 0

		player_api.controls.update_player_controls(player, 0.1)
		local state = player_api.get_player_state(player)

		local time_now = core.get_us_time() * 0.000001
		assert.is_true(state.eating)
		assert.is_true(pstate.eat_until >= time_now + 1.2)
	end)

	it("immediately cancels eating animation and switches to attack when pressing LMB with weapon", function()
		core.registered_items["default:apple"] = {type = "craftitem", groups = {food = 1}}
		core.registered_items["default:sword_steel"] = {type = "tool", groups = {sword = 1}}
		player:set_wielded_item("default:apple", 1)
		player_api.clear_item_cache()
		player_api.trigger_eat(player, 1.34, "default:apple")

		local pstate = player_api.controls.player_states[player:get_player_name()]
		assert.is_true(pstate.eat_until > 0)

		-- Switch to sword and press LMB to attack
		player:set_wielded_item("default:sword_steel", 1)
		player_api.clear_item_cache()
		player._controls = {LMB = true, dig = true, RMB = false, place = false}

		player_api.controls.update_player_controls(player, 0.05)
		local state = player_api.get_player_state(player)

		assert.equal("attack_slash", state.action)
		assert.is_false(state.eating)
		assert.equal(0, pstate.eat_until)
	end)

	it("immediately cancels eating animation and switches to mine when pressing LMB with tool or bare hands", function()
		core.registered_items["default:apple"] = {type = "craftitem", groups = {food = 1}}
		core.registered_items["default:pick_steel"] = {type = "tool", groups = {pickaxe = 1}}
		player:set_wielded_item("default:apple", 1)
		player_api.clear_item_cache()
		player_api.trigger_eat(player, 1.34, "default:apple")

		local pstate = player_api.controls.player_states[player:get_player_name()]
		assert.is_true(pstate.eat_until > 0)

		-- Switch to pickaxe and press LMB to mine
		player:set_wielded_item("default:pick_steel", 1)
		player_api.clear_item_cache()
		player._controls = {LMB = true, dig = true, RMB = false, place = false}

		player_api.controls.update_player_controls(player, 0.05)
		local state = player_api.get_player_state(player)

		assert.equal("mine", state.action)
		assert.is_false(state.eating)
		assert.equal(0, pstate.eat_until)
	end)

	it("immediately cancels eating and enters bow_aim when aiming a bow", function()
		core.registered_items["default:apple"] = {type = "craftitem", groups = {food = 1}}
		core.registered_items["default:bow"] = {type = "tool", groups = {bow = 1}}
		player:set_wielded_item("default:apple", 1)
		player_api.clear_item_cache()
		player_api.trigger_eat(player, 1.34, "default:apple")

		local pstate = player_api.controls.player_states[player:get_player_name()]
		assert.is_true(pstate.eat_until > 0)

		-- Hold RMB with bow
		player:set_wielded_item("default:bow", 1)
		player_api.clear_item_cache()
		player._controls = {LMB = false, dig = false, RMB = true, place = true}

		player_api.controls.update_player_controls(player, 0.05)
		local state = player_api.get_player_state(player)

		assert.equal("bow_aim", state.action)
		assert.is_true(state.aiming_bow)
		assert.is_false(state.eating)
		assert.equal(0, pstate.eat_until)
	end)

	it("immediately cancels eating and enters bow_shoot when shooting a bow", function()
		core.registered_items["default:apple"] = {type = "craftitem", groups = {food = 1}}
		core.registered_items["default:bow"] = {type = "tool", groups = {bow = 1}}
		player:set_wielded_item("default:bow", 1)
		player_api.clear_item_cache()
		player_api.trigger_eat(player, 1.34, "default:apple")

		local pstate = player_api.controls.player_states[player:get_player_name()]
		local time_now = core.get_us_time() * 0.000001
		pstate.bow_shoot_until = time_now + 0.35
		player._controls = {LMB = false, dig = false, RMB = false, place = false}

		local state = player_api.get_player_state(player)

		assert.equal("bow_shoot", state.action)
		assert.is_true(state.shooting_bow)
		assert.is_false(state.eating)
		assert.equal(0, pstate.eat_until)
	end)

	it("immediately cancels eating and enters block when blocking with shield", function()
		core.registered_items["default:apple"] = {type = "craftitem", groups = {food = 1}}
		core.registered_items["default:shield_wood"] = {type = "tool", groups = {shield = 1}}
		player:set_wielded_item("default:apple", 1)
		player_api.clear_item_cache()
		player_api.trigger_eat(player, 1.34, "default:apple")

		local pstate = player_api.controls.player_states[player:get_player_name()]
		assert.is_true(pstate.eat_until > 0)

		-- Hold RMB with shield
		player:set_wielded_item("default:shield_wood", 1)
		player_api.clear_item_cache()
		player._controls = {LMB = false, dig = false, RMB = true, place = true}

		player_api.controls.update_player_controls(player, 0.05)
		local state = player_api.get_player_state(player)

		assert.equal("block", state.action)
		assert.is_true(state.blocking)
		assert.is_false(state.eating)
		assert.equal(0, pstate.eat_until)
	end)

	it("resets eating state and stops action track cleanly via cancel_eat", function()
		core.registered_items["default:apple"] = {type = "craftitem", groups = {food = 1}}
		player:set_wielded_item("default:apple", 1)
		player_api.clear_item_cache()
		player_api.trigger_eat(player, 1.34, "default:apple")

		local pstate = player_api.controls.player_states[player:get_player_name()]
		assert.is_true(pstate.eat_until > 0)

		local was_eating = player_api.cancel_eat(player)
		assert.is_true(was_eating)

		local state = player_api.get_player_state(player)
		assert.is_false(state.eating)
		assert.is_nil(state.action)
		assert.equal(0, pstate.eat_until)

		-- Repeated cancel returns false when not eating
		assert.is_false(player_api.cancel_eat(player))
	end)
end)
