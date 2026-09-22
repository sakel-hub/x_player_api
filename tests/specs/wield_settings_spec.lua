-- Specs for 3D Wield Item Enable/Disable Setting

local mock_env = require("tests.mock_env")

describe("Wield Item Feature Settings", function()
	local player

	before_each(function()
		player = mock_env.join_player("SettingsPlayer")
		player_api.set_wield_item_enabled(true)
	end)

	after_each(function()
		player_api.remove_wield_item(player)
		player_api.set_wield_item_enabled(true)
	end)

	it("is enabled by default", function()
		assert.is_true(player_api.enable_wield_item)
	end)

	it("disables 3D wield items and cleans up active entities", function()
		player_api.attach_wield_item(player)
		assert.is_not_nil(player_api.get_wield_entity(player))

		player_api.set_wield_item_enabled(false)
		assert.is_false(player_api.enable_wield_item)
		assert.is_nil(player_api.get_wield_entity(player))
	end)

	it("makes attachment and update operations no-ops while disabled", function()
		player_api.set_wield_item_enabled(false)

		local res = player_api.attach_wield_item(player)
		assert.is_nil(res)

		player_api.update_wield_item(player, true)
		assert.is_nil(player_api.get_wield_entity(player))
	end)

	it("reattaches entities to connected players when re-enabled", function()
		player_api.set_wield_item_enabled(false)
		assert.is_nil(player_api.get_wield_entity(player))

		player_api.set_wield_item_enabled(true)
		assert.is_true(player_api.enable_wield_item)
		assert.is_not_nil(player_api.get_wield_entity(player))
	end)

	it("hides wield entity when switching to sprite and restores on mesh", function()
		player:set_wielded_item("default:sword_steel")
		player_api.attach_wield_item(player)
		local entity = player_api.get_wield_entity(player)
		assert.is_not_nil(entity)
		local props = entity:get_properties()
		assert.is_true(props.is_visible)

		-- Switch to non-existent model (triggers upright_sprite)
		player_api.set_model(player, "missing_model")
		props = entity:get_properties()
		assert.is_false(props.is_visible)

		-- Switch back to registered mesh
		player_api.set_model(player, "character.b3d")
		props = entity:get_properties()
		assert.is_true(props.is_visible)
	end)

	it("auto-reattaches entity if detached or missing during update_wield_item", function()
		player_api.attach_wield_item(player)
		local name = player:get_player_name()
		local data = player_api.wield_entities[name]
		assert.is_not_nil(data.obj)

		-- Simulate entity detachment
		data.obj:set_detach()
		player_api.update_wield_item(player, false)

		-- Should have been re-attached
		local active = player_api.get_wield_entity(player)
		assert.is_not_nil(active)
		local proxies = x_player_api.get_visual_proxies(player)
		local expected_parent = (proxies and proxies.glb) or player
		local parent = active:get_attach()
		assert.equal(expected_parent, parent)
	end)

	it("instantly updates wield item on item switch without waiting for throttle timer", function()
		player:set_wielded_item("default:pick_steel")
		player_api.attach_wield_item(player)
		local name = player:get_player_name()
		local data = player_api.wield_entities[name]
		assert.is_not_nil(data)

		-- Update to match current wield
		player_api.update_wield_item(player, false)
		assert.equal("default:pick_steel", data.item)
		data.last_wield_name = "default:pick_steel"

		-- Now switch item to a sword
		player:set_wielded_item("default:sword_steel")

		-- Run all globalsteps with a tiny dtime of 0.01s (far below WIELD_UPDATE_INTERVAL = 0.2s)
		for _, step_fn in ipairs(core._globalsteps) do
			step_fn(0.01)
		end

		-- Wield item should have updated immediately!
		assert.equal("default:sword_steel", data.item)
	end)

	it("preserves user visibility preference across player death and respawn", function()
		player:set_wielded_item("default:sword_steel")
		player_api.attach_wield_item(player)
		player_api.set_wield_item_visibility(player, false)

		local name = player:get_player_name()
		local data = player_api.wield_entities[name]
		assert.is_not_nil(data)
		assert.is_false(data.visible)

		-- Simulate player death
		for _, fn in ipairs(core._on_dieplayers) do
			fn(player)
		end
		assert.is_false(data.visible)

		-- Simulate player respawn
		for _, fn in ipairs(core._on_respawnplayers) do
			fn(player)
		end
		assert.is_false(data.visible)
	end)

	it("caches bone attachment transform and avoids redundant set_attach calls", function()
		player:set_wielded_item("default:sword_steel")
		player_api.attach_wield_item(player)

		local name = player:get_player_name()
		local data = player_api.wield_entities[name]
		assert.is_not_nil(data)
		assert.is_not_nil(data.obj)

		local attach_calls = 0
		local orig_set_attach = data.obj.set_attach
		data.obj.set_attach = function(self, parent, bone, pos, rot, force)
			attach_calls = attach_calls + 1
			return orig_set_attach(self, parent, bone, pos, rot, force)
		end

		-- Forced update with identical item transform should NOT call set_attach
		player_api.update_wield_item(player, true)
		assert.equal(0, attach_calls)

		-- Switch item to node with different transform
		core.registered_items["default:wood"] = {type = "node"}
		player:set_wielded_item("default:wood")
		player_api.update_wield_item(player, false)
		assert.equal(1, attach_calls)

		-- Another update with same node should NOT call set_attach
		player_api.update_wield_item(player, true)
		assert.equal(1, attach_calls)
	end)

	it("safely handles deleted or invalid ObjectRef in attach_wield_item", function()
		player_api.attach_wield_item(player)
		local name = player:get_player_name()
		local data = player_api.wield_entities[name]
		assert.is_not_nil(data)

		-- Simulate entity being deleted/destroyed in C++ engine
		data.obj.get_luaentity = function() return nil end

		local new_obj = player_api.attach_wield_item(player)
		assert.is_not_nil(new_obj)
		assert.is_not_nil(new_obj:get_luaentity())
		assert.equal(new_obj, data.obj)
	end)

	it("memoizes attachment parameters in WIELD_PARAMS_CACHE", function()
		player_api.clear_wield_params_cache()
		core.registered_items["test_mod:static_tool"] = {type = "tool"}

		local _, pos1 = player_api.get_wield_attachment_params("test_mod:static_tool")
		assert.is_not_nil(pos1)

		-- Modify the base offset registry for tools
		local orig_x = player_api.wield_item_offsets.types.tool.pos.x
		player_api.wield_item_offsets.types.tool.pos.x = 999.0

		-- Calling again should return cached params with original x
		local _, pos2 = player_api.get_wield_attachment_params("test_mod:static_tool")
		assert.equal(pos1.x, pos2.x)

		-- After clearing cache, new calculation takes effect
		player_api.clear_wield_params_cache()
		local _, pos3 = player_api.get_wield_attachment_params("test_mod:static_tool")
		assert.equal(999.0, pos3.x)

		-- Restore
		player_api.wield_item_offsets.types.tool.pos.x = orig_x
		player_api.clear_wield_params_cache()
	end)

	it("safely handles deleted entities in get_wield_entity and set_wield_item_visibility", function()
		player_api.attach_wield_item(player)
		local entity = player_api.get_wield_entity(player)
		assert.is_not_nil(entity)

		-- Simulate engine entity removal
		entity:remove()
		assert.is_nil(entity:get_luaentity())

		-- Calling get_wield_entity returns nil instead of dead object
		assert.is_nil(player_api.get_wield_entity(player))

		-- Calling set_wield_item_visibility does not crash on deleted entity
		player_api.set_wield_item_visibility(player, false)
		assert.is_false(player_api.get_wield_item_visibility(player))
	end)
end)
