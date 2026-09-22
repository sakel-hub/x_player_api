-- Specs for 3D Wield Item Offsets, Rotations, Scaling, and Colors

local mock_env = require("tests.mock_env")

describe("Wield Item Offsets and Orientations", function()
	before_each(function()
		mock_env.join_player("WieldTester")
	end)

	it("calculates base default attachment parameters for standard tools", function()
		core.registered_items["default:sword_steel"] = {
			type = "tool",
			wield_image = "default_tool_steelsword.png",
		}
		local visual_size, pos, rot, glow, item_color =
			player_api.get_wield_attachment_params("default:sword_steel")

		assert.near(0.275 * 1.33, visual_size.x, 1e-4)
		assert.near(0.275 * 1.33, visual_size.y, 1e-4)
		assert.near(0.275 * 1.33, visual_size.z, 1e-4)
		assert.equal({x = 0, y = 4.9, z = -3.5}, pos)
		assert.equal({x = -90, y = 45, z = 90}, rot)
		assert.equal(0, glow)
		assert.equal(nil, item_color)
	end)

	it("applies upright orientation and compact scaling to nodes", function()
		core.registered_items["default:cobble"] = {
			type = "node",
			description = "Cobblestone",
		}
		core.registered_nodes["default:cobble"] = core.registered_items["default:cobble"]
		local visual_size, pos, rot = player_api.get_wield_attachment_params("default:cobble")

		assert.near(0.275 * 0.60, visual_size.x, 1e-4)
		assert.near(0.275 * 0.60, visual_size.y, 1e-4)
		assert.near(0.275 * 0.60, visual_size.z, 1e-4)
		assert.equal({x = 0, y = 4.9, z = -1.5}, pos)
		assert.equal({x = 180, y = 0, z = 0}, rot)
	end)

	it("applies upright orientation to craftitems", function()
		core.registered_items["default:stick"] = {
			type = "craftitem",
		}
		local visual_size, pos, rot = player_api.get_wield_attachment_params("default:stick")

		assert.near(0.275, visual_size.x, 1e-4)
		assert.equal({x = 0, y = 4.9, z = -1.7}, pos)
		assert.equal({x = 180, y = 0, z = 0}, rot)
	end)

	it("handles group orientation overrides for torches, shovels, and bows", function()
		core.registered_items["default:torch"] = {
			type = "node",
			groups = {torch = 1},
		}
		local _, _, rot_torch = player_api.get_wield_attachment_params("default:torch")
		assert.equal(0, rot_torch.y)

		core.registered_items["default:shovel_steel"] = {
			type = "tool",
			groups = {shovel = 1},
		}
		local _, _, rot_shovel = player_api.get_wield_attachment_params("default:shovel_steel")
		assert.equal(45, rot_shovel.y)

		core.registered_items["bows:bow_wood"] = {
			type = "tool",
			groups = {bow = 1},
		}
		local _, _, rot_bow = player_api.get_wield_attachment_params("bows:bow_wood")
		assert.equal(-90, rot_bow.z)
	end)

	it("supports custom anisotropic scale overrides", function()
		core.registered_items["mymod:halberd"] = {
			type = "tool",
			_wield_scale = {x = 1.0, y = 2.0, z = 1.0},
		}
		local visual_size = player_api.get_wield_attachment_params("mymod:halberd")
		assert.near(0.275 * 1.33, visual_size.x, 1e-4)
		assert.near(0.275 * 1.33 * 2.0, visual_size.y, 1e-4)
		assert.near(0.275 * 1.33, visual_size.z, 1e-4)
	end)

	it("converts light_source values to entity glow brightness", function()
		core.registered_nodes["default:meselamp"] = {
			light_source = 14,
		}
		local _, _, _, glow_node = player_api.get_wield_attachment_params("default:meselamp")
		assert.equal(7, glow_node)

		core.registered_nodes["glow_mod:crystal"] = {
			groups = {light_source = 8},
		}
		local _, _, _, glow_group = player_api.get_wield_attachment_params("glow_mod:crystal")
		assert.equal(4, glow_group)

		core.registered_items["magic:torch"] = {
			light_source = 10,
			glow = 5,
		}
		local _, _, _, glow_exp = player_api.get_wield_attachment_params("magic:torch")
		assert.equal(5, glow_exp)
	end)

	it("supports uniform scalar scale overrides", function()
		core.registered_items["weapons:claymore"] = {
			type = "tool",
			_wield_scale = 1.5,
		}
		local visual_size = player_api.get_wield_attachment_params("weapons:claymore")
		assert.near(0.275 * 1.33 * 1.5, visual_size.x, 1e-4)
		assert.near(0.275 * 1.33 * 1.5, visual_size.y, 1e-4)
		assert.near(0.275 * 1.33 * 1.5, visual_size.z, 1e-4)
	end)

	it("normalizes item definition wield_scale property", function()
		core.registered_items["custom:scale_vector"] = {
			type = "craftitem",
			wield_scale = {x = 2.0, y = 1.5, z = 0.5},
		}
		local vs_vec = player_api.get_wield_attachment_params("custom:scale_vector")
		assert.near(0.275 / 2.0, vs_vec.x, 1e-4)
		assert.near(0.275 / 1.5, vs_vec.y, 1e-4)
		assert.near(0.275 / 0.5, vs_vec.z, 1e-4)

		core.registered_items["custom:scale_number"] = {
			type = "craftitem",
			wield_scale = 2.0,
		}
		local vs_num = player_api.get_wield_attachment_params("custom:scale_number")
		assert.near(0.275 / 2.0, vs_num.x, 1e-4)
	end)

	it("supports custom offset registry overrides", function()
		player_api.register_wield_item_offset("custom:wand", {
			pos = {x = 0.1, y = 1.0, z = -0.2},
			rot = {x = 10, y = 20, z = 30},
			scale = 0.8,
			glow = 7,
		})
		core.registered_items["custom:wand"] = {type = "tool"}
		local vs, pos, rot, glow = player_api.get_wield_attachment_params("custom:wand")

		assert.near(0.275 * 1.33 * 0.8, vs.x, 1e-4)
		assert.near(0.1, pos.x, 1e-4)
		assert.near(4.9 + 1.0, pos.y, 1e-4)
		assert.near(-3.5 - 0.2, pos.z, 1e-4)
		assert.equal({x = 10, y = 20, z = 30}, rot)
		assert.equal(7, glow)
	end)

	it("honors flat Luanti prefixed definition properties (_wield_*)", function()
		core.registered_items["custom:direct_dagger"] = {
			type = "tool",
			_wield_offset = {x = 0.05, y = -0.5, z = 0.1},
			_wield_rotation = {x = -45, y = 0, z = 90},
			_wield_scale = 0.5,
			_wield_glow = 12,
		}
		local vs, pos, rot, glow = player_api.get_wield_attachment_params("custom:direct_dagger")

		assert.near(0.275 * 1.33 * 0.5, vs.x, 1e-4)
		assert.near(0.05, pos.x, 1e-4)
		assert.near(4.9 - 0.5, pos.y, 1e-4)
		assert.near(-3.5 + 0.1, pos.z, 1e-4)
		assert.equal({x = -45, y = 0, z = 90}, rot)
		assert.equal(12, glow)
	end)

	it("ignores non-prefixed attributes (wield_offset / wield_rotation)", function()
		core.registered_items["custom:old_unprefixed"] = {
			type = "tool",
			wield_offset = {x = 999, y = 999, z = 999},
			wield_rotation = {x = 999, y = 999, z = 999},
		}
		local _, pos, rot = player_api.get_wield_attachment_params("custom:old_unprefixed")
		assert.equal({x = 0, y = 4.9, z = -3.5}, pos)
		assert.equal({x = -90, y = 45, z = 90}, rot)
	end)

	it("handles texture modifier rotation negation", function()
		core.registered_items["rotated:item_90"] = {
			type = "craftitem",
			inventory_image = "item_tex.png^[transformR90",
		}
		local _, _, rot90 = player_api.get_wield_attachment_params("rotated:item_90")
		assert.equal(-90, rot90.z)

		core.registered_items["rotated:item_270"] = {
			type = "craftitem",
			inventory_image = "item_tex.png^[transformR270",
		}
		local _, _, rot270 = player_api.get_wield_attachment_params("rotated:item_270")
		assert.equal(-270, rot270.z)
	end)

	it("preserves colorization and extracts color metadata", function()
		core.registered_items["wool:colored"] = {
			type = "node",
			palette = "unifieddyes_palette.png",
			color = "#FF8000",
		}
		local _, _, _, _, color = player_api.get_wield_attachment_params("wool:colored")
		assert.equal("#FF8000", color)

		local stack = ItemStack('default:glass 1 0 "\1color\2#00FF00\3"')
		local _, _, _, _, stack_color = player_api.get_wield_attachment_params(stack)
		assert.equal("#00FF00", stack_color)

		core.registered_items["wool:table_color"] = {
			type = "node",
			color = {r = 255, g = 128, b = 0},
		}
		local _, _, _, _, tbl_color = player_api.get_wield_attachment_params("wool:table_color")
		assert.equal("#FF8000", tbl_color)
	end)

	it("applies format-aware position and rotation compensation when switching between glb and b3d", function()
		core.registered_items["default:sword_steel"] = {
			type = "tool",
			wield_image = "default_tool_steelsword.png",
		}
		player_api.clear_item_cache()
		player_api.set_model_format("glb")
		local _, pos_glb, rot_glb = player_api.get_wield_attachment_params("default:sword_steel")
		assert.equal({x = 0, y = 4.9, z = -3.5}, pos_glb)
		assert.equal({x = -90, y = 45, z = 90}, rot_glb)

		player_api.clear_item_cache()
		player_api.set_model_format("b3d")
		local _, pos_b3d, rot_b3d = player_api.get_wield_attachment_params("default:sword_steel")
		-- In B3D, converts position coordinates for +Z facing mesh and sets y=225 for diagonal tools
		assert.equal({x = 0, y = 4.9, z = 3.5}, pos_b3d)
		assert.equal({x = -90, y = 225, z = 90}, rot_b3d)

		-- Verify bow orientation parity: both GLB and B3D use {-90, 45, -90}
		core.registered_items["bows:bow_wood"] = {
			type = "tool",
			groups = {bow = 1},
		}
		player_api.clear_item_cache()
		player_api.set_model_format("glb")
		local _, _, rot_bow_glb = player_api.get_wield_attachment_params("bows:bow_wood")
		assert.equal({x = -90, y = 45, z = -90}, rot_bow_glb)

		player_api.clear_item_cache()
		player_api.set_model_format("b3d")
		local _, _, rot_bow_b3d = player_api.get_wield_attachment_params("bows:bow_wood")
		assert.equal({x = -90, y = 45, z = -90}, rot_bow_b3d)

		-- Verify node position parity: GLB z = -1.5, B3D z = 1.5
		core.registered_items["default:cobble"] = {
			type = "node",
		}
		player_api.clear_item_cache()
		player_api.set_model_format("glb")
		local _, node_pos_glb, node_rot_glb = player_api.get_wield_attachment_params("default:cobble")
		assert.equal({x = 0, y = 4.9, z = -1.5}, node_pos_glb)
		assert.equal({x = 180, y = 0, z = 0}, node_rot_glb)

		player_api.clear_item_cache()
		player_api.set_model_format("b3d")
		local _, node_pos_b3d, node_rot_b3d = player_api.get_wield_attachment_params("default:cobble")
		assert.equal({x = 0, y = 4.9, z = 1.5}, node_pos_b3d)
		assert.equal({x = 180, y = 0, z = 0}, node_rot_b3d)

		-- Restore format to glb for subsequent tests
		player_api.clear_item_cache()
		player_api.set_model_format("glb")
	end)
end)
