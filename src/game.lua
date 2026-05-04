---------------------------------------------
-- Function IDs
-- Just in case it ever comes in handy for a mod to implement unique IDs for each function.
---------------------------------------------

-- This is a weak-key table mapping functions to unique numeric IDs.
-- IDs are monotone and never reused.
local ids = setmetatable({}, { __mode = "k" })
local next_id = 0

--- Returns a unique numeric ID associated with a specific function.
--- IDs persist for the entire lifetime of the function object.
---
--- @param func function
--- @return number
function function_id(func)
	assert(type(func) == "function", "function_id expects a function")
	
	local id = ids[func]
	if not id then
		next_id = next_id + 1
		id = next_id
		ids[func] = id
	end
	return id
end

---------------------------------------------
-- Alias system
-- Could be used if you want to communicate the purpose of a function or variable more clearly, just for temporary ease of access, things like that.
---------------------------------------------

--- This is a table mapping aliases to values, which can be any Lua object.
CUTIL.aliases = {}

local identity = function(x) return x end

--- Creates or overwrites an alias.
---
--- @param value any|nil The object you are instantiating an alias of. If null, it defaults to the identity function.
--- @param alias string|nil The alias you have in mind for the object. If null, it defaults to a unique numeric ID.
--- @return string
function CUTIL.alias(value, alias)
	value = value or identity
	alias = alias or tostring(function_id(value))
	
	CUTIL.aliases[alias] = value
	return alias
end

--- Resolves an alias and returns nil if the alias does not exist.
--- 
--- @param alias string
--- @return any
function CUTIL.resolve_alias(alias)
	return CUTIL.aliases[alias]
end

--- Removes an alias.
--- 
--- @param alias string
function CUTIL.remove_alias(alias)
	CUTIL.aliases[alias] = nil
end

---------------------------------------------
-- Game Helpers
-- I still don't understand why these functions don't already exist natively, but here we are.
---------------------------------------------

--- Activates the win screen for the game.
function CUTIL.game_win()
	G.GAME.win = true
	G.STATE = G.STATES.GAME_OVER
	
	G:save_settings()
	G.FILE_HANDLER.force = true
	G.STATE_COMPLETE = false
end

--- Activates the lose screen for the game.
function CUTIL.game_lose()
	G.GAME.win = false
	G.STATE = G.STATES.GAME_OVER
	
	if not G.GAME.seeded and not G.GAME.challenge then
		G.PROFILES[G.SETTINGS.profile].high_scores.current_streak.amt = 0
	end
	
	G:save_settings()
	G.FILE_HANDLER.force = true
	G.STATE_COMPLETE = false
end

---------------------------------------------
-- Game variable manager
-- Managing and initializing game variables and doing all of that sort of stuff can be pretty annoying, but this should help a lot.
---------------------------------------------

--- Authoritative variable definitions.
--- Names of variables are mapped to their values.
local variables = {}

--- Authoritative modifier type definitions.
local modifier_types = {}

--- Registers a variable with a default value.
--- It returns whether or not the addition was successful.
function CUTIL.add_variable(name, default_value)
	if not variables[name] then
		variables[name] = default_value
		
		CUTIL.ensure_variable_integrity()
		CUTIL.update_game_variables()
		
		return true
	end
	
	return false
end

function CUTIL.remove_variable(name)
	if not variables[name] then return false end
	
	variables[name] = nil
	if G.GAME and G.GAME.cutil_vars then
		G.GAME.cutil_vars[name] = nil
	end
	
	CUTIL.update_game_variables()
	
	return true
end

function CUTIL.pop_variable(name)
	local variable = variables[name]
	CUTIL.remove_variable(name)
	return variable
end

function CUTIL.set_variable(name, value)
	variables[name] = value
	
	CUTIL.ensure_variable_integrity()
	CUTIL.update_game_variables()
end

function CUTIL.get_variable(name)
	return variables[name]
end


--- Ensures G.GAME.cutil_vars contains all registered variables. Does not overwrite existing values.
function CUTIL.ensure_variable_integrity()
	if not G.GAME then return end

	G.GAME.cutil_vars = G.GAME.cutil_vars or {}
	for key, value in pairs(variables) do
		if G.GAME.cutil_vars[key] == nil then
			G.GAME.cutil_vars[key] = value
		end
	end
end

---------------------------------------------
-- Variable modifier system
-- Have you ever wanted to be able to modify variables after-the-fact while still remembering the original value?
-- This removes all of the complication; just add your multipliers or additions or whatever you needed right here,
-- that way, you only ever need to update the variable itself when you're sure you'll never need that value again.
---------------------------------------------

--- Registers a named modifier template, must be called at load time.
--- fn receives (base_value, params) and returns the modified value.
---
--- @param name string
--- @param fn function
function CUTIL.register_modifier_type(name, fn)
	assert(type(name) == "string", "modifier type name must be a string")
	assert(type(fn) == "function", "modifier type fn must be a function")
	
	modifier_types[name] = fn
end

--- Adds a modifier to a target variable; returns the index of the modifier on the target variable.
--- (That is, if there are already three modifiers on the given variable, it will be the fourth, having an index of four.)
--- (Modifiers are applied in insertion order.)
--- 
--- @param target string
--- @param modification function
--- @return function
function CUTIL.add_modifier(target, name, params)
	assert(type(name) == "string", "modifier name must be a string")
	assert(modifier_types[name], "unregistered modifier type: '" .. name .. "'")
	if not G.GAME then return nil end
	
	G.GAME.cutil_mods = G.GAME.cutil_mods or {}
	G.GAME.cutil_mods[target] = G.GAME.cutil_mods[target] or {}
	
	table.insert(G.GAME.cutil_mods[target], { name = name, params = params or {} })	
	CUTIL.update_game_variables()
	
	return #G.GAME.cutil_mods[target]
end

--- Removes a modifier.
--- If modifier_index is nil, it instead removes all modifiers for the target variable.
function CUTIL.remove_modifier(target, modifier_index)
	if not G.GAME or not G.GAME.cutil_mods or not G.GAME.cutil_mods[target] then return end
	
	if not modifier_index then
		G.GAME.cutil_mods[target] = nil
	else
		table.remove(G.GAME.cutil_mods[target], modifier_index)
		if #G.GAME.cutil_mods[target] == 0 then
			G.GAME.cutil_mods[target] = nil
		end
	end
	
	CUTIL.update_game_variables()
end

function CUTIL.pop_modifier(target, modifier_index)
	if not G.GAME or not G.GAME.cutil_mods or not G.GAME.cutil_mods[target] then return end

	if not modifier_index then
		local mods = G.GAME.cutil_mods[target]
		CUTIL.remove_modifier(target)
		return mods
	else
		local mod = G.GAME.cutil_mods[target][modifier_index]
		CUTIL.remove_modifier(target, modifier_index)
		return mod
	end
end

function CUTIL.set_modifier(target, modifier_index, name, params)
	assert(type(name) == "string", "modifier name must be a string")
	assert(modifier_types[name], "unregistered modifier type: '" .. name .. "'")
	assert(G.GAME and G.GAME.cutil_mods and G.GAME.cutil_mods[target], "no modifiers for target")
	
	G.GAME.cutil_mods[target][modifier_index] = { name = name, params = params or {} }
	CUTIL.update_game_variables()
end

function CUTIL.get_modifier(target, modifier_index)
	if not G.GAME or not G.GAME.cutil_mods or not G.GAME.cutil_mods[target] then return nil end
	return G.GAME.cutil_mods[target][modifier_index]
end

---------------------------------------------
-- Variable + Modifier Update Logic
-- Fully updates the variables and stores them in the game variables table so they get automatically saved.
---------------------------------------------

--- Applies all modifiers to all variables in the order they were applied.
function CUTIL.update_game_variables()
	if not G.GAME then return end

	G.GAME.cutil_vars = G.GAME.cutil_vars or {}
	G.GAME.cutil_mods = G.GAME.cutil_mods or {}
	
	for key, base_value in pairs(variables) do
		local value = base_value
		local mods = G.GAME.cutil_mods[key]
		if mods then
			for i = 1, #mods do
				local mod = mods[i]
				local fn = modifier_types[mod.name]
				if fn then
					value = fn(value, mod.params)
				end
			end
		end
		G.GAME.cutil_vars[key] = value
	end
end

local game_start_run_hook = Game.start_run
function Game:start_run(args)
	local ret = game_start_run_hook(self, args)
	
	CUTIL.ensure_variable_integrity()
	CUTIL.update_game_variables()
	
	return ret
end	