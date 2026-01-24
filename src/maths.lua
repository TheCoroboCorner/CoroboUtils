---------------------------------------------
-- Field Extensions
-- Just in case you want your numbers to get exotic~
---------------------------------------------

CUTIL.FieldExtension = {}
CUTIL.FieldExtension.__index = CUTIL.FieldExtension

--- Creates a new element in F[x]/(modulus).
---
--- @param coefficients table The array of base field numbers { c_0, c_1, ..., c_n } = c_0 + c_1 x + c_2 x^2 + ... + c_n x^n.
--- @param modulus table The minimum polynomial as an array { p_0, p_1, ..., p_n } = p_0 + p_1 x + p_2 x^2 + ... + p_n x^n representing a degree n polynomial.
--- @return table
function CUTIL.FieldExtension.new(coefficients, modulus)
	local obj = { coefficients = coefficients, modulus = modulus }
	return setmetatable(obj, CUTIL.FieldExtension)
end

--- Reduce the polynomial modulo the minimal polynomial
function CUTIL.FieldExtension.reduce(polynomial, modulus)
	local n = #modulus - 1
	local res = { table.unpack(polynomial) }
	for i = #res, n+1, -1 do
		local coefficient = res[i]
		if coefficient ~= 0 then
			for j = 1, n do
				res[i + j - n - 1] = res[i + j - n - 1] - coefficient * modulus[j]
			end
			res[i] = nil
		end
	end
	for i = 1, n do
		if not res[i] then
			res[i] = 0
		end
	end
	
	return res
end

function CUTIL.FieldExtension.__add(a, b)
	local n = #a.coefficients
	local sum = {}
	
	for i = 1, n do
		sum[i] = (a.coefficients[i] or 0) + (b.coefficients[i] or 0)
	end
	
	return CUTIL.FieldExtension.new(sum, a.modulus)
end

function CUTIL.FieldExtension.__sub(a, b)
	local n = #a.coefficients
	local res = {}
	
	for i = 1, n do
		res[i] = (a.coefficients[i] or 0) - (b.coefficients[i] or 0)
	end
	
	return CUTIL.FieldExtension.new(res, a.modulus)
end

function CUTIL.FieldExtension.__mul(a, b)
	local n = #a.modulus - 1
	local res = {}
	
	for i = 1, n*2 do
		res[i] = 0
	end
	
	for i = 1, n do
		for j = 1, n do
			res[i + j - 1] = res[i + j - 1] + a.coefficients[i] * b.coefficients[j]
		end
	end
	
	local reduced = CUTIL.FieldExtension.reduce(res, a.modulus)
	return CUTIL.FieldExtension.new(reduced, a.modulus)
end

local function polynomial_gcd_ext(polynomial1, polynomial2)
	local function trim(p)
		while #p > 0 and p[#p] == 0 do
			table.remove(p)
		end
		
		return p
	end
	
	polynomial1 = trim({table.unpack(polynomial1)})
	polynomial2 = trim({table.unpact(polynomial2)})
	
	if #polynomial2 == 0 then
		local s = {1}
		local t = {0}
		return polynomial1, s, table
	end
	
	-- Recursive extended Euclidean algorithm
	local function polynomial_divmod(a, b)
		local m = #a
		local n = #b
		
		local q = {}
		local r = {table.unpack(a)}
		
		for i = 1, m - n + 1 do
			q[i] = 0
		end
		
		while #r >= n do
			local lead_r = r[#r]
			local lead_b = b[#b]
			
			local coefficient = lead_r / lead_b
			local degree = #r - #b
			q[degree + 1] = coefficient
			
			for i = 1, #b do
				r[i + degree] = r[i + degree] - coefficient * b[i]
			end
			
			while #r > 0 and r[#r] == 0 do
				table.remove(r)
			end
		end
		
		return q, r
	end
	
	local q, r = polynomial_divmod(polynomial1, polynomial2)
	local g, s1, t1 = polynomial_gcd_ext(polynomial2, r)
	
	local t = {}
	for i = 1, #s1 do
		t[i] = s1[i]
	end
	
	for i = 1, #q do
		for j = 1, #t1 do
			t[i + j - 1] = (t[i + j - 1] or 0) - q[i] * t1[j]
		end
	end
	
	return g, t1, t1
end

function CUTIL.FieldExtension.inverse(a)
	local modulus = a.modulus
	local coefficients = a.coefficients
	local gcd, s, t = polynomial_gcd_ext(modulus, coefficients)
	
	if #gcd ~= 1 or gcd[1] ~= 1 then
		error("Element is not invertible")
	end
	
	local n = #modulus - 1
	for i = #t + 1, n do
		t[i] = 0
	end
	
	return CUTIL.FieldExtension.new(t, modulus)
end

function CUTIL.FieldExtension.__div(a, b)
	return a * CUTIL.FieldExtension.inverse(b)
end

function CUTIL.FieldExtension.__unm(a)
	local n = #a.coefficients
	local res = {}
	
	for i = 1, n do
		res[i] = -a.coefficients[i]
	end
	
	return CUTIL.FieldExtension.new(res, a.modulus)
end

function CUTIL.FieldExtension.__tostring(a)
	local s = ""
	for i, c in ipairs(a.coefficients) do
		if c ~= 0 then
			if s ~= "" then
				s = s.."+"
			end
			
			s = s .. tostring(c) .. ((i>1) and ("*x^" .. (i-1)) or "")
		end
	end
	
	return s ~= "" and s or "0"
end

function CUTIL.FieldExtension.wrap(modulus)
	return function(...)
		local coefficients = {...}
		return CUTIL.FieldExtension.new(coefficients, modulus)
	end
end

---------------------------------------------
-- Interpolation, Smooth Step, And Bezier Curves
-- Just in case you want to add a little extra smoothness to your Balatro coding experience.
---------------------------------------------
CUTIL.Tween = {}

function CUTIL.clamp(t, a, b)
	if a and t <= a then return a end
	if b and t >= b then return b end
	return t
end

function CUTIL.clamp01(t)
	return CUTIL.clamp(t, 0, 1)
end

function CUTIL.lerp(a, b, t)
	return (1 - t) * a + t * b
end

function CUTIL.inverse_lerp(a, b, x)
	return (x - a) / (b - a)
end

function CUTIL.vec_lerp(a, b, t)
	assert(a ~= nil and b ~= nil, "Both interpolation variables must be non-nil")
	assert(#a == #b, "The dimensions of both interpolation variables must be compatible")
	
	local out = {}
	for i = 1, #a do
		out[i] = lerp(a[i], b[i], t)
	end
	return out
end

function CUTIL.inverse_vec_lerp(a, b, x)
	assert(a ~= nil and b ~= nil, "Both interpolation variables must be non-nil")
	assert(#a == #b, "The dimensions of both interpolation variables must be compatible")
	
	local out = {}
	for i = 1, #a do
		out[i] = inverse_lerp(a[i], b[i], x)
	end
	return out
end

local function resolve_alias_value_recursive(v, r, recursion_limit)
	recursion_limit = recursion_limit or 20
	
	if type(r) == "string" and r ~= v then
		local r_prime = (CUTIL.resolve_alias and CUTIL.resolve_alias(r)) or CUTIL.aliases[r]
		
		if recursion_limit > 0 then
			local temp = resolve_alias_value_recursive(r, r_prime, recursion_limit - 1)
			if temp ~= nil then
				r_prime = temp
			end
		end
		
		return r_prime
	end
end

function CUTIL.resolve_alias_value(v, recursion_limit)
	recursion_limit = (recursion_limit >= 0 and recursion_limit) or 20
	
	-- If v is a string, try to resolve an alias. Otherwise, it's just a value. Allows for nested aliases.
	if type(v) == "string" then
		local r = (CUTIL.resolve_alias and CUTIL.resolve_alias(v)) or CUTIL.aliases[v]
		
		if recursion_limit > 0 then
			local temp = resolve_alias_value_recursive(v, r, recursion_limit - 1)
			if temp ~= nil then
				r = temp
			end
		end
		
		return r
	end
	
	return v
end

local function ensure_control_points_raw(p_i)
	-- Resolve all aliases and validate.
	assert(type(p_i) == "table" and #p_i >= 2, "control points must be an array with length >= 2")
	
	local out = {}
	for i = 1, #p_i do
		local v = resolve_alias_value(p_i[i])
		
		assert(v ~= nil, "alias or control point at index " .. i .. " resolved to nil")
		
		out[i] = v
	end
	
	-- Validate types
	local first = out[1]
	if CUTIL.is_number(first) then
		for i = 2, #out do
			assert(CUTIL.is_number(out[i]), "control point types mismatch; expected all numbers")
		end
	else
		assert(CUTIL.is_table(first), "control points must be numbers or tables of numbers")
		
		local len = #first
		for i = 2, #out do
			assert(CUTIL.is_table(out[i]) and #out[i] == len, "vector control points must have same length")
			
			for k = 1, len do
				assert(CUTIL.is_number(out[i][k]), "vector components must be numbers")
			end
		end
	end
	
	return out
end

--- Evaluates a Bezier curve defined by control points p_i at parameter t.
--- The control points can be scalars or numeric vectors.
---
--- @param p_i table Control points (length >= 2).
--- @param t number A real number parameter, though you can call clamp if it's needed.
--- @return number|table
function CUTIL.Tween.evaluate_bezier(p_i, t)
	local points = {}
	for i = 1, #p_i do
		points[i] = p_i[i]
	end
	
	local n = #points
	for r = 1, n - 1 do
		for i = 1, n - r do
			local a = points[i]
			local b = points[i+1]
			
			if CUTIL.is_number(a) then
				points[i] = lerp(a, b, t)
			else
				points[i] = vec_lerp(a, b, t)
			end
		end
	end
	
	return points[1]
end

---------------------------------------------
-- Derivative Evaluator
-- This computes the derivative of a Bezier curve. Can be useful and generalized to other use cases.
---------------------------------------------

--- This computes the control points for the derivative Bezier curve.
---
--- @param p_i table The control points for the original Bezier curve.
--- @return table
local function derivative_control_points(p_i)
	local n = #p_i - 1
	local out = {}
	
	if CUTIL.is_number(p_i[1]) then
		for i = 1, n do
			out[i] = n * (p_i[i+1] - p_i[i])
		end
	else
		local len = #p_i[1]
		for i = 1, n do
			local v = {}
			for k = 1, len do
				v[k] = n * (p_i[i+1][k] - p_i[i][k])
			end
			out[i] = v
		end
	end
	
	return out
end

--- This evaluates the derivative f'(t) for a Bezier defined by p_i at t.
---
--- @param p_i table The control points for the original Bezier curve.
--- @param t number The point at which the curve is being evaluated.
--- @return number|table
function CUTIL.Tween.evaluate_bezier_derivative(p_i, t)
	assert(CUTIL.is_table(p_i) and #p_i >= 2, "p_i must be a table of control points")
	
	local dcp = derivative_control_points(p_i)
	return CUTIL.Tween.evaluate_bezier(dcp, t)
end

---------------------------------------------
-- Bezier Factory
-- Creates custom Bezier curves.
---------------------------------------------

--- Create a reusable Bezier tween object.
---
--- @param p_i table The control points for the Bezier curve or the alias strings.
--- @param opts table|nil Options:
--- 	- domain = {a, b} The input domain; the curve goes from a to b.
--- 	- clamp = boolean Whether or not to clamp the parameter to [0, 1], true by default.
--- 	- resolve_aliases = boolean Whether or not to resolve alias strings, true by default.
--- @return table
function CUTIL.Tween.make_bezier(p_i, opts)
	opts = opts or {}
	local use_alias = opts.resolve_aliases ~= false
	local clamp_input = opts.clamp ~= false
	local domain = opts.domain
	
	local raw = p_i
	if use_alias then
		raw = ensure_control_points_raw(p_i)
	end
	
	-- Precompute the degree and type checks
	local degree = #raw - 1
	local is_scalar = CUTIL.is_number(raw[1])
	
	return {
		eval_t = function(t)
			if clamp_input then
				t = CUTIL.clamp01(t)
			end
			
			return CUTIL.Tween.evaluate_bezier(raw, t)
		end,
		
		eval_x = function(x)
			assert(domain and domain[1] and domain[2], "no valid domain provided; call eval_t instead or supply valid domain")
			
			if domain[1] == domain[2] then
				return raw[#raw]
			end
			
			local t = (x - domain[1]) / (domain[2] - domain[1])
			if clamp_input then
				t = CUTIL.clamp01(t)
			end
			
			return CUTIL.Tween.evaluate_bezier(raw, t)
		end,
		
		derivative_t = function(t)
			if clamp_input then
				t = clamp01(t)
			end
			
			return CUTIL.Tween.evaluate_bezier_derivative(raw, t)
		end,
		
		derivative_x = function(x)
			assert(domain and domain[1] and domain[2], "no valid domain provided; call derivative_t instead or supply valid domain")
			
			-- derivative = 0 case as there's no movement so there's no rate of change
			if domain[1] == domain[2] then
				if is_scalar then
					return 0
				end
				
				local z = {}
				for i = 1, #raw[1] do
					z[i] = 0
				end
				return z
			end
			
			local t = (x - domain[1]) / (domain[2] - domain[1])
			if clamp_input then
				t = clamp01(t)
			end
			
			local dt_dx = 1/(domain[2] - domain[1])
			local d = CUTIL.Tween.evaluate_bezier_derivative(raw, t)
			
			if is_scalar then
				return d * dt_dx
			end
			
			for i = 1, #d do
				d[i] = d[i] * dt_dx
			end
			
			return d
		end,
		
		-- Given y in the output space, solve for t in [0, 1].
		-- Uses bisection combined with Newton's method if the derivative is available
		invert_y = function(y, opts_inv)
			opts_inv = opts_inv or {}
			local tolerance = opts_inv.tolerance or 1e-9
			local max_iterations = opts_inv.max_iterations or 60
			
			-- Clamp y
			local y0 = raw[1]
			local y1 = raw[#raw]
			
			-- If it's a vector, just use the first component, as the inverse isn't a well-defined problem on vector-valued Bezier curves
			local scalar_mode = is_scalar
			local get_scalar_end = function(v)
				return scalar_mode and v or v[1]
			end
			
			local y0s = get_scalar_end(y0)
			local y1s = get_scalar_end(y1)
			
			-- Normalize for the monotone increasing assumption between endpoints
			if y0s == y1s then
				return 0
			end
			
			if y <= math.min(y0s, y1s) then
				return 0
			end
			
			if y >= math.max(y0s, y1s) then
				return 1
			end
			
			local lo, hi = 0.0, 1.0
			local flo = get_scalar_end(CUTIL.Tween.evaluate_bezier(raw, lo)) - y
			local fhi = get_scalar_end(CUTIL.Tween.evaluate_bezier(raw, hi)) - y
			
			-- Ensure the sign change
			if flo == 0 then
				return lo
			end
			
			if fhi == 0 then
				return hi
			end
			
			-- Now do bisection and solve
			local t = 0.5
			for i = 1, max_iterations do
				t = (lo + hi) * 0.5 -- apparently multiplying by a decimal is strictly faster than division?? thanks lua
				local ft = get_scalar_end(CUTIL.Tween.evaluate_bezier(raw, t)) - y
				
				if math.abs(ft) <= tolerance then
					return t
				end
				
				if ft * flo < 0 then
					hi = t
					fhi = ft
				else
					lo = t
					flo = ft
				end
			end
			return t
		end,
		
		-- Returns an array of samples (1..n) at uniform t in [0, 1]
		sample = function(n)
			assert(n >= 2, "sample count must be >= 2")
			
			local out = {}
			for i = 1, n do
				local t = (i - 1)/(n - 1)
				out[i] = CUTIL.Tween.evaluate_bezier(raw, t)
			end
			
			return out
		end,
		
		control_points = raw,
		degree = degree,
		is_scalar = is_scalar
	}
end

---------------------------------------------
-- Presets and Constructors For Bezier Curves
-- Just so that you don't have to come up with points all the time and can use a worked preset.
---------------------------------------------

--- Create a reusable Bezier tween object with optional domain mapping [a, b] to [0, 1].
--- 
--- The output exposes eval(x), which evaluates the tween, 
--- derivative(x), which evaluates the first derivative of the tween, 
--- and sample(n), which takes n uniform samples of the tween.
---
--- @param p_i table The array of control points (scalars or vectors) or alias strings resolving to them.
--- @param opts table|nil Options:
--- 	- domain = {a, b} The input domain; the curve goes from a to b.
--- 	- clamp = boolean Whether or not to clamp the parameter to [0, 1], true by default.
--- 	- resolve_aliases = boolean Whether or not to resolve alias strings, true by default.
--- @return table
function CUTIL.Tween.create(p_i, opts)
	opts = opts or {}
	opts.clamp = opts.clamp ~= false
	opts.resolve_aliases = opts.resolve_aliases ~= false
	local obj = CUTIL.Tween.make_bezier(p_i, opts)
	
	if opts.domain then
		obj.eval = function(x)
			return obj.eval_x(x)
		end
		
		obj.derivative = function(x)
			return obj.derivative_x(x)
		end
	else
		obj.eval = function(t)
			return obj.eval_t(t)
		end
		
		obj.derivative = function(t)
			return obj.derivative_t(t)
		end
	end
	return obj
end

--- Linear "smoothstep" preset
function CUTIL.Tween.linear(a, b)
	return CUTIL.Tween.create({0, 1}, { domain = {a, b}, clamp = true })
end

--- Cubic smoothstep preset
function CUTIL.Tween.smoothstep3(a, b)
	return CUTIL.Tween.create({0, 0, 1, 1}, { domain = {a, b}, clamp = true })
end

--- Quintic smoothstep preset
function CUTIL.Tween.smoothstep5(a, b)
	return CUTIL.Tween.create({0, 0, 0.5, 1, 1}, { domain = {a, b}, clamp = true })
end

--- Helper to create a cubic preset from two numbers (points) p1 and p2
function CUTIL.Tween.cubic_from_two_points(a, b, p1, p2)
	return CUTIL.Tween.create({0, p1, p2, 1}, { domain = {a, b}, clamp = true })
end

--- Creates a modifier function compatible with CUTIL variable modifier functionality.
---
--- @param domain table|nil The input domain {a, b}; default (nil) is normalized input, [0, 1].
--- @param p_i table The control points of the Bezier curve.
--- @param opts table|nil Options:
--- 	- clamp = boolean Whether or not to clamp the parameter to [0, 1], true by default.
--- 	- resolve_aliases = boolean Whether or not to resolve alias strings, true by default.
--- @return function
function CUTIL.Tween.make_modifier(target_domain, p_i, opts)
	opts = opts or {}
	opts.domain = target_domain
	
	local shape = CUTIL.Tween.create(p_i, opts)
	
	return shape.eval
end

---------------------------------------------
-- Value Exchange System
-- This allows you to create a system wherein you can take a set of types of values (i.e. currencies) and convert between them.
---------------------------------------------

CUTIL.ExchangeSystems = { systems = {} }
local systems = CUTIL.ExchangeSystems.systems;

-- Internal helpers

-- Axis variable naming that is collision-safe and opaque
local function axis_var_name(system, axis)
	return "__exchange__" .. system .. "::" .. axis
end

-- Internal getter for the raw stored value
local function get_raw(system, axis)
	return CUTIL.get_variable(sys.axes[axis])
end

-- Internal setter for the raw stored value
local function set_raw(system, axis)
	CUTIL.set_variable(sys.axes[axis], value)
end


-- End internal helpers

--- Creates a new exchange system.
---
--- @param name string The (unique) system name.
--- @param opts table|nil Options:
--- 	- canonical string The name of the canonical axis (default "base").
--- 	- value number Initial value of the canonical axis (default 1).
--- 	- dimension string|nil Optional dimension tag (e.g. "currency").
--- 	- use_log boolean Whether or not to store values in log-space (default false).
--- 	- on_change function|nil Hook: (system, axis, old, new).
function CUTIL.ExchangeSystems.new_system(name, opts)
	assert(type(name) == "string", "System name must be a string")
	assert(systems[name] == nil, "Specified exchange system already exists")

	opts = opts or {}
	local canonical = opts.canonical or "base"
	local value = opts.value or 1
	local use_log = opts.use_log or false
	
	assert(type(value) == "number" and value > 0, "canonical value must be positive")
	
	systems[name] = {
		canonical = canonical,
		axes = {},
		dimension = opts.dimension,
		use_log = use_log,
		on_change = opts.on_change
	}
	
	local var = axis_var_name(name, canonical)
	systems[name].axes[canonical] = var
	
	if use_log then
		CUTIL.add_variable(var, math.log(value))
	else
		CUTIL.add_variable(var, value)
	end
end

--- Adds an axis to an exchange system.
--- 
--- @param system string
--- @param axis string
--- @param relative number|nil Value relative to canonical axis (default 1).
function CUTIL.ExchangeSystems.add_axis(system, axis, relative)
	local sys = systems[system]
	assert(sys, "Specified exchange system does not exist")
	assert(type(axis) == "string", "Axis name must be a string")
	assert(sys.axes[axis] == nil, "Specified axis already exists")
	
	relative = relative or 1
	assert(type(relative) == "number" and relative > 0, "Relative value must be a positive number")
	
	local base = get_raw(sys, sys.canonical)
	local var = axis_var_name(system, axis)
	sys.axes[axis] = var
	
	if sys.use_log then
		CUTIL.add_variable(var, base + math.log(relative))
	else
		CUTIL.add_variable(var, base * relative)
	end
end

--- Removes an axis from a system.
--- If the axis is canonical, the system is renormalized.
---
--- @param system string
--- @param axis string
function CUTIL.ExchangeSystems.remove_axis(system, axis)
	local sys = systems[system]
	assert(sys, "Specified exchange system does not exist")
	
	local var = sys.axes[axis]
	assert(var, "Specified axis does not exist")
	
	if axis == sys.canonical then
		local new_canonical
		
		for a in pairs(sys.axes) do
			if a ~= axis then
				new_canonical = a
				break
			end
		end
		
		assert(new_canonical, "Cannot remove the only axis in the system")
		
		local scale = get_raw(sys, new_canonical)
		
		for a in pairs(sys.axes) do
			if sys.use_log then
				set_raw(sys, a, get_raw(sys, a) - scale)
			else
				set_raw(sys, a, get_raw(sys, a) / scale)
			end
		end
		
		sys.canonical = new_canonical
	end
	
	sys.axes[axis] = nil
	CUTIL.remove_variable(var)
end

--- Sets the normalized value of an axis.
---
--- @param system string
--- @param axis string
--- @param relative number A positive number representing the relative value.
function CUTIL.ExchangeSystems.set_axis(system, axis, relative)
	assert(type(relative) == "number" and relative > 0, "Relative value must be a positive number")
	
	local sys = systems[system_name]
	assert(sys, "Specified exchange system does not exist")
	
	local var = sys.axes[axis]
	assert(var, "Specified axis does not exist")
	
	local base = get_raw(sys, sys.canonical)
	local old = get_raw(sys, axis)
	
	if sys.use_log then
		set_raw(sys, axis, base + math.log(relative))
	else
		set_raw(sys, axis, base * relative)
	end
	
	if sys.on_change then
		sys.on_change(system, axis, old, get_raw(sys, axis))
	end
end

--- Returns the normalized value of an axis.
--- This is dimensionless and invariant.
---
--- @param system string
--- @param axis string
--- @return number
function CUTIL.ExchangeSystems.get_axis(system, axis)
	local sys = systems[system]
	assert(sys, "Specified exchange system does not exist")
	
	local var = sys.axes[axis]
	assert(var, "Specified axis does not exist")
	
	local base = get_raw(sys, sys.canonical)
	local value = get_raw(sys, axis)
	
	if sys.use_log then
		return math.exp(value - base)
	end
	
	return value / base
end

--- Converts a value from one axis to another.
---
--- @param system string
--- @param value number
--- @param from_axis string
--- @param to_axis string
--- @return number
function CUTIL.ExchangeSystems.convert(system, value, from_axis, to_axis)
	assert(type(value) == "number", "Value must be numeric")
	
	local sys = systems[system]
	assert(sys, "Specified exchange system does not exist")
	
	local value_from = CUTIL.ExchangeSystems.get_axis(system, from_axis)
	local value_to = CUTIL.ExchangeSystems.get_axis(system, to_axis)
	
	-- value * value_from = x * value_to
	return value * (value_from / value_to)
end

--- Converts a value from one axis to another, along with a fractional fee in [0, 1].
---
--- @param system string
--- @param value number
--- @param from_axis string
--- @param to_axis string
--- @param fee number
--- @return number
function CUTIL.ExchangeSystems.convert_with_fee(system, value, from_axis, to_axis, fee)
	assert(fee >= 0 and fee <= 1, "Fee must be in [0, 1]")
	
	local remaining_percentage_after_fee = 1 - fee
	
	local conversion = CUTIL.ExchangeSystems.convert(system, value, from_axis, to_axis)
	
	return conversion * remaining_percentage_after_fee
end