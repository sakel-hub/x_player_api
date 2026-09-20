-- x_player_api/bone_overrides.lua
-- Dedicated module to handle the network throttle state and logic for bone attachments.

x_player_api = x_player_api or player_api

---@class BoneOverride
---@field position Vector3 Local position offset vector {x, y, z}
---@field rotation Vector3 Local rotation vector in radians {x, y, z}

---@type table<string, table<string, BoneOverride>> Cached bone transformations for network throttling
x_player_api.bone_caches = {}

---Set a bone position and rotation override with network throttling
---Applies pitch, yaw, and roll rotation to visual proxy entities.
---Throttles Head bone updates below 0.08 radians (~4.5 degrees) to optimize multiplayer bandwidth.
---@param player ObjectRef Target player
---@param bone string Target bone name (e.g. "Head")
---@param position Vector3 Local bone translation offset
---@param rotation Vector3 Local bone rotation in radians
function x_player_api.set_bone_override(player, bone, position, rotation)
	if not player or not player.get_player_name then return end
	local name = player:get_player_name()
	local proxies = x_player_api.get_visual_proxies(player)

	if not proxies then return end

	x_player_api.bone_caches[name] = x_player_api.bone_caches[name] or {}
	x_player_api.bone_caches[name][bone] = x_player_api.bone_caches[name][bone] or {
		position = {x = 0, y = 0, z = 0},
		rotation = {x = 0, y = 0, z = 0}
	}

	local cache = x_player_api.bone_caches[name][bone]

	local pos_x = position and position.x or 0
	local pos_y = position and position.y or 0
	local pos_z = position and position.z or 0
	local rot_x = rotation and rotation.x or 0
	local rot_y = rotation and rotation.y or 0
	local rot_z = rotation and rotation.z or 0

	-- Throttle pitch tracking for "Head" bone using ~0.08 radian (~4.5 degree) delta
	if bone == "Head" then
		local pitch_delta = math.abs(cache.rotation.x - rot_x)
		local yaw_delta = math.abs(cache.rotation.y - rot_y)
		local roll_delta = math.abs(cache.rotation.z - rot_z)

		if pitch_delta < 0.08 and yaw_delta < 0.08 and roll_delta < 0.08 then
			return -- Skip sending packet to proxies
		end
	end

	-- Mutate cache in-place to avoid Lua table allocations on hot loop
	local cp, cr = cache.position, cache.rotation
	cp.x, cp.y, cp.z = pos_x, pos_y, pos_z
	cr.x, cr.y, cr.z = rot_x, rot_y, rot_z

	if x_player_api.is_pure_native_b3d_active and x_player_api.is_pure_native_b3d_active(player) then
		if player.set_bone_override then
			player:set_bone_override(bone, {
				position = {vec = cp, absolute = true},
				rotation = {vec = cr, absolute = true},
			})
		end
		return
	end

	if proxies.glb and proxies.glb:is_valid() then
		proxies.glb:set_bone_override(bone, {
			position = {vec = cp, absolute = true},
			rotation = {vec = cr, absolute = true},
		})
	end
	if proxies.b3d and proxies.b3d:is_valid() then
		proxies.b3d:set_bone_override(bone, {
			position = {vec = cp, absolute = true},
			rotation = {vec = cr, absolute = true},
		})
	end
end

-- Metatable wrapping for set_bone_override is consolidated idempotently in
-- x_player_api.wrap_player_metatable within proxies.lua

core.register_on_leaveplayer(function(player)
	if player then
		x_player_api.bone_caches[player:get_player_name()] = nil
	end
end)

core.register_on_respawnplayer(function(player)
	if player then
		x_player_api.bone_caches[player:get_player_name()] = nil
	end
end)
