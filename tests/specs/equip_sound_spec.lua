-- Specs for Declarative Equip Sound Registry and Audio Playback
-- S.O.L.I.D. Open/Closed Principle (OCP) verification

local mock_env = require("tests.mock_env")

describe("Declarative Equip Sound Registry", function()
	local player

	before_each(function()
		player = mock_env.join_player("SoundTester")
		core._sounds_played = {}
		player_api.enable_equip_sound = true

		-- Register test items with appropriate groups
		core.registered_items["default:sword_steel"] = {
			groups = {sword = 1, weapon = 1},
		}
		core.registered_items["default:bow_wood"] = {
			groups = {bow = 1, weapon = 1},
		}
		core.registered_items["default:pick_diamond"] = {
			groups = {pickaxe = 1, tool = 1},
		}
		core.registered_items["default:axe_steel"] = {
			groups = {axe = 1, tool = 1},
		}
		core.registered_items["default:shovel_stone"] = {
			groups = {shovel = 1, tool = 1},
		}
		core.registered_items["default:dirt"] = {
			groups = {crumbly = 3},
		}

		player_api.clear_equip_sound_cache()
	end)

	after_each(function()
		player_api.enable_equip_sound = true
		player_api.registered_equip_sounds["default:special_blade"] = nil
		player_api.registered_equip_sounds["default:silent_blade"] = nil
		player_api.registered_equip_sounds["default:sword_steel"] = nil
		player_api.clear_equip_sound_cache()
	end)

	it("resolves default group equip sounds for swords, bows, and tools", function()
		local sword_sound = player_api.get_equip_sound("default:sword_steel")
		assert.is_not_nil(sword_sound)
		assert.equal("x_player_api_draw_blade", sword_sound.sound)
		assert.equal(0.18, sword_sound.gain)

		local bow_sound = player_api.get_equip_sound("default:bow_wood")
		assert.is_not_nil(bow_sound)
		assert.equal("x_player_api_draw_bow", bow_sound.sound)
		assert.equal(0.15, bow_sound.gain)

		local pick_sound = player_api.get_equip_sound("default:pick_diamond")
		assert.is_not_nil(pick_sound)
		assert.equal("x_player_api_draw_tool", pick_sound.sound)
		assert.equal(0.15, pick_sound.gain)

		local axe_sound = player_api.get_equip_sound("default:axe_steel")
		assert.is_not_nil(axe_sound)
		assert.equal("x_player_api_draw_tool", axe_sound.sound)

		local shovel_sound = player_api.get_equip_sound("default:shovel_stone")
		assert.is_not_nil(shovel_sound)
		assert.equal("x_player_api_draw_tool", shovel_sound.sound)
	end)

	it("supports custom item registration that overrides group sound via direct precedence", function()
		player_api.register_equip_sound("default:special_blade", {
			sound = "custom_blade_draw",
			gain = 0.95,
			pitch = 1.1,
			max_hear_distance = 24,
		})
		core.registered_items["default:special_blade"] = {
			groups = {sword = 1},
		}

		local sdef = player_api.get_equip_sound("default:special_blade")
		assert.is_not_nil(sdef)
		assert.equal("custom_blade_draw", sdef.sound)
		assert.equal(0.95, sdef.gain)
		assert.equal(1.1, sdef.pitch)
		assert.equal(24, sdef.max_hear_distance)
	end)

	it("honors item definition _equip_sound field over group default", function()
		-- String sound spec in item definition
		core.registered_items["magic:wand"] = {
			groups = {tool = 1},
			_equip_sound = "magic_wand_unsheathe",
		}
		local wand_sound = player_api.get_equip_sound("magic:wand")
		assert.is_not_nil(wand_sound)
		assert.equal("magic_wand_unsheathe", wand_sound.sound)

		-- Table sound spec in item definition
		core.registered_items["magic:staff"] = {
			groups = {tool = 1},
			_equip_sound = {sound = "staff_hum", gain = 0.85, pitch = 0.9},
		}
		local staff_sound = player_api.get_equip_sound("magic:staff")
		assert.is_not_nil(staff_sound)
		assert.equal("staff_hum", staff_sound.sound)
		assert.equal(0.85, staff_sound.gain)
		assert.equal(0.9, staff_sound.pitch)
	end)

	it("allows silencing/suppressing equip sound via registry or item definition", function()
		-- Suppress via registry with false
		player_api.register_equip_sound("default:silent_blade", false)
		core.registered_items["default:silent_blade"] = {groups = {sword = 1}}
		assert.is_nil(player_api.get_equip_sound("default:silent_blade"))

		-- Suppress via item definition with false
		core.registered_items["stealth:dagger"] = {
			groups = {sword = 1},
			_equip_sound = false,
		}
		assert.is_nil(player_api.get_equip_sound("stealth:dagger"))

		-- Suppress via item definition with empty string
		core.registered_items["stealth:silent_bow"] = {
			groups = {bow = 1},
			_equip_sound = "",
		}
		assert.is_nil(player_api.get_equip_sound("stealth:silent_bow"))
	end)

	it("returns nil for empty, nil, or items without sound mappings", function()
		assert.is_nil(player_api.get_equip_sound(""))
		assert.is_nil(player_api.get_equip_sound(nil))
		assert.is_nil(player_api.get_equip_sound("default:dirt"))
	end)

	it("memoizes sound lookups and clears cache on registration or clear_equip_sound_cache", function()
		-- Initial resolution
		local sdef1 = player_api.get_equip_sound("default:sword_steel")
		assert.is_not_nil(sdef1)

		-- Override in registry should invalidate and update cache
		player_api.register_equip_sound("default:sword_steel", {sound = "steel_draw_custom", gain = 0.8})
		local sdef2 = player_api.get_equip_sound("default:sword_steel")
		assert.is_not_nil(sdef2)
		assert.equal("steel_draw_custom", sdef2.sound)

		-- Clearing item cache also clears equip sound cache
		player_api.clear_item_cache()
		local sdef3 = player_api.get_equip_sound("default:sword_steel")
		assert.is_not_nil(sdef3)
		assert.equal("steel_draw_custom", sdef3.sound)
	end)

	it("plays sound on play_equip_sound with positional and ephemeral parameters", function()
		player._pos = {x = 12, y = 24, z = 36}

		local ok = player_api.play_equip_sound(player, "default:sword_steel")
		assert.is_true(ok)
		assert.equal(1, #core._sounds_played)

		local played = core._sounds_played[1]
		assert.equal("x_player_api_draw_blade", played.spec)
		assert.is_not_nil(played.params)
		assert.equal(12, played.params.pos.x)
		assert.equal(24, played.params.pos.y)
		assert.equal(36, played.params.pos.z)
		assert.equal(0.18, played.params.gain)
		assert.is_true(played.params.pitch >= 0.94 and played.params.pitch <= 1.06)
		assert.equal(16, played.params.max_hear_distance)
		assert.is_true(played.ephemeral)
	end)

	it("respects enable_equip_sound toggle", function()
		player_api.enable_equip_sound = false

		local ok = player_api.play_equip_sound(player, "default:sword_steel")
		assert.is_false(ok)
		assert.equal(0, #core._sounds_played)

		player_api.enable_equip_sound = true
		local ok2 = player_api.play_equip_sound(player, "default:sword_steel")
		assert.is_true(ok2)
		assert.equal(1, #core._sounds_played)
	end)

	it("triggers sound via trigger_equip both with explicit item_name and inferred wield item", function()
		player_api.set_model(player, "character.glb")

		-- Explicit item_name passed
		core._sounds_played = {}
		local ok1 = player_api.trigger_equip(player, "default:bow_wood")
		assert.is_true(ok1)
		assert.equal(1, #core._sounds_played)
		assert.equal("x_player_api_draw_bow", core._sounds_played[1].spec)

		-- Inferred from player's wielded item
		core._sounds_played = {}
		player:set_wielded_item("default:pick_diamond")
		local ok2 = player_api.trigger_equip(player)
		assert.is_true(ok2)
		assert.equal(1, #core._sounds_played)
		assert.equal("x_player_api_draw_tool", core._sounds_played[1].spec)
	end)

	it("triggers equip sound even when active model lacks equip animation (fallback)", function()
		player_api.register_model("legacy_audio_test.b3d", {
			animations = {
				stand = {x = 0, y = 79},
				-- No equip animation track
			},
		})
		player_api.set_model(player, "legacy_audio_test.b3d")

		core._sounds_played = {}
		local ok = player_api.trigger_equip(player, "default:sword_steel")
		-- Model has no equip animation, so animation trigger returns false
		assert.is_false(ok)
		-- But equip audio feedback still plays!
		assert.equal(1, #core._sounds_played)
		assert.equal("x_player_api_draw_blade", core._sounds_played[1].spec)
	end)

	it("supports disabling pitch randomization with pitch_variance = 0", function()
		player_api.register_equip_sound("default:exact_pitch_sword", {
			sound = "exact_draw_sound",
			pitch = 1.25,
			pitch_variance = 0,
		})
		core.registered_items["default:exact_pitch_sword"] = {groups = {sword = 1}}

		core._sounds_played = {}
		player_api.play_equip_sound(player, "default:exact_pitch_sword")
		assert.equal(1, #core._sounds_played)
		assert.equal(1.25, core._sounds_played[1].params.pitch)
	end)

	it("randomizes pitch across repeated play_equip_sound calls within configured pitch_variance", function()
		player_api.register_equip_sound("default:varied_tool", {
			sound = "varied_tool_sound",
			pitch = 1.0,
			pitch_variance = 0.08,
		})
		core.registered_items["default:varied_tool"] = {groups = {tool = 1}}

		local pitches = {}
		for _ = 1, 10 do
			core._sounds_played = {}
			player_api.play_equip_sound(player, "default:varied_tool")
			assert.equal(1, #core._sounds_played)
			local p = core._sounds_played[1].params.pitch
			assert.is_true(p >= 0.92 and p <= 1.08)
			pitches[#pitches + 1] = p
		end

		-- Verify not all 10 pitches are identical (randomization produces variations)
		local all_same = true
		for i = 2, #pitches do
			if pitches[i] ~= pitches[1] then
				all_same = false
				break
			end
		end
		assert.is_false(all_same)
	end)
end)
