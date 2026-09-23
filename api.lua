---@class Vector2
---@field x number
---@field y number

---@class Vector3
---@field x number
---@field y number
---@field z number

---@class PlayerAnimationData
---@field model string|nil Active model mesh filename
---@field textures string[]|nil Active applied texture filenames
---@field animation string|nil Current active locomotion animation name
---@field animation_b3d string|nil Current active B3D single-timeline animation name
---@field animation_speed number|nil Current animation playback speed
---@field animation_loop boolean|nil Whether current animation is looping

---@class EquipSoundDefinition
---@field sound string|table Sound name string or SimpleSoundSpec table
---@field gain? number Playback gain/volume (default: 0.7)
---@field pitch? number Playback pitch multiplier (default: 1.0)
---@field pitch_variance? number Pitch randomization variance range +/- (default: 0.06, set 0 to disable)
---@field max_hear_distance? number Maximum hearing distance (default: 16)

---@alias ModelRedirectRule string|fun(player: ObjectRef|nil, model: string): string|nil
---
---@class x_player_api
---@field registered_models table<string, ModelDefinition> Registry of model definitions by name
---@field model_redirects table<string, ModelRedirectRule> Model redirection rules
---@field animation_aliases table<string, string> Semantic animation alias dictionary
---@field player_attached table<string, boolean> Attachment state map for connected players
---@field _players table<string, PlayerAnimationData> Internal per-player animation data map
---@field _callbacks_registered? boolean Internal flag for registered engine callbacks
---@field _wrappers_applied? boolean Internal flag for API safety wrappers
---@field _modpath_hooked? boolean Internal flag for modpath interception
---@field _join_registered? boolean Internal flag for player join handler
---@field model_format string Currently active player model format ("glb" or "b3d")
---@field active_proxies? table<string, PlayerProxies> Active visual proxy entity instances by player name
---@field modern_cohort? table<string, boolean> Observer set of players connected with 5.17.0+ protocol
---@field legacy_cohort? table<string, boolean> Observer set of players connected with legacy protocol
---@field bone_caches? table<string, table<string, BoneOverride>> Cached bone transformations for network throttling
---@field controls? PlayerControlsSubsystem Locomotion controls and state evaluation subsystem
---@field registered_consumables? table<string, ConsumableDefinition> Registry of consumable items
---@field registered_particle_generators? table<string, ParticleGeneratorFunc> Registry of eating particle generators
---@field enable_eating? boolean Whether eating simulation is active
---@field enable_wield_item? boolean Whether 3D wielded item rendering is active
---@field enable_equip_sound? boolean Whether declarative equip sounds are active
---@field equip_sounds? table<string, string|EquipSoundDefinition|boolean> Sound definition lookup cache
---@field registered_equip_sounds table<string, string|EquipSoundDefinition|boolean> Registry of equip sound definitions
---@field wield_item_offsets? WieldOffsetsRegistry Custom 3D wield item transform registry
---@field wield_entities? table<string, WieldItemEntityData> Active wield item entity tracking state
---@field register_equip_sound? fun(target: string, sound_def: string|EquipSoundDefinition|boolean)
---@field get_equip_sound? fun(item_name: string): EquipSoundDefinition|nil
---@field play_equip_sound? fun(player: ObjectRef, item_name?: string): any
---@field trigger_equip? fun(player: ObjectRef, item_name?: string, duration?: number): boolean
---@field clear_equip_sound_cache? fun(item_name?: string)
---@field clear_consumable_cache? fun(item_name?: string)
---@field is_consumable? fun(item_name?: string): boolean
---@field trigger_eat? fun(player: ObjectRef, duration?: number, item_name?: string)
---@field cancel_eat? fun(player: ObjectRef): boolean
---@field spawn_eat_particles? fun(p: ObjectRef, item?: string, dur?: number, ptype?: string): integer|nil
---@field get_wield_item_visibility? fun(player: ObjectRef): boolean
---@field set_wield_item_visibility? fun(player: ObjectRef, visible: boolean)
---@field wiggle_b3d_data? fun(data: string): string, integer, integer
---@field scan_and_wiggle_b3d_model? fun(mesh_name: string, full_path?: string): string
---@field scan_and_wiggle_registered_b3d_models? fun()

---@class player_api : x_player_api
x_player_api = rawget(_G, "x_player_api") or rawget(_G, "player_api") or {}
player_api = x_player_api
rawset(_G, "x_player_api", x_player_api)
rawset(_G, "player_api", x_player_api)

-- Hook get_modpath to alias player_api <-> x_player_api bidirectionally if one is missing
if not x_player_api._modpath_hooked then
	x_player_api._modpath_hooked = true
	local orig_get_modpath = core.get_modpath
	function core.get_modpath(name)
		if name == "player_api" and not orig_get_modpath("player_api") then
			return orig_get_modpath("x_player_api")
		elseif name == "x_player_api" and not orig_get_modpath("x_player_api") then
			return orig_get_modpath("player_api")
		end
		return orig_get_modpath(name)
	end
end

---@type Vector2 Animation frame range with zero duration
local ZERO_RANGE = {x = 0, y = 0}

---@type table<string, PlayerAnimationData> Internal map of per-player state tables
x_player_api._players = x_player_api._players or {}
---@type table<string, PlayerAnimationData>
local players = x_player_api._players

---@type table<string, boolean> Map of player attachment states
x_player_api.player_attached = x_player_api.player_attached or {}
---@type table<string, boolean>
local player_attached = x_player_api.player_attached

---@type ObjectRef[] Locally maintained array of connected players for zero-allocation tick iteration
x_player_api.connected_players = x_player_api.connected_players or {}

---Get or initialize internal player state data table
---@nodiscard
---@param player ObjectRef Target player
---@return PlayerAnimationData data Player animation and model data table
local function get_player_data(player)
	local name = player:get_player_name()
	local data = players[name]
	if not data then
		data = {}
		players[name] = data
	end
	return data
end
x_player_api.get_player_data = get_player_data

---Determine the texture filename or modifier string for an item
---@nodiscard
---@param iname string Item name
---@return string|nil texture Texture name or modifier string
function x_player_api.get_item_texture(iname)
	if not iname or iname == "" then
		return nil
	end

	local def = core.registered_items[iname]
	if def then
		if type(def.inventory_image) == "string" and def.inventory_image ~= "" then
			return def.inventory_image
		elseif type(def.inventory_image) == "table" and def.inventory_image.name
			and def.inventory_image.name ~= "" then
			return def.inventory_image.name
		end

		if type(def.wield_image) == "string" and def.wield_image ~= "" then
			return def.wield_image
		elseif type(def.wield_image) == "table" and def.wield_image.name
			and def.wield_image.name ~= "" then
			return def.wield_image.name
		end

		if type(def.tiles) == "table" and #def.tiles > 0 then
			local t = def.tiles[1]
			if type(t) == "string" and t ~= "" then
				return t
			elseif type(t) == "table" and t.name and t.name ~= "" then
				return t.name
			end
		end
	end

	if core.registered_aliases[iname] then
		local alias_target = core.registered_aliases[iname]
		if alias_target and alias_target ~= iname then
			return x_player_api.get_item_texture(alias_target)
		end
	end

	return nil
end

---Get current animation data for player
---@nodiscard
---@param player ObjectRef Target player
---@return PlayerAnimationData animation_data Active animation and model metadata
function x_player_api.get_animation(player)
	local player_data = get_player_data(player)
	return {
		model = player_data.model,
		textures = player_data.textures,
		animation = player_data.animation,
		animation_b3d = player_data.animation_b3d,
		animation_speed = player_data.animation_speed,
		animation_loop = player_data.animation_loop,
		override_local = player_data.override_local,
	}
end

-- Configuration methods
---@type "glb"|"b3d" Currently active player model format preference
local cfg_format = core.settings:get("x_player_api.model_format")
x_player_api.model_format = (cfg_format == "b3d" or cfg_format == "glb") and cfg_format or "glb"

---@type boolean Whether pure native B3D rendering is enabled (bypassing visual proxies in B3D mode)
x_player_api.pure_native_b3d = core.settings:get_bool("x_player_api.pure_native_b3d", false)

---Get active global model format preferred by the server
---@nodiscard
---@return "glb"|"b3d" format Preferred model format ("glb" or "b3d")
function x_player_api.get_model_format() return x_player_api.model_format end

---Check whether pure native B3D mode is currently active for a player/session
---@nodiscard
---@param player? ObjectRef Target player (optional)
---@param target_model_name? string Optional specific model name being resolved
---@return boolean is_active
function x_player_api.is_pure_native_b3d_active(player, target_model_name)
	if not x_player_api.pure_native_b3d then
		return false
	end
	if x_player_api.get_model_format() ~= "b3d" then
		return false
	end
	local model_name = target_model_name or (player and x_player_api.get_model_name(player))
	if model_name then
		local model = x_player_api.get_model(model_name)
		if model and model.mesh and model.mesh:match("%.glb$") and not model.mesh_b3d then
			return false
		end
	end
	return true
end

---Set active global model format preferred by the server
---@param format "glb"|"b3d" Preferred model format
---@return boolean success Whether format was accepted
---@return string? error_or_format Error message on failure, or confirmed format on success
function x_player_api.set_model_format(format)
	if format ~= "glb" and format ~= "b3d" then
		return false, "Invalid format"
	end
	x_player_api.model_format = format
	x_player_api.clear_wield_params_cache()
	local def_model = x_player_api.get_default_model()
	local connected = (core._connected_players and #core._connected_players > 0 and core._connected_players)
		or (x_player_api.connected_players and #x_player_api.connected_players > 0 and x_player_api.connected_players)
		or core.get_connected_players()
	for i = 1, #connected do
		local p = connected[i]
		local pdata = x_player_api.get_animation(p)
		if pdata then
			if pdata.model == "character.glb" or pdata.model == "character.b3d" or pdata.model == "character" then
				x_player_api.set_model(p, def_model)
			else
				x_player_api.set_model(p, pdata.model)
			end
		end
		x_player_api.update_wield_item(p, true)
	end
	x_player_api.refresh_observers()
	return true, format
end

---Set pure native B3D mode
---@param enable boolean Whether to enable pure native B3D mode
function x_player_api.set_pure_native_b3d(enable)
	x_player_api.pure_native_b3d = not not enable
	local def_model = x_player_api.get_default_model()
	local connected = (core._connected_players and #core._connected_players > 0 and core._connected_players)
		or (x_player_api.connected_players and #x_player_api.connected_players > 0 and x_player_api.connected_players)
		or core.get_connected_players()
	for i = 1, #connected do
		local p = connected[i]
		local pdata = x_player_api.get_animation(p)
		if pdata then
			if pdata.model == "character.glb" or pdata.model == "character.b3d" or pdata.model == "character" then
				x_player_api.set_model(p, def_model)
			else
				x_player_api.set_model(p, pdata.model)
			end
		end
		x_player_api.update_wield_item(p, true)
	end
	x_player_api.refresh_observers()
end

---Apply model redirects (deprecated no-op hook maintained for legacy backwards compatibility)
---@deprecated Handled dynamically by resolve_model and set_model
function x_player_api.apply_model_redirects() end

---Get default player model definition
---@nodiscard
---@return string model_name Default resolved model identifier ("character")
function x_player_api.get_default_model() return x_player_api.resolve_model(nil, "character") end

---Update player model and reset appearance/animations
---@param player ObjectRef Target player
---@param model_name string Target model filename
function x_player_api.set_model(player, model_name)
	model_name = x_player_api.resolve_model(player, model_name)
	local is_pure_b3d = x_player_api.is_pure_native_b3d_active(player, model_name)
	local player_data = get_player_data(player)
	local current_model = x_player_api.get_model(model_name)
	local current_proxies = x_player_api.get_visual_proxies(player)

	if player_data.model == model_name then
		-- Self-healing verification: check whether player or proxy properties match active model
		local needs_healing = false
		local active_format = x_player_api.get_model_format()
		if player_data.pure_native_b3d ~= is_pure_b3d then
			needs_healing = true
		elseif current_model then
			local exp_mesh_glb = (active_format ~= "b3d") and (current_model.mesh_glb
				or (current_model.mesh and current_model.mesh:match("%.glb$") and current_model.mesh))
			local exp_mesh_b3d = (current_model.mesh and not current_model.mesh:match("%.glb$")
				and current_model.mesh) or current_model.mesh_b3d

			if is_pure_b3d and exp_mesh_b3d then
				local pprops = player:get_properties()
				if not pprops or pprops.mesh ~= exp_mesh_b3d or (pprops.visual_size and pprops.visual_size.x == 0)
					or pprops.use_texture_alpha == true or pprops.is_visible == false then
					needs_healing = true
				end
			elseif current_proxies then
				if current_proxies.glb and current_proxies.glb:is_valid() then
					local props = current_proxies.glb:get_properties()
					if exp_mesh_glb then
						if props and (props.mesh ~= exp_mesh_glb or (props.visual_size and props.visual_size.x == 0)
							or props.is_visible == false) then
							needs_healing = true
						end
					else
						if props and props.visual_size and props.visual_size.x ~= 0 then
							needs_healing = true
						end
					end
				end
				if current_proxies.b3d and current_proxies.b3d:is_valid() then
					local props = current_proxies.b3d:get_properties()
					if exp_mesh_b3d then
						if props and (props.mesh ~= exp_mesh_b3d or (props.visual_size and props.visual_size.x == 0)
							or props.is_visible == false) then
							needs_healing = true
						end
					else
						if props and props.visual_size and props.visual_size.x ~= 0 then
							needs_healing = true
						end
					end
				end
			end
		end
		if not needs_healing then
			return
		end
	end

	player_data.model = model_name
	player_data.pure_native_b3d = is_pure_b3d
	player_data.animation, player_data.animation_b3d = nil, nil
	player_data.animation_speed, player_data.animation_loop = nil, nil
	player_data.animation_b3d_speed, player_data.animation_b3d_loop = nil, nil
	player_data.action = nil

	local model = current_model
	local proxies = current_proxies

	if model and proxies then
		player:stop_animation()

		local textures = player_data.textures or model.textures or {"character.png"}
		if model.textures and #model.textures > #textures then
			local padded = table.copy(textures)
			for i = #textures + 1, #model.textures do
				padded[i] = model.textures[i] or "blank.png"
			end
			textures = padded
		end
		player_data.textures = textures

		local active_format = x_player_api.get_model_format()
		local mesh_glb = (active_format ~= "b3d") and (model.mesh_glb
			or (model.mesh and model.mesh:match("%.glb$") and model.mesh))
		local mesh_b3d = (model.mesh and not model.mesh:match("%.glb$") and model.mesh) or model.mesh_b3d

		if is_pure_b3d and mesh_b3d then
			-- In pure native B3D mode: mesh & textures apply directly to native player entity
			player:set_properties({
				visual = "mesh",
				mesh = mesh_b3d,
				textures = textures,
				visual_size = model.visual_size or {x = 1, y = 1},
				collisionbox = model.collisionbox,
				stepheight = model.stepheight,
				eye_height = model.eye_height,
				use_texture_alpha = false,
				is_visible = true,
			})
			if proxies.glb and proxies.glb:is_valid() then
				proxies.glb:set_properties({visual_size = {x = 0, y = 0}, textures = {"blank.png"}})
			end
			if proxies.b3d and proxies.b3d:is_valid() then
				proxies.b3d:set_properties({visual_size = {x = 0, y = 0}, textures = {"blank.png"}})
			end
			local anims = model.animations or {}
			local stand = anims.stand and {x = anims.stand.x, y = anims.stand.y} or ZERO_RANGE
			local walk = anims.walk and {x = anims.walk.x, y = anims.walk.y} or ZERO_RANGE
			local mine = anims.mine and {x = anims.mine.x, y = anims.mine.y} or ZERO_RANGE
			local walk_mine = anims.walk_mine and {x = anims.walk_mine.x, y = anims.walk_mine.y} or ZERO_RANGE
			player:set_local_animation(stand, walk, mine, walk_mine, model.animation_speed or 30)
			player_data.local_anim_silenced = false
		else
			if proxies.glb and proxies.glb:is_valid() and mesh_glb then
				proxies.glb:set_properties({
					mesh = mesh_glb,
					textures = textures,
					visual_size = model.visual_size or {x = 1, y = 1},
					is_visible = true,
				})
			elseif proxies.glb and proxies.glb:is_valid() then
				proxies.glb:set_properties({
					visual_size = {x = 0, y = 0},
					textures = {"blank.png"}
				})
			end

			if proxies.b3d and proxies.b3d:is_valid() and mesh_b3d then
				proxies.b3d:set_properties({
					mesh = mesh_b3d,
					textures = textures,
					visual_size = model.visual_size or {x = 1, y = 1},
					is_visible = true,
				})
			elseif proxies.b3d and proxies.b3d:is_valid() then
				proxies.b3d:set_properties({
					visual_size = {x = 0, y = 0},
					textures = {"blank.png"}
				})
			end

			local wield_data = x_player_api.wield_entities[player:get_player_name()]
			if active_format == "b3d" or not mesh_glb then
				-- In B3D format or B3D-only model: route B3D proxy and wield entity to ALL observers
				if proxies.b3d and proxies.b3d:is_valid() then
					proxies.b3d:set_observers(nil)
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
				-- Dual model in GLB mode: modern clients observe GLB proxy, legacy observe B3D
				if proxies.glb and proxies.glb:is_valid() then
					proxies.glb:set_observers(x_player_api.get_modern_observers())
				end
				if proxies.b3d and proxies.b3d:is_valid() then
					proxies.b3d:set_observers(x_player_api.get_legacy_observers())
				end
				if wield_data then
					if wield_data.glb and wield_data.glb:is_valid() then
						wield_data.glb:set_observers(x_player_api.get_modern_observers())
					end
					if wield_data.b3d and wield_data.b3d:is_valid() then
						wield_data.b3d:set_observers(x_player_api.get_legacy_observers())
					end
				end
			elseif mesh_glb then
				-- GLB-only model
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

			player:set_properties({
				collisionbox = model.collisionbox,
				stepheight = model.stepheight,
				eye_height = model.eye_height,
			})

			-- Silence client-side local animation prediction on the invisible native player entity
			player:set_local_animation(ZERO_RANGE, ZERO_RANGE, ZERO_RANGE, ZERO_RANGE, 0)
		end

		x_player_api.set_animation(player, "stand")
		x_player_api.set_wield_item_visibility(player, true)
	else
		-- Hide proxies if no model
		if proxies then
			if proxies.glb and proxies.glb:is_valid() then
				proxies.glb:set_properties({visual_size = {x = 0, y = 0}, textures = {"blank.png"}})
			end
			if proxies.b3d and proxies.b3d:is_valid() then
				proxies.b3d:set_properties({visual_size = {x = 0, y = 0}, textures = {"blank.png"}})
			end
		end
		player:set_properties({
			collisionbox = {-0.3, 0.0, -0.3, 0.3, 1.75, 0.3},
			stepheight = 0.6,
			eye_height = 1.625,
		})
		x_player_api.set_wield_item_visibility(player, false)
	end
end

---Get current textures assigned to player
---@nodiscard
---@param player ObjectRef Target player
---@return string[] textures List of applied texture filenames
function x_player_api.get_textures(player)
	local player_data = get_player_data(player)
	local model = x_player_api.get_model(player_data.model)
	return player_data.textures or (model and model.textures) or {"character.png"}
end

---Get current model name assigned to player
---@nodiscard
---@param player ObjectRef Target player
---@return string model_name
function x_player_api.get_model_name(player)
	local player_data = get_player_data(player)
	return player_data.model or "character.b3d"
end

---Set textures for player
---@param player ObjectRef Target player
---@param textures string[] List of texture filenames
function x_player_api.set_textures(player, textures)
	local player_data = get_player_data(player)
	local model = x_player_api.get_model(player_data.model)
	local new_textures = textures or (model and model.textures) or {"character.png"}

	-- Pad texture slots to match model mesh material count if fewer textures were supplied
	if model and model.textures and #model.textures > #new_textures then
		local padded = table.copy(new_textures)
		for i = #new_textures + 1, #model.textures do
			padded[i] = model.textures[i] or "blank.png"
		end
		new_textures = padded
	end

	player_data.textures = new_textures

	local proxies = x_player_api.get_visual_proxies(player)
	if model then
		if x_player_api.is_pure_native_b3d_active(player) then
			player:set_properties({textures = new_textures})
		elseif proxies then
			local mesh_glb = model.mesh_glb or (model.mesh and model.mesh:match("%.glb$") and model.mesh)
			local mesh_b3d = (model.mesh and not model.mesh:match("%.glb$") and model.mesh) or model.mesh_b3d
			if proxies.glb and proxies.glb:is_valid() and mesh_glb then
				proxies.glb:set_properties({textures = new_textures})
			end
			if proxies.b3d and proxies.b3d:is_valid() and mesh_b3d then
				proxies.b3d:set_properties({textures = new_textures})
			end
		end
	end
end

---Set a single texture layer by index
---@param player ObjectRef Target player
---@param index integer 1-based texture slot index
---@param texture string Texture filename or modifier string
function x_player_api.set_texture(player, index, texture)
	local textures = table.copy(x_player_api.get_textures(player))
	textures[index] = texture
	x_player_api.set_textures(player, textures)
end

---@type table<string, string> Semantic animation alias dictionary
x_player_api.animation_aliases = x_player_api.animation_aliases or {
	die = "lay",
	death = "lay",
	sleep = "lay",
	duck_std = "crouch",
	duck = "crouch_walk",
	sneak = "crouch",
	sneak_stand = "crouch",
	sneak_walk = "crouch_walk",
	sneak_mine = "mine",
	sneak_walk_mine = "walk_mine",
	run = "sprint",
	running = "sprint",
	run_walk = "sprint",
	run_walk_mine = "walk_mine",
	dig = "mine",
	chop = "mine",
	punch = "attack_slash",
	slash = "attack_slash",
	thrust = "attack_thrust",
	stab = "attack_thrust",
	lunge = "attack_thrust",
	shield = "block",
	defend = "block",
	aim = "bow_aim",
	shoot = "bow_shoot",
	drink = "eat",
	consume = "eat",
	ride = "sit",
	mount = "sit",
	glide = "fly",
	spin = "attack_slash",
	spin_attack = "attack_slash",
	tumble = "slide",
	roll = "slide",
	cast = "attack_thrust",
	fish = "attack_slash",
	throw = "attack_slash",
	crawl = "crouch_walk",
	crawling = "crouch_walk",
	prone = "lay",
	salute = "point",
	clap = "cheer",
	dance = "cheer",
	shrug = "stand",
	facepalm = "stand",
}

---Register an animation alias
---@param alias string Semantic alias
---@param target string Canonical animation track identifier
function x_player_api.register_animation_alias(alias, target)
	x_player_api.animation_aliases[alias] = target
end

---Set active animation for player
---Set animation on player ObjectRef, synchronizing visual proxies
---@param player ObjectRef Target player
---@param anim_name string Animation identifier for GLB proxy (locomotion layer in multitrack)
---@param speed? number Playback speed (defaults to model's animation_speed)
---@param loop_or_blend? boolean|number Whether to loop playback (boolean) or transition blend time in seconds (number)
---@param override_local? boolean Whether local client animation prediction should be overridden
---@param anim_name_b3d? string|boolean Optional animation ID for B3D proxy, or false to skip B3D
function x_player_api.set_animation(player, anim_name, speed, loop_or_blend, override_local, anim_name_b3d)
	anim_name = x_player_api.animation_aliases[anim_name] or anim_name
	local player_data = get_player_data(player)
	local model = x_player_api.get_model(player_data.model)
	if not model then return end

	local skip_b3d = (anim_name_b3d == false)
	local b3d_target
	local anim_b3d
	if not skip_b3d then
		b3d_target = anim_name_b3d or anim_name
		b3d_target = x_player_api.animation_aliases[b3d_target] or b3d_target
		anim_b3d = model.animations and model.animations[b3d_target]
	end

	local anim_glb = model.animations_glb and model.animations_glb[anim_name]

	local base_fps = model.animation_speed or 30
	if speed == nil then speed = base_fps end

	local loop
	local animation_blend
	if type(loop_or_blend) == "boolean" then
		loop = loop_or_blend
	elseif type(loop_or_blend) == "number" then
		animation_blend = loop_or_blend
	end
	if loop == nil then
		if anim_glb and anim_glb.loop ~= nil then loop = anim_glb.loop
		elseif anim_b3d and anim_b3d.loop ~= nil then loop = anim_b3d.loop
		else loop = true end
	end

	local loop_b3d = loop
	if anim_b3d and anim_b3d.loop ~= nil then
		loop_b3d = anim_b3d.loop
	end

	local blend_glb
	local blend_b3d
	if animation_blend ~= nil then
		blend_glb = animation_blend
		blend_b3d = animation_blend
	else
		blend_glb = (anim_glb and anim_glb.blend) or 0.15
		blend_b3d = (anim_b3d and anim_b3d.blend) or 0
	end
	if not skip_b3d and player_data.animation_b3d == nil and player_data.animation == anim_name then
		blend_b3d = 0
	end

	if skip_b3d then
		if player_data.animation == anim_name
			and player_data.animation_speed == speed
			and player_data.animation_loop == loop
			and (override_local == nil or player_data.override_local == override_local)
		then
			return
		end
	else
		if player_data.animation == anim_name
			and player_data.animation_b3d == b3d_target
			and player_data.animation_speed == speed
			and player_data.animation_loop == loop
			and player_data.animation_b3d_loop == loop_b3d
			and (override_local == nil or player_data.override_local == override_local)
		then
			return
		end
	end

	local prev_anim_name = player_data.animation
	player_data.animation = anim_name
	if not skip_b3d then
		player_data.animation_b3d = b3d_target
		player_data.animation_b3d_loop = loop_b3d
	end
	player_data.animation_speed = speed
	player_data.animation_loop = loop

	-- Calculate proper speed for B3D (FPS) vs GLB (multiplier / seconds per second)
	local speed_factor = 1.0
	if speed > 2.0 and base_fps > 0 then
		speed_factor = speed / base_fps
	elseif speed <= 2.0 and speed >= 0 then
		speed_factor = speed
	end

	local speed_glb = speed_factor * (anim_glb and anim_glb.speed or 1.0)
	local speed_b3d = (speed <= 2.0 and (speed * base_fps) or speed) * (anim_b3d and anim_b3d.speed or 1.0)
	if speed == 0 then
		loop = false
		loop_b3d = false
	end
	if not skip_b3d then
		player_data.animation_b3d_speed = speed_b3d
		player_data.animation_b3d_loop = loop_b3d
	end

	local eff_override_local = override_local
	if eff_override_local == nil and anim_glb then
		eff_override_local = anim_glb.override_local
	end
	if eff_override_local == nil and anim_b3d then
		eff_override_local = anim_b3d.override_local
	end
	if eff_override_local == nil and model then
		eff_override_local = model.override_local
	end
	player_data.override_local = eff_override_local

	local proxies = x_player_api.get_visual_proxies(player)
	local is_pure_b3d = x_player_api.is_pure_native_b3d_active(player)
	if is_pure_b3d then
		local anim_override = (override_local ~= nil and override_local)
			or (anim_b3d and anim_b3d.override_local)
			or (anim_glb and anim_glb.override_local)
		local is_standard_local = (anim_name == "stand" or anim_name == "walk"
			or anim_name == "mine" or anim_name == "walk_mine") and not anim_override
		if is_standard_local then
			local a = model.animations or {}
			player:set_local_animation(
				a.stand and {x=a.stand.x, y=a.stand.y} or ZERO_RANGE,
				a.walk and {x=a.walk.x, y=a.walk.y} or ZERO_RANGE,
				a.mine and {x=a.mine.x, y=a.mine.y} or ZERO_RANGE,
				a.walk_mine and {x=a.walk_mine.x, y=a.walk_mine.y} or ZERO_RANGE,
				model.animation_speed or 30
			)
			player_data.local_anim_silenced = false
		else
			player:set_local_animation(ZERO_RANGE, ZERO_RANGE, ZERO_RANGE, ZERO_RANGE, 0)
			player_data.local_anim_silenced = true
		end
	elseif proxies or eff_override_local or (model.animations and (model.animations.jump or model.animations.fall)) then
		player:set_local_animation(ZERO_RANGE, ZERO_RANGE, ZERO_RANGE, ZERO_RANGE, 0)
	else
		local a = model.animations or {}
		player:set_local_animation(
			a.stand and {x=a.stand.x, y=a.stand.y} or ZERO_RANGE,
			a.walk and {x=a.walk.x, y=a.walk.y} or ZERO_RANGE,
			a.mine and {x=a.mine.x, y=a.mine.y} or ZERO_RANGE,
			a.walk_mine and {x=a.walk_mine.x, y=a.walk_mine.y} or ZERO_RANGE,
			model.animation_speed or 30
		)
	end

	if proxies then
		if proxies.glb and proxies.glb:is_valid() then
			local track_name = anim_glb and (anim_glb.track or anim_name)
			local prev_anim_glb = prev_anim_name and model.animations_glb and model.animations_glb[prev_anim_name]
			local prev_track = prev_anim_glb and (prev_anim_glb.track or prev_anim_name) or prev_anim_name
			if (prev_anim_name == anim_name or prev_track == track_name) and track_name then
				-- Same track is already playing; update speed seamlessly without restarting from frame 0
				if proxies.glb.update_animation then
					proxies.glb:update_animation(track_name, {speed = speed_glb})
				end
			else
				if prev_track and proxies.glb.stop_animation then
					proxies.glb:stop_animation(prev_track)
				end
				if anim_glb and proxies.glb.play_animation and track_name then
					proxies.glb:play_animation(track_name, {
						speed = speed_glb,
						loop = loop,
						priority = anim_glb.priority or 0,
						blend = blend_glb,
					})
				end
			end
		end
		if not skip_b3d and proxies.b3d and proxies.b3d:is_valid() and anim_b3d then
			if anim_b3d.x and anim_b3d.y then
				proxies.b3d:set_animation(anim_b3d, speed_b3d, blend_b3d, loop_b3d)
			end
		end
	end

	-- Synchronize skeletal bone animation on native player ObjectRef so attached child entities
	-- (such as 3D wield items, shields, and armor pieces) swing and animate in lockstep with proxies
	if not skip_b3d and anim_b3d and anim_b3d.x and anim_b3d.y then
		player:set_animation(anim_b3d, speed_b3d, blend_b3d, loop_b3d)
	end

	local eff_collision = (anim_glb and anim_glb.collisionbox)
		or (anim_b3d and anim_b3d.collisionbox) or model.collisionbox
	local eff_eye_height = (anim_glb and anim_glb.eye_height)
		or (anim_b3d and anim_b3d.eye_height) or model.eye_height
	player:set_properties({
		collisionbox = eff_collision,
		eye_height = eff_eye_height,
	})
end

---Play an action animation directly on a player
---@param player ObjectRef Target player
---@param action? string Action animation track name or nil to stop active action
---@param force? boolean Force replay even if the action is already active
---@param skip_b3d? boolean When true, skip updating B3D proxy and player entity (used in globalstep)
function x_player_api.play_action(player, action, force, skip_b3d)
	local player_data = get_player_data(player)
	local model = x_player_api.get_model(player_data.model)
	if not model then return end

	local active_format = x_player_api.get_model_format()
	local proxies = x_player_api.get_visual_proxies(player)
	local anim_glb = action and model.animations_glb and model.animations_glb[action]
	local anim_b3d = action and model.animations and model.animations[action]

	if action and (anim_glb or anim_b3d) then
		if force or player_data.action ~= action then
			if player_data.action and proxies and proxies.glb and proxies.glb:is_valid() and proxies.glb.stop_animation then
				local prev_act = model.animations_glb and model.animations_glb[player_data.action]
				local prev_track = (prev_act and prev_act.track) or player_data.action
				proxies.glb:stop_animation(prev_track)
			end
			player_data.action = action

			-- Play on GLB proxy if modern multitrack GLB is active
			if model.is_multitrack and active_format ~= "b3d" and anim_glb
					and proxies and proxies.glb and proxies.glb:is_valid() and proxies.glb.play_animation then
				proxies.glb:play_animation(anim_glb.track or action, {
					speed = anim_glb.speed or 1.0,
					loop = anim_glb.loop ~= false,
					priority = anim_glb.priority or 1,
					blend = anim_glb.blend or 0.1,
				})
			end

			-- Play on B3D proxy and native player entity
			if not skip_b3d and anim_b3d and anim_b3d.x and anim_b3d.y then
				local base_fps = model.animation_speed or 30
				local speed_b3d = base_fps * (anim_b3d.speed or 1.0)
				local loop_b3d = anim_b3d.loop ~= false
				local blend_b3d = anim_b3d.blend or 0
				if proxies and proxies.b3d and proxies.b3d:is_valid() then
					proxies.b3d:set_animation(anim_b3d, speed_b3d, blend_b3d, loop_b3d)
				end
				player:set_animation(anim_b3d, speed_b3d, blend_b3d, loop_b3d)
				player_data.animation_b3d = action
				player_data.animation_b3d_speed = speed_b3d
				player_data.animation_b3d_loop = loop_b3d
			end
		end
	else
		if player_data.action then
			if proxies and proxies.glb and proxies.glb:is_valid() and proxies.glb.stop_animation then
				local prev_act = model.animations_glb and model.animations_glb[player_data.action]
				local prev_track = (prev_act and prev_act.track) or player_data.action
				proxies.glb:stop_animation(prev_track)
			end
			player_data.action = nil

			-- Restore base locomotion on B3D proxy and player entity
			if not skip_b3d then
				local loco = player_data.animation or "stand"
				local loco_b3d = model.animations and model.animations[loco]
				if loco_b3d and loco_b3d.x and loco_b3d.y then
					local base_fps = model.animation_speed or 30
					local speed_b3d = (player_data.animation_speed or base_fps) * (loco_b3d.speed or 1.0)
					local loop_b3d = loco_b3d.loop ~= false
					local blend_b3d = loco_b3d.blend or 0
					if proxies and proxies.b3d and proxies.b3d:is_valid() then
						proxies.b3d:set_animation(loco_b3d, speed_b3d, blend_b3d, loop_b3d)
					end
					player:set_animation(loco_b3d, speed_b3d, blend_b3d, loop_b3d)
					player_data.animation_b3d = loco
					player_data.animation_b3d_speed = speed_b3d
					player_data.animation_b3d_loop = loop_b3d
				end
			end
		end
	end
end

if not x_player_api._callbacks_registered then
	x_player_api._callbacks_registered = true

	core.register_on_joinplayer(function(player)
		local name = player:get_player_name()
		players[name] = {}
		x_player_api.player_attached[name] = false
		local cp = x_player_api.connected_players
		for i = #cp, 1, -1 do
			local p = cp[i]
			if not p or not p:is_player() or p:get_player_name() == name or p == player then
				table.remove(cp, i)
			end
		end
		cp[#cp + 1] = player
	end)

	core.register_on_leaveplayer(function(player)
		local name = player:get_player_name()
		players[name] = nil
		x_player_api.player_attached[name] = nil
		local cp = x_player_api.connected_players
		for i = #cp, 1, -1 do
			local p = cp[i]
			if not p or p == player or p:get_player_name() == name then
				table.remove(cp, i)
			end
		end
	end)

	local old_calculate_knockback = core.calculate_knockback
	if old_calculate_knockback then
		function core.calculate_knockback(player, ...)
			if player and player:is_player() and (player_attached[player:get_player_name()]
				or (player:get_attach() ~= nil)) then
				return 0
			end
			return old_calculate_knockback(player, ...)
		end
	end

	local parent_has_step = core.get_modpath("player_api") and
		(core.get_modpath("player_api") ~= core.get_modpath("x_player_api"))
	if not parent_has_step then
		core.register_globalstep(function(...)
			x_player_api.globalstep(...)
		end)
	end
end

x_player_api._wield_unified_active = true

---Check each player and apply animations
---@param dtime number Delta time in seconds since last server step
function x_player_api.globalstep(dtime)
	local time_now = core.get_us_time() * 0.000001
	local is_throttled_wield = false
	if x_player_api.enable_wield_item then
		x_player_api._wield_timer = (x_player_api._wield_timer or 0) + dtime
		local interval = x_player_api.WIELD_UPDATE_INTERVAL or 0.2
		if x_player_api._wield_timer >= interval then
			x_player_api._wield_timer = 0
			is_throttled_wield = true
		end
	end

	-- Low-frequency server garbage collector for disconnected player proxies
	x_player_api._proxy_gc_timer = (x_player_api._proxy_gc_timer or 0) + dtime
	if x_player_api._proxy_gc_timer >= 3.0 then
		x_player_api._proxy_gc_timer = 0
		if x_player_api.cleanup_orphaned_proxies then
			x_player_api.cleanup_orphaned_proxies()
		end
	end

	local connected = (core._connected_players and #core._connected_players > 0 and core._connected_players)
		or (x_player_api.connected_players and #x_player_api.connected_players > 0 and x_player_api.connected_players)
		or core.get_connected_players()
	for i = 1, #connected do
		local player = connected[i]
		local name = player:get_player_name()
		local player_data = players[name]
		local model = player_data and x_player_api.get_model(player_data.model)
		if model then
			x_player_api.update_player_controls(player, dtime, time_now)

			local state = x_player_api.get_player_state(player, time_now)
			local animation_speed_mod = model.animation_speed or 30
			local active_format = x_player_api.get_model_format()
			local is_multitrack = model.is_multitrack and (active_format ~= "b3d")

			if state.crouching or state.crouch_walking then
				animation_speed_mod = animation_speed_mod * 0.8
			end

			if state.locomotion == "climb" and not state.climbing_active then
				animation_speed_mod = 0
			end

			if is_multitrack then
				local anims = model.animations or {}
				local anims_glb = model.animations_glb or {}
				local loco = state.locomotion
				if not anims_glb[loco] and not anims[loco] then
					if loco == "crouch_walk" then
						loco = (anims_glb.crouch or anims.crouch) and "crouch" or "walk"
					elseif loco == "crouch" then
						loco = "stand"
					elseif loco == "sprint" then
						loco = "walk"
					elseif loco == "fly" or loco == "hover" then
						loco = "stand"
					elseif loco == "swim" or loco == "climb" or loco == "fall" or loco == "slide" then
						loco = state.moving and "walk" or "stand"
					else
						loco = "stand"
					end
				end

				local anim_def = anims_glb[loco] or anims[loco]
				local loop = (anim_def and anim_def.loop ~= nil) and anim_def.loop or true
				local override_local = (state.test_anim ~= nil) or nil

				local action = state.action

				-- Drive GLB multi-track locomotion layer (Track 0) without touching B3D
				x_player_api.set_animation(player, loco, animation_speed_mod, loop, override_local, false)
				-- Drive GLB multi-track action layer (Track 1) without touching B3D
				x_player_api.play_action(player, action, false, true)
				-- Decoupled B3D single-timeline pipeline autonomously resolves & drives B3D proxy and native player bones
				x_player_api.step_b3d_animation(player, state, model, animation_speed_mod)
			else
				x_player_api.step_b3d_animation(player, state, model, animation_speed_mod)
			end
		end

		x_player_api.step_player_wield(player, is_throttled_wield)
	end
end

if not x_player_api._wrappers_applied then
	x_player_api._wrappers_applied = true
	local wrapped_functions = {
		"get_animation", "set_animation", "play_action",
		"set_model", "set_textures", "get_textures", "set_bone_override"
	}
	for _, api_function in ipairs(wrapped_functions) do
		local original_function = x_player_api[api_function]
		if original_function then
			x_player_api[api_function] = function(player, ...)
				if not (player and player:is_player()) then return end
				local name = player:get_player_name()
				if not name or name == "" then return end
				players[name] = players[name] or {}
				return original_function(player, ...)
			end
		end
	end
end
