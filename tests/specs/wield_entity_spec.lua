-- Specs for 3D Wield Item Entity Management, Properties, and Player Lifecycle

local mock_env = require("tests.mock_env")

describe("Wield Item Entity Lifecycle & Properties", function()
	local player

	before_each(function()
		core._connected_players = {}
		player = mock_env.join_player("EntityTester")
	end)

	it("registers the ephemeral LuaEntity with non-physical properties", function()
		local ent_def = core.registered_entities["x_player_api:wield_item"]
		assert.is_not_nil(ent_def, "Entity 'x_player_api:wield_item' must be registered")
		assert.equal("wielditem", ent_def.initial_properties.visual)
		assert.equal(false, ent_def.initial_properties.static_save)
		assert.equal(false, ent_def.initial_properties.pointable)
		assert.equal(false, ent_def.initial_properties.physical)
		assert.equal(false, ent_def.initial_properties.collide_with_objects)
	end)

	it("sets immortal armor group upon activation", function()
		local ent_def = core.registered_entities["x_player_api:wield_item"]
		local obj = core.add_entity({x = 0, y = 0, z = 0}, "x_player_api:wield_item")
		assert.is_not_nil(obj)
		ent_def.on_activate(obj:get_luaentity())
		assert.equal({immortal = 1}, obj._armor_groups)
	end)

	it("removes self during step if unattached", function()
		local ent_def = core.registered_entities["x_player_api:wield_item"]
		local obj = core.add_entity({x = 0, y = 0, z = 0}, "x_player_api:wield_item")
		local luaent = obj:get_luaentity()
		luaent.timer = 0
		ent_def.on_step(luaent, 1.1)
		assert.is_true(obj._removed, "Unattached entity must remove self during on_step")
	end)

	it("manages join lifecycle with 0.5s attachment delay", function()
		local fresh_player = mock_env.create_player("JoinTester")
		table.insert(core._connected_players, fresh_player)
		core._after_timers = {}
		for _, join_cb in ipairs(core._on_joinplayers) do
			join_cb(fresh_player)
		end
		assert.equal(1, #core._after_timers)
		assert.equal(0.5, core._after_timers[1].delay)

		core._after_timers[1].fn()
		local active_ent = player_api.get_wield_entity(fresh_player)
		assert.is_not_nil(active_ent, "Wield entity should be attached after delay")
	end)

	it("performs delta checking so set_properties is only called on change", function()
		player:set_wielded_item("default:sword_steel", 1)
		player_api.update_wield_item(player, false)

		local obj = player_api.get_wield_entity(player)
		assert.is_not_nil(obj)
		local call_count = 0
		local orig_set_props = obj.set_properties
		obj.set_properties = function(self, props)
			call_count = call_count + 1
			orig_set_props(self, props)
		end

		player_api.update_wield_item(player, false)
		assert.equal(0, call_count, "set_properties must not be called when item is unchanged")

		player:set_wielded_item("default:stick", 1)
		player_api.update_wield_item(player, false)
		assert.equal(1, call_count, "set_properties must be called when item changed")
	end)

	it("hides entity when wielding empty hand", function()
		player:set_wielded_item("default:sword_steel", 1)
		player_api.update_wield_item(player, true)
		local obj = player_api.get_wield_entity(player)
		assert.is_not_nil(obj)

		player:set_wielded_item("", 0)
		player_api.update_wield_item(player, false)
		assert.equal(false, obj:get_properties().is_visible)
	end)

	it("handles death and respawn correctly", function()
		player:set_wielded_item("default:sword_steel", 1)
		player_api.update_wield_item(player, true)
		local obj = player_api.get_wield_entity(player)
		assert.is_not_nil(obj)
		assert.equal(true, obj:get_properties().is_visible)

		player:set_hp(0)
		for _, die_cb in ipairs(core._on_dieplayers) do
			die_cb(player)
		end
		assert.equal(false, obj:get_properties().is_visible)

		player:set_hp(20)
		core._after_timers = {}
		for _, respawn_cb in ipairs(core._on_respawnplayers) do
			respawn_cb(player)
		end
		for _, timer in ipairs(core._after_timers) do
			if timer.delay == 0.1 then
				timer.fn()
			end
		end
		local respawn_obj = player_api.get_wield_entity(player)
		assert.is_not_nil(respawn_obj)
		assert.equal(true, respawn_obj:get_properties().is_visible)
	end)

	it("removes entity cleanly on player leave", function()
		local obj = player_api.get_wield_entity(player)
		assert.is_not_nil(obj)

		for _, leave_cb in ipairs(core._on_leaveplayers) do
			leave_cb(player)
		end
		assert.is_nil(player_api.get_wield_entity(player))
		assert.is_true(obj._removed, "Entity must be removed from engine on player leave")
	end)

	it("attaches dual wield entities directly to visual proxy entities with format-appropriate transforms", function()
		local proxies = x_player_api.get_visual_proxies(player)
		assert.is_not_nil(proxies)
		assert.is_not_nil(proxies.glb)
		assert.is_not_nil(proxies.b3d)

		player:set_wielded_item("default:sword_steel", 1)
		player_api.update_wield_item(player, true)

		local name = player:get_player_name()
		local data = player_api.wield_entities[name]
		assert.is_not_nil(data)
		assert.is_not_nil(data.glb, "GLB proxy wield entity must exist")
		assert.is_not_nil(data.b3d, "B3D proxy wield entity must exist")

		local parent_glb, bone_glb, _, rot_glb = data.glb:get_attach()
		assert.equal(proxies.glb, parent_glb)
		assert.equal("Arm_Right", bone_glb)

		local parent_b3d, bone_b3d, _, rot_b3d = data.b3d:get_attach()
		assert.equal(proxies.b3d, parent_b3d)
		assert.equal("Arm_Right", bone_b3d)

		-- Verify format-specific orientation: GLB uses {-90, 45, 90}, B3D uses {-90, 225, 90} for swords
		assert.equal(-90, rot_glb.x)
		assert.equal(45, rot_glb.y)
		assert.equal(90, rot_glb.z)
		assert.equal(-90, rot_b3d.x)
		assert.equal(225, rot_b3d.y)
		assert.equal(90, rot_b3d.z)

		-- Verify observer cohort assignment for GLB and B3D wield entities
		assert.equal(x_player_api.get_modern_observers(), data.glb:get_observers())
		assert.equal(x_player_api.get_legacy_observers(), data.b3d:get_observers())
	end)

	it("hides inactive wield entity and routes active entity to all observers when switched to B3D format", function()
		player:set_wielded_item("default:sword_steel", 1)
		player_api.update_wield_item(player, true)

		local name = player:get_player_name()
		local data = player_api.wield_entities[name]

		-- Switch to B3D format
		player_api.set_model_format("b3d")

		-- data.glb must be hidden
		assert.equal(false, data.glb:get_properties().is_visible)
		assert.equal(0, data.glb:get_properties().visual_size.x)

		-- data.b3d must be visible to all observers (nil)
		assert.equal(true, data.b3d:get_properties().is_visible)
		assert.is_nil(data.b3d:get_observers())

		-- Restore format to glb
		player_api.set_model_format("glb")
	end)

	it("falls back to attaching directly to player when proxies are absent", function()
		local isolated_player = mock_env.create_player("IsolatedTester")
		local orig_get_proxies = x_player_api.get_visual_proxies
		x_player_api.get_visual_proxies = function() return nil end

		local active_ent = player_api.attach_wield_item(isolated_player)
		assert.is_not_nil(active_ent)

		local parent, bone, _, rot = active_ent:get_attach()
		assert.equal(isolated_player, parent)
		assert.equal("Arm_Right", bone)

		local _, _, exp_rot = x_player_api.get_wield_attachment_params("", "b3d")
		assert.equal(exp_rot.x, rot.x)

		player_api.remove_wield_item(isolated_player)
		x_player_api.get_visual_proxies = orig_get_proxies
	end)
end)
