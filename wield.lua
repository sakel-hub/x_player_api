-- 3D Wield Items for x_player_api
-- Native 3D rendering attached to Arm_Right bone via ephemeral LuaEntity

---@class WieldOffsetDefinition
---@field pos? Vector3 Translation offset relative to base hand attachment
---@field rot? Vector3 Euler rotation in degrees (X, Y, Z)
---@field scale? Vector3|number Scale multipliers for visual_size
---@field glow? number Explicit entity glow override (0-14)

---Custom wield properties specified directly inside an item or node definition.
---Following Luanti engine conventions (lua_api.md), custom fields must use flat prefixes starting
---with an underscore (`_`) to avoid naming collisions with future engine usage.
---@class WieldItemCustomDef
---@field _wield_offset? Vector3 Translation offset relative to base hand attachment
---@field _wield_rotation? Vector3 Euler rotation in degrees (X, Y, Z)
---@field _wield_scale? Vector3|number Visual scale multiplier (scalar number or Vector3)
---@field _wield_glow? number Explicit entity glow brightness level (0-14)

---@class WieldItemEntityData
---@field obj ObjectRef|nil Active attached child LuaEntity (glb or b3d for backward compatibility)
---@field glb ObjectRef|nil Attached child entity for modern GLB visual proxy
---@field b3d ObjectRef|nil Attached child entity for legacy B3D visual proxy
---@field item string Current cached item key
---@field visible boolean User-controlled visibility flag
---@field attached_pos_glb? Vector3 Currently attached relative position on GLB proxy
---@field attached_rot_glb? Vector3 Currently attached relative rotation on GLB proxy
---@field attached_pos_b3d? Vector3 Currently attached relative position on B3D proxy
---@field attached_rot_b3d? Vector3 Currently attached relative rotation on B3D proxy
---@field attached_pos? Vector3 Currently attached relative position (fallback)
---@field attached_rot? Vector3 Currently attached relative rotation (fallback)
---@field last_wield_name? string Last checked wielded item name

---@class WieldOffsetsRegistry
---@field types table<string, WieldOffsetDefinition>
---@field groups table<string, WieldOffsetDefinition>
---@field items table<string, WieldOffsetDefinition>

x_player_api = rawget(_G, "x_player_api") or rawget(_G, "player_api") or {}

local enable_wield_item = core.settings:get_bool("x_player_api.enable_wield_item", true)

---Whether 3D wielded item rendering attached to the player hand is enabled
---@type boolean
x_player_api.enable_wield_item = enable_wield_item

---Set whether 3D wielded item rendering is enabled
---@param enabled boolean Whether 3D wield items should be active
function x_player_api.set_wield_item_enabled(enabled)
	local was_enabled = x_player_api.enable_wield_item
	x_player_api.enable_wield_item = (enabled == true)
	if was_enabled and not x_player_api.enable_wield_item then
		local players = core.get_connected_players()
		for i = 1, #players do
			x_player_api.remove_wield_item(players[i])
		end
	elseif not was_enabled and x_player_api.enable_wield_item then
		local players = core.get_connected_players()
		for i = 1, #players do
			x_player_api.attach_wield_item(players[i])
		end
	end
end

---@type table<string, WieldItemEntityData>
x_player_api.wield_entities = x_player_api.wield_entities or {}
local wield_entities = x_player_api.wield_entities

-- Base configuration constants
local BASE_BONE = "Arm_Right"
local BASE_POS_GLB = {x = 0, y = 5.2, z = -3.5}
local BASE_ROT_GLB = {x = -90, y = 45, z = 90}
local BASE_POS_B3D = {x = 0, y = 5.2, z = 3.5}
local BASE_ROT_B3D = {x = -90, y = 225, z = 90}
local BASE_SCALE_VAL = 0.275
local WIELD_UPDATE_INTERVAL = tonumber(core.settings:get("x_player_api.wield_update_interval")) or 0.2

x_player_api.BASE_POS_GLB = BASE_POS_GLB
x_player_api.BASE_ROT_GLB = BASE_ROT_GLB
x_player_api.BASE_POS_B3D = BASE_POS_B3D
x_player_api.BASE_ROT_B3D = BASE_ROT_B3D
x_player_api.BASE_POS = BASE_POS_GLB
x_player_api.BASE_ROT = BASE_ROT_GLB

-- Offset and rotation customization registry
---@type WieldOffsetsRegistry
x_player_api.wield_item_offsets = {
	types = {
		node = {
			pos = {x = 0, y = -0.3, z = 2.0},
			rot = {x = 180, y = 0, z = 0},
			scale = {x = 0.60, y = 0.60, z = 0.60},
		},
		tool = {
			pos = {x = 0, y = -0.3, z = 0},
			scale = {x = 1.33, y = 1.33, z = 1.33},
		},
		craft = {
			pos = {x = 0, y = -0.3, z = 1.8},
			rot = {x = 180, y = 0, z = 0},
		},
		craftitem = {
			pos = {x = 0, y = -0.3, z = 1.8},
			rot = {x = 180, y = 0, z = 0},
		},
	},
	groups = {
		torch = {
			pos = {x = 0, y = -0.3, z = -1},
			rot = {x = -90, y = 0, z = 90},
		},
		sapling = {
			pos = {x = 0, y = -0.2, z = 0.2},
			rot = {x = 180, y = 0, z = 0},
		},
		flower = {
			pos = {x = 0, y = -0.2, z = 0.2},
			rot = {x = 180, y = 0, z = 0},
		},
		flora = {
			pos = {x = 0, y = -0.2, z = 0.2},
			rot = {x = 180, y = 0, z = 0},
		},
		plant = {
			pos = {x = 0, y = -0.2, z = 0.2},
			rot = {x = 180, y = 0, z = 0},
		},
		shovel = {
			pos = {x = 0, y = 0, z = 0},
		},
		bow = {
			pos = {x = 0, y = 0, z = 0},
			rot = {y = 45, z = -90},
		},
		vessel = {
			pos = {x = 0, y = 0, z = 0.2},
			rot = {x = 180, y = 0, z = 0},
		},
		bucket = {
			pos = {x = 0, y = 0, z = 0.2},
			rot = {x = 180, y = 0, z = 0},
		},
		screwdriver = {
			pos = {x = 0, y = 0, z = 0},
		},
	},
	items = {},
}

-- Memoized static wield attachment parameters cache (item_name -> params)
local WIELD_PARAMS_CACHE = {}

---Clear internal wield attachment parameter cache
function x_player_api.clear_wield_params_cache()
	WIELD_PARAMS_CACHE = {}
end

---Register a custom wield offset, rotation, or scale adjustment
---@param identifier string Item name ("default:sword_steel"), group ("group:sword"), or type ("type:node")
---@param def WieldOffsetDefinition Table containing pos, rot, scale, and/or glow overrides
function x_player_api.register_wield_item_offset(identifier, def)
	if identifier:find("^type:") then
		local type_name = identifier:sub(6)
		x_player_api.wield_item_offsets.types[type_name] = def
	elseif identifier:find("^group:") then
		local group_name = identifier:sub(7)
		x_player_api.wield_item_offsets.groups[group_name] = def
	else
		x_player_api.wield_item_offsets.items[identifier] = def
	end
	x_player_api.clear_wield_params_cache()
end

---Parse texture modifiers for rotation and colorization
---@param def table|nil Item definition table
---@param wield_stack any ItemStack or nil
---@return number rot_deg Rotation angle from texture modifiers (0, 90, 180, 270)
---@return string|nil item_color Extracted color string if specified
local function parse_texture_modifiers(def, wield_stack)
	local rot_deg = 0
	local item_color = nil

	-- Check ItemStack metadata for color
	if wield_stack and wield_stack.get_meta then
		local c = wield_stack:get_meta():get_string("color")
		if c ~= "" then
			item_color = c
		end
	end

	-- Check item definition color
	if not item_color and def then
		if type(def.color) == "string" and def.color ~= "" then
			item_color = def.color
		elseif type(def.color) == "table" then
			item_color = core.rgba(def.color.r or 255, def.color.g or 255, def.color.b or 255, def.color.a or 255)
		end
	end

	-- Extract texture string to inspect for modifiers
	local tex_str = ""
	if def then
		if type(def.wield_image) == "string" and def.wield_image ~= "" then
			tex_str = def.wield_image
		elseif type(def.wield_image) == "table" and def.wield_image.name then
			tex_str = def.wield_image.name
		elseif type(def.inventory_image) == "string" and def.inventory_image ~= "" then
			tex_str = def.inventory_image
		end
	end

	if tex_str ~= "" then
		-- Check for ^[transform... with R90, R180, R270
		for transform_args in tex_str:gmatch("%^%[transform([^%^]+)") do
			local r = transform_args:match("R(%d+)")
			if r then
				local rot_val = tonumber(r)
				if rot_val and rot_val > 0 then
					rot_deg = (rot_deg + rot_val) % 360
				end
			end
		end

		-- Check for ^[colorize:...
		if not item_color then
			local col = tex_str:match("%^%[colorize:([^:%^]+)")
			if col then
				item_color = col
			end
		end
	end

	return rot_deg, item_color
end

---Apply scaling multiplier to a visual_size vector in-place
---@param visual_size Vector3 Target visual size vector
---@param scale number|Vector3|table|nil Scaling multiplier or dimensions table
local function apply_scale(visual_size, scale)
	if not scale then return end
	if type(scale) == "table" then
		visual_size.x = visual_size.x * (scale.x or 1.0)
		visual_size.y = visual_size.y * (scale.y or 1.0)
		visual_size.z = visual_size.z * (scale.z or 1.0)
	elseif type(scale) == "number" and scale > 0 then
		visual_size.x = visual_size.x * scale
		visual_size.y = visual_size.y * scale
		visual_size.z = visual_size.z * scale
	end
end

---Calculate visual_size, attachment position, rotation, glow, and color for a wielded item.
---Automatically adjusts attachment position coordinates and Euler rotation angles for B3D models
---to compensate for Blitz3D exporter axis inversions and align tool handles squarely in the palm.
---@nodiscard
---@param item_or_stack string|ItemStack ItemStack object or item name string
---@param format_override? string Optional model format override ("glb" or "b3d")
---@return Vector3 visual_size Normalised 3D scale vector
---@return Vector3 position Local attachment position offset
---@return Vector3 rotation Local Euler rotation angles
---@return number glow Entity glow brightness level (0-14)
---@return string|nil item_color Extracted color string if specified
function x_player_api.get_wield_attachment_params(item_or_stack, format_override)
	local item_name = ""
	local wield_stack = nil
	local has_meta = false
	if type(item_or_stack) == "userdata" or type(item_or_stack) == "table" then
		wield_stack = item_or_stack
		item_name = wield_stack.get_name and wield_stack:get_name() or ""
		if wield_stack.get_meta and wield_stack:get_meta() and wield_stack:get_meta().get_string
				and wield_stack:get_meta():get_string("color") ~= "" then
			has_meta = true
		end
	elseif type(item_or_stack) == "string" then
		item_name = item_or_stack:match("%S+") or ""
		if item_or_stack:find(" ") then
			wield_stack = ItemStack(item_or_stack)
			item_name = wield_stack.get_name and wield_stack:get_name() or ""
			if wield_stack.get_meta and wield_stack:get_meta() and wield_stack:get_meta().get_string
					and wield_stack:get_meta():get_string("color") ~= "" then
				has_meta = true
			end
		end
	end

	local current_format = format_override or x_player_api.get_model_format()
	local cache_key = item_name .. ":" .. current_format

	if not has_meta and item_name ~= "" then
		local cached = WIELD_PARAMS_CACHE[cache_key]
		if cached then
			return cached.visual_size, cached.pos, cached.rot, cached.glow, cached.item_color
		end
	end

	local def = core.registered_items[item_name] or {}
	local item_type = def.type or "unknown"

	-- Uniform sizing normalization:
	-- Luanti's C++ WieldMeshSceneNode internally multiplies meshes by itemdef.wield_scale.
	-- Normalize against wield_scale so all held items have consistent, uniform scale in hand.
	local ws_x, ws_y, ws_z = 1, 1, 1
	local item_ws = def.wield_scale
	if type(item_ws) == "table" then
		ws_x = (item_ws.x and item_ws.x > 0) and item_ws.x or 1
		ws_y = (item_ws.y and item_ws.y > 0) and item_ws.y or 1
		ws_z = (item_ws.z and item_ws.z > 0) and item_ws.z or 1
	elseif type(item_ws) == "number" and item_ws > 0 then
		ws_x, ws_y, ws_z = item_ws, item_ws, item_ws
	end

	local visual_size = {
		x = BASE_SCALE_VAL / ws_x,
		y = BASE_SCALE_VAL / ws_y,
		z = BASE_SCALE_VAL / ws_z,
	}

	-- Start with canonical hand transform
	local pos = {x = BASE_POS_GLB.x, y = BASE_POS_GLB.y, z = BASE_POS_GLB.z}
	local rot = (current_format == "b3d")
		and {x = BASE_ROT_B3D.x, y = BASE_ROT_B3D.y, z = BASE_ROT_B3D.z}
		or  {x = BASE_ROT_GLB.x, y = BASE_ROT_GLB.y, z = BASE_ROT_GLB.z}

	-- Apply type-level customizations if registered
	local type_override = x_player_api.wield_item_offsets.types[item_type]
	if type_override then
		if type_override.pos then
			pos.x = pos.x + (type_override.pos.x or 0)
			pos.y = pos.y + (type_override.pos.y or 0)
			pos.z = pos.z + (type_override.pos.z or 0)
		end
		if type_override.rot then
			rot.x = type_override.rot.x or rot.x
			rot.y = type_override.rot.y or rot.y
			rot.z = type_override.rot.z or rot.z
		end
		apply_scale(visual_size, type_override.scale)
	end

	-- Apply group-level customizations if registered
	local active_group_override = nil
	if def.groups then
		for group_name, rating in pairs(def.groups) do
			if (rating or 0) > 0 then
				local group_override = x_player_api.wield_item_offsets.groups[group_name]
				if group_override then
					active_group_override = group_override
					if group_override.pos then
						pos.x = pos.x + (group_override.pos.x or 0)
						pos.y = pos.y + (group_override.pos.y or 0)
						pos.z = pos.z + (group_override.pos.z or 0)
					end
					if group_override.rot then
						rot.x = group_override.rot.x or rot.x
						rot.y = group_override.rot.y or rot.y
						rot.z = group_override.rot.z or rot.z
					end
					apply_scale(visual_size, group_override.scale)
					break
				end
			end
		end
	end

	-- Apply exact item-level customizations if registered
	local item_override = x_player_api.wield_item_offsets.items[item_name]
	if item_override then
		if item_override.pos then
			pos.x = pos.x + (item_override.pos.x or 0)
			pos.y = pos.y + (item_override.pos.y or 0)
			pos.z = pos.z + (item_override.pos.z or 0)
		end
		if item_override.rot then
			rot.x = item_override.rot.x or rot.x
			rot.y = item_override.rot.y or rot.y
			rot.z = item_override.rot.z or rot.z
		end
		apply_scale(visual_size, item_override.scale)
	end

	-- Direct item definition properties
	-- Following Luanti engine convention (lua_api.md), custom fields must use flat prefixes
	-- starting with '_' to avoid naming collisions with future engine usage.
	-- Supports:
	--   _wield_offset, _wield_rotation, _wield_scale, _wield_glow
	local custom_offset = def._wield_offset
	if custom_offset then
		pos.x = pos.x + (custom_offset.x or 0)
		pos.y = pos.y + (custom_offset.y or 0)
		pos.z = pos.z + (custom_offset.z or 0)
	end

	local custom_rot = def._wield_rotation
	if custom_rot then
		rot.x = custom_rot.x or rot.x
		rot.y = custom_rot.y or rot.y
		rot.z = custom_rot.z or rot.z
	end

	apply_scale(visual_size, def._wield_scale)

	-- Apply texture modifier rotation negation:
	-- If texture is rotated clockwise (e.g. ^[transformR90), compensate so held item remains facing forward.
	local rot_deg, item_color = parse_texture_modifiers(def, wield_stack)
	if rot_deg ~= 0 then
		if item_type == "craftitem" or item_type == "craft" then
			rot.z = rot.z - rot_deg
		else
			rot.y = rot.y + rot_deg
		end
	end

	-- In B3D format, convert canonical hand transform into B3D bone coordinate space
	-- (B3D Arm_Right basis has X/Z inverted relative to GLB for position)
	if current_format == "b3d" then
		pos = {x = -pos.x, y = pos.y, z = -pos.z}
	end

	-- Convert item light_source to entity glow value
	-- Follows Luanti's standard item entity conversion: glow = floor(light_source / 2 + 0.5)
	local glow = 0
	if def._wield_glow ~= nil then
		glow = def._wield_glow
	else
		local light_source = def.light_source
		if not light_source and def.groups and def.groups.light_source then
			light_source = def.groups.light_source
		end
		if not light_source and core.registered_nodes[item_name] then
			local ndef = core.registered_nodes[item_name]
			light_source = ndef.light_source or (ndef.groups and ndef.groups.light_source)
		end

		if type(light_source) == "number" and light_source > 0 then
			glow = math.floor(light_source / 2 + 0.5)
		elseif type(light_source) == "boolean" and light_source then
			glow = math.floor((core.LIGHT_MAX or 14) / 2 + 0.5)
		end
	end

	-- Allow explicit glow override from wield_item_offsets if registered
	if item_override and item_override.glow ~= nil then
		glow = item_override.glow
	elseif active_group_override and active_group_override.glow ~= nil then
		glow = active_group_override.glow
	elseif type_override and type_override.glow ~= nil then
		glow = type_override.glow
	end

	glow = math.min(14, math.max(0, glow or 0))

	if not has_meta and item_name ~= "" then
		WIELD_PARAMS_CACHE[cache_key] = {
			visual_size = visual_size,
			pos = pos,
			rot = rot,
			glow = glow,
			item_color = item_color,
		}
	end
	return visual_size, pos, rot, glow, item_color
end

-- Ephemeral child LuaEntity definition
core.register_entity("x_player_api:wield_item", {
	initial_properties = {
		visual = "wielditem",
		wield_item = "",
		visual_size = {x = BASE_SCALE_VAL, y = BASE_SCALE_VAL, z = BASE_SCALE_VAL},
		pointable = false,
		physical = false,
		collide_with_objects = false,
		collisionbox = {0, 0, 0, 0, 0, 0},
		selectionbox = {0, 0, 0, 0, 0, 0},
		static_save = false,
		use_texture_alpha = true,
		backface_culling = false,
		is_visible = false,
		glow = 0,
	},
	on_activate = function(self)
		local object = self.object
		object:set_armor_groups({immortal = 1})
	end,
	on_step = function(self, dtime)
		self._timer = (self._timer or 0) + (dtime or 0.1)
		if self._timer < 1.0 then
			return
		end
		self._timer = 0
		local object = self.object
		local parent = object:get_attach()
		if not parent or not parent:is_valid() or (parent.get_pos and not parent:get_pos()) then
			object:remove()
		end
	end,
})

---Get the active wield item entity ObjectRef for a player
---Get the active wield item entity ObjectRef for a player
---@nodiscard
---@param player ObjectRef Target player
---@return ObjectRef|nil entity Active wield item entity or nil
function x_player_api.get_wield_entity(player)
	if not x_player_api.enable_wield_item then
		return nil
	end
	if not player or not player:is_player() then
		return nil
	end
	local name = player:get_player_name()
	local data = wield_entities[name]
	if not data then
		return nil
	end
	if data.obj and data.obj:get_luaentity() then
		return data.obj
	end
	return nil
end

---Set visibility of the wield item entity for a player
---@param player ObjectRef Target player
---@param visible boolean Whether held item should be rendered
function x_player_api.set_wield_item_visibility(player, visible)
	if not x_player_api.enable_wield_item then
		return
	end
	if not player or not player:is_player() then
		return
	end
	local name = player:get_player_name()
	local data = wield_entities[name]
	if not data then
		return
	end
	data.visible = visible
	local pdata = x_player_api.get_animation(player)
	local model = pdata and x_player_api.get_model(pdata.model)
	local active_format = x_player_api.get_model_format()
	local has_glb = (active_format ~= "b3d") and model and (model.mesh_glb or (model.mesh and model.mesh:match("%.glb$")))
	local has_b3d = not model or (model.mesh and not model.mesh:match("%.glb$")) or model.mesh_b3d

	if data.glb and data.glb:get_luaentity() then
		data.glb:set_properties({
			is_visible = (has_glb and visible and data.item ~= "") or false,
		})
	end
	if data.b3d and data.b3d:get_luaentity() then
		data.b3d:set_properties({
			is_visible = (has_b3d and visible and data.item ~= "") or false,
		})
	end
	if data.obj and data.obj:get_luaentity() and data.obj ~= data.glb and data.obj ~= data.b3d then
		data.obj:set_properties({
			is_visible = visible and data.item ~= "",
		})
	end
end

---Get visibility preference of the wield item entity for a player
---@nodiscard
---@param player ObjectRef Target player
---@return boolean visible Whether wield item entity is configured to be visible
function x_player_api.get_wield_item_visibility(player)
	if not player or not player:is_player() then
		return false
	end
	local name = player:get_player_name()
	local data = wield_entities[name]
	if data and data.visible ~= nil then
		return data.visible
	end
	return true
end

---Attach or spawn a 3D wield item entity to an arbitrary entity bone (corpses, mobs, visual proxies)
---@param parent ObjectRef Target parent object to attach to
---@param item_or_stack string|ItemStack Held item name or ItemStack
---@param format_override? string Model format ("glb" or "b3d", defaults to active format or "b3d")
---@param bone? string Target bone name (defaults to "Arm_Right")
---@param entity_name? string Registered entity name (defaults to "x_player_api:wield_item")
---@param forced_visible? boolean Visibility override (true for standalone entities, false for player proxies)
---@return ObjectRef|nil wield_ent The spawned and attached entity or nil
function x_player_api.attach_wield_item_to_entity(
	parent, item_or_stack, format_override, bone, entity_name, forced_visible
)
	if not x_player_api.enable_wield_item then
		return nil
	end
	if not parent or not parent:is_valid() then
		return nil
	end
	local pos = parent.get_pos and parent:get_pos()
	if not pos then
		return nil
	end

	local ent_type = entity_name or "x_player_api:wield_item"
	local wield_ent = core.add_entity(pos, ent_type)
	if not wield_ent then
		return nil
	end

	local target_bone = bone or BASE_BONE
	local fmt = format_override or x_player_api.get_model_format()
	local v_size, att_pos, att_rot, glow, item_col = x_player_api.get_wield_attachment_params(item_or_stack, fmt)

	local stack_str = ""
	local item_name = ""
	if type(item_or_stack) == "userdata" or type(item_or_stack) == "table" then
		stack_str = (item_or_stack.to_string and item_or_stack:to_string())
			or (item_or_stack.get_name and item_or_stack:get_name()) or ""
		item_name = (item_or_stack.get_name and item_or_stack:get_name()) or ""
	elseif type(item_or_stack) == "string" then
		stack_str = item_or_stack
		item_name = item_or_stack:match("%S+") or ""
	end

	local is_empty = (item_name == "")
		or (type(item_or_stack) == "userdata" and item_or_stack.is_empty and item_or_stack:is_empty())
	local is_vis = not is_empty
	local force_vis = true
	if forced_visible ~= nil then
		force_vis = forced_visible
	end

	local props = {
		visual = "wielditem",
		wield_item = stack_str,
		textures = { stack_str },
		visual_size = is_empty and {x = 0, y = 0, z = 0} or v_size,
		glow = glow or 0,
		pointable = false,
		use_texture_alpha = true,
		backface_culling = false,
		is_visible = is_vis,
	}
	if item_col then
		props.color = item_col
	end
	wield_ent:set_properties(props)

	if wield_ent.set_attach then
		wield_ent:set_attach(parent, target_bone, att_pos, att_rot, force_vis)
	end
	return wield_ent
end

---Attach or re-attach the ephemeral wield item entity to player's Arm_Right bone
---@param player ObjectRef Target player
---@return ObjectRef|nil entity Attached entity reference or nil
function x_player_api.attach_wield_item(player)
	if not x_player_api.enable_wield_item then
		return nil
	end
	if not player or not player:is_player() then
		return nil
	end
	local name = player:get_player_name()
	local data = wield_entities[name]
	if not data then
		data = {
			obj = nil,
			glb = nil,
			b3d = nil,
			item = "",
			visible = true,
		}
		wield_entities[name] = data
	end

	local pos = player:get_pos()
	if not pos then
		return nil
	end

	local proxies = x_player_api.get_visual_proxies(player)
	local is_pure_b3d = x_player_api.is_pure_native_b3d_active and x_player_api.is_pure_native_b3d_active(player)

	if is_pure_b3d then
		-- In pure native B3D mode: attach wield entity directly to player entity
		local obj_valid = data.obj and data.obj:get_luaentity() and data.obj:get_attach() == player
		if not obj_valid then
			if data.obj and data.obj:get_luaentity() then
				data.obj:remove()
			end
			local entity = x_player_api.attach_wield_item_to_entity(
				player, "", "b3d", BASE_BONE, "x_player_api:wield_item", false
			)
			if entity then
				local _, init_pos, init_rot = x_player_api.get_wield_attachment_params("", "b3d")
				data.obj = entity
				data.attached_pos = init_pos
				data.attached_rot = init_rot
			end
		end
		if data.glb and data.glb:get_luaentity() then data.glb:remove(); data.glb = nil end
		if data.b3d and data.b3d:get_luaentity() then data.b3d:remove(); data.b3d = nil end
	elseif proxies and (proxies.glb or proxies.b3d) then
		-- Proxy-backed mode: attach format-specific wield entities to active proxies
		if proxies.glb and proxies.glb:is_valid() then
			local glb_valid = data.glb and data.glb:get_luaentity() and data.glb:get_attach() == proxies.glb
			if not glb_valid then
				if data.glb and data.glb:get_luaentity() then
					data.glb:remove()
				end
				local ent = x_player_api.attach_wield_item_to_entity(
					proxies.glb, "", "glb", BASE_BONE, "x_player_api:wield_item", false
				)
				if ent then
					local _, init_pos, init_rot = x_player_api.get_wield_attachment_params("", "glb")
					ent:set_observers(x_player_api.get_modern_observers())
					data.glb = ent
					data.attached_pos_glb = init_pos
					data.attached_rot_glb = init_rot
				end
			end
		elseif data.glb and data.glb:get_luaentity() then
			data.glb:remove()
			data.glb = nil
			data.attached_pos_glb = nil
			data.attached_rot_glb = nil
		end

		if proxies.b3d and proxies.b3d:is_valid() then
			local b3d_valid = data.b3d and data.b3d:get_luaentity() and data.b3d:get_attach() == proxies.b3d
			if not b3d_valid then
				if data.b3d and data.b3d:get_luaentity() then
					data.b3d:remove()
				end
				local ent = x_player_api.attach_wield_item_to_entity(
					proxies.b3d, "", "b3d", BASE_BONE, "x_player_api:wield_item", false
				)
				if ent then
					local _, init_pos, init_rot = x_player_api.get_wield_attachment_params("", "b3d")
					ent:set_observers(x_player_api.get_legacy_observers())
					data.b3d = ent
					data.attached_pos_b3d = init_pos
					data.attached_rot_b3d = init_rot
				end
			end
		elseif data.b3d and data.b3d:get_luaentity() then
			data.b3d:remove()
			data.b3d = nil
			data.attached_pos_b3d = nil
			data.attached_rot_b3d = nil
		end

		if data.obj and data.obj:get_luaentity() and data.obj ~= data.glb and data.obj ~= data.b3d then
			data.obj:remove()
			data.attached_pos = nil
			data.attached_rot = nil
		end

		local active_fmt = x_player_api.get_model_format()
		if active_fmt == "b3d" then
			data.obj = data.b3d or data.glb
		else
			data.obj = data.glb or data.b3d
		end
	else
		-- Direct player fallback mode
		local obj_valid = data.obj and data.obj:get_luaentity() and data.obj:get_attach() == player
		if not obj_valid then
			if data.obj and data.obj:get_luaentity() then
				data.obj:remove()
			end
			local entity = x_player_api.attach_wield_item_to_entity(
				player, "", "b3d", BASE_BONE, "x_player_api:wield_item", false
			)
			if entity then
				local _, init_pos, init_rot = x_player_api.get_wield_attachment_params("", "b3d")
				data.obj = entity
				data.attached_pos = init_pos
				data.attached_rot = init_rot
			end
		end
		data.glb = nil
		data.b3d = nil
	end

	x_player_api.update_wield_item(player, true)
	return data.glb or data.b3d or data.obj
end

---Remove the wield item entity for a player
---@param player ObjectRef Target player
function x_player_api.remove_wield_item(player)
	if not player or not player:is_player() then
		return
	end
	local name = player:get_player_name()
	local data = wield_entities[name]
	if data then
		if data.glb and data.glb:get_luaentity() then
			data.glb:remove()
			data.glb = nil
		end
		if data.b3d and data.b3d:get_luaentity() then
			data.b3d:remove()
			data.b3d = nil
		end
		if data.obj and data.obj:get_luaentity() then
			data.obj:remove()
			data.obj = nil
		end
		data.attached_pos_glb = nil
		data.attached_rot_glb = nil
		data.attached_pos_b3d = nil
		data.attached_rot_b3d = nil
		data.attached_pos = nil
		data.attached_rot = nil
		wield_entities[name] = nil
	end
end

---Update held wield item on the child entity (throttled delta check)
---@param player ObjectRef Target player
---@param force boolean? Force entity property updates even if held item unchanged
---@param wield_stack ItemStack? Optional cached wield ItemStack to avoid redundant get_wielded_item call
function x_player_api.update_wield_item(player, force, wield_stack)
	if not x_player_api.enable_wield_item then
		return
	end
	if not player or not player:is_player() then
		return
	end
	local name = player:get_player_name()
	local data = wield_entities[name]
	if not data then
		return
	end

	local proxies = x_player_api.get_visual_proxies(player)
	local is_pure_b3d = x_player_api.is_pure_native_b3d_active and x_player_api.is_pure_native_b3d_active(player)
	local needs_reattach = false

	if is_pure_b3d then
		if not data.obj or not data.obj:get_luaentity() or data.obj:get_attach() ~= player then
			needs_reattach = true
		end
	elseif proxies and (proxies.glb or proxies.b3d) then
		if proxies.glb and proxies.glb:is_valid() then
			if not data.glb or not data.glb:get_luaentity() or data.glb:get_attach() ~= proxies.glb then
				needs_reattach = true
			end
		end
		if proxies.b3d and proxies.b3d:is_valid() then
			if not data.b3d or not data.b3d:get_luaentity() or data.b3d:get_attach() ~= proxies.b3d then
				needs_reattach = true
			end
		end
	else
		if not data.obj or not data.obj:get_luaentity() or data.obj:get_attach() ~= player then
			needs_reattach = true
		end
	end

	if needs_reattach then
		x_player_api.attach_wield_item(player)
		return
	end

	-- Dead players hide wield item
	if player:get_hp() <= 0 or data.visible == false then
		if data.item ~= "" or force then
			data.item = ""
			local hide_props = {
				is_visible = false,
				wield_item = "",
			}
			if data.glb and data.glb:get_luaentity() then
				data.glb:set_properties(hide_props)
			end
			if data.b3d and data.b3d:get_luaentity() then
				data.b3d:set_properties(hide_props)
			end
			if data.obj and data.obj:get_luaentity() and data.obj ~= data.glb and data.obj ~= data.b3d then
				data.obj:set_properties(hide_props)
			end
		end
		return
	end

	wield_stack = wield_stack or player:get_wielded_item()
	local item_name = (wield_stack and wield_stack:get_name()) or ""

	-- Item identity key: combines item_name with color metadata so color changes trigger updates
	local item_key = item_name
	if wield_stack and wield_stack.get_meta then
		local c = wield_stack:get_meta():get_string("color")
		if c ~= "" then
			item_key = item_name .. ":" .. c
		end
	end

	-- If item identity has not changed and not forced, skip completely
	if not force and item_key == data.item then
		return
	end

	data.item = item_key

	if item_name == "" or (wield_stack and wield_stack.is_empty and wield_stack:is_empty()) then
		local empty_props = {
			is_visible = false,
			wield_item = "",
			glow = 0,
		}
		if data.glb and data.glb:get_luaentity() then
			data.glb:set_properties(empty_props)
		end
		if data.b3d and data.b3d:get_luaentity() then
			data.b3d:set_properties(empty_props)
		end
		if data.obj and data.obj:get_luaentity() and data.obj ~= data.glb and data.obj ~= data.b3d then
			data.obj:set_properties(empty_props)
		end
		return
	end

	local stack_str = (wield_stack and wield_stack.to_string and wield_stack:to_string()) or item_name
	local pdata = x_player_api.get_animation(player)
	local model = pdata and x_player_api.get_model(pdata.model)
	local active_format = x_player_api.get_model_format()
	local has_glb = (active_format ~= "b3d") and model and (model.mesh_glb or (model.mesh and model.mesh:match("%.glb$")))
	local has_b3d = not model or (model.mesh and not model.mesh:match("%.glb$")) or model.mesh_b3d

	-- Update GLB proxy wield entity
	if not is_pure_b3d and proxies and proxies.glb and proxies.glb:is_valid()
			and data.glb and data.glb:get_luaentity() then
		if has_glb then
			local v_size_glb, pos_glb, rot_glb, glow_glb, col_glb = x_player_api.get_wield_attachment_params(wield_stack, "glb")
			local props_glb = {
				visual = "wielditem",
				wield_item = stack_str,
				visual_size = v_size_glb,
				glow = glow_glb,
				is_visible = true,
				pointable = false,
			}
			if col_glb then props_glb.color = col_glb end
			data.glb:set_properties(props_glb)

			local last_pos = data.attached_pos_glb
			local last_rot = data.attached_rot_glb
			if not last_pos or not last_rot
					or pos_glb.x ~= last_pos.x or pos_glb.y ~= last_pos.y or pos_glb.z ~= last_pos.z
					or rot_glb.x ~= last_rot.x or rot_glb.y ~= last_rot.y or rot_glb.z ~= last_rot.z then
				data.glb:set_attach(proxies.glb, BASE_BONE, pos_glb, rot_glb, false)
				data.attached_pos_glb = pos_glb
				data.attached_rot_glb = rot_glb
			end
		else
			data.glb:set_properties({
				is_visible = false,
				visual_size = {x = 0, y = 0},
				wield_item = "",
				glow = 0,
			})
		end
	end

	-- Update B3D wield entity attached to B3D proxy
	if not is_pure_b3d and proxies and proxies.b3d and proxies.b3d:is_valid()
			and data.b3d and data.b3d:get_luaentity() then
		if has_b3d then
			local v_size_b3d, pos_b3d, rot_b3d, glow_b3d, col_b3d = x_player_api.get_wield_attachment_params(wield_stack, "b3d")
			local props_b3d = {
				visual = "wielditem",
				wield_item = stack_str,
				visual_size = v_size_b3d,
				glow = glow_b3d,
				is_visible = true,
				pointable = false,
			}
			if col_b3d then props_b3d.color = col_b3d end
			data.b3d:set_properties(props_b3d)

			local last_pos = data.attached_pos_b3d
			local last_rot = data.attached_rot_b3d
			if not last_pos or not last_rot
					or pos_b3d.x ~= last_pos.x or pos_b3d.y ~= last_pos.y or pos_b3d.z ~= last_pos.z
					or rot_b3d.x ~= last_rot.x or rot_b3d.y ~= last_rot.y or rot_b3d.z ~= last_rot.z then
				data.b3d:set_attach(proxies.b3d, BASE_BONE, pos_b3d, rot_b3d, false)
				data.attached_pos_b3d = pos_b3d
				data.attached_rot_b3d = rot_b3d
			end
		else
			data.b3d:set_properties({
				is_visible = false,
				visual_size = {x = 0, y = 0},
				wield_item = "",
				glow = 0,
			})
		end
	end

	-- Update direct player fallback wield entity (or pure native B3D entity)
	if (is_pure_b3d or not proxies or not (proxies.glb or proxies.b3d)) and data.obj and data.obj:get_luaentity() then
		local v_size, pos, rot, glow, item_col = x_player_api.get_wield_attachment_params(wield_stack, "b3d")
		local props = {
			visual = "wielditem",
			wield_item = stack_str,
			visual_size = v_size,
			glow = glow,
			is_visible = true,
			pointable = false,
		}
		if item_col then props.color = item_col end
		data.obj:set_properties(props)

		local last_pos = data.attached_pos
		local last_rot = data.attached_rot
		if not last_pos or not last_rot
				or pos.x ~= last_pos.x or pos.y ~= last_pos.y or pos.z ~= last_pos.z
				or rot.x ~= last_rot.x or rot.y ~= last_rot.y or rot.z ~= last_rot.z then
			data.obj:set_attach(player, BASE_BONE, pos, rot, false)
			data.attached_pos = pos
			data.attached_rot = rot
		end
	end
end

x_player_api.WIELD_UPDATE_INTERVAL = WIELD_UPDATE_INTERVAL

---Step wield item for an individual player (called during unified globalstep)
---@param player ObjectRef Target player
---@param is_throttled_tick boolean Whether periodic throttle interval has elapsed
function x_player_api.step_player_wield(player, is_throttled_tick)
	if not x_player_api.enable_wield_item then
		return
	end
	local name = player:get_player_name()
	local data = wield_entities[name]
	if data and data.obj then
		local pstates = x_player_api.controls.player_states
		local pstate = pstates and pstates[name]
		local wield_stack = (pstate and pstate.wielded_item) or player:get_wielded_item()
		local item_name = (pstate and pstate.wield_name) or (wield_stack and wield_stack:get_name()) or ""
		-- Fast-path: instantly update on item swap or run on periodic throttle
		if (item_name ~= data.last_wield_name) or is_throttled_tick then
			local item_changed = (item_name ~= data.last_wield_name)
			data.last_wield_name = item_name
			x_player_api.update_wield_item(player, false, wield_stack)

			-- Trigger upper-body skeletal equip montage on weapon/item switch if model supports it
			if item_changed and item_name ~= "" then
				local time_now = core.get_us_time() * 0.000001
				local sem_state = pstate and pstate.semantic_state
				local is_eating = (pstate and pstate.eat_until and (pstate.eat_until > time_now))
					or (sem_state and sem_state.eating)
				local is_attacking = (pstate and pstate.controls and (pstate.controls.LMB or pstate.controls.dig))
					or (sem_state and sem_state.acting)
				local is_rmb = pstate and pstate.controls and (pstate.controls.RMB or pstate.controls.place)
				local item_info = pstate and pstate.item_info
				local is_blocking = (sem_state and sem_state.blocking)
					or (is_rmb and item_info and item_info.is_shield)
				local is_aiming_bow = (sem_state and sem_state.aiming_bow)
					or (item_info and item_info.is_bow and (item_info.is_bow_charged or is_rmb))

				if not is_eating and not is_attacking and not is_blocking and not is_aiming_bow then
					x_player_api.trigger_equip(player, item_name)
				end
			end
		end
	elseif is_throttled_tick then
		x_player_api.update_wield_item(player, false)
	end
end

-- Globalstep handler: delegates to unified step if api.lua globalstep is active,
-- otherwise operates in standalone mode for isolated testing environments
local wield_timer = 0
core.register_globalstep(function(dtime)
	if x_player_api._wield_unified_active then
		return
	end
	if not x_player_api.enable_wield_item then
		return
	end
	wield_timer = wield_timer + dtime
	local is_throttled_tick = (wield_timer >= WIELD_UPDATE_INTERVAL)
	if is_throttled_tick then
		wield_timer = 0
	end

	local connected = core.get_connected_players()
	for i = 1, #connected do
		x_player_api.step_player_wield(connected[i], is_throttled_tick)
	end
end)

-- Player Lifecycle Event Handlers
core.register_on_joinplayer(function(player)
	if not x_player_api.enable_wield_item then
		return
	end
	local name = player:get_player_name()
	local wield_stack = player:get_wielded_item()
	local initial_item = (wield_stack and wield_stack:get_name()) or ""
	wield_entities[name] = {
		obj = nil,
		item = "",
		visible = true,
		last_wield_name = initial_item,
	}
	-- Delay attachment by 0.5s to ensure client has loaded character model mesh
	core.after(0.5, function()
		local p = core.get_player_by_name(name)
		if p then
			x_player_api.attach_wield_item(p)
		end
	end)
end)

core.register_on_leaveplayer(function(player)
	x_player_api.remove_wield_item(player)
end)

core.register_on_dieplayer(function(player)
	if not x_player_api.enable_wield_item then
		return
	end
	local name = player:get_player_name()
	local data = wield_entities[name]
	if data then
		data.item = ""
		local hide_props = {
			is_visible = false,
			wield_item = "",
			glow = 0,
		}
		if data.glb and data.glb:get_luaentity() then
			data.glb:set_properties(hide_props)
		end
		if data.b3d and data.b3d:get_luaentity() then
			data.b3d:set_properties(hide_props)
		end
		if data.obj and data.obj:get_luaentity() and data.obj ~= data.glb and data.obj ~= data.b3d then
			data.obj:set_properties(hide_props)
		end
	end
end)

core.register_on_respawnplayer(function(player)
	if not x_player_api.enable_wield_item then
		return
	end
	local name = player:get_player_name()
	local data = wield_entities[name]
	if data then
		data.item = ""
		core.after(0.1, function()
			local p = core.get_player_by_name(name)
			if p then
				x_player_api.attach_wield_item(p)
			end
		end)
	end
end)
