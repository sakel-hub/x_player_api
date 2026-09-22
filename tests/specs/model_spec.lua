-- Specs for Model Registration, Animation Range Management, and Format Switching

local mock_env = require("tests.mock_env")

describe("Model & Animation Architecture", function()
	local player

	before_each(function()
		player = mock_env.join_player("ModelTester")
	end)

	after_each(function()
		player_api.set_model_format("glb")
	end)

	it("exposes x_player_api as a global alias to player_api", function()
		assert.equal(player_api, x_player_api)
	end)

	it("registers character.b3d with standardized animation frame ranges", function()
		local mdef = player_api.registered_models["character.b3d"]
		assert.is_not_nil(mdef)
		assert.equal(30, mdef.animation_speed)
		assert.equal(1, mdef.animations.stand.x)
		assert.equal(79, mdef.animations.stand.y)
		assert.equal(168, mdef.animations.walk.x)
		assert.equal(187, mdef.animations.walk.y)
		assert.equal(190, mdef.animations.mine.x)
		assert.equal(200, mdef.animations.mine.y)
		assert.equal(201, mdef.animations.walk_mine.x)
		assert.equal(220, mdef.animations.walk_mine.y)
		assert.equal(730, mdef.animations.equip.x)
		assert.equal(740, mdef.animations.equip.y)
		assert.is_false(mdef.animations.equip.loop)
	end)

	it("registers character.glb with equip action animation track", function()
		local mdef = player_api.registered_models["character.glb"]
		assert.is_not_nil(mdef)
		assert.is_not_nil(mdef.animations_glb.equip)
		assert.equal("equip", mdef.animations_glb.equip.track)
		assert.equal(1, mdef.animations_glb.equip.priority)
		assert.is_true(mdef.animations_glb.equip.is_action)
		assert.is_false(mdef.animations_glb.equip.loop)
		assert.is_not_nil(mdef.animations.equip)
		assert.equal(730, mdef.animations.equip.x)
		assert.equal(740, mdef.animations.equip.y)
	end)

	it("allows dynamic registration, editing, and removal of model animations", function()
		local reg_ok = player_api.register_model_animation("character.glb", "cast_spell", {
			track = "cast_spell",
			priority = 1,
			is_action = true,
			loop = false,
		})
		assert.is_true(reg_ok)
		local glb_model = player_api.get_model("character.glb")
		assert.is_not_nil(glb_model.animations_glb.cast_spell)
		assert.equal("cast_spell", glb_model.animations_glb.cast_spell.track)

		local edit_ok = player_api.edit_model_animation("character.b3d", "walk", {x = 170, y = 189})
		assert.is_true(edit_ok)
		local b3d_model = player_api.get_model("character.b3d")
		assert.equal(170, b3d_model.animations.walk.x)
		assert.equal(189, b3d_model.animations.walk.y)

		player_api.remove_model_animation("character.glb", "cast_spell")
		assert.is_nil(glb_model.animations_glb.cast_spell)
		player_api.edit_model_animation("character.b3d", "walk", {x = 168, y = 187})
	end)

	it("verifies physical model files exist with valid B3D and GLB headers", function()
		local f = io.open("models/character.b3d", "rb")
		assert.is_not_nil(f, "models/character.b3d must be readable")
		local magic = f:read(4)
		f:close()
		assert.equal("BB3D", magic, "File magic must be BB3D")

		local f_glb = io.open("models/character.glb", "rb")
		assert.is_not_nil(f_glb, "models/character.glb must be readable")
		local glb_magic = f_glb:read(4)
		f_glb:close()
		assert.equal("glTF", glb_magic, "File magic must be glTF")
	end)

	it("verifies character.glb bow animation keeps Body translation locked and counter-rotates legs", function()
		local f = io.open("models/character.glb", "rb")
		assert.is_not_nil(f, "models/character.glb must be readable")
		local data = f:read("*all")
		f:close()

		local json_len = mock_env.read_u32_le(data, 13)
		assert.is_true(json_len > 0, "JSON length must be positive")
		local json_str = data:sub(21, 20 + json_len)
		local parsed = core.parse_json(json_str)
		assert.is_not_nil(parsed, "Failed to parse character.glb JSON chunk")

		local bin_data_start = 21 + json_len + 8

		-- Find bow animation
		local bow_anim
		for _, a in ipairs(parsed.animations or {}) do
			if a.name == "bow" then
				bow_anim = a
				break
			end
		end
		assert.is_not_nil(bow_anim, "bow animation not found in character.glb")

		-- Map channels
		local body_trans_ch
		local leg_r_rot_ch
		local leg_l_rot_ch

		for _, ch in ipairs(bow_anim.channels) do
			local node_name = parsed.nodes[ch.target.node + 1].name
			local path = ch.target.path
			if node_name == "Body" and path == "translation" then
				body_trans_ch = ch
			elseif node_name == "Leg_Right" and path == "rotation" then
				leg_r_rot_ch = ch
			elseif node_name == "Leg_Left" and path == "rotation" then
				leg_l_rot_ch = ch
			end
		end

		assert.is_not_nil(body_trans_ch, "Body translation channel missing in bow")
		assert.is_not_nil(leg_r_rot_ch, "Leg_Right rotation channel missing in bow")
		assert.is_not_nil(leg_l_rot_ch, "Leg_Left rotation channel missing in bow")

		-- Verify Body translation is locked to (0, 6.3, 0) across all 4 keyframes
		local bt_sampler = bow_anim.samplers[body_trans_ch.sampler + 1]
		local bt_acc = parsed.accessors[bt_sampler.output + 1]
		local bt_bv = parsed.bufferViews[bt_acc.bufferView + 1]
		local bt_offset = bin_data_start + (bt_bv.byteOffset or 0) + (bt_acc.byteOffset or 0)
		assert.equal(4, bt_acc.count, "Body translation should have 4 keyframes")

		for k = 0, bt_acc.count - 1 do
			local x = mock_env.read_f32_le(data, bt_offset + k * 12)
			local y = mock_env.read_f32_le(data, bt_offset + k * 12 + 4)
			local z = mock_env.read_f32_le(data, bt_offset + k * 12 + 8)
			assert.is_true(math.abs(x - 0.0) < 1e-4, "Body translation x must be 0.0")
			assert.is_true(math.abs(y - 6.3) < 1e-3, "Body translation y must be locked to 6.3")
			assert.is_true(math.abs(z - 0.0) < 1e-4, "Body translation z must be 0.0")
		end

		-- Verify Leg_Right and Leg_Left counter-rotations
		local function verify_leg_rot(ch, leg_name)
			local sampler = bow_anim.samplers[ch.sampler + 1]
			local acc = parsed.accessors[sampler.output + 1]
			local bv = parsed.bufferViews[acc.bufferView + 1]
			local offset = bin_data_start + (bv.byteOffset or 0) + (acc.byteOffset or 0)
			assert.equal(4, acc.count, leg_name .. " should have 4 rotation keyframes")

			-- Key 0 and 3 are rest rotation: (1.0, 0.0, 0.0, 0.0)
			for _, k in ipairs({0, 3}) do
				local x = mock_env.read_f32_le(data, offset + k * 16)
				local y = mock_env.read_f32_le(data, offset + k * 16 + 4)
				local z = mock_env.read_f32_le(data, offset + k * 16 + 8)
				local w = mock_env.read_f32_le(data, offset + k * 16 + 12)
				assert.is_true(math.abs(x - 1.0) < 1e-4, leg_name .. " rest rot x must be 1.0 at key " .. k)
				assert.is_true(math.abs(y - 0.0) < 1e-4, leg_name .. " rest rot y must be 0.0 at key " .. k)
				assert.is_true(math.abs(z - 0.0) < 1e-4, leg_name .. " rest rot z must be 0.0 at key " .. k)
				assert.is_true(math.abs(w - 0.0) < 1e-4, leg_name .. " rest rot w must be 0.0 at key " .. k)
			end

			-- Key 1 and 2 are counter-rotation +30 deg pitch: +/- (0.965926, 0.0, 0.0, -0.258819)
			for _, k in ipairs({1, 2}) do
				local x = mock_env.read_f32_le(data, offset + k * 16)
				local y = mock_env.read_f32_le(data, offset + k * 16 + 4)
				local z = mock_env.read_f32_le(data, offset + k * 16 + 8)
				local w = mock_env.read_f32_le(data, offset + k * 16 + 12)
				assert.is_true(math.abs(math.abs(x) - 0.965926) < 1e-3, leg_name .. " counter rot x mismatch at key " .. k)
				assert.is_true(math.abs(y - 0.0) < 1e-4, leg_name .. " counter rot y mismatch at key " .. k)
				assert.is_true(math.abs(z - 0.0) < 1e-4, leg_name .. " counter rot z mismatch at key " .. k)
				assert.is_true(math.abs(math.abs(w) - 0.258819) < 1e-3, leg_name .. " counter rot w mismatch at key " .. k)
				assert.is_true(x * w < 0, leg_name .. " counter rot pitch sign must be opposite at key " .. k)
			end
		end

		verify_leg_rot(leg_r_rot_ch, "Leg_Right")
		verify_leg_rot(leg_l_rot_ch, "Leg_Left")
	end)

	it("normalizes animation aliases to canonical model track names", function()
		player_api.set_animation(player, "die")
		local anim_die = player_api.get_animation(player)
		assert.equal("lay", anim_die.animation)

		player_api.set_animation(player, "run")
		local anim_run = player_api.get_animation(player)
		assert.equal("sprint", anim_run.animation)

		player_api.set_animation(player, "duck")
		local anim_duck = player_api.get_animation(player)
		assert.equal("crouch_walk", anim_duck.animation)

		player_api.set_animation(player, "drink")
		local anim_drink = player_api.get_animation(player)
		assert.equal("eat", anim_drink.animation)

		player_api.set_animation(player, "shield")
		local anim_shield = player_api.get_animation(player)
		assert.equal("block", anim_shield.animation)
	end)

	it("switches model formats between GLB and B3D via API and chatcommands", function()
		assert.equal("glb", player_api.get_model_format())

		local switch_ok = player_api.set_model_format("b3d")
		assert.is_true(switch_ok)
		assert.equal("b3d", player_api.get_model_format())

		local cmd_toggle = core.chatcommands["model_format"]
		assert.is_not_nil(cmd_toggle)
		cmd_toggle.func(player:get_player_name(), "glb")
		assert.equal("glb", player_api.get_model_format())

		local cmd_alias = core.chatcommands["toggle_model"]
		assert.is_not_nil(cmd_alias)
		cmd_alias.func(player:get_player_name())
		assert.equal("b3d", player_api.get_model_format())

		player_api.set_model_format("glb")
	end)

	it("supports multi-hop chained redirects and handles redirect cycles gracefully", function()
		player_api.register_model("model_target.glb", {
			animations = {stand = {x = 0, y = 10}},
		})
		player_api.register_model_redirect("model_step2.glb", "model_target.glb")
		player_api.register_model_redirect("model_step1.glb", "model_step2.glb")

		local resolved = player_api.resolve_model("model_step1.glb")
		assert.equal("model_target.glb", resolved)

		-- Cyclic redirect test
		player_api.register_model_redirect("cycle_a.glb", "cycle_b.glb")
		player_api.register_model_redirect("cycle_b.glb", "cycle_a.glb")
		local cycle_resolved = player_api.resolve_model("cycle_a.glb")
		assert.is_not_nil(cycle_resolved)
	end)

	it("provides bidirectional modpath lookup for x_player_api and player_api", function()
		local path_x = core.get_modpath("x_player_api")
		local path_legacy = core.get_modpath("player_api")
		assert.is_not_nil(path_x)
		assert.is_not_nil(path_legacy)
		assert.equal(path_x, path_legacy)
	end)

	it("clears stale _equals clustering before recomputing animation metadata", function()
		local mdef = {
			animations = {
				anim1 = {x = 0, y = 10, _equals = "old_stale_group"},
				anim2 = {x = 0, y = 10},
			},
		}
		player_api.recompute_model_metadata(mdef)
		assert.not_equal("old_stale_group", mdef.animations.anim1._equals)
		assert.equal(mdef.animations.anim1._equals, mdef.animations.anim2._equals)
	end)

	it("stops previous animation track when switching animations", function()
		local proxies = player_api.get_visual_proxies(player)
		local glb = proxies.glb

		glb._played_animations = {}
		glb._stopped_animations = {}

		player_api.set_animation(player, "walk")
		assert.equal("walk", glb._played_animations[#glb._played_animations].track)

		player_api.set_animation(player, "mine")
		assert.equal("walk", glb._stopped_animations[#glb._stopped_animations])
		assert.equal("mine", glb._played_animations[#glb._played_animations].track)
	end)

	it("respects and passes override_local parameter in player_api.set_animation", function()
		player._local_animation_calls = {}
		player_api.set_animation(player, "walk", 30, true, true)
		assert.is_true(#player._local_animation_calls > 0)
		local last_call = player._local_animation_calls[#player._local_animation_calls]
		-- When override_local is true, local client animation is suppressed with ZERO_RANGE and speed 0
		assert.equal(0, last_call[1].x)
		assert.equal(0, last_call[1].y)
		assert.equal(0, last_call[5])
	end)

	it("suppresses local client prediction for models defining extended animations", function()
		player_api.set_model(player, "character.b3d")
		player._local_animation_calls = {}
		player_api.set_animation(player, "walk")
		assert.is_true(#player._local_animation_calls > 0)
		local last_call = player._local_animation_calls[#player._local_animation_calls]
		-- For character.b3d (which defines jump and fall), local client animation ranges must be 0
		-- to prevent the Luanti client engine from dropping server animation packets
		assert.equal(0, last_call[1].x)
		assert.equal(0, last_call[1].y)
		assert.equal(0, last_call[2].x)
		assert.equal(0, last_call[2].y)
	end)

	it("activates GLB proxy and hides B3D proxy symmetrically when setting GLB-only model", function()
		player_api.register_model("exclusive_test.glb", {
			mesh = "exclusive_test.glb",
			mesh_glb = "exclusive_test.glb",
			animations_glb = {
				stand = {track = "idle", priority = 0, loop = true},
			},
		})
		player_api.set_model(player, "exclusive_test.glb")
		local proxies = player_api.get_visual_proxies(player)
		assert.is_not_nil(proxies)

		local glb_props = proxies.glb:get_properties()
		assert.equal("exclusive_test.glb", glb_props.mesh)
		assert.equal(1, glb_props.visual_size.x)
		assert.equal(1, glb_props.visual_size.y)

		local b3d_props = proxies.b3d:get_properties()
		assert.equal(0, b3d_props.visual_size.x)
		assert.equal(0, b3d_props.visual_size.y)
	end)

	it("activates both GLB and B3D proxies symmetrically when setting dual-model character.glb", function()
		player_api.set_model(player, "character.glb")
		local proxies = player_api.get_visual_proxies(player)
		assert.is_not_nil(proxies)

		local glb_props = proxies.glb:get_properties()
		assert.equal("character.glb", glb_props.mesh)
		assert.equal(1, glb_props.visual_size.x)
		assert.equal(1, glb_props.visual_size.y)

		local b3d_props = proxies.b3d:get_properties()
		assert.equal("character.b3d", b3d_props.mesh)
		assert.equal(1, b3d_props.visual_size.x)
		assert.equal(1, b3d_props.visual_size.y)
	end)

	it("updates collisionbox and eye_height during posture animation and restores defaults on stand", function()
		player_api.set_model(player, "character.glb")
		local initial_props = player:get_properties()
		assert.equal(1.47, initial_props.eye_height)

		-- Crouch: custom eye_height and collisionbox
		player_api.set_animation(player, "crouch")
		local crouch_props = player:get_properties()
		assert.equal(1.25, crouch_props.eye_height)
		assert.equal(1.45, crouch_props.collisionbox[5])

		-- Stand: restored to model defaults
		player_api.set_animation(player, "stand")
		local stand_props = player:get_properties()
		assert.equal(1.47, stand_props.eye_height)
		assert.equal(1.7, stand_props.collisionbox[5])
	end)

	it("inherits animations and physical defaults when base_model is specified", function()
		player_api.register_model("derived_armor.b3d", {
			base_model = "character.b3d",
			mesh = "derived_armor.b3d",
			mesh_glb = "derived_armor.glb",
			textures = {"derived_armor.png"},
		})

		local mdef = player_api.get_model("derived_armor.b3d")
		assert.is_not_nil(mdef)
		assert.equal(30, mdef.animation_speed)
		assert.equal(1.47, mdef.eye_height)
		assert.equal(0.6, mdef.stepheight)
		assert.is_not_nil(mdef.animations.stand)
		assert.equal(1, mdef.animations.stand.x)
		assert.equal(79, mdef.animations.stand.y)
		assert.is_not_nil(mdef.animations_glb.sprint)
		assert.equal("sprint", mdef.animations_glb.sprint.track)
	end)

	it("inherits textures from base_model when textures is unspecified", function()
		player_api.register_model("derived_skinless.b3d", {
			base_model = "character.b3d",
			mesh = "derived_skinless.b3d",
		})

		local mdef = player_api.get_model("derived_skinless.b3d")
		assert.is_not_nil(mdef)
		assert.is_not_nil(mdef.textures)
		assert.equal("character.png", mdef.textures[1])
	end)

	it("supports wildcard string target in model_redirects", function()
		player_api.model_redirects["*"] = "wildcard_fallback.b3d"
		local resolved = player_api.resolve_model("unknown_custom_model.b3d")
		assert.equal("wildcard_fallback.b3d", resolved)
		player_api.model_redirects["*"] = nil
	end)

	it("switches default model and updates wield items on connected players on set_model_format", function()
		player_api.set_model(player, "character.glb")
		assert.equal("character.glb", player_api.get_animation(player).model)

		local switch_ok = player_api.set_model_format("b3d")
		assert.is_true(switch_ok)
		assert.equal("character.b3d", player_api.get_animation(player).model)

		-- Restore format to glb
		player_api.set_model_format("glb")
		assert.equal("character.glb", player_api.get_animation(player).model)
	end)

	it("normalizes glb animation speed to 1.0 multiplier instead of raw B3D frame rate", function()
		player_api.set_model(player, "character.glb")
		local proxies = player_api.get_visual_proxies(player)
		assert.is_not_nil(proxies)
		proxies.glb._played_animations = {}

		player_api.set_animation(player, "walk", 30)
		local played = proxies.glb._played_animations
		assert.is_true(#played > 0)
		local last_call = played[#played]
		assert.equal("walk", last_call.track)
		assert.equal(1.0, last_call.params.speed)
		assert.equal(0.15, last_call.params.blend)
	end)

	it("updates glb animation speed via update_animation without track restart when same track repeats", function()
		player_api.set_model(player, "character.glb")
		local proxies = player_api.get_visual_proxies(player)
		assert.is_not_nil(proxies)
		proxies.glb._played_animations = {}
		proxies.glb._updated_animations = {}

		player_api.set_animation(player, "walk", 30)
		local play_count = #proxies.glb._played_animations

		-- Adjust speed on the same track (e.g. crouching/sneaking or sprinting)
		player_api.set_animation(player, "walk", 15)
		assert.equal(play_count, #proxies.glb._played_animations)
		assert.is_true(#proxies.glb._updated_animations > 0)
		local last_up = proxies.glb._updated_animations[#proxies.glb._updated_animations]
		assert.equal("walk", last_up.track)
		assert.equal(0.5, last_up.update.speed)
	end)

	it("blends glb animation tracks with configurable transition time", function()
		player_api.set_model(player, "character.glb")
		local proxies = player_api.get_visual_proxies(player)
		assert.is_not_nil(proxies)
		proxies.glb._played_animations = {}

		player_api.set_animation(player, "walk", 30, 0.25)
		local played = proxies.glb._played_animations
		assert.is_true(#played > 0)
		local last_call = played[#played]
		assert.equal("walk", last_call.track)
		assert.equal(0.25, last_call.params.blend)
	end)

	it("defaults def.mesh to model name when mesh is omitted in registration", function()
		player_api.register_model("custom_hero.b3d", {
			animations = {
				stand = {x = 0, y = 79},
			},
		})
		local m = player_api.registered_models["custom_hero.b3d"]
		assert.is_not_nil(m)
		assert.equal("custom_hero.b3d", m.mesh)
	end)

	it("merges and preserves existing metadata and glb tracks when model is re-registered", function()
		player_api.register_model("dual_test_model.b3d", {
			base_model = "character.b3d",
			mesh = "dual_test_model.b3d",
			mesh_glb = "dual_test_model.glb",
		})
		local initial = player_api.registered_models["dual_test_model.b3d"]
		assert.is_not_nil(initial.animations_glb["walk"])
		assert.equal("dual_test_model.glb", initial.mesh_glb)

		-- Simulate legacy mod re-registering model with only B3D frames
		player_api.register_model("dual_test_model.b3d", {
			animation_speed = 35,
			animations = {
				stand = {x = 0, y = 80},
			},
		})
		local updated = player_api.registered_models["dual_test_model.b3d"]
		assert.equal("dual_test_model.b3d", updated.mesh)
		assert.equal("dual_test_model.glb", updated.mesh_glb)
		assert.is_not_nil(updated.animations_glb["walk"])
		assert.is_true(updated.is_multitrack)
	end)

	it("heals zero-scale proxies when set_model is called with current model name", function()
		player_api.set_model(player, "character.glb")
		local proxies = player_api.get_visual_proxies(player)
		assert.is_not_nil(proxies)

		-- Simulate corrupted or zeroed proxy visual size
		proxies.glb:set_properties({visual_size = {x = 0, y = 0}})
		assert.equal(0, proxies.glb:get_properties().visual_size.x)

		-- Calling set_model again should heal the proxy to active model's scale
		player_api.set_model(player, "character.glb")
		assert.equal(1, proxies.glb:get_properties().visual_size.x)
	end)
end)


