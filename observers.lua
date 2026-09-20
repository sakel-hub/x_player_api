-- x_player_api/observers.lua
-- Manages modern and legacy client cohorts.

x_player_api = x_player_api or player_api

---@type table<string, boolean> Map of player names with Luanti 5.17.0+ modern client protocol
x_player_api.modern_cohort = {}

---@type table<string, boolean> Map of player names with legacy client protocol
x_player_api.legacy_cohort = {}

---Check if a connected player is using a modern client supporting glTF multi-track animations
---@nodiscard
---@param player_name string Connected player username
---@return boolean is_modern True if client uses Luanti 5.17.0+ protocol
function x_player_api.is_modern_client(player_name)
	return x_player_api.modern_cohort[player_name] == true
end

---Get the observer cohort set of modern clients
---@nodiscard
---@return table<string, boolean> observers Map of player name to true
function x_player_api.get_modern_observers()
	return x_player_api.modern_cohort
end

---Get the observer cohort set of legacy clients
---@nodiscard
---@return table<string, boolean> observers Map of player name to true
function x_player_api.get_legacy_observers()
	return x_player_api.legacy_cohort
end

---Ensure a player's client protocol cohort has been classified
---@param player_name string Connected player username
function x_player_api.ensure_player_cohort(player_name)
	if x_player_api.modern_cohort[player_name] or x_player_api.legacy_cohort[player_name] then
		return
	end
	local info = core.get_player_information(player_name)
	if not info then
		x_player_api.legacy_cohort[player_name] = true
		return
	end

	-- Check explicit version_string if available (e.g. 5.10.0 client)
	if info.version_string then
		local major, minor = info.version_string:match("^(%d+)%.(%d+)")
		if major and minor then
			local maj = tonumber(major)
			local min = tonumber(minor)
			if maj < 5 or (maj == 5 and min < 12) then
				x_player_api.legacy_cohort[player_name] = true
				return
			else
				x_player_api.modern_cohort[player_name] = true
				return
			end
		end
	end

	local pvers = core.protocol_versions
	local min_protocol = (pvers and (pvers["5.17.0"] or pvers["5.12.0"])) or 44
	if info.protocol_version and info.protocol_version >= min_protocol then
		x_player_api.modern_cohort[player_name] = true
	else
		x_player_api.legacy_cohort[player_name] = true
	end
end

---Refresh observer visibility sets on all active visual proxy entities and wield items across connected players
function x_player_api.refresh_observers()
	local connected = (x_player_api.connected_players and #x_player_api.connected_players > 0
		and x_player_api.connected_players) or core.get_connected_players()
	for i = 1, #connected do
		local player = connected[i]
		local proxies = x_player_api.get_visual_proxies(player)
		local wield_data = x_player_api.wield_entities[player:get_player_name()]
		if proxies then
			local pdata = x_player_api.get_animation(player)
			local model = pdata and x_player_api.get_model(pdata.model)
			local active_format = x_player_api.get_model_format()
			local mesh_glb = (active_format ~= "b3d") and model and (model.mesh_glb
				or (model.mesh and model.mesh:sub(-4) == ".glb" and model.mesh))
			local mesh_b3d = model and ((model.mesh and model.mesh:sub(-4) ~= ".glb" and model.mesh)
				or model.mesh_b3d)

			if active_format == "b3d" or not mesh_glb then
				if proxies.b3d and proxies.b3d:is_valid() then
					proxies.b3d:set_observers(nil)
				end
				if proxies.glb and proxies.glb:is_valid() then
					proxies.glb:set_properties({
						visual_size = {x = 0, y = 0},
						textures = {"blank.png"},
					})
				end
				if wield_data and wield_data.b3d and wield_data.b3d:is_valid() then
					wield_data.b3d:set_observers(nil)
				end
				if wield_data and wield_data.glb and wield_data.glb:is_valid() then
					wield_data.glb:set_properties({
						is_visible = false,
						visual_size = {x = 0, y = 0},
						wield_item = "",
						glow = 0,
					})
				end
			elseif mesh_glb and mesh_b3d then
				if proxies.glb and proxies.glb:is_valid() then
					proxies.glb:set_properties({
						visual_size = model.visual_size or {x = 1, y = 1},
					})
					proxies.glb:set_observers(x_player_api.modern_cohort)
				end
				if proxies.b3d and proxies.b3d:is_valid() then
					proxies.b3d:set_properties({
						visual_size = model.visual_size or {x = 1, y = 1},
					})
					proxies.b3d:set_observers(x_player_api.legacy_cohort)
				end
				if wield_data then
					if wield_data.glb and wield_data.glb:is_valid() then
						wield_data.glb:set_observers(x_player_api.modern_cohort)
					end
					if wield_data.b3d and wield_data.b3d:is_valid() then
						wield_data.b3d:set_observers(x_player_api.legacy_cohort)
					end
				end
			elseif mesh_glb then
				if proxies.glb and proxies.glb:is_valid() then
					proxies.glb:set_observers(nil)
				end
				if wield_data and wield_data.glb and wield_data.glb:is_valid() then
					wield_data.glb:set_observers(nil)
				end
				if wield_data and wield_data.b3d and wield_data.b3d:is_valid() then
					wield_data.b3d:set_properties({
						is_visible = false,
						visual_size = {x = 0, y = 0},
						wield_item = "",
						glow = 0,
					})
				end
			end
		end
	end
end

core.register_on_joinplayer(function(player)
	if not player then return end
	local name = player:get_player_name()
	x_player_api.ensure_player_cohort(name)
	x_player_api.refresh_observers()
end)

core.register_on_leaveplayer(function(player)
	if not player then return end
	local name = player:get_player_name()
	x_player_api.modern_cohort[name] = nil
	x_player_api.legacy_cohort[name] = nil
	x_player_api.refresh_observers()
end)
