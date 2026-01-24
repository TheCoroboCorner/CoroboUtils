---------------------------------------------
-- Event System
-- Just in case you want to add custom events into Balatro that get activated at certain context moments.
---------------------------------------------

CUTIL.Events = { registry = {} }
local registry = CUTIL.Events.registry

-- Internal helpers

-- Generate variable name for storage
local function event_var_name(owner, name)
	return "__event__" .. owner .. "::" .. name
end

-- Shallow copy
local function shallow_copy(table)
	local copy = {}
	
	for key, value in pairs(table) do
		copy[key] = value
	end
	
	return copy
end

-- Normalize phase spec into a useful form:
-- phase_spec may be:
-- 		- function(context) -> boolean => call it
--  	- string (phase name) => match if context.phase == string OR if context[string] == true
-- 		- table (array of strings) => match if any element matches as above
local function phase_matches(phase_spec, context)
	if phase_spec == nil then
		return true
	end
	
	local ct_phase = context and context.phase
	
	if type(phase_spec) == "function" then
		local ok, res = pcall(phase_spec, context)
		return ok and res
	end
	
	if type(phase_spec) == "string" then
		if ct_phase == phase_spec then
			return true
		end
		
		if context and context[phase_spec] then
			return true
		end
	end
	
	if type(phase_spec) == "table" then
		for _, value in ipairs(phase_spec) do
			if type(value) == "string" then
				if ct_phase == value then
					return true
				end
				
				if context and context[value] then
					return true
				end
			elseif type(value) == "function" then
				local ok, res = pcall(value, context)
				if ok and res then
					return true
				end
			end
		end
		
		return false
	end
	
	return false
end

-- Filter matching: either a predicate function(context) or table of required truthy flags
local function filter_matches(filter, context)
	if not filter then
		return true
	end
	
	if type(filter) == "function" then
		local ok, res = pcall(filter, context)
		return ok and res
	end
	
	if type(filter) == "table" then
		for _, key in ipairs(filter) do
			if not (context and context[key]) then
				return false
			end
		end
		
		return true
	end
	
	return false
end

-- Merge two effect tables into the first using aggregation semantics:
-- Numeric keys are summed.
-- 'stop' becomes true if any is true.
-- 'message' becomes an array of message objects appended.
-- 'extra' fields are appended into a list under 'extra'.
-- Unknwon keys are placed under 'extra' (as key/value).
local numeric_keys = { chips = true, mult = true, dollars = true, xchips = true, xmult = true }

local function append_message(target, msg)
	if not msg then
		return
	end
	
	if type(msg) == "string" then
		table.insert(target, { text = msg })
	elseif type(msg) == "table" then
		if msg.text or msg.message then
			table.insert(target, msg)
		else
			for _, m in ipairs(msg) do
				table.insert(target, m)
			end
		end
	end
end

local function merge_effects(target, addition)
	if not addition then
		return target
	end
	
	-- Numeric accumulation
	for key, _ in pairs(numeric_keys) do
		if addition[key] then
			target[key] = (target[key] or 0) + addition[key]
		end
	end
	
	-- Stop flag
	if addition.stop then
		target.stop = true
	end
	
	-- Message handling
	target.messages = target.messages or {}
	if addition.message then
		append_message(target.messages, addition.message)
	end
	
	-- Extras
	target.extra = target.extra or {}
	if addition.extra then
		if type(addition.extra) == "table" then
			table.insert(target.extra, addition.extra)
		else
			table.insert(target.extra, { value = addition.extra })
		end
	end
	
	-- Copy other keys into extra
	for key, value in pairs(addition) do
		if not numeric_keys[key] and key ~= "stop" and key ~= "message" and key ~= "extra" and key ~= "messages" then
			-- Avoid duplications
			if target[key] == nil then
				target[key] = value
			else
				-- If there's a collision, just push it into extra
				table.insert(target.extra, { [key] = value })
			end
		end
	end
	
	return target
end

-- End internal helpers

-- Default effect application hook. If SMODS.calculate_effect exists, call it, otherwise just delegate to the user-provided CUTIL.Events.on_effect_apply which does nothing by default.
function CUTIL.Events.apply_effects(effect_table, scored_card, from_edition, context)
	if not effect_table then
		return
	end
	
	-- Just to be absolutely 100% sure that SMODS.calculate_effect even exists; I don't want to handle weird crashes
	if type(SMODS) == "table" and type(SMODS.calculate_effect) == "function" then
		SMODS.calculate_effect(effect_table, scored_card, from_edition)
	else
		-- Expose a hook as a fallback
		if CUTIL.Events.on_effect_apply then
			CUTIL.Events.on_effect_apply(effect_table, scored_card, context)
		end
	end
end

-- No-op hook intended to be overwritten by other mods
CUTIL.Events.on_effect_apply = function(effect_table, scored_card, context)
end
	
--- Adds an event into the registry.
--- 
--- An event is identified by (owner, name) and has the following metadata:
--- 	- phase: string|table|function (default nil == matches all). If string: matches when
--- 				context.phase == string OR context[string] == true.
--- 	- priority: number (higher runs earlier). The default is 0.
--- 	- filter: table of required context flag names OR predicate function(context) -> bool.
--- 	- once: boolean (remove after the first successful dispatch).
--- 	- apply: boolean (if true, aggregated returns will be automatically applied via apply_effects).
---
--- @param owner string Owner/mod identifier
--- @param name string Event name (unique per owner per phase)
--- @param fn function Callback: fn(self, card, context) -> effect_table|nil
--- @param opts table|nil Optional metadata (phase, priority, filter, once, apply)
function CUTIL.Events.add(owner, name, fn, opts)
	assert(type(owner) == "string", "owner must be string")
	assert(type(name) == "string", "name must be string")
	assert(type(fn) == "function", "fn must be function")
	
	opts = opts or {}
	local phase = opts.phase
	local priority = opts.priority or 0
	local filter = opts.filter
	local once = opts.once or false
	local apply = opts.apply or false
	
	-- store under a global phase-bucket if the phase is stringable, otherwise just under "__any"
	local bucket = tostring(phase or "__any")
	registry[bucket] = registry[bucket] or {}
	
	-- Events have to have a unique id
	for _, evt in ipairs(registry[bucket]) do
		assert(not (evt.owner == owner and evt.name == name), "An event with the same owner and name already exists for that phase/bucket")
	end
	
	local event = {
		fn = nil, -- We're not storing the function directly here as to avoid accidental in-memory drift
		name = name,
		owner = owner,
		phase_spec = phase,
		priority = priority,
		filter = filter,
		once = once,
		apply = apply,
		bucket = bucket
	}
	
	table.insert(registry[bucket], event)
	
	-- persist the function in the variable system as the source-of-truth
	assert(CUTIL.add_variable(event_var_name(owner, name), fn), "Failed to register event variable")
end

--- Removes a single event.
--- 
--- @param owner string
--- @param name string
function CUTIL.Events.remove(owner, name)
	for bucket, bucket_table in pairs(registry) do
		for i = #bucket_table, 1, -1 do
			local evt = bucket_table[i]
			
			if evt.owner == owner and evt.name == name then
				table.remove(bucket_table, i)
				CUTIL.remove_variable(event_var_name(owner, name))
			end
		end
	end
end

--- Gets the current callback (from variables).
--- 
--- @param owner string
--- @param name string
--- @return function|nil
function CUTIL.Events.get(owner, name)
	return CUTIL.get_variable(event_var_name(owner, name))
end

--- Sets/updates a registered event's callback.
--- 
--- @param owner string
--- @param name string
--- @param fn function
function CUTIL.Events.set(owner, name, fn)
	assert(type(fn) == "function", "fn must be function")
	assert(CUTIL.Events.get(owner, name), "Specified event does not exist")
	
	CUTIL.set_variable(event_var_name(owner, name), fn)
end

--- Remove all events owned by a specific owner/mod.
--- 
--- @param owner string
function CUTIL.Events.remove_owner(owner)
	for bucket, bucket_table in pairs(registry) do
		for i = #bucket_table, 1, -1 do
			local evt = bucket_table[i]
			
			if evt.owner == owner then
				table.remove(bucket_table, i)
				CUTIL.remove_variable(event_var_name(evt.owner, evt.name))
			end
		end
	end
end

--- Returns a shallow copy of the entire event registry.
---
--- @return table
function CUTIL.Events.list()
	return shallow_copy(registry)
end

--- Update the G.GAME mirror for external inspection/debugging.
function CUTIL.Events.update_game_events()
	G.GAME.cutil_events = shallow_copy(registry)
end

--- Dispatch events that match the provided context.
---
--- The dispatcher does the following:
--- 	- It collects all events whose phase_spec matches the context (phase matching rules)
--- 	- It filters by filter predicate or flag table
--- 	- It sorts by priority in descending order
--- 	- It executes callbacks in order
--- 	- It aggregates returned effect tables via merge_effects
--- 	- It respects "stop" in aggregated results, so if any event returns "stop = true", the dispatch halts
--- 	- It removes "once" events after they runs
--- 	- If any matched event requested "apply", it automatically calls CUTIL.Events.apply_effects on the aggregated results
--- 
---	@param self object The caller object for the event_helper Joker below
--- @param card object The card instance (which may be nil if it's not a card context)
--- @param context table The relevant context table, which can include the following:
---		- phase: string The semantic phase name
--- 	- arbitrary flags (things like joker_main, before, main_scoring, etc.)
--- @return table Aggregated effects
function CUTIL.Events.dispatch(self, card, context)
	context = context or {}
	local candidates = {}
	
	for bucket, bucket_table in pairs(registry) do
		for _, evt in ipairs(bucket_table) do
			if phase_matches(evt.phase_spec, context) and filter_matches(evt.filter, context) then
				table.insert(candidates, evt)
			end
		end
	end
	
	if #candidates == 0 then
		return nil
	end
	
	-- Sort by priority in descending order
	table.sort(candidates, function(a, b) return a.priority > b.priority end)
	
	-- Snapshot for safe mutation and to remember which "once" events to remove
	local snapshot = shallow_copy(candidates)
	local aggregated = {}
	
	local to_remove = {}
	
	for _, evt in ipairs(snapshot) do
		local fn = CUTIL.get_variable(event_var_name(evt.owner, evt.name))
		
		if type(fn) == "function" then
			local ok, result = xpcall(function() return fn(self, card, context) end, debug.traceback)
			if not ok then
				print("[CUTIL] Runtime error in event callback for event '" .. event_var_name(evt.owner, evt.name) .. "': " .. result)
			else
				merge_effects(aggregated, result)
				
				if evt.once then
					table.insert(to_remove, { owner = evt.owner, name = evt.name })
				end
				
				if aggregated.stop then
					break
				end
			end
		end
	end
	
	-- Remove one-shot events after iteration (safe)
	for _, r in ipairs(to_remove) do
		CUTIL.Events.remove(r.owner, r.name)
	end
	
	-- If any event requested automatic apply, call the apply pipeline (only once with the aggregated table)
	for _, evt in ipairs(candidates) do
		if evt.apply then
			CUTIL.Events.apply_effects(aggregated, card, nil, context)
			break
		end
	end
	
	return aggregated
end

-- Convenience helpers

--- Dispatches only the events that specifically match a specific named phase (shorthand).
--- This will set context.phase = phase if it's not provided.
---
--- @param self object
--- @param card object
--- @param phase string
--- @param context table|nil
--- @return table|nil
function CUTIL.Events.dispatch_phase(self, card, phase, context)
	context = context or {}
	if not context.phase then 
		context.phase = phase
	end
	
	return CUTIL.Events.dispatch(self, card, context)
end

--- Convenience wrapper to register a calculate-style event.
--- Keeps parity with SMODS calculate semantics (that is, fn receives self, card, and context, returning an effect table).
---
--- @param owner string Owner/mod identifier
--- @param name string Event name (unique per owner per phase)
--- @param fn function Callback: fn(self, card, context) -> effect_table|nil
--- @param opts table|nil Optional metadata (phase, priority, filter, once, apply)
function CUTIL.Events.add_calculate(owner, name, fn, opts)
	opts = opts or {}
	opts.phase = opts.phase or nil
	opts.priority = opts.priority or 0
	opts.apply = opts.apply or false
	
	return CUTIL.Events.add(owner, name, fn, opts)
end

---------------------------------------------
-- Helper Functions To Make It Work
-- You can ignore these, these are just to make it work in Balatro properly
---------------------------------------------

-- Helper Joker
SMODS.Joker {
	key = "event_helper",
	order = 0,
	rarity = 1,
	cost = 0,
	
	blueprint_compat = false,
	perishable_compat = false,
	no_collection = true,
	no_doe = true,
	
	in_pool = function(self, args)
		return false
	end,
	
	loc_vars = function(self, info_queue, card)
		return {}
	end,
	
	calculate = function(self, card, context)
		CUTIL.Events.dispatch(self, card, context)
	end
}

-- Hooking the Game:start_run function to add the helper Joker and its CardArea
local game_start_run = Game.start_run
function Game:start_run(args)
	local ret = game_start_run(self, args)
	
	-- Establishes CardArea
	self.cutil_helper_area = CardArea(
		G.TILE_W - 600 * G.CARD_W - 200.95, -- Don't ask me what these parameters are but this seems to work
		-100.1 * G.jokers.T.h,
		0,
		0,
		{
			card_limit = 1,
			type = "joker",
			highlighted_limit = 0
		}
	)
	CUTIL.helper_area = G.cutil_helper_area
	
	if #CUTIL.helper_area.cards == 0 then
		local event_helper = SMODS.add_card {
			key = "j_coroboutil_event_helper",
			area = CUTIL.helper_area,
			skip_materialize = true,
			no_edition = true
		}
	end
	
	return ret
end