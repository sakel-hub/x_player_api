-- x_player_api controls management module
-- Provides control tracking, double-tap detection, and semantic player states.

---@class PlayerControlState
---@field keys table<string, number|boolean> Raw control key hold state
---@field last_press_time table<string, number> Timestamps for double-tap detection
---@field double_tap_sprint boolean Whether double-tap sprinting is active
---@field sliding_until number Expiration timestamp for power slide
---@field bow_shoot_until number Expiration timestamp for bow firing animation
---@field hurt_until number Expiration timestamp for hurt flinch
---@field lmb_action_until number Expiration timestamp for LMB action duration window
---@field lmb_action string|nil Active action identifier triggered by LMB
---@field lmb_cycle_count integer Number of action cycles completed
---@field was_on_ground boolean Grounded flag from previous step
---@field prev_bow_charged boolean Charged bow state from previous step
---@field active_emote string|nil Active gesture or posture emote name
---@field emote_until number Expiration timestamp for active emote (-1 for indefinite)
---@field equip_until number|nil Expiration timestamp for weapon equip montage
---@field prev_loco_state string Previous locomotion state identifier
---@field prev_action_state string|nil Previous action state identifier
---@field semantic_state PlayerSemanticState Cached semantic state table
---@field controls table<string, boolean|number>|nil Last sampled player controls table
---@field prev_control_bits integer|nil Last sampled player control bitmask

---@class PlayerSemanticState
---@field moving boolean Whether player has directional horizontal motion
---@field sprinting boolean Whether player is sprinting
---@field crouching boolean Whether player is sneaking/crouching
---@field crouch_walking boolean Whether player is sneaking while moving
---@field sliding boolean Whether player is power-sliding
---@field jumping boolean Whether player is ascending in jump arc
---@field falling boolean Whether player is descending in free-fall
---@field flying boolean Whether player is flying with flight speed
---@field hovering boolean Whether player is hovering in air
---@field swimming boolean Whether player is in water or submerged
---@field climbing boolean Whether player is on ladder or vine
---@field climbing_active boolean Whether player is moving up/down a ladder
---@field acting boolean Whether player is actively mining or using item
---@field blocking boolean Whether player is holding shield block
---@field eating boolean Whether player is consuming food or beverage
---@field aiming_bow boolean Whether player is drawing back a bow
---@field shooting_bow boolean Whether player is releasing a bow shot
---@field hurt boolean Whether player is reacting to damage
---@field equipping boolean Whether player is performing weapon equip animation
---@field locomotion string Active locomotion animation track or alias
---@field action string|nil Active upper-body action track or alias
---@field emote string|nil Active gesture or posture emote track or alias

---@class ItemActionDefinition
---@field action string Primary attack/action track name (e.g. "attack_slash", "attack_thrust", "mine")
---@field alt_action? string Secondary action track name (e.g. "block")
---@field shoot_action? string Bow release/fire track name (e.g. "bow_shoot")
---@field is_shield? boolean Whether this item behaves as a defensive shield
---@field is_bow? boolean Whether this item behaves as an aiming bow

---@class ItemClassification
---@field is_shield boolean Whether item acts as a shield
---@field is_bow boolean Whether item acts as a bow
---@field is_bow_charged boolean Whether item is currently in drawn/charged state
---@field is_food boolean Whether item is edible or consumable
---@field weapon_action string Primary action track name
---@field action_def ItemActionDefinition|nil Registered item action configuration

---@class StateEvaluationContext
---@field player ObjectRef Target player
---@field controls table<string, boolean> Raw player control keys
---@field pos Vector3 Player world position
---@field vel Vector3 Player velocity vector
---@field hp number Player health points
---@field is_moving boolean Whether player has directional movement
---@field is_sprinting boolean Whether player is sprinting
---@field in_air boolean Whether player is airborne
---@field in_water boolean Whether player is submerged in liquid
---@field on_ladder boolean Whether player is attached to a climbable node
---@field wield_name string Name of currently wielded item
---@field item_info ItemClassification Classification of held item
---@field time_now number Current server timestamp in seconds
---@field is_hurt boolean Whether hurt flinch is active
---@field is_equipping boolean Whether weapon equip animation is active

---@alias StateChangeCallback fun(player: ObjectRef, state: PlayerSemanticState, prev_loco: string, prev_act: string?)
---@alias StateEvaluatorFunc fun(player: ObjectRef, ctx: StateEvaluationContext): string?

---@class PlayerControlsSubsystem
---@field registered_on_press (fun(player: ObjectRef, key: string))[]
---@field registered_on_hold (fun(player: ObjectRef, key: string, duration: number))[]
---@field registered_on_release (fun(player: ObjectRef, key: string, duration: number))[]
---@field registered_on_state_change StateChangeCallback[]
---@field locomotion_evaluators {priority: number, func: StateEvaluatorFunc}[]
---@field action_evaluators {priority: number, func: StateEvaluatorFunc}[]
---@field player_states table<string, PlayerControlState>

x_player_api = rawget(_G, "x_player_api") or rawget(_G, "player_api") or {}

local S = core.get_translator(core.get_current_modname())

---@type PlayerControlsSubsystem
x_player_api.controls = {
	registered_on_press = {},
	registered_on_hold = {},
	registered_on_release = {},
	registered_on_state_change = {},
	locomotion_evaluators = {},
	action_evaluators = {},
	player_states = {},
}

---@type (fun(player: ObjectRef, wield_name: string, item_info: ItemClassification): boolean)[]
x_player_api.blocking_predicates = x_player_api.blocking_predicates or {}

---Register a predicate function to determine whether a player is capable of blocking
---@param predicate fun(player: ObjectRef, wield_name: string, item_info: ItemClassification): boolean
function x_player_api.register_blocking_predicate(predicate)
	table.insert(x_player_api.blocking_predicates, predicate)
end

local ctrl = x_player_api.controls
local states = ctrl.player_states

-- Fast localized math functions for LuaJIT hot loop
local math_abs = math.abs
local math_sqrt = math.sqrt

-- Static immutable zero-allocation fallbacks
local ZERO_VEL = {x = 0, y = 0, z = 0}

-- Fixed numeric control keys array for linear trace compilation without pairs()
local CONTROL_KEYS = {
	"up", "down", "left", "right", "jump", "aux1", "sneak", "LMB", "RMB", "zoom", "dig", "place"
}

local enable_double_tap_sprint = core.settings:get_bool("x_player_api.enable_double_tap_sprint", true)

-- Double-tap detection threshold (in seconds)
local DOUBLE_TAP_TIME = 0.28
-- Slide duration (in seconds)
local SLIDE_DURATION = 0.8

---@type table
local scratch_eval_ctx = {}
local is_evaluating_ctx = false

---@type table<string, ItemClassification> Memoized item classification cache
local ITEM_CACHE = {}

x_player_api.registered_item_actions = x_player_api.registered_item_actions or {}
local item_actions = x_player_api.registered_item_actions

---@type table<string, string>
x_player_api.registered_weapon_categories = x_player_api.registered_weapon_categories or {
	["group:spear"] = "attack_thrust",
	["group:pike"] = "attack_thrust",
	["group:javelin"] = "attack_thrust",
	["group:sword"] = "attack_slash",
	["group:blade"] = "attack_slash",
	["group:saber"] = "attack_slash",
}
local weapon_categories = x_player_api.registered_weapon_categories

---Register or override a weapon category mapping
---@param category string Group filter (e.g. "group:spear") or exact item name
---@param action string Primary action track name (e.g. "attack_thrust")
function x_player_api.register_weapon_category(category, action)
	weapon_categories[category] = action
	x_player_api.clear_item_cache()
end

---Clear internal item classification cache
function x_player_api.clear_item_cache()
	ITEM_CACHE = {}
	x_player_api.clear_equip_sound_cache()
	x_player_api.clear_wield_params_cache()
	x_player_api.clear_consumable_cache()
end

---Register an action definition for an item name or group
---@param item_or_group string Item name or group filter (e.g. "group:sword", "default:sword_steel")
---@param def string|ItemActionDefinition Action name string or definition table
function x_player_api.register_item_action(item_or_group, def)
	if type(def) == "string" then
		item_actions[item_or_group] = {action = def}
	elseif type(def) == "table" then
		item_actions[item_or_group] = def
	end
	x_player_api.clear_item_cache()
end

---Get registered action configuration for an item name
---@nodiscard
---@param item_name string Item name
---@return ItemActionDefinition|nil action_def Registered configuration or nil
function x_player_api.get_item_action(item_name)
	if not item_name or item_name == "" then
		return nil
	end

	-- Direct item match
	if item_actions[item_name] then
		return item_actions[item_name]
	end

	-- Group matches
	for key, act_def in pairs(item_actions) do
		if key:sub(1, 6) == "group:" then
			local group = key:sub(7)
			if core.get_item_group(item_name, group) > 0 then
				return act_def
			end
		end
	end

	return nil
end

-- Register standard engine and Luanti defaults out of the box
x_player_api.register_item_action("group:sword", "attack_slash")
x_player_api.register_item_action("group:spear", "attack_thrust")
x_player_api.register_item_action("group:shield", {action = "block", alt_action = "block", is_shield = true})
x_player_api.register_item_action("group:armor_shield", {action = "block", alt_action = "block", is_shield = true})
x_player_api.register_item_action("group:bow", {action = "bow_aim", shoot_action = "bow_shoot", is_bow = true})

local EMPTY_CLASSIFICATION = {
	is_shield = false,
	is_bow = false,
	is_bow_charged = false,
	is_food = false,
	weapon_action = "mine",
	action_def = nil,
}

---Classify wielded item properties with memoized results
---@nodiscard
---@param item_name string Item name
---@return ItemClassification classification
local function classify_item(item_name)
	if not item_name or item_name == "" then
		return EMPTY_CLASSIFICATION
	end

	local cached = ITEM_CACHE[item_name]
	if cached then
		return cached
	end

	local action_def = x_player_api.get_item_action(item_name)
	local lname = item_name:lower()

	local is_shield = (action_def and action_def.is_shield == true)
		or (action_def and action_def.action == "block")
		or (core.get_item_group(item_name, "shield") > 0)
		or (core.get_item_group(item_name, "armor_shield") > 0)
		or (lname:find("shield") ~= nil)

	local is_bow = (action_def and action_def.is_bow == true)
		or (action_def and (action_def.action == "bow_aim" or action_def.shoot_action == "bow_shoot"))
		or (core.get_item_group(item_name, "bow") > 0)
		or (lname:find("bow") ~= nil and not lname:find("bowl") and not lname:find("rainbow"))

	local is_bow_charged = false
	if is_bow then
		is_bow_charged = (core.get_item_group(item_name, "bow_charged") > 0)
			or (core.get_item_group(item_name, "charged") > 0)
			or (lname:find("_charged") ~= nil)
			or (lname:find("_loaded") ~= nil)
	end

	local is_food = x_player_api.is_consumable(item_name) or false

	local weapon_action = (action_def and action_def.action)
	if not weapon_action then
		if weapon_categories[item_name] then
			weapon_action = weapon_categories[item_name]
		else
			for cat_pattern, cat_action in pairs(weapon_categories) do
				if cat_pattern:sub(1, 6) == "group:" then
					local group = cat_pattern:sub(7)
					if core.get_item_group(item_name, group) > 0 then
						weapon_action = cat_action
						break
					end
				end
			end
		end
	end
	if not weapon_action then
		if is_food then
			weapon_action = (action_def and action_def.action) or "eat"
		else
			weapon_action = "mine"
		end
	end

	local result = {
		is_shield = is_shield,
		is_bow = is_bow,
		is_bow_charged = is_bow_charged,
		is_food = is_food,
		weapon_action = weapon_action,
		action_def = action_def,
	}

	ITEM_CACHE[item_name] = result
	return result
end

---Register a callback invoked immediately when a control key transition to pressed
---@param callback fun(player: ObjectRef, key: string)
function x_player_api.register_on_press(callback)
	table.insert(ctrl.registered_on_press, callback)
end

---Register a callback invoked continuously each tick while a control key is held
---@param callback fun(player: ObjectRef, key: string, duration: number)
function x_player_api.register_on_hold(callback)
	table.insert(ctrl.registered_on_hold, callback)
end

---Register a callback invoked immediately when a control key transitions to released
---@param callback fun(player: ObjectRef, key: string, duration: number)
function x_player_api.register_on_release(callback)
	table.insert(ctrl.registered_on_release, callback)
end

---Register a callback invoked whenever high-level player state changes
---@param callback StateChangeCallback
function x_player_api.register_on_state_change(callback)
	table.insert(ctrl.registered_on_state_change, callback)
end

---Register a custom locomotion state evaluator
---@param priority number Higher numbers evaluate first
---@param evaluator StateEvaluatorFunc Return state name string or nil to fall through
function x_player_api.register_locomotion_evaluator(priority, evaluator)
	table.insert(ctrl.locomotion_evaluators, {priority = priority or 0, func = evaluator})
	table.sort(ctrl.locomotion_evaluators, function(a, b) return a.priority > b.priority end)
end

---Register a custom action state evaluator
---@param priority number Higher numbers evaluate first
---@param evaluator StateEvaluatorFunc Return state name string or nil to fall through
function x_player_api.register_action_evaluator(priority, evaluator)
	table.insert(ctrl.action_evaluators, {priority = priority or 0, func = evaluator})
	table.sort(ctrl.action_evaluators, function(a, b) return a.priority > b.priority end)
end

-- Initialize tracking on join
core.register_on_joinplayer(function(player)
	local name = player:get_player_name()
	states[name] = {
		keys = {},
		last_press_time = {},
		double_tap_sprint = false,
		sliding_until = 0,
		bow_shoot_until = 0,
		hurt_until = 0,
		lmb_action_until = 0,
		lmb_action = nil,
		lmb_cycle_count = 0,
		eat_until = 0,
		last_chew_particle_time = 0,
		equip_until = 0,
		was_on_ground = true,
		was_jumping = false,
		prev_bow_charged = false,
		active_emote = nil,
		emote_until = 0,
		test_anim = nil,
		test_anim_is_action = false,
		prev_loco_state = "stand",
		prev_action_state = nil,
		semantic_state = {
			moving = false,
			sprinting = false,
			crouching = false,
			crouch_walking = false,
			sliding = false,
			jumping = false,
			falling = false,
			flying = false,
			hovering = false,
			swimming = false,
			climbing = false,
			climbing_active = false,
			acting = false,
			blocking = false,
			eating = false,
			aiming_bow = false,
			shooting_bow = false,
			hurt = false,
			equipping = false,
			locomotion = "stand",
			action = nil,
			emote = nil,
		},
		controls = nil,
		prev_control_bits = 0,
	}
	for i = 1, #CONTROL_KEYS do
		states[name].keys[CONTROL_KEYS[i]] = false
	end
end)

-- Cleanup on leave
core.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	x_player_api.stop_anim_test(name, true)
	states[name] = nil
end)

-- Cancel active test animation on player death
core.register_on_dieplayer(function(player)
	local name = player:get_player_name()
	x_player_api.stop_anim_test(name, true)
end)

---Trigger bow shoot animation externally
---@param player ObjectRef Target player
---@param duration? number Duration in seconds (defaults to 0.35s)
function x_player_api.trigger_bow_shoot(player, duration)
	if not player or not player.is_player or not player:is_player() then return end
	local name = player:get_player_name()
	local pstate = states[name]
	if not pstate then return end
	pstate.bow_shoot_until = (core.get_us_time() * 0.000001) + (duration or 0.35)
end

---Trigger hurt reaction animation externally
---@param player ObjectRef Target player
---@param duration? number Duration in seconds (defaults to 0.35s)
function x_player_api.trigger_hurt(player, duration)
	if not player or not player.is_player or not player:is_player() then return end
	local name = player:get_player_name()
	local pstate = states[name]
	if not pstate then return end
	local time_now = core.get_us_time() * 0.000001
	pstate.hurt_until = time_now + (duration or 0.35)

	-- Play immediately with force restart (zero-latency visual feedback & rapid-hit support)
	x_player_api.play_action(player, "hurt", true)
end

-- Trigger hurt animation on player damage
core.register_on_player_hpchange(function(player, hp_change)
	if hp_change and hp_change < 0 and player and player:is_player() then
		-- Only flinch if the player survives the blow; fatal damage transitions directly to death (lay)
		if player:get_hp() > 0 and (player:get_hp() + hp_change > 0) then
			x_player_api.trigger_hurt(player, 0.35)
		end
	end
end)

-- Spatial ground, liquid, and ladder detection is handled modularly in environment.lua
local is_ground_near = function(pos, dist, pstate) return x_player_api.is_ground_near(pos, dist, pstate) end

---Bitmask constants corresponding to Luanti engine control bits
local BIT_UP    = 0x001
local BIT_DOWN  = 0x002
local BIT_LEFT  = 0x004
local BIT_RIGHT = 0x008
local BIT_JUMP  = 0x010
local BIT_AUX1  = 0x020
local BIT_SNEAK = 0x040
local BIT_LMB   = 0x080
local BIT_RMB   = 0x100

---Get integer control bitmask from active player controls
---@nodiscard
---@param controls table<string, boolean>
---@return integer bitmask 9-bit packed integer mask
function x_player_api.get_player_control_bits(controls)
	local bits = 0
	if controls.up then bits = bits + BIT_UP end
	if controls.down then bits = bits + BIT_DOWN end
	if controls.left then bits = bits + BIT_LEFT end
	if controls.right then bits = bits + BIT_RIGHT end
	if controls.jump then bits = bits + BIT_JUMP end
	if controls.aux1 then bits = bits + BIT_AUX1 end
	if controls.sneak then bits = bits + BIT_SNEAK end
	if controls.LMB or controls.dig then bits = bits + BIT_LMB end
	if controls.RMB or controls.place then bits = bits + BIT_RMB end
	return bits
end

---Update raw keys and detect presses, holds, releases, double-taps
---@param player ObjectRef
---@param _dtime number
---@param time_now number? Optional timestamp in seconds to avoid redundant system calls
function x_player_api.update_player_controls(player, _dtime, time_now)
	local name = player:get_player_name()
	local pstate = states[name]
	if not pstate then return end

	time_now = time_now or (core.get_us_time() * 0.000001)
	local current_controls = player:get_player_control()
	pstate.controls = current_controls

	-- Fast control-bits change tracking
	local current_bits = (player.get_player_control_bits and player:get_player_control_bits()) or 0
	pstate.prev_control_bits = current_bits

	-- Cache player position for step reuse (avoiding redundant vector allocations)
	local pos = player:get_pos()
	pstate.pos = pos

	-- Bow release/charge tracking
	local wielded = player:get_wielded_item()
	local wield_name = wielded and wielded:get_name() or ""
	pstate.wielded_item = wielded
	pstate.wield_name = wield_name
	local item_info = classify_item(wield_name)
	pstate.item_info = item_info
	local is_bow_charged = item_info.is_bow_charged
	if pstate.prev_bow_charged and not is_bow_charged
		and (current_controls.LMB or current_controls.dig or not current_controls.RMB) then
		pstate.bow_shoot_until = time_now + 0.35
	end
	pstate.prev_bow_charged = is_bow_charged

	-- Action tracking (attacks, mining, interactions, secondary clicks on LMB and RMB)
	local is_lmb = (current_controls.LMB or current_controls.dig) and not (current_controls.RMB or current_controls.place)
	local is_rmb = (current_controls.RMB or current_controls.place) and not (current_controls.LMB or current_controls.dig)
	local can_block = item_info.is_shield
	if not can_block and x_player_api.blocking_predicates then
		for _, pred in ipairs(x_player_api.blocking_predicates) do
			if pred(player, wield_name, item_info) then
				can_block = true
				break
			end
		end
	end
	local is_blocking = is_rmb and can_block
	local is_aiming_bow = item_info.is_bow and (item_info.is_bow_charged or current_controls.RMB or current_controls.place)

	if is_lmb and not item_info.is_food then
		local act = item_info.weapon_action or "mine"
		if pstate.lmb_action ~= act or (pstate.lmb_action_until or 0) <= time_now then
			pstate.lmb_action = act
			pstate.lmb_action_until = time_now + 0.45
			pstate.lmb_cycle_count = (pstate.lmb_cycle_count or 0) + 1
		end
	elseif is_rmb and not is_blocking and not is_aiming_bow and not item_info.is_food then
		-- Default animation for RMB interaction/secondary clicks (placing nodes, interacting with world)
		local act = item_info.alt_action or "mine"
		if pstate.lmb_action ~= act or (pstate.lmb_action_until or 0) <= time_now then
			pstate.lmb_action = act
			pstate.lmb_action_until = time_now + 0.45
			pstate.lmb_cycle_count = (pstate.lmb_cycle_count or 0) + 1
		end
	end

	for i = 1, #CONTROL_KEYS do
		local key = CONTROL_KEYS[i]
		local pressed = current_controls[key]
		local was_pressed = pstate.keys[key]

		if pressed and not was_pressed then
			-- Pressed event
			local last_press = pstate.last_press_time[key] or 0
			local activated_double_tap = false
			if key == "up" and enable_double_tap_sprint then
				if (time_now - last_press) <= DOUBLE_TAP_TIME then
					pstate.double_tap_sprint = true
					activated_double_tap = true
				end
			end

			-- Detect sprint-slide (pressing sneak while sprinting on ground)
			if key == "sneak" and (current_controls.aux1 or pstate.double_tap_sprint) and current_controls.up then
				if pstate.was_on_ground or is_ground_near(pos, 0.5, pstate) then
					pstate.sliding_until = time_now + SLIDE_DURATION
				end
			end

			pstate.last_press_time[key] = activated_double_tap and 0 or time_now
			pstate.keys[key] = time_now

			local callbacks = ctrl.registered_on_press
			for cb_i = 1, #callbacks do
				callbacks[cb_i](player, key)
			end
		elseif pressed and was_pressed then
			-- Held event
			local duration = (type(was_pressed) == "number" and (time_now - was_pressed)) or 0
			local callbacks = ctrl.registered_on_hold
			for cb_i = 1, #callbacks do
				callbacks[cb_i](player, key, duration)
			end
		elseif not pressed and was_pressed then
			-- Released event
			local duration = (type(was_pressed) == "number" and (time_now - was_pressed)) or 0
			pstate.keys[key] = false

			if key == "up" then
				pstate.double_tap_sprint = false
			end

			local callbacks = ctrl.registered_on_release
			for cb_i = 1, #callbacks do
				callbacks[cb_i](player, key, duration)
			end
		end
	end
end
x_player_api.controls.update_player_controls = x_player_api.update_player_controls

---Detect environmental contact flags (water, ladder, ground, airborne)
---@param pos Vector3 Player position
---@param vel Vector3 Player velocity
---@param pstate PlayerControlState? Player internal control state
---@return boolean in_water Whether player is in water
---@return boolean on_ladder Whether player is on ladder or vine
---@return boolean is_on_ground Whether player is supported by ground
---@return boolean in_air Whether player is airborne
local function detect_environment(pos, vel, pstate)
	return x_player_api.detect_environment(pos, vel, pstate)
end

---Evaluate primary locomotion track and movement flags
---@param player ObjectRef Target player
---@param pstate PlayerControlState? Player internal control state
---@param controls table<string, boolean> Player controls table
---@param vel Vector3 Player velocity vector
---@param hp number Player health
---@param is_attached boolean Whether player is attached to mount or vehicle
---@param in_water boolean Whether player is in water
---@param on_ladder boolean Whether player is on ladder
---@param is_on_ground boolean Whether player is grounded
---@param in_air boolean Whether player is airborne
---@param time_now number Current server timestamp in seconds
---@return string loco Primary locomotion track name
---@return boolean is_moving Whether player has horizontal motion
---@return boolean is_sneaking Whether player is holding sneak
---@return boolean is_sprinting Whether player is sprinting
---@return boolean is_sliding Whether player is power-sliding
---@return boolean is_jumping Whether player is ascending
---@return boolean is_falling Whether player is descending
---@return boolean is_flying Whether player is flying
---@return boolean is_hovering Whether player is hovering
---@return boolean climbing_active Whether player is moving on ladder
---@return string|nil active_emote Active posture or gesture emote name
---@return boolean is_gesture_emote Whether active emote is an upper-body gesture
local function resolve_locomotion(player, pstate, controls, vel, hp, is_attached,
		in_water, on_ladder, is_on_ground, in_air, time_now)
	if hp <= 0 then
		return "lay", false, false, false, false, false, false, false, false, false, nil, false
	end

	if is_attached then
		local current_anim = x_player_api.get_animation(player)
		local current_anim_name = current_anim and current_anim.animation
		local loco
		if current_anim_name == "lay" or (pstate and pstate.active_emote == "lay") then
			loco = "lay"
		else
			loco = "sit"
		end
		return loco, false, false, false, false, false, false, false, false, false, nil, false
	end

	-- Check horizontal motion (supports auto-forward F key, analog pads, gamepads)
	local horiz_speed_sq = (vel.x * vel.x) + (vel.z * vel.z)
	local is_moving = controls.up or controls.down or controls.left or controls.right
		or (controls.movement_y and math_abs(controls.movement_y) > 0.05)
		or (controls.movement_x and math_abs(controls.movement_x) > 0.05)
		or (horiz_speed_sq > 0.08)
	local is_forward = not controls.down and (controls.up
		or (controls.movement_y and controls.movement_y > 0.05)
		or (horiz_speed_sq > 0.08 and not controls.left and not controls.right))

	local is_sneaking = controls.sneak

	local climbing_active = on_ladder and (controls.jump or controls.sneak or controls.up or controls.down
		or math_abs(vel.y) > 0.15)

	-- Sprint detection (auxiliary key or double-tap forward while moving)
	local sprint_key = controls.aux1 or (pstate and pstate.double_tap_sprint)
	local is_sprinting = is_moving and is_forward and sprint_key and not is_sneaking and not in_water

	-- Sliding detection (requires forward movement on ground)
	local is_sliding = pstate and (pstate.sliding_until > time_now) and is_moving and is_on_ground and not in_water

	-- Airborne locomotion (velocity and motion driven)
	local is_flying = false
	local is_jumping = false
	local is_falling = false
	local is_hovering = false

	if in_air and not in_water and not on_ladder then
		local horiz_speed = math_sqrt(horiz_speed_sq)
		local fly_speed_threshold = 6.5

		-- Jumping and falling take precedence over flight (e.g. sprint-jumping)
		if vel.y > 0.5 or (controls.jump and vel.y > 0.0) then
			is_jumping = true
			if pstate then pstate.was_jumping = true end
		elseif vel.y < -0.5 then
			is_falling = true
			if pstate then pstate.was_jumping = false end
		elseif pstate and pstate.was_jumping then
			-- Parabolic jump turnover: smooth transition from ascent to descent without hover interrupt
			if vel.y > 0.0 then
				is_jumping = true
			elseif vel.y < 0.0 then
				is_falling = true
				pstate.was_jumping = false
			else
				is_hovering = true
				pstate.was_jumping = false
			end
		else
			-- Level / hovering flight (|vel.y| <= 0.5 and not actively jumping)
			is_flying = is_moving and horiz_speed >= fly_speed_threshold
			if not is_flying then
				is_hovering = true
			end
		end
	elseif not in_water and not on_ladder then
		-- Grounded: detect upward launch impulse with jump key
		if vel.y > 1.2 and controls.jump then
			is_jumping = true
			if pstate then pstate.was_jumping = true end
		end
	end

	-- Emote / posture expiry check (cancel on movement for posture emotes like sit, lay, bow)
	local active_emote = nil
	local cur_emote = pstate and pstate.active_emote
	local reg_emotes = x_player_api.registered_emotes
	local cur_def = cur_emote and reg_emotes and reg_emotes[cur_emote]
	local cur_is_posture = (cur_def and cur_def.is_posture)
		or (cur_emote == "sit" or cur_emote == "lay" or cur_emote == "bow")
	if pstate and cur_emote and (pstate.emote_until == -1 or pstate.emote_until > time_now) then
		if is_moving and cur_is_posture then
			pstate.active_emote = nil
			pstate.emote_until = 0
		else
			active_emote = cur_emote
		end
	elseif pstate and cur_emote then
		pstate.active_emote = nil
	end

	local active_def = active_emote and reg_emotes and reg_emotes[active_emote]
	local is_posture_emote = (active_def and active_def.is_posture)
		or (active_emote == "sit" or active_emote == "lay" or active_emote == "bow")
	local is_gesture_emote = active_emote and not is_posture_emote

	-- Determine primary locomotion animation
	local loco
	if in_water then
		loco = is_moving and "swim" or "stand"
	elseif on_ladder then
		loco = "climb"
	elseif is_posture_emote and not is_moving and not in_air then
		loco = active_emote
	elseif is_sliding then
		loco = "slide"
	elseif is_flying then
		loco = "fly"
	elseif is_jumping then
		loco = "jump"
	elseif is_falling then
		loco = "fall"
	elseif is_hovering then
		loco = "hover"
	elseif is_sneaking then
		loco = is_moving and "crouch_walk" or "crouch"
	elseif is_sprinting then
		loco = "sprint"
	elseif is_moving then
		loco = "walk"
	else
		loco = "stand"
	end

	return loco, is_moving, is_sneaking, is_sprinting, is_sliding,
		is_jumping, is_falling, is_flying, is_hovering, climbing_active,
		active_emote, is_gesture_emote
end

---Evaluate primary upper-body action track and interaction flags
---@param player ObjectRef Target player
---@param pstate PlayerControlState? Player internal control state
---@param controls table<string, boolean> Player controls table
---@param item_info ItemClassification Classification of held item
---@param wield_name string Name of held item
---@param hp number Player health
---@param time_now number Current server timestamp in seconds
---@param is_gesture_emote boolean Whether active emote is a gesture
---@param active_emote string|nil Name of active emote
---@param is_acting boolean Whether player is pressing any action control
---@return string? action Action track name or nil
---@return boolean is_blocking Whether blocking with shield
---@return boolean is_aiming_bow Whether aiming bow
---@return boolean is_shooting_bow Whether releasing bow shot
---@return boolean is_eating Whether consuming food
---@return boolean is_hurt Whether reacting to damage
---@return boolean is_equipping Whether playing equip montage
local function resolve_action(player, pstate, controls, item_info, wield_name,
		hp, time_now, is_gesture_emote, active_emote)
	local can_block = item_info.is_shield
	if not can_block and x_player_api.blocking_predicates then
		for _, pred in ipairs(x_player_api.blocking_predicates) do
			if pred(player, wield_name, item_info) then
				can_block = true
				break
			end
		end
	end
	local is_blocking = (controls.RMB or controls.place) and can_block
	local is_aiming_bow = item_info.is_bow and (item_info.is_bow_charged or controls.RMB or controls.place)
	local is_shooting_bow = (pstate and pstate.bow_shoot_until and (pstate.bow_shoot_until > time_now)) or false
	-- Allow food consumption via LMB (on_use / dig)
	local is_food_click = (controls.LMB or controls.dig) and item_info.is_food
		and not is_blocking and not is_aiming_bow
	local is_eating = (x_player_api.enable_eating ~= false)
		and ((pstate and pstate.eat_until and (pstate.eat_until > time_now)) or is_food_click) or false

	if pstate and not is_eating and pstate.eat_action then
		pstate.eat_action = nil
	end
	if pstate then
		if is_food_click then
			local cdef = x_player_api.get_consumable_definition(wield_name)
			local act_duration = (cdef and cdef.duration) or 1.34
			local act_name = (cdef and cdef.action) or "eat"
			pstate.eat_until = math.max(pstate.eat_until or 0, time_now + act_duration)
			pstate.eat_action = act_name
		end
		if is_eating then
			pstate.last_chew_particle_time = pstate.last_chew_particle_time or 0
			if time_now - pstate.last_chew_particle_time >= 0.25 then
				pstate.last_chew_particle_time = time_now
				x_player_api.spawn_eat_particles(player, wield_name, 0.25)
			end
		else
			pstate.last_chew_particle_time = 0
		end
	end

	local is_hurt = (pstate and pstate.hurt_until and (pstate.hurt_until > time_now)) or false
	local is_equipping = (pstate and pstate.equip_until and (pstate.equip_until > time_now)) or false

	-- Equipping animation auto-cancels immediately if active combat or defense inputs occur
	local is_active_combat_input = (controls.LMB or controls.dig) and not item_info.is_food
	local cancel_equip = is_active_combat_input or is_blocking or is_eating
		or is_aiming_bow or is_shooting_bow or is_hurt
	if is_equipping and cancel_equip then
		if pstate then
			pstate.equip_until = 0
		end
		is_equipping = false
	end

	local action = nil
	if hp > 0 then
		if is_hurt then
			action = "hurt"
		elseif is_shooting_bow then
			action = "bow_shoot"
		elseif is_aiming_bow then
			action = "bow_aim"
		elseif is_blocking then
			action = "block"
		elseif is_eating then
			local cdef = x_player_api.get_consumable_definition(wield_name)
			action = (pstate and pstate.eat_action) or (cdef and cdef.action) or "eat"
		elseif is_equipping then
			action = "equip"
		elseif is_gesture_emote then
			action = active_emote
		elseif (controls.LMB or controls.dig) and not item_info.is_food then
			action = item_info.weapon_action or "mine"
		elseif pstate and pstate.lmb_action_until and (pstate.lmb_action_until > time_now) then
			action = pstate.lmb_action or item_info.weapon_action or "mine"
		elseif (controls.RMB or controls.place) and not is_blocking and not is_aiming_bow and not item_info.is_food then
			action = item_info.alt_action or "mine"
		end
	end

	return action, is_blocking, is_aiming_bow, is_shooting_bow, is_eating, is_hurt, is_equipping
end

---Evaluate high-level locomotion and action state for a player
---@nodiscard
---@param player ObjectRef Target player
---@param time_now number? Optional timestamp in seconds to avoid redundant system calls
---@return PlayerSemanticState state High-level locomotion, action, and movement flags
function x_player_api.get_player_state(player, time_now)
	local name = player:get_player_name()
	local pstate = states[name]
	-- Single-pass control reuse: avoids allocating a second Lua table per frame
	local controls = (pstate and pstate.controls) or player:get_player_control()

	-- Track attachment state (vehicles, mounts, carts)
	local is_attached = x_player_api.player_attached[name]
		or (player:get_attach() ~= nil)

	local pos = (pstate and pstate.pos) or player:get_pos()
	local vel = player:get_velocity() or ZERO_VEL
	local hp = player:get_hp()
	time_now = time_now or (core.get_us_time() * 0.000001)

	local is_acting = controls.dig or controls.place or controls.LMB or controls.RMB
		or (pstate and pstate.lmb_action_until and pstate.lmb_action_until > time_now)

	-- Environmental detection
	local in_water, on_ladder, is_on_ground, in_air = false, false, false, false
	if not is_attached then
		in_water, on_ladder, is_on_ground, in_air = detect_environment(pos, vel, pstate)
	end

	-- Locomotion resolution
	local loco, is_moving, is_sneaking, is_sprinting, is_sliding,
		is_jumping, is_falling, is_flying, is_hovering, climbing_active,
		active_emote, is_gesture_emote = resolve_locomotion(
			player, pstate, controls, vel, hp, is_attached,
			in_water, on_ladder, is_on_ground, in_air, time_now)

	-- Action resolution
	local wielded = (pstate and pstate.wielded_item) or player:get_wielded_item()
	local wield_name = (pstate and pstate.wield_name) or (wielded and wielded:get_name() or "")
	local item_info = (pstate and pstate.item_info) or classify_item(wield_name)

	local action, is_blocking, is_aiming_bow, is_shooting_bow,
		is_eating, is_hurt, is_equipping = resolve_action(
			player, pstate, controls, item_info, wield_name,
			hp, time_now, is_gesture_emote, active_emote)

	-- Extensible evaluators pipeline (allows third-party mods to register custom states)
	if #ctrl.locomotion_evaluators > 0 or #ctrl.action_evaluators > 0 then
		local eval_ctx = scratch_eval_ctx
		local was_evaluating = is_evaluating_ctx
		if was_evaluating then
			eval_ctx = {}
		else
			is_evaluating_ctx = true
		end
		eval_ctx.player = player
		eval_ctx.controls = controls
		eval_ctx.pos = pos
		eval_ctx.vel = vel
		eval_ctx.hp = hp
		eval_ctx.is_moving = is_moving
		eval_ctx.is_sprinting = is_sprinting
		eval_ctx.in_air = in_air
		eval_ctx.in_water = in_water
		eval_ctx.on_ladder = on_ladder
		eval_ctx.wield_name = wield_name
		eval_ctx.item_info = item_info
		eval_ctx.time_now = time_now
		eval_ctx.is_hurt = is_hurt
		eval_ctx.is_equipping = is_equipping

		local loc_evals = ctrl.locomotion_evaluators
		for i = 1, #loc_evals do
			local custom_loco = loc_evals[i].func(player, eval_ctx)
			if custom_loco then
				loco = custom_loco
				break
			end
		end

		local act_evals = ctrl.action_evaluators
		for i = 1, #act_evals do
			local custom_action = act_evals[i].func(player, eval_ctx)
			if custom_action then
				action = custom_action
				break
			end
		end

		if not was_evaluating then
			is_evaluating_ctx = false
		end
	end

	-- If admin test animation is active, override locomotion and action
	if pstate and pstate.test_anim then
		if pstate.test_anim_is_action then
			loco = "stand"
			action = pstate.test_anim
		else
			loco = pstate.test_anim
			action = nil
		end
		if pstate.test_anim == "climb" then
			climbing_active = true
		end
	end

	-- Mutate pre-allocated state table in-place (Zero-GC hot loop)
	local out_state = pstate and pstate.semantic_state or {}
	out_state.moving = is_moving
	out_state.sprinting = is_sprinting
	out_state.crouching = is_sneaking and not is_moving and is_on_ground and not in_water and not on_ladder
	out_state.crouch_walking = is_sneaking and is_moving and is_on_ground and not in_water and not on_ladder
	out_state.sliding = is_sliding
	out_state.jumping = is_jumping
	out_state.falling = is_falling
	out_state.flying = is_flying
	out_state.hovering = is_hovering
	out_state.swimming = in_water
	out_state.climbing = on_ladder
	out_state.climbing_active = (pstate and pstate.test_anim == "climb") or climbing_active
	out_state.acting = is_acting
	out_state.blocking = is_blocking
	out_state.eating = is_eating
	out_state.aiming_bow = is_aiming_bow
	out_state.shooting_bow = is_shooting_bow
	out_state.hurt = is_hurt
	out_state.equipping = is_equipping
	out_state.locomotion = loco
	out_state.action = action
	out_state.emote = active_emote
	out_state.test_anim = pstate and pstate.test_anim

	-- Fire registered state change callbacks on state transition
	if pstate then
		local prev_loco = pstate.prev_loco_state
		local prev_action = pstate.prev_action_state
		if loco ~= prev_loco or action ~= prev_action then
			pstate.prev_loco_state = loco
			pstate.prev_action_state = action
			local callbacks = ctrl.registered_on_state_change
			for cb_i = 1, #callbacks do
				callbacks[cb_i](player, out_state, prev_loco, prev_action)
			end
		end
	end

	return out_state
end
x_player_api.controls.get_player_state = x_player_api.get_player_state

-- Chat command to toggle/inspect controls debug
core.register_chatcommand("controls_debug", {
	description = S("Display current player control and locomotion state"),
	privs = {server = true},
	func = function(name)
		local player = core.get_player_by_name(name)
		if not player then return false end
		local state = x_player_api.get_player_state(player)
		local fmt = S("[Controls] Loco: @1 | Action: @2 | Hurt: @3 | Fly: @4 | Hover: @5 | "
			.. "Sprint: @6 | Crouch: @7 | Water: @8 | Climb: @9")
		local info = S(fmt,
			tostring(state.locomotion), tostring(state.action),
			tostring(state.hurt),
			tostring(state.flying), tostring(state.hovering),
			tostring(state.sprinting), tostring(state.crouching or state.crouch_walking),
			tostring(state.swimming), tostring(state.climbing))
		core.chat_send_player(name, info)
		return true
	end,
})

core.register_chatcommand("hurt", {
	description = S("Trigger the hurt flinch animation (for testing)"),
	func = function(name)
		local player = core.get_player_by_name(name)
		if not player then return false end
		x_player_api.trigger_hurt(player)
		return true, S("Triggered hurt animation")
	end,
})

core.register_chatcommand("model_format", {
	params = S("[glb|b3d|toggle|status]"),
	description = S("Switch active player model format (glb or b3d) in real-time or query status"),
	privs = {server = true},
	func = function(name, param)
		local player = core.get_player_by_name(name)
		local str_trim = param and (param.trim and param:trim() or param:match("^%s*(.-)%s*$")) or ""
		param = str_trim:lower()

		if param == "" or param == "status" then
			local fmt = x_player_api.get_model_format()
			local def_model = x_player_api.get_default_model()
			local p_anim = player and x_player_api.get_animation(player)
			local active_model = p_anim and p_anim.model or def_model
			local m_def = x_player_api.get_model(active_model)
			local is_modern = player and x_player_api.is_modern_client(name)
			local rendered_mesh = nil
			if m_def then
				if is_modern then
					rendered_mesh = m_def.mesh_glb or (m_def.mesh and m_def.mesh:match("%.glb$") and m_def.mesh) or m_def.mesh
				else
					rendered_mesh = (m_def.mesh and not m_def.mesh:match("%.glb$") and m_def.mesh) or m_def.mesh_b3d or m_def.mesh
				end
			end
			local mesh_info = (rendered_mesh and rendered_mesh ~= active_model)
				and (" (mesh: " .. rendered_mesh .. ")") or ""
			local msg = S("[x_player_api] Format: @1 | Default model: @2 | Your model: @3@4",
				fmt:upper(), def_model, active_model, mesh_info)
			return true, msg
		end

		if param == "toggle" then
			local current = x_player_api.get_model_format()
			param = (current == "glb") and "b3d" or "glb"
		end

		if param ~= "glb" and param ~= "b3d" then
			return false, S("Invalid format: use 'glb', 'b3d', 'toggle', or 'status'")
		end

		local success, new_fmt = x_player_api.set_model_format(param)
		if not success then
			return false, S("Failed to switch format: @1", tostring(new_fmt))
		end

		local def_model = x_player_api.get_default_model()
		local desc = (new_fmt == "glb") and S("GLB (multi-track glTF binary)") or S("B3D (Blitz3D single-track)")
		local msg = S("[x_player_api] Switched player model format to @1 (mesh: @2)",
			desc, def_model)
		core.chat_send_all(core.colorize("#00FF88", msg))
		return true
	end,
})

core.register_chatcommand("toggle_model", {
	description = S("Toggle between GLB and B3D player models on the fly"),
	privs = {server = true},
	func = function(name)
		return core.chatcommands["model_format"].func(name, "toggle")
	end,
})

---Trigger an explicit action duration window on a player (for combat hits, mining, swings)
---@param player ObjectRef Target player
---@param action_override? string Optional explicit action name (e.g. "mine", "attack_slash")
---@param duration? number Optional duration in seconds (defaults to 0.45s)
function x_player_api.trigger_player_action(player, action, duration)
	if not player or not player:is_player() then return end
	local name = player:get_player_name()
	local pstate = states[name]
	if not pstate then return end

	local time_now = core.get_us_time() * 0.000001
	local act = action
	if not act then
		local wielded = player:get_wielded_item()
		local item_info = classify_item(wielded and wielded:get_name() or "")
		if item_info.is_food then return end
		act = item_info.weapon_action or "mine"
	end

	pstate.lmb_action = act
	pstate.lmb_action_until = time_now + (duration or 0.45)
	pstate.lmb_cycle_count = (pstate.lmb_cycle_count or 0) + 1
end

core.register_on_punchnode(function(...)
	local puncher = select(3, ...)
	if puncher and puncher:is_player() then
		x_player_api.trigger_player_action(puncher)
	end
end)

core.register_on_punchplayer(function(...)
	local hitter = select(2, ...)
	if hitter and hitter:is_player() then
		x_player_api.trigger_player_action(hitter)
	end
end)

core.register_on_placenode(function(...)
	local placer = select(3, ...)
	if placer and placer:is_player() then
		x_player_api.trigger_player_action(placer, "mine", 0.45)
	end
end)
