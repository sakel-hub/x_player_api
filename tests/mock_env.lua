-- Mock Luanti Engine Environment for Unit Testing
-- Provides pure Lua simulation of core.*, vector, ItemStack, and Player SAO

local mock_env = {
	registered = false,
}

function mock_env.setup()
	if mock_env.registered then return end
	mock_env.registered = true

	rawset(string, "trim", function(s)
		return s:match("^%s*(.-)%s*$") or ""
	end)

	-- Mock Luanti builtin table.copy
	rawset(table, "copy", rawget(table, "copy") or function(t, seen)
		if type(t) ~= "table" then return t end
		seen = seen or {}
		if seen[t] then return seen[t] end
		local copy = {}
		seen[t] = copy
		for k, v in pairs(t) do
			copy[k] = type(v) == "table" and table.copy(v, seen) or v
		end
		return copy
	end)

	-- Mock vector library
	rawset(_G, "vector", rawget(_G, "vector") or {
		new = function(a, b, c)
			if type(a) == "table" then
				return {x = a.x or 0, y = a.y or 0, z = a.z or 0}
			end
			return {x = a or 0, y = b or 0, z = c or 0}
		end,
		add = function(a, b)
			return {x = (a.x or 0) + (b.x or 0), y = (a.y or 0) + (b.y or 0), z = (a.z or 0) + (b.z or 0)}
		end,
	})

	-- Mock ItemStack library
	rawset(_G, "ItemStack", rawget(_G, "ItemStack") or function(item)
		local name = ""
		local count = 1
		if type(item) == "string" then
			name = item:match("%S+") or ""
		elseif type(item) == "table" then
			name = item.name or ""
			count = item.count or 1
		end
		local meta_tbl = {}
		if type(item) == "string" then
			local c = item:match("\1color\2([^\3]+)\3")
			if c then meta_tbl.color = c end
		end
		return {
			get_name = function() return name end,
			get_count = function() return count end,
			is_empty = function() return name == "" or count == 0 end,
			to_string = function() return name end,
			take_item = function(_, n)
				n = n or 1
				local taken = math.min(n, count)
				count = count - taken
				if count <= 0 then
					name = ""
				end
				return ItemStack({name = name, count = taken})
			end,
			get_meta = function()
				return {
					get_string = function(_, k) return meta_tbl[k] or "" end,
					set_string = function(_, k, v) meta_tbl[k] = v end,
				}
			end,
		}
	end)

	local function parse_json(str)
		if type(str) ~= "string" or str == "" then return nil end
		local pos = 1
		local len = #str

		local function skip_ws()
			while pos <= len do
				local c = str:sub(pos, pos)
				if c == " " or c == "\t" or c == "\r" or c == "\n" then
					pos = pos + 1
				else
					break
				end
			end
		end

		local parse_val

		local function parse_str()
			pos = pos + 1
			local s = {}
			while pos <= len do
				local c = str:sub(pos, pos)
				if c == "\"" then
					pos = pos + 1
					return table.concat(s)
				elseif c == "\\" then
					local esc = str:sub(pos + 1, pos + 1)
					if esc == "\"" or esc == "\\" or esc == "/" then
						table.insert(s, esc)
						pos = pos + 2
					elseif esc == "b" then table.insert(s, "\b"); pos = pos + 2
					elseif esc == "f" then table.insert(s, "\f"); pos = pos + 2
					elseif esc == "n" then table.insert(s, "\n"); pos = pos + 2
					elseif esc == "r" then table.insert(s, "\r"); pos = pos + 2
					elseif esc == "t" then table.insert(s, "\t"); pos = pos + 2
					elseif esc == "u" then
						local hex = str:sub(pos + 2, pos + 5)
						local code = tonumber(hex, 16) or 0
						if code < 128 then table.insert(s, string.char(code)) end
						pos = pos + 6
					else
						table.insert(s, esc)
						pos = pos + 2
					end
				else
					table.insert(s, c)
					pos = pos + 1
				end
			end
			error("Unterminated string in JSON")
		end

		local function parse_num()
			local start = pos
			if str:sub(pos, pos) == "-" then pos = pos + 1 end
			while pos <= len and str:sub(pos, pos):match("[0-9]") do pos = pos + 1 end
			if pos <= len and str:sub(pos, pos) == "." then
				pos = pos + 1
				while pos <= len and str:sub(pos, pos):match("[0-9]") do pos = pos + 1 end
			end
			if pos <= len and str:sub(pos, pos):match("[eE]") then
				pos = pos + 1
				if pos <= len and (str:sub(pos, pos) == "+" or str:sub(pos, pos) == "-") then pos = pos + 1 end
				while pos <= len and str:sub(pos, pos):match("[0-9]") do pos = pos + 1 end
			end
			local num_str = str:sub(start, pos - 1)
			return tonumber(num_str)
		end

		local function parse_arr()
			pos = pos + 1
			local arr = {}
			skip_ws()
			if pos <= len and str:sub(pos, pos) == "]" then
				pos = pos + 1
				return arr
			end
			while pos <= len do
				table.insert(arr, parse_val())
				skip_ws()
				local c = str:sub(pos, pos)
				if c == "," then
					pos = pos + 1
					skip_ws()
				elseif c == "]" then
					pos = pos + 1
					return arr
				else
					error("Expected , or ] in JSON array at " .. pos)
				end
			end
		end

		local function parse_obj()
			pos = pos + 1
			local obj = {}
			skip_ws()
			if pos <= len and str:sub(pos, pos) == "}" then
				pos = pos + 1
				return obj
			end
			while pos <= len do
				skip_ws()
				if str:sub(pos, pos) ~= "\"" then
					error("Expected string key in JSON object at " .. pos)
				end
				local k = parse_str()
				skip_ws()
				if str:sub(pos, pos) ~= ":" then
					error("Expected : in JSON object at " .. pos)
				end
				pos = pos + 1
				obj[k] = parse_val()
				skip_ws()
				local c = str:sub(pos, pos)
				if c == "," then
					pos = pos + 1
					skip_ws()
				elseif c == "}" then
					pos = pos + 1
					return obj
				else
					error("Expected , or } in JSON object at " .. pos)
				end
			end
		end

		function parse_val()
			skip_ws()
			local c = str:sub(pos, pos)
			if c == "{" then return parse_obj()
			elseif c == "[" then return parse_arr()
			elseif c == "\"" then return parse_str()
			elseif c == "t" and str:sub(pos, pos + 3) == "true" then pos = pos + 4; return true
			elseif c == "f" and str:sub(pos, pos + 4) == "false" then pos = pos + 5; return false
			elseif c == "n" and str:sub(pos, pos + 3) == "null" then pos = pos + 4; return nil
			else return parse_num()
			end
		end

		return parse_val()
	end

	-- Mock core / Luanti API environment
	local core_mock = {
		parse_json = parse_json,
		registered_entities = {},
		registered_items = {},
		registered_nodes = {},
		registered_aliases = {},
		_globalsteps = {},
		_particlespawners = {},
		_next_spawner_id = 1,
		_on_joinplayers = {},
		_on_leaveplayers = {},
		_on_dieplayers = {},
		_on_respawnplayers = {},
		_on_mods_loaded = {},
		_on_hpchange = {},
		_on_item_eat = {},
		_on_punchnode = {},
		_on_punchplayer = {},
		_on_placenode = {},
		_on_shutdown = {},
		chatcommands = {},
		registered_chatcommands = {},
		_after_timers = {},
		_connected_players = {},
		_sounds_played = {},

		sound_play = function(spec, params, ephemeral)
			table.insert(core._sounds_played, {spec = spec, params = params, ephemeral = ephemeral})
			return 1
		end,

		settings = {
			_values = {},
			get = function(self, key) return self._values[key] end,
			get_bool = function(self, key, default)
				if self._values[key] ~= nil then
					return self._values[key]
				end
				return default
			end,
			set = function(self, key, val) self._values[key] = val end,
			set_bool = function(self, key, val) self._values[key] = val end,
		},

		get_current_modname = function() return "x_player_api" end,
		get_player_information = function() return { protocol_version = 44 } end,
		_mock_us_time = 1000000,
		get_us_time = function() return core._mock_us_time or 1000000 end,
		get_node_or_nil = function() return {name = "air"} end,
		check_player_privs = function() return false end,
		get_item_group = function(item, group)
			local idef = core.registered_items[item] or core.registered_nodes[item]
			if idef and idef.groups and idef.groups[group] then
				return idef.groups[group]
			end
			return 0
		end,
		colorize = function(_, text) return text end,
		rgba = function(r, g, b, a)
			if a and a < 255 then
				return string.format("#%02X%02X%02X%02X", r or 255, g or 255, b or 255, a)
			end
			return string.format("#%02X%02X%02X", r or 255, g or 255, b or 255)
		end,
		LIGHT_MAX = 14,
		get_translator = function(_modname)
			return function(s, ...)
				local args = {...}
				if #args == 0 then return s end
				return (s:gsub("@(%d+)", function(n) return tostring(args[tonumber(n)] or "") end))
			end
		end,
		chat_send_player = function() end,
		chat_send_all = function() end,
		_enabled_mods = {},
		get_modpath = function(mod)
			local source = debug.getinfo(1, "S").source:match("^@?(.-)tests/mock_env%.lua$")
			local root = (source and source ~= "") and source or "."
			if root:sub(-1) == "/" then root = root:sub(1, -2) end
			if mod == "x_player_api" or mod == "player_api" then
				return root
			end
			if core._enabled_mods[mod] then
				return "/fake_mods/" .. mod
			end
			return nil
		end,
		register_entity = function(name, def)
			core.registered_entities[name] = def
		end,
		register_alias = function(alias, target)
			core.registered_aliases[alias] = target
		end,
		register_globalstep = function(fn)
			table.insert(core._globalsteps, fn)
		end,
		register_on_joinplayer = function(fn)
			table.insert(core._on_joinplayers, fn)
		end,
		register_on_leaveplayer = function(fn)
			table.insert(core._on_leaveplayers, fn)
		end,
		register_on_dieplayer = function(fn)
			table.insert(core._on_dieplayers, fn)
		end,
		register_on_respawnplayer = function(fn)
			table.insert(core._on_respawnplayers, fn)
		end,
		register_on_mods_loaded = function(fn)
			table.insert(core._on_mods_loaded, fn)
		end,
		register_on_player_hpchange = function(fn)
			table.insert(core._on_hpchange, fn)
		end,
		register_on_item_eat = function(fn)
			table.insert(core._on_item_eat, fn)
		end,
		register_on_punchnode = function(fn)
			table.insert(core._on_punchnode, fn)
		end,
		register_on_punchplayer = function(fn)
			table.insert(core._on_punchplayer, fn)
		end,
		register_on_placenode = function(fn)
			table.insert(core._on_placenode, fn)
		end,
		register_on_shutdown = function(fn)
			table.insert(core._on_shutdown, fn)
		end,
		item_eat = function(hp_change, replace_with_item)
			return function(itemstack, user, pointed_thing)
				if core.do_item_eat then
					return core.do_item_eat(hp_change, replace_with_item, itemstack, user, pointed_thing)
				end
				return itemstack
			end
		end,
		do_item_eat = function(hp_change, replace_with_item, itemstack, user, pointed_thing)
			if itemstack and itemstack.take_item then
				itemstack:take_item()
			end
			for _, cb in ipairs(core._on_item_eat) do
				cb(hp_change, replace_with_item, itemstack, user, pointed_thing)
			end
			return itemstack
		end,
		log = function() end,
		add_particlespawner = function(def)
			local id = core._next_spawner_id
			core._next_spawner_id = core._next_spawner_id + 1
			core._particlespawners[id] = def
			return id
		end,
		delete_particlespawner = function(id)
			core._particlespawners[id] = nil
		end,
		register_chatcommand = function(name, def)
			core.chatcommands[name] = def
			core.registered_chatcommands[name] = def
		end,
		after = function(delay, fn, ...)
			table.insert(core._after_timers, {delay = delay, fn = fn, args = {...}})
		end,
		get_connected_players = function()
			return core._connected_players
		end,
		get_player_by_name = function(name)
			for _, p in ipairs(core._connected_players) do
				if p:get_player_name() == name then
					return p
				end
			end
			return nil
		end,
		add_entity = function(pos, entity_name)
			local def = core.registered_entities[entity_name]
			if not def then return nil end
			local obj = {
				_pos = {x = pos.x, y = pos.y, z = pos.z},
				_properties = {},
				_armor_groups = {},
				_attach = nil,
				_removed = false,
				_luaentity = nil,

				set_properties = function(self, props)
					for k, v in pairs(props) do
						self._properties[k] = v
					end
				end,
				get_properties = function(self)
					return self._properties
				end,
				set_armor_groups = function(self, groups)
					self._armor_groups = groups
				end,
				set_attach = function(self, parent, bone, position, rotation, forced_visible)
					if self._attach and self._attach.parent and self._attach.parent._children then
						for i = #self._attach.parent._children, 1, -1 do
							if self._attach.parent._children[i] == self then
								table.remove(self._attach.parent._children, i)
							end
						end
					end
					self._attach = {
						parent = parent,
						bone = bone,
						pos = position,
						rot = rotation,
						forced = forced_visible,
					}
					if parent then
						parent._children = parent._children or {}
						local found = false
						for i = 1, #parent._children do
							if parent._children[i] == self then found = true; break end
						end
						if not found then
							table.insert(parent._children, self)
						end
					end
				end,
				set_detach = function(self)
					self._detach_calls = (self._detach_calls or 0) + 1
					if self._attach and self._attach.parent and self._attach.parent._children then
						for i = #self._attach.parent._children, 1, -1 do
							if self._attach.parent._children[i] == self then
								table.remove(self._attach.parent._children, i)
							end
						end
					end
					self._attach = nil
				end,
				get_attach = function(self)
					if not self._attach then return nil end
					return self._attach.parent, self._attach.bone, self._attach.pos, self._attach.rot, self._attach.forced
				end,
				get_children = function(self)
					local res = {}
					if self._children then
						for i = 1, #self._children do
							local child = self._children[i]
							if child and child:is_valid() then
								table.insert(res, child)
							end
						end
					end
					return res
				end,
				set_observers = function(self, observers)
					self._observers = observers
				end,
				get_observers = function(self)
					return self._observers
				end,
				set_bone_position = function(self, bone, position, rotation)
					self._bones = self._bones or {}
					self._bones[bone] = {pos = position, rot = rotation}
				end,
				get_bone_position = function(self, bone)
					if self._bone_overrides and self._bone_overrides[bone] then
						local ov = self._bone_overrides[bone]
						local p = (ov.position and ov.position.vec) or {x=0, y=0, z=0}
						local r = (ov.rotation and ov.rotation.vec) or {x=0, y=0, z=0}
						return p, {
							x = math.deg(r.x or 0),
							y = math.deg(r.y or 0),
							z = math.deg(r.z or 0),
						}
					end
					if not self._bones or not self._bones[bone] then return {x=0, y=0, z=0}, {x=0, y=0, z=0} end
					return self._bones[bone].pos, self._bones[bone].rot
				end,
				set_bone_override = function(self, bone, override)
					self._bone_overrides = self._bone_overrides or {}
					self._bone_overrides[bone] = override
				end,
				get_bone_override = function(self, bone)
					return self._bone_overrides and self._bone_overrides[bone]
				end,
				get_bone_overrides = function(self)
					return self._bone_overrides or {}
				end,
				set_animation = function(self, ...)
					self._animation_calls = self._animation_calls or {}
					table.insert(self._animation_calls, {...})
				end,
				play_animation = function(self, track, params)
					self._played_animations = self._played_animations or {}
					table.insert(self._played_animations, {track = track, params = params})
				end,
				update_animation = function(self, track, update)
					self._updated_animations = self._updated_animations or {}
					table.insert(self._updated_animations, {track = track, update = update})
				end,
				stop_animation = function(self, track)
					self._stopped_animations = self._stopped_animations or {}
					table.insert(self._stopped_animations, track)
				end,
				get_pos = function(self)
					if self._removed then return nil end
					return self._pos
				end,
				set_pos = function(self, new_pos)
					self._pos = {x = new_pos.x, y = new_pos.y, z = new_pos.z}
				end,
				remove = function(self)
					self._removed = true
					self._attach = nil
				end,
				is_valid = function(self)
					return not self._removed
				end,
				get_luaentity = function(self)
					if self._removed then return nil end
					return self._luaentity
				end,
			}
			for k, v in pairs(def.initial_properties or {}) do
				obj._properties[k] = v
			end
			local luaent = {object = obj, name = entity_name}
			for k, v in pairs(def) do
				if type(v) == "function" then
					luaent[k] = v
				end
			end
			obj._luaentity = luaent
			if luaent.on_activate then
				luaent:on_activate()
			end
			return obj
		end,
	}

	rawset(_G, "core", core_mock)
	rawset(_G, "minetest", core_mock)
end

local MockPlayerRef = {
	is_valid = function(self)
		return not self._removed
	end,
	set_bone_position = function(self, bone, position, rotation)
		self._bones = self._bones or {}
		self._bones[bone] = {pos = position, rot = rotation}
	end,
	get_bone_position = function(self, bone)
		if self._bone_overrides and self._bone_overrides[bone] then
			local ov = self._bone_overrides[bone]
			local p = (ov.position and ov.position.vec) or {x=0, y=0, z=0}
			local r = (ov.rotation and ov.rotation.vec) or {x=0, y=0, z=0}
			return p, {
				x = math.deg(r.x or 0),
				y = math.deg(r.y or 0),
				z = math.deg(r.z or 0),
			}
		end
		if not self._bones or not self._bones[bone] then return {x=0, y=0, z=0}, {x=0, y=0, z=0} end
		return self._bones[bone].pos, self._bones[bone].rot
	end,
	set_bone_override = function(self, bone, override)
		self._bone_overrides = self._bone_overrides or {}
		self._bone_overrides[bone] = override
	end,
	get_bone_override = function(self, bone)
		return self._bone_overrides and self._bone_overrides[bone]
	end,
	get_bone_overrides = function(self)
		return self._bone_overrides or {}
	end,
	set_properties = function(self, props)
		self._props = self._props or {}
		for k, v in pairs(props) do self._props[k] = v end
	end,
	get_properties = function(self)
		return self._props or {}
	end,
}
MockPlayerRef.__index = MockPlayerRef
mock_env.PlayerRef = MockPlayerRef

function mock_env.create_player(name)
	local wielded = {name = "", count = 0}
	local p = {
		_name = name,
		_hp = 20,
		_pos = {x = 0, y = 10, z = 0},
		_props = {},
		is_player = function() return true end,
		is_valid = function(self) return not self._removed end,
		get_player_name = function(self) return self._name end,
		get_hp = function(self) return self._hp end,
		set_hp = function(self, hp) self._hp = hp end,
		get_pos = function(self) return self._pos end,
		set_pos = function(self, pos) self._pos = {x = pos.x, y = pos.y, z = pos.z} end,
		get_wielded_item = function()
			local meta_table = wielded.meta or {}
			return {
				get_name = function() return wielded.name end,
				is_empty = function() return wielded.name == "" or wielded.count <= 0 end,
				get_count = function() return wielded.count end,
				to_string = function()
					if wielded.name == "" then return "" end
					if meta_table.color then
						return string.format('%s 1 0 "\1color\2%s\3"', wielded.name, meta_table.color)
					end
					if (wielded.count or 1) > 1 then
						return string.format("%s %d", wielded.name, wielded.count)
					end
					return wielded.name
				end,
				get_meta = function()
					return {
						get_string = function(_, k) return meta_table[k] or "" end,
						set_string = function(_, k, v) meta_table[k] = v end,
					}
				end,
			}
		end,
		set_wielded_item = function(_, item_name, count, meta)
			wielded.name = item_name or ""
			wielded.count = count or (item_name ~= "" and 1 or 0)
			wielded.meta = meta or {}
		end,
		get_player_control = function(self) return (self and self._controls) or {} end,
		get_player_control_bits = function(self)
			if self and self._control_bits then return self._control_bits end
			local c = (self and type(self.get_player_control) == "function" and self:get_player_control())
				or (self and self._controls) or {}
			local bits = 0
			if c.up then bits = bits + 1 end
			if c.down then bits = bits + 2 end
			if c.left then bits = bits + 4 end
			if c.right then bits = bits + 8 end
			if c.jump then bits = bits + 16 end
			if c.aux1 then bits = bits + 32 end
			if c.sneak then bits = bits + 64 end
			if c.LMB then bits = bits + 128 end
			if c.RMB then bits = bits + 256 end
			if c.zoom then bits = bits + 512 end
			return bits
		end,
		_yaw = 0,
		_velocity = {x = 0, y = 0, z = 0},
		_attach = nil,
		get_look_horizontal = function(self) return self._yaw or 0 end,
		set_look_horizontal = function(self, yaw) self._yaw = yaw end,
		get_yaw = function(self) return self._yaw or 0 end,
		set_yaw = function(self, yaw) self._yaw = yaw end,
		get_velocity = function(self) return self._velocity or {x = 0, y = 0, z = 0} end,
		set_velocity = function(self, vel) self._velocity = {x = vel.x or 0, y = vel.y or 0, z = vel.z or 0} end,
		get_player_velocity = function(self) return self:get_velocity() end,
		set_attach = function(self, parent, bone, position, rotation, forced_visible)
			if self._attach and self._attach.parent and self._attach.parent._children then
				for i = #self._attach.parent._children, 1, -1 do
					if self._attach.parent._children[i] == self then
						table.remove(self._attach.parent._children, i)
					end
				end
			end
			self._attach = {
				parent = parent,
				bone = bone,
				pos = position,
				rot = rotation,
				forced = forced_visible,
			}
			if parent then
				parent._children = parent._children or {}
				local found = false
				for i = 1, #parent._children do
					if parent._children[i] == self then found = true; break end
				end
				if not found then
					table.insert(parent._children, self)
				end
			end
		end,
		set_detach = function(self)
			if self._attach and self._attach.parent and self._attach.parent._children then
				for i = #self._attach.parent._children, 1, -1 do
					if self._attach.parent._children[i] == self then
						table.remove(self._attach.parent._children, i)
					end
				end
			end
			self._attach = nil
		end,
		get_attach = function(self)
			if not self._attach then return nil end
			return self._attach.parent, self._attach.bone, self._attach.pos, self._attach.rot, self._attach.forced
		end,
		get_children = function(self)
			local res = {}
			if self._children then
				for i = 1, #self._children do
					local child = self._children[i]
					if child and child:is_valid() then
						table.insert(res, child)
					end
				end
			end
			return res
		end,
		set_local_animation = function(self, ...)
			self._local_animation_calls = self._local_animation_calls or {}
			table.insert(self._local_animation_calls, {...})
		end,
		set_animation = function(self, anim, speed, blend, loop)
			self._last_animation = {anim = anim, speed = speed, blend = blend, loop = loop}
		end,
		_played_animations = {},
		_stopped_animations = {},
		_updated_animations = {},
		play_animation = function(self, track, params)
			table.insert(self._played_animations, {track = track, params = params})
		end,
		update_animation = function(self, track, update)
			table.insert(self._updated_animations, {track = track, update = update})
		end,
		stop_animation = function(self, track)
			table.insert(self._stopped_animations, track)
		end,
	}
	return setmetatable(p, MockPlayerRef)
end

function mock_env.leave_player(player)
	local name = player:get_player_name()
	for i = #core._connected_players, 1, -1 do
		if core._connected_players[i]:get_player_name() == name then
			table.remove(core._connected_players, i)
		end
	end
	for _, leave_cb in ipairs(core._on_leaveplayers) do
		leave_cb(player)
	end
end

function mock_env.join_player(name)
	name = name or "Hero"
	for i = #core._connected_players, 1, -1 do
		if core._connected_players[i]:get_player_name() == name then
			table.remove(core._connected_players, i)
		end
	end
	local p = mock_env.create_player(name)
	table.insert(core._connected_players, p)
	for _, join_cb in ipairs(core._on_joinplayers) do
		join_cb(p)
	end
	local timers = core._after_timers
	core._after_timers = {}
	local unpack_fn = rawget(table, "unpack") or unpack
	for _, t in ipairs(timers) do
		t.fn(unpack_fn(t.args or {}))
	end
	return p
end

function mock_env.step_timers(dt)
	dt = dt or 0.05
	local timers = core._after_timers
	core._after_timers = {}
	local unpack_fn = rawget(table, "unpack") or unpack
	for _, t in ipairs(timers) do
		t.delay = t.delay - dt
		if t.delay <= 0.0001 then
			t.fn(unpack_fn(t.args or {}))
		else
			table.insert(core._after_timers, t)
		end
	end
end

function mock_env.read_u32_le(str, pos)
	local b1, b2, b3, b4 = str:byte(pos, pos + 3)
	if not b4 then return 0 end
	return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
end

function mock_env.read_f32_le(str, pos)
	local b1, b2, b3, b4 = str:byte(pos, pos + 3)
	if not b4 then return 0.0 end
	local sign = (b4 >= 128) and -1 or 1
	local exp = (b4 % 128) * 2 + math.floor(b3 / 128)
	local mant = ((b3 % 128) * 256 + b2) * 256 + b1
	if exp == 0 then
		if mant == 0 then return 0.0 end
		return sign * (mant / 8388608) * (2 ^ -126)
	elseif exp == 255 then
		return sign * ((mant == 0) and (1 / 0) or (0 / 0))
	end
	return sign * (1 + mant / 8388608) * (2 ^ (exp - 127))
end

function mock_env.init(custom_init)
	mock_env.setup()
	local source = debug.getinfo(1, "S").source:match("^@?(.-)tests/mock_env%.lua$")
	local root = (source and source ~= "") and source or "./"
	if root:sub(-1) ~= "/" then root = root .. "/" end
	dofile(custom_init or (root .. "init.lua"))
end

return mock_env
