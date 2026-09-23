-- Specs for Dual-Model Visual Proxies, Observer Filtering, and Bone Override Throttling

local mock_env = require("tests.mock_env")

describe("Visual Proxies & Observer Cohorts", function()
	local player

	before_each(function()
		player = mock_env.join_player("ProxyTester")
	end)

	after_each(function()
		mock_env.leave_player(player)
	end)

	it("creates dual visual proxy entities attached to joining player", function()
		local proxies = x_player_api.get_visual_proxies(player)
		assert.is_not_nil(proxies, "Proxies table must exist for player")
		assert.is_not_nil(proxies.glb, "GLB proxy entity must exist")
		assert.is_not_nil(proxies.b3d, "B3D proxy entity must exist")

		local parent_glb, _, _, _ = proxies.glb:get_attach()
		assert.equal(player, parent_glb, "GLB proxy must be attached to player")

		local parent_b3d, _, _, _ = proxies.b3d:get_attach()
		assert.equal(player, parent_b3d, "B3D proxy must be attached to player")
	end)

	it("classifies protocol version 5.17.0+ as modern cohort and older as legacy cohort", function()
		local name = player:get_player_name()
		assert.is_true(x_player_api.is_modern_client(name))
		assert.is_true(x_player_api.get_modern_observers()[name])
		assert.is_nil(x_player_api.get_legacy_observers()[name])

		-- Simulate legacy client joining
		local old_get_info = core.get_player_information
		core.get_player_information = function()
			return { protocol_version = 43 } -- Less than 5.17.0 (44)
		end

		local legacy_player = mock_env.join_player("LegacyHero")
		local legacy_name = legacy_player:get_player_name()

		assert.is_false(x_player_api.is_modern_client(legacy_name))
		assert.is_nil(x_player_api.get_modern_observers()[legacy_name])
		assert.is_true(x_player_api.get_legacy_observers()[legacy_name])

		-- Clean up legacy client
		mock_env.leave_player(legacy_player)
		core.get_player_information = old_get_info
	end)

	it("refreshes observer visibility sets on proxy entities", function()
		local proxies = x_player_api.get_visual_proxies(player)
		x_player_api.refresh_observers()

		assert.equal(x_player_api.get_modern_observers(), proxies.glb._observers)
		assert.equal(x_player_api.get_legacy_observers(), proxies.b3d._observers)
	end)

	it("throttles Head bone rotation delta under 0.08 radians", function()
		local proxies = x_player_api.get_visual_proxies(player)
		local initial_pos = {x = 0, y = 0, z = 0}
		local initial_rot = {x = 0.5, y = 0, z = 0}

		-- Initial override should apply
		x_player_api.set_bone_override(player, "Head", initial_pos, initial_rot)
		local ov1 = proxies.glb:get_bone_override("Head")
		assert.is_not_nil(ov1)
		assert.near(0.5, ov1.rotation.vec.x, 1e-4)

		-- Small pitch delta (0.04 < 0.08): should be throttled (skipped)
		local small_rot = {x = 0.54, y = 0, z = 0}
		x_player_api.set_bone_override(player, "Head", initial_pos, small_rot)
		local ov2 = proxies.glb:get_bone_override("Head")
		assert.near(0.5, ov2.rotation.vec.x, 1e-4, "Head bone should retain previous rotation when throttled")

		-- Large pitch delta (0.15 >= 0.08): should be dispatched
		local large_rot = {x = 0.65, y = 0, z = 0}
		x_player_api.set_bone_override(player, "Head", initial_pos, large_rot)
		local ov3 = proxies.glb:get_bone_override("Head")
		assert.near(0.65, ov3.rotation.vec.x, 1e-4, "Head bone should update when delta exceeds throttle threshold")

		-- Verify dispatch to both glb and b3d proxies
		local ov_b3d = proxies.b3d:get_bone_override("Head")
		assert.is_not_nil(ov_b3d)
		assert.near(0.65, ov_b3d.rotation.vec.x, 1e-4, "B3D proxy must also receive bone override")
	end)

	it("mutates bone cache in-place and safely handles nil position or rotation", function()
		local name = player:get_player_name()
		x_player_api.set_bone_override(player, "Arm_Right", {x = 1, y = 2, z = 3}, {x = 0, y = 0, z = 0})
		local cache = x_player_api.bone_caches[name]["Arm_Right"]
		assert.is_not_nil(cache)
		local orig_pos_tbl = cache.position
		local orig_rot_tbl = cache.rotation

		-- Update with new values
		x_player_api.set_bone_override(player, "Arm_Right", {x = 4, y = 5, z = 6}, {x = 1, y = 1, z = 1})
		-- Must mutate in-place (same table references, zero-GC)
		assert.equal(orig_pos_tbl, cache.position)
		assert.equal(orig_rot_tbl, cache.rotation)
		assert.equal(4, cache.position.x)

		-- Graceful nil handling
		x_player_api.set_bone_override(player, "Arm_Right", nil, {x = 0.5, y = 0, z = 0})
		assert.equal(0, cache.position.x)
		assert.equal(0.5, cache.rotation.x)
	end)

	it("cleans up visual proxies and bone cache on player leave", function()
		local name = player:get_player_name()
		local proxies = x_player_api.get_visual_proxies(player)

		assert.is_not_nil(proxies)
		assert.is_false(proxies.glb._removed)
		assert.is_false(proxies.b3d._removed)

		mock_env.leave_player(player)

		assert.is_nil(x_player_api.get_visual_proxies(player))
		assert.is_nil(x_player_api.active_proxies[name])
		assert.is_nil(x_player_api.bone_caches[name])
		assert.is_true(proxies.glb._removed)
		assert.is_true(proxies.b3d._removed)
	end)

	it("handles missing core.protocol_versions gracefully on player join", function()
		local old_map = core.protocol_versions
		core.protocol_versions = nil

		local test_player = mock_env.join_player("FallbackProtocolHero")
		local test_name = test_player:get_player_name()

		assert.is_not_nil(x_player_api.get_visual_proxies(test_player))
		assert.is_true(x_player_api.is_modern_client(test_name))

		mock_env.leave_player(test_player)
		core.protocol_versions = old_map
	end)

	it("preserves hidden native visual and validates proxies on player respawn", function()
		local proxies = x_player_api.get_visual_proxies(player)
		assert.is_not_nil(proxies)

		-- Simulate engine/external mod resetting properties on death/respawn
		player:set_properties({visual_size = {x = 1, y = 1}, textures = {"character.png"}})

		-- Trigger respawn callbacks
		for _, cb in ipairs(core._on_respawnplayers) do
			cb(player)
		end

		local props = player:get_properties()
		assert.equal(1, props.visual_size.x, "Native player mesh must maintain unit scale on respawn for child attachments")
		assert.equal(1, props.visual_size.y)
		assert.is_true(props.use_texture_alpha)
		assert.equal("blank.png", props.textures[1])
	end)


	it("routes player:set_bone_override calls to visual proxies", function()
		local proxies = x_player_api.get_visual_proxies(player)
		local override = {
			position = {vec = {x = 0, y = 1.5, z = 0}, absolute = true},
			rotation = {vec = {x = 0.45, y = 0.2, z = 0}, absolute = true},
		}

		player:set_bone_override("Head", override)

		local ov_glb = proxies.glb:get_bone_override("Head")
		local ov_b3d = proxies.b3d:get_bone_override("Head")
		assert.is_not_nil(ov_glb, "GLB proxy must receive bone override")
		assert.is_not_nil(ov_b3d, "B3D proxy must receive bone override")
		assert.near(0.45, ov_glb.rotation.vec.x, 1e-4)
		assert.near(0.45, ov_b3d.rotation.vec.x, 1e-4)
	end)

	it("synchronizes skeletal animation on player ObjectRef in set_animation", function()
		player_api.set_model(player, "character.b3d")
		player_api.set_animation(player, "walk")
		assert.is_not_nil(player._last_animation, "player:set_animation must be called on player ObjectRef")
		assert.is_not_nil(player._last_animation.anim.x)
		assert.is_not_nil(player._last_animation.anim.y)
	end)

	it("auto-heals and recreates visual proxies when an entity ObjectRef becomes invalid", function()
		local proxies = x_player_api.get_visual_proxies(player)
		assert.is_not_nil(proxies)
		local old_glb = proxies.glb

		-- Simulate entity removal (e.g. chunk unload, deactivation, or clear_objects)
		old_glb:remove()
		assert.is_false(old_glb:is_valid())

		-- Calling get_visual_proxies should detect invalid entity and re-spawn
		local new_proxies = x_player_api.get_visual_proxies(player)
		assert.is_not_nil(new_proxies)
		assert.is_not_nil(new_proxies.glb)
		assert.is_true(new_proxies.glb:is_valid())
		assert.is_true(new_proxies.glb ~= old_glb, "Must allocate fresh proxy entity")
	end)

	it("configures visual proxy entities with immortal armor groups", function()
		local proxies = x_player_api.get_visual_proxies(player)
		assert.is_not_nil(proxies)
		assert.is_not_nil(proxies.glb._armor_groups)
		assert.equal(1, proxies.glb._armor_groups.immortal)
		assert.is_not_nil(proxies.b3d._armor_groups)
		assert.equal(1, proxies.b3d._armor_groups.immortal)
	end)

	it("intercepts player:set_properties to protect hidden native mesh and routes to proxies", function()
		local proxies = x_player_api.get_visual_proxies(player)
		assert.is_not_nil(proxies)

		-- External mod attempts to set visible properties on player
		player:set_properties({
			visual = "upright_sprite",
			visual_size = {x = 1, y = 1},
			textures = {"custom_skin.png"}
		})

		-- Native player must remain hidden 3D mesh with unit scale to preserve child attachment scale
		local player_props = player:get_properties()
		assert.equal("mesh", player_props.visual)
		assert.equal("character.b3d", player_props.mesh)
		assert.equal(1, player_props.visual_size.x)
		assert.equal(1, player_props.visual_size.y)
		assert.is_true(player_props.use_texture_alpha)
		assert.equal("blank.png", player_props.textures[1])

		-- Proxies must receive forwarded custom textures and visual size
		local glb_props = proxies.glb:get_properties()
		local b3d_props = proxies.b3d:get_properties()
		assert.equal("custom_skin.png", glb_props.textures[1])
		assert.equal("custom_skin.png", b3d_props.textures[1])
		assert.equal(1, glb_props.visual_size.x)
		assert.equal(1, b3d_props.visual_size.x)
	end)

	it("forwards is_visible to visual proxies and self-heals in set_model", function()
		local proxies = x_player_api.get_visual_proxies(player)
		assert.is_not_nil(proxies)

		-- Hide player via player:set_properties
		player:set_properties({ is_visible = false })
		assert.is_false(proxies.glb:get_properties().is_visible)
		assert.is_false(proxies.b3d:get_properties().is_visible)

		-- Show player via player:set_properties
		player:set_properties({ is_visible = true })
		assert.is_true(proxies.glb:get_properties().is_visible)
		assert.is_true(proxies.b3d:get_properties().is_visible)

		-- Simulate external mod directly setting is_visible = false on active proxy
		proxies.glb:set_properties({ is_visible = false })
		assert.is_false(proxies.glb:get_properties().is_visible)

		-- set_model with current model must trigger self-healing and restore is_visible = true
		x_player_api.set_model(player, x_player_api.get_model_name(player))
		assert.is_true(proxies.glb:get_properties().is_visible)
	end)

	it("does not overwrite proxy textures when player:set_properties is passed blank textures", function()
		local proxies = x_player_api.get_visual_proxies(player)
		assert.is_not_nil(proxies)

		-- First set custom textures on proxies
		player:set_properties({
			textures = {"warrior_skin.png"}
		})
		assert.equal("warrior_skin.png", proxies.glb:get_properties().textures[1])

		-- Now pass blank textures to player
		player:set_properties({
			textures = {"blank.png", "blank.png"}
		})

		-- Proxies must preserve warrior_skin.png and not be overwritten with blank.png
		assert.equal("warrior_skin.png", proxies.glb:get_properties().textures[1])
		assert.equal("warrior_skin.png", proxies.b3d:get_properties().textures[1])
	end)

	it("pads missing texture slots up to model specification in set_textures and proxies", function()
		x_player_api.register_model("test_multi_mat.b3d", {
			mesh = "test_multi_mat.b3d",
			textures = {"default_char.png", "default_armor.png", "blank.png"},
		})
		x_player_api.set_model(player, "test_multi_mat.b3d")

		local proxies = x_player_api.get_visual_proxies(player)
		assert.is_not_nil(proxies)

		-- Call set_textures with only 1 texture
		x_player_api.set_textures(player, {"only_skin.png"})

		local textures = x_player_api.get_textures(player)
		assert.equal(3, #textures)
		assert.equal("only_skin.png", textures[1])
		assert.equal("default_armor.png", textures[2])
		assert.equal("blank.png", textures[3])

		-- Call player:set_properties with only 1 texture
		player:set_properties({
			textures = {"second_skin.png"}
		})
		local b3d_props = proxies.b3d:get_properties()
		assert.equal(3, #b3d_props.textures)
		assert.equal("second_skin.png", b3d_props.textures[1])
		assert.equal("default_armor.png", b3d_props.textures[2])
		assert.equal("blank.png", b3d_props.textures[3])
	end)

	it("exhaustively detaches and cleans up engine child attachments on leave", function()
		local test_player = mock_env.join_player("ChildSweepUser")
		local proxies = x_player_api.get_visual_proxies(test_player)
		assert.is_not_nil(proxies)

		-- Simulate an extra untracked proxy child attached directly in engine
		local orphan = core.add_entity(test_player:get_pos(), "x_player_api:visual_glb")
		orphan:set_attach(test_player, "", {x=0, y=0, z=0}, {x=0, y=0, z=0})

		-- Verify child is in get_children()
		local children = test_player:get_children()
		assert.is_true(#children >= 3)

		mock_env.leave_player(test_player)

		assert.is_true(proxies.glb._removed)
		assert.is_true(proxies.b3d._removed)
		assert.is_true(orphan._removed)
		assert.is_nil(proxies.glb:get_attach())
		assert.is_nil(proxies.b3d:get_attach())
		assert.is_nil(orphan:get_attach())
	end)

	it("sweeps orphaned proxies for disconnected players via cleanup_orphaned_proxies", function()
		x_player_api.cleanup_orphaned_proxies()
		local test_player = mock_env.join_player("GhostPlayer")
		local proxies = x_player_api.get_visual_proxies(test_player)
		local name = test_player:get_player_name()

		assert.is_not_nil(proxies)
		-- Simulate disconnected player without proper leave hook firing
		for i = #core._connected_players, 1, -1 do
			if core._connected_players[i] == test_player then
				table.remove(core._connected_players, i)
			end
		end

		assert.is_nil(core.get_player_by_name(name))
		assert.is_not_nil(x_player_api.active_proxies[name])

		local cleaned = x_player_api.cleanup_orphaned_proxies()
		assert.equal(2, cleaned)
		assert.is_nil(x_player_api.active_proxies[name])
		assert.is_true(proxies.glb._removed)
		assert.is_true(proxies.b3d._removed)
	end)

	it("cleans up all active proxies on server shutdown", function()
		local test_player = mock_env.join_player("ShutdownTester")
		local proxies = x_player_api.get_visual_proxies(test_player)
		local name = test_player:get_player_name()

		assert.is_not_nil(x_player_api.active_proxies[name])

		for _, fn in ipairs(core._on_shutdown or {}) do
			fn()
		end

		assert.is_nil(x_player_api.active_proxies[name])
		assert.is_true(proxies.glb._removed)
		assert.is_true(proxies.b3d._removed)

		mock_env.leave_player(test_player)
	end)
end)

