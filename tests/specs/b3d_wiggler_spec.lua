-- Tests for B3D Model Rotation Wiggler and Irrlicht Matrix Decomposition Mitigation (Issue #15692)

describe("B3D Model Rotation Wiggler Subsystem", function()
	local mock_env = require("tests.mock_env")
	local wiggler_test = x_player_api._b3d_wiggler_test
	assert.is_not_nil(wiggler_test, "Wiggler test helpers must be exposed")

	it("identifies perfect 180-degree rotations causing zero off-diagonals", function()
		local is_perf = wiggler_test.is_perfect_rotation

		-- Identity quaternion (0 deg) has zero off-diagonals but scale is positive (+1, +1, +1)
		assert.is_false(is_perf(1, 0, 0, 0))

		-- 180 degrees around X axis: quat = (w=0, x=1, y=0, z=0) -> diagonal = (1, -1, -1)
		assert.is_true(is_perf(0, 1, 0, 0))

		-- 180 degrees around Y axis: quat = (w=0, x=0, y=1, z=0) -> diagonal = (-1, 1, -1)
		assert.is_true(is_perf(0, 0, 1, 0))

		-- 180 degrees around Z axis: quat = (w=0, x=0, y=0, z=1) -> diagonal = (-1, -1, 1)
		assert.is_true(is_perf(0, 0, 0, 1))

		-- 90 degrees around X axis: quat = (w=cos(45°)=0.7071, x=sin(45°)=0.7071, y=0, z=0)
		-- Matrix has non-zero off-diagonals, Irrlicht does not early-exit
		local q45 = math.sqrt(0.5)
		assert.is_false(is_perf(q45, q45, 0, 0))

		-- 45 degrees around Y axis
		assert.is_false(is_perf(math.cos(math.pi / 8), 0, math.sin(math.pi / 8), 0))
	end)

	it("perturbs perfect rotations into non-perfect unit quaternions", function()
		local is_perf = wiggler_test.is_perfect_rotation
		local wiggle = wiggler_test.wiggle_quaternion

		-- Unperturbed non-perfect quat returns unchanged
		local w, x = wiggle(1, 0, 0, 0)
		assert.equal(1, w)
		assert.equal(0, x)

		-- Perturb 180 deg around Y (Arm_Right standing rest pose)
		local nw, nx, ny, nz = wiggle(0, 0, 1, 0)
		assert.is_false(is_perf(nw, nx, ny, nz), "Wiggled quat must break zero off-diagonals")

		-- Check unit length
		local mag = math.sqrt(nw * nw + nx * nx + ny * ny + nz * nz)
		assert.is_true(math.abs(mag - 1.0) < 1e-5, "Wiggled quat must remain normalized")

		-- Angular deviation must be tiny (< 0.1 degrees)
		assert.is_true(math.abs(ny) > 0.999, "Dominant rotation axis must remain intact")
	end)

	it("accurately reads and writes little-endian binary IEEE-754 floats and uint32s", function()
		local read_u32 = wiggler_test.read_u32_le
		local read_f32 = wiggler_test.read_f32_le
		local write_f32 = wiggler_test.write_f32_le

		local test_floats = {0, 1.0, -1.0, 0.5, -0.5, 0.001, -0.001, 3.14159, 100.25}
		for _, val in ipairs(test_floats) do
			local packed = write_f32(val)
			assert.equal(4, #packed)
			local unpacked = read_f32(packed, 1)
			assert.is_true(math.abs(unpacked - val) < 1e-5,
				string.format("Float round-trip mismatch for %f (got %f)", val, unpacked))
		end

		-- Verify uint32 reading
		local sample_u32 = string.char(0x01, 0x02, 0x03, 0x04)
		local val_u32 = read_u32(sample_u32, 1)
		assert.equal(0x04030201, val_u32)
	end)

	it("handles malformed or truncated B3D data without error", function()
		local corrupt = "NOT_A_B3D_FILE"
		local out, nw, kw = x_player_api.wiggle_b3d_data(corrupt)
		assert.equal(corrupt, out)
		assert.equal(0, nw)
		assert.equal(0, kw)

		local short_header = "BB3D"
		local out2, nw2, kw2 = x_player_api.wiggle_b3d_data(short_header)
		assert.equal(short_header, out2)
		assert.equal(0, nw2)
		assert.equal(0, kw2)
	end)

	it("processes synthetic B3D chunks and perturbs NODE and KEYS rotations in-place", function()
		local write_f32 = wiggler_test.write_f32_le

		-- Build a minimal synthetic B3D chunk structure:
		-- BB3D [size] [version]
		--   NODE [size]
		--     "TestBone\0" [pos: 3f] [scale: 3f] [rot: 4f (perfect 180° around Y)]
		--     KEYS [size]
		--       [flags=4 (rotation only)]
		--       [frame=1] [rot: 4f (perfect 180° around Y)]
		local node_name = "TestBone\0"
		local pos_floats = write_f32(0) .. write_f32(0) .. write_f32(0)
		local scale_floats = write_f32(1) .. write_f32(1) .. write_f32(1)
		local perf_rot_floats = write_f32(0) .. write_f32(0) .. write_f32(1) .. write_f32(0) -- w=0, x=0, y=1, z=0

		-- KEYS payload
		local keys_flags = string.char(4, 0, 0, 0) -- flags = 4 (rotation)
		local keys_frame = string.char(1, 0, 0, 0) -- frame = 1
		local keys_payload = keys_flags .. keys_frame .. perf_rot_floats
		local keys_chunk = "KEYS" .. string.char(#keys_payload, 0, 0, 0) .. keys_payload

		-- NODE payload
		local node_payload = node_name .. pos_floats .. scale_floats .. perf_rot_floats .. keys_chunk
		local node_chunk = "NODE" .. string.char(#node_payload, 0, 0, 0) .. node_payload

		-- Top BB3D payload
		local version = string.char(1, 0, 0, 0)
		local bb3d_payload = version .. node_chunk
		local raw_b3d = "BB3D" .. string.char(#bb3d_payload, 0, 0, 0) .. bb3d_payload

		-- Run wiggler on synthetic model
		local patched, nw, kw = x_player_api.wiggle_b3d_data(raw_b3d)
		assert.equal(1, nw, "Must have wiggled 1 node")
		assert.equal(1, kw, "Must have wiggled 1 keyframe")
		assert.equal(#raw_b3d, #patched, "Length of patched data must match original exactly")

		-- Re-running on already wiggled data must detect 0 perfect rotations
		local _, nw2, kw2 = x_player_api.wiggle_b3d_data(patched)
		assert.equal(0, nw2, "Second pass must have 0 wiggled nodes")
		assert.equal(0, kw2, "Second pass must have 0 wiggled keys")
	end)

	it("verifies character.b3d has 0 remaining un-wiggled rotations", function()
		local f = io.open("models/character.b3d", "rb")
		if not f then return end
		local data = f:read("*a")
		f:close()

		local _, nw, kw = x_player_api.wiggle_b3d_data(data)
		assert.equal(0, nw, "Pre-wiggled character.b3d must have 0 buggy nodes")
		assert.equal(0, kw, "Pre-wiggled character.b3d must have 0 buggy keyframes")
	end)

	it("scan_and_wiggle_b3d_model preserves clean models without creating redundant redirects", function()
		local resolved = x_player_api.scan_and_wiggle_b3d_model("character.b3d", "models/character.b3d")
		assert.equal("character.b3d", resolved)
		assert.is_nil(x_player_api.model_redirects["character.b3d"])
	end)

	it("deduplicates scan_and_wiggle_b3d_model calls and prevents duplicate dynamic media", function()
		local dynamic_add_calls = 0
		local old_dynamic_add = core.dynamic_add_media
		core.dynamic_add_media = function(def)
			dynamic_add_calls = dynamic_add_calls + 1
			if old_dynamic_add then return old_dynamic_add(def) end
			return true
		end

		-- Clean test cache for this test
		wiggler_test.processed_models["mock_unpatched.b3d"] = nil
		wiggler_test.added_dynamic_media["_wiggled_mock_unpatched.b3d"] = nil

		-- Create a temporary unpatched file
		local mock_path = "scratch_test_model.b3d"
		local write_f32 = wiggler_test.write_f32_le
		local node_name = "MockBone\0"
		local pos_floats = write_f32(0) .. write_f32(0) .. write_f32(0)
		local scale_floats = write_f32(1) .. write_f32(1) .. write_f32(1)
		local perf_rot = write_f32(0) .. write_f32(0) .. write_f32(1) .. write_f32(0) -- 180° around Y
		local node_payload = node_name .. pos_floats .. scale_floats .. perf_rot
		local node_chunk = "NODE" .. string.char(#node_payload, 0, 0, 0) .. node_payload
		local raw_b3d = "BB3D" .. string.char(#node_chunk + 4, 0, 0, 0) .. string.char(1, 0, 0, 0) .. node_chunk

		local f = io.open(mock_path, "wb")
		assert.is_not_nil(f)
		f:write(raw_b3d)
		f:close()

		-- First scan call should detect unpatched model and call dynamic_add_media once
		local res1 = x_player_api.scan_and_wiggle_b3d_model("mock_unpatched.b3d", mock_path)
		assert.equal("_wiggled_mock_unpatched.b3d", res1)
		assert.equal(1, dynamic_add_calls, "First call must invoke dynamic_add_media exactly once")

		-- Repeated scan calls must return cached target name and NOT call dynamic_add_media again
		local res2 = x_player_api.scan_and_wiggle_b3d_model("mock_unpatched.b3d", mock_path)
		assert.equal("_wiggled_mock_unpatched.b3d", res2)
		assert.equal(1, dynamic_add_calls, "Second call must NOT re-register dynamic media")

		local res3 = x_player_api.scan_and_wiggle_b3d_model("_wiggled_mock_unpatched.b3d")
		assert.equal("_wiggled_mock_unpatched.b3d", res3)
		assert.equal(1, dynamic_add_calls, "Passing _wiggled_ prefix directly must not re-register")

		-- Cleanup
		os.remove(mock_path)
		core.dynamic_add_media = old_dynamic_add
	end)

	it("does not hijack canonical model names via model_redirects and resolves via get_model", function()
		local write_f32 = wiggler_test.write_f32_le
		local mock_path = "scratch_test_clean_redirect.b3d"
		local node_name = "MockBone\0"
		local pos_floats = write_f32(0) .. write_f32(0) .. write_f32(0)
		local scale_floats = write_f32(1) .. write_f32(1) .. write_f32(1)
		local perf_rot = write_f32(0) .. write_f32(0) .. write_f32(1) .. write_f32(0)
		local node_payload = node_name .. pos_floats .. scale_floats .. perf_rot
		local node_chunk = "NODE" .. string.char(#node_payload, 0, 0, 0) .. node_payload
		local raw_b3d = "BB3D" .. string.char(#node_chunk + 4, 0, 0, 0) .. string.char(1, 0, 0, 0) .. node_chunk

		local f = io.open(mock_path, "wb")
		assert.is_not_nil(f)
		f:write(raw_b3d)
		f:close()

		x_player_api.scan_and_wiggle_b3d_model("test_unhijacked.b3d", mock_path)
		assert.is_nil(x_player_api.model_redirects["test_unhijacked.b3d"],
			"Model redirects must never be polluted with wiggled mesh names")

		x_player_api.register_model("test_unhijacked.b3d", {
			mesh = "test_unhijacked.b3d",
			mesh_glb = "character.glb",
			animations = { walk = {x = 1, y = 20} },
			animations_glb = { walk = {track = "walk"} },
		})

		local def = x_player_api.get_model("test_unhijacked.b3d")
		assert.is_not_nil(def, "Model must be discoverable via its canonical name")
		assert.equal("_wiggled_test_unhijacked.b3d", def.mesh, "Underlying mesh must be wiggled")

		local def_by_wiggled = x_player_api.get_model("_wiggled_test_unhijacked.b3d")
		assert.is_not_nil(def_by_wiggled, "Model must also be discoverable via wiggled alias")
		assert.equal(def, def_by_wiggled, "Both lookups must return identical model definition")

		os.remove(mock_path)
	end)

	it("preserves GLB visibility and B3D animations when wiggled model is assigned to player", function()
		local player = mock_env.create_player("WiggleTestPlayer")
		mock_env.join_player("WiggleTestPlayer")

		x_player_api.set_model(player, "test_unhijacked.b3d")
		local pdata = x_player_api.get_animation(player)
		assert.equal("test_unhijacked.b3d", pdata.model)

		local proxies = x_player_api.get_visual_proxies(player)
		assert.is_not_nil(proxies)
		assert.equal(1, proxies.glb:get_properties().visual_size.x, "GLB proxy must remain visible (size 1)")
		assert.equal(1, proxies.b3d:get_properties().visual_size.x, "B3D proxy must remain visible (size 1)")

		x_player_api.set_animation(player, "walk")
		local anim_data = x_player_api.get_animation(player)
		assert.equal("walk", anim_data.animation, "GLB walk animation must be set")
		assert.equal("walk", anim_data.animation_b3d, "B3D walk animation must be set")
	end)
end)
