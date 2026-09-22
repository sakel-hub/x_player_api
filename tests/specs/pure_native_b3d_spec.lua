-- Specs for Pure Native B3D Rendering & Connected Players Optimization
-- Tests bypassing visual proxies in B3D mode for zero camera jitter on legacy clients,
-- as well as local connected_players maintenance.

local mock_env = require("tests.mock_env")

describe("Pure Native B3D Mode & Connected Players Subsystem", function()
	local player

	before_each(function()
		player = mock_env.join_player("PureB3DTester")
		core.registered_nodes["default:dirt"] = {walkable = true}
		core.get_node_or_nil = function() return {name = "default:dirt"} end
		player._pos = {x = 0, y = 0.5, z = 0}
		player.get_velocity = function() return {x = 0, y = 0, z = 0} end
	end)

	after_each(function()
		player_api.set_pure_native_b3d(false)
		player_api.set_model_format("glb")
	end)

	it("maintains connected_players array on player join and leave", function()
		local cp = x_player_api.connected_players
		assert.is_not_nil(cp)

		local found = false
		for i = 1, #cp do
			if cp[i] == player then
				found = true
				break
			end
		end
		assert.is_true(found, "joined player must be present in connected_players")

		-- Test leave
		mock_env.leave_player(player)
		found = false
		for i = 1, #cp do
			if cp[i] == player then
				found = true
				break
			end
		end
		assert.is_false(found, "leaving player must be removed from connected_players")
	end)

	it("enables pure native B3D mode and assigns mesh/textures directly to player", function()
		player_api.set_model_format("b3d")
		player_api.set_pure_native_b3d(true)
		assert.is_true(x_player_api.is_pure_native_b3d_active(player))

		player_api.set_model(player, "character.b3d")
		local props = player:get_properties()
		assert.equal("mesh", props.visual)
		assert.equal("character.b3d", props.mesh)
		assert.is_false(props.use_texture_alpha)
		assert.equal("character.png", props.textures[1])

		-- Visual proxies should be scaled down to 0
		local proxies = x_player_api.get_visual_proxies(player)
		assert.is_not_nil(proxies)
		if proxies.glb and proxies.glb:is_valid() then
			local glb_props = proxies.glb:get_properties()
			assert.equal(0, glb_props.visual_size.x)
			assert.equal(0, glb_props.visual_size.y)
		end
		if proxies.b3d and proxies.b3d:is_valid() then
			local b3d_props = proxies.b3d:get_properties()
			assert.equal(0, b3d_props.visual_size.x)
			assert.equal(0, b3d_props.visual_size.y)
		end
	end)

	it("configures local animation prediction for standard ranges and silences for extended animations", function()
		player_api.set_model_format("b3d")
		player_api.set_pure_native_b3d(true)
		player_api.set_model(player, "character.b3d")

		-- Native player local animations should be set to standard ranges (stand, walk, mine, walk_mine)
		assert.is_not_nil(player._local_animation_calls)
		local last_local = player._local_animation_calls[#player._local_animation_calls]
		assert.is_not_nil(last_local)
		local stand, walk, mine, walk_mine, speed = last_local[1], last_local[2], last_local[3], last_local[4], last_local[5]
		assert.equal(30, speed)
		assert.equal(1, stand.x)
		assert.equal(79, stand.y)
		assert.equal(168, walk.x)
		assert.equal(187, walk.y)
		assert.equal(190, mine.x)
		assert.equal(200, mine.y)
		assert.equal(201, walk_mine.x)
		assert.equal(220, walk_mine.y)

		-- Trigger extended non-standard action (e.g. attack_slash)
		core.registered_items["default:sword_steel"] = {description = "Steel Sword", groups = {sword = 1}}
		player:set_wielded_item("default:sword_steel")
		player.get_player_control = function() return {LMB = true} end
		player.get_velocity = function() return {x = 0, y = 0, z = 0} end

		player_api.globalstep(0.05)

		-- When extended animation (attack_slash: 405..415) plays, local animation must be silenced
		-- to allow server animation to take precedence on client without local prediction fighting it
		local silenced_call = player._local_animation_calls[#player._local_animation_calls]
		assert.equal(0, silenced_call[5])
		assert.equal(0, silenced_call[1].x)
		assert.equal(0, silenced_call[1].y)
		assert.is_not_nil(player._last_animation)
		assert.equal(405, player._last_animation.anim.x)
		assert.equal(415, player._last_animation.anim.y)

		-- Return to stationary without controls: stand locomotion restored
		player.get_player_control = function() return {} end
		local pstate = player_api.controls.player_states[player:get_player_name()]
		pstate.lmb_action_until = 0

		player_api.globalstep(0.05)

		-- Standard local animations restored
		local restored_call = player._local_animation_calls[#player._local_animation_calls]
		assert.equal(30, restored_call[5])
		assert.equal(1, restored_call[1].x)
		assert.equal(79, restored_call[1].y)
	end)

	it("attaches 3D wield items directly to player ObjectRef in pure native B3D mode", function()
		player_api.set_model_format("b3d")
		player_api.set_pure_native_b3d(true)
		player_api.set_model(player, "character.b3d")

		core.registered_items["default:sword_steel"] = {description = "Steel Sword", groups = {sword = 1}}
		player:set_wielded_item("default:sword_steel")

		player_api.globalstep(0.25)

		local wield_data = x_player_api.wield_entities[player:get_player_name()]
		assert.is_not_nil(wield_data)
		assert.is_not_nil(wield_data.obj)
		assert.equal(player, wield_data.obj:get_attach(),
			"wield item must be attached directly to player in pure native B3D mode")
	end)

	it("applies bone overrides directly to player ObjectRef in pure native B3D mode", function()
		player_api.set_model_format("b3d")
		player_api.set_pure_native_b3d(true)
		player_api.set_model(player, "character.b3d")

		local override_called = false
		local target_bone = nil
		player.set_bone_override = function(_, bone)
			override_called = true
			target_bone = bone
		end

		player_api.set_bone_override(player, "Head", {x = 0, y = 0, z = 0}, {x = 0.5, y = 0, z = 0})
		assert.is_true(override_called)
		assert.equal("Head", target_bone)
	end)

	it("updates textures directly on player ObjectRef in pure native B3D mode", function()
		player_api.set_model_format("b3d")
		player_api.set_pure_native_b3d(true)
		player_api.set_model(player, "character.b3d")

		player_api.set_textures(player, {"custom_skin.png"})
		local props = player:get_properties()
		assert.equal("custom_skin.png", props.textures[1])
	end)
end)
