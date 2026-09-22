-- Specs for Environmental Spatial Probing Subsystem (environment.lua)
-- Tests zero-allocation liquid, ladder, ground, and air detection.

require("tests.mock_env")

describe("Environmental Spatial Probing Subsystem", function()
	before_each(function()
		core.registered_nodes["default:dirt"] = {walkable = true}
		core.registered_nodes["default:water_source"] = {liquidtype = "source", drawtype = "liquid"}
		core.registered_nodes["default:water_flowing"] = {liquidtype = "flowing", drawtype = "flowingliquid"}
		core.registered_nodes["default:ladder"] = {climbable = true, walkable = false}
		core.registered_nodes["air"] = {walkable = false}

		core.get_node_or_nil = function() return {name = "air"} end
	end)

	it("detects liquid at waist and foot levels", function()
		assert.is_false(x_player_api.is_player_in_liquid(nil))
		assert.is_false(x_player_api.is_player_in_liquid({x = 0, y = 0, z = 0}))

		-- Liquid at waist height (pos.y + 0.8)
		core.get_node_or_nil = function(pos)
			if math.abs(pos.y - 0.8) < 0.1 then
				return {name = "default:water_source"}
			end
			return {name = "air"}
		end
		assert.is_true(x_player_api.is_player_in_liquid({x = 0, y = 0, z = 0}))

		-- Liquid at lower body (pos.y + 0.2)
		core.get_node_or_nil = function(pos)
			if math.abs(pos.y - 0.2) < 0.1 then
				return {name = "default:water_flowing"}
			end
			return {name = "air"}
		end
		assert.is_true(x_player_api.is_player_in_liquid({x = 0, y = 0, z = 0}))
	end)

	it("detects climbable ladders at feet, waist, and reach heights", function()
		assert.is_false(x_player_api.is_player_on_ladder(nil))
		assert.is_false(x_player_api.is_player_on_ladder({x = 0, y = 0, z = 0}))

		-- Ladder at waist height (pos.y + 0.5)
		core.get_node_or_nil = function(pos)
			if math.abs(pos.y - 0.5) < 0.1 then
				return {name = "default:ladder"}
			end
			return {name = "air"}
		end
		assert.is_true(x_player_api.is_player_on_ladder({x = 0, y = 0, z = 0}))

		-- Ladder at reach height (pos.y + 1.2 in upper node)
		core.get_node_or_nil = function(pos)
			if pos.y >= 1.5 then
				return {name = "default:ladder"}
			end
			return {name = "air"}
		end
		assert.is_true(x_player_api.is_player_on_ladder({x = 0, y = 0.4, z = 0}))

		-- Ladder at feet (pos.y <= 0.1 in lower node)
		core.get_node_or_nil = function(pos)
			if pos.y <= 0.1 then
				return {name = "default:ladder"}
			end
			return {name = "air"}
		end
		assert.is_true(x_player_api.is_player_on_ladder({x = 0, y = 0.1, z = 0}))
	end)

	it("detects solid ground directly beneath feet and via edge offsets", function()
		assert.is_false(x_player_api.is_ground_near(nil, 0.8))
		assert.is_false(x_player_api.is_ground_near({x = 0, y = 10, z = 0}, 0.8))

		-- Ground directly below center
		core.get_node_or_nil = function(pos)
			if pos.y <= 0 then
				return {name = "default:dirt"}
			end
			return {name = "air"}
		end
		assert.is_true(x_player_api.is_ground_near({x = 0, y = 0.2, z = 0}, 0.8))

		-- Ground under edge/corner only (standing with center over void at x=0.35 and feet supported on x>0.4)
		core.get_node_or_nil = function(pos)
			if pos.x > 0.4 and pos.y <= 0 then
				return {name = "default:dirt"}
			end
			return {name = "air"}
		end
		assert.is_true(x_player_api.is_ground_near({x = 0.35, y = 0.2, z = 0}, 0.8))

		-- Unloaded chunk: returns true if previously grounded to prevent false hover
		core.get_node_or_nil = function() return {name = "ignore"} end
		local pstate = {was_on_ground = true}
		assert.is_true(x_player_api.is_ground_near({x = 0, y = 0.2, z = 0}, 0.8, pstate))

		pstate.was_on_ground = false
		assert.is_false(x_player_api.is_ground_near({x = 0, y = 0.2, z = 0}, 0.8, pstate))
	end)

	it("returns comprehensive environment states via detect_environment", function()
		core.get_node_or_nil = function(pos)
			if pos.y <= 0 then
				return {name = "default:dirt"}
			end
			return {name = "air"}
		end

		local pstate = {was_on_ground = false, was_jumping = true}
		local in_water, on_ladder, is_on_ground, in_air = x_player_api.detect_environment(
			{x = 0, y = 0.2, z = 0},
			{x = 0, y = 0, z = 0},
			pstate
		)
		assert.is_false(in_water)
		assert.is_false(on_ladder)
		assert.is_true(is_on_ground)
		assert.is_false(in_air)
		assert.is_true(pstate.was_on_ground)
		assert.is_false(pstate.was_jumping)
	end)
end)
