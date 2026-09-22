-- Modular BDD Test Framework for Luanti Mods
-- Zero-dependency, fast, failure-resilient, and Busted-compatible

local framework = {
	suites = {},
	stats = {
		passed = 0,
		failed = 0,
		errors = 0,
		assertions = 0,
	},
}

-- ANSI terminal color helpers
local has_color = true
local colors = {
	reset = "\27[0m",
	green = "\27[32m",
	red = "\27[31m",
	yellow = "\27[33m",
	cyan = "\27[36m",
	dim = "\27[2m",
	bold = "\27[1m",
}

local function colorize(color_key, text)
	if not has_color then return text end
	return (colors[color_key] or "") .. text .. colors.reset
end

-- Deep table equality comparator
local function deep_equals(actual, expected)
	if actual == expected then return true end
	if type(actual) ~= "table" or type(expected) ~= "table" then
		if type(actual) == "number" and type(expected) == "number" then
			return math.abs(actual - expected) <= 1e-5
		end
		return false
	end

	for k, v in pairs(expected) do
		if actual[k] == nil then return false end
		if not deep_equals(actual[k], v) then return false end
	end
	for k, _ in pairs(actual) do
		if expected[k] == nil then return false end
	end
	return true
end

-- Custom Assertion Library
local assertions = {}

function assertions.equal(expected, actual, message)
	framework.stats.assertions = framework.stats.assertions + 1
	if type(expected) == "number" and type(actual) == "number" then
		if math.abs(expected - actual) > 1e-5 then
			error(string.format("%s[expected %s, got %s]",
				message and (message .. " ") or "", tostring(expected), tostring(actual)), 2)
		end
		return
	end
	if type(expected) == "table" and type(actual) == "table" then
		assertions.table_equal(expected, actual, message)
		return
	end
	if expected ~= actual then
		error(string.format("%s[expected %s, got %s]",
			message and (message .. " ") or "", tostring(expected), tostring(actual)), 2)
	end
end

function assertions.not_equal(unexpected, actual, message)
	framework.stats.assertions = framework.stats.assertions + 1
	if unexpected == actual then
		error(string.format("%s[expected value to not equal %s]",
			message and (message .. " ") or "", tostring(unexpected)), 2)
	end
end

function assertions.near(expected, actual, epsilon, message)
	framework.stats.assertions = framework.stats.assertions + 1
	local eps = epsilon or 1e-5
	if math.abs(expected - actual) > eps then
		error(string.format("%s[expected %s to be near %s within %s]",
			message and (message .. " ") or "", tostring(actual), tostring(expected), tostring(eps)), 2)
	end
end

function assertions.is_true(condition, message)
	framework.stats.assertions = framework.stats.assertions + 1
	if condition ~= true then
		error(string.format("%s[expected true, got %s]",
			message and (message .. " ") or "", tostring(condition)), 2)
	end
end

function assertions.is_false(condition, message)
	framework.stats.assertions = framework.stats.assertions + 1
	if condition ~= false then
		error(string.format("%s[expected false, got %s]",
			message and (message .. " ") or "", tostring(condition)), 2)
	end
end

function assertions.is_nil(val, message)
	framework.stats.assertions = framework.stats.assertions + 1
	if val ~= nil then
		error(string.format("%s[expected nil, got %s]",
			message and (message .. " ") or "", tostring(val)), 2)
	end
end

function assertions.is_not_nil(val, message)
	framework.stats.assertions = framework.stats.assertions + 1
	if val == nil then
		error(string.format("%s[expected non-nil value, got nil]",
			message and (message .. " ") or ""), 2)
	end
end

function assertions.table_equal(expected, actual, message)
	framework.stats.assertions = framework.stats.assertions + 1
	if not deep_equals(actual, expected) then
		local function format_diff(exp_tbl, act_tbl)
			for k, v in pairs(exp_tbl) do
				if act_tbl[k] == nil then
					return string.format("missing key '%s'", tostring(k))
				elseif not deep_equals(act_tbl[k], v) then
					return string.format("key '%s': expected %s, got %s",
						tostring(k), tostring(v), tostring(act_tbl[k]))
				end
			end
			for k, v in pairs(act_tbl) do
				if exp_tbl[k] == nil then
					return string.format("extra key '%s': %s", tostring(k), tostring(v))
				end
			end
			return "table values mismatch"
		end
		error(string.format("%s[%s]",
			message and (message .. " ") or "", format_diff(expected, actual)), 2)
	end
end

function assertions.error(fn, message)
	framework.stats.assertions = framework.stats.assertions + 1
	local ok, _ = pcall(fn)
	if ok then
		error(string.format("%s[expected function to throw an error]",
			message and (message .. " ") or ""), 2)
	end
end

framework.assert = assertions

-- Suite Context State
local current_suite = nil

function framework.describe(description, fn)
	local suite = {
		name = description,
		parent = current_suite,
		before_each = {},
		after_each = {},
		tests = {},
		children = {},
	}

	if current_suite then
		table.insert(current_suite.children, suite)
	else
		table.insert(framework.suites, suite)
	end

	local previous_suite = current_suite
	current_suite = suite
	fn()
	current_suite = previous_suite
end

function framework.it(description, fn)
	if not current_suite then
		error("it() must be called within a describe() block", 2)
	end
	table.insert(current_suite.tests, {
		name = description,
		fn = fn,
	})
end

function framework.before_each(fn)
	if not current_suite then
		error("before_each() must be called within a describe() block", 2)
	end
	table.insert(current_suite.before_each, fn)
end

function framework.after_each(fn)
	if not current_suite then
		error("after_each() must be called within a describe() block", 2)
	end
	table.insert(current_suite.after_each, fn)
end

local function gather_hooks(suite, hook_name)
	local hooks = {}
	local s = suite
	while s do
		if s[hook_name] then
			for i = #s[hook_name], 1, -1 do
				table.insert(hooks, 1, s[hook_name][i])
			end
		end
		s = s.parent
	end
	return hooks
end

-- Runner Execution
function framework.run()
	local start_time = os.clock()
	local failures = {}

	local function run_suite(suite, depth)
		local indent = string.rep("  ", depth)
		print(indent .. colorize("bold", suite.name))

		local before_hooks = gather_hooks(suite, "before_each")
		local after_hooks = gather_hooks(suite, "after_each")

		for _, test in ipairs(suite.tests) do
			for _, hook in ipairs(before_hooks) do
				hook()
			end

			local ok, err = pcall(test.fn)

			for _, hook in ipairs(after_hooks) do
				pcall(hook)
			end

			if ok then
				framework.stats.passed = framework.stats.passed + 1
				print(indent .. "  " .. colorize("green", "✓") .. " " .. colorize("dim", test.name))
			else
				framework.stats.failed = framework.stats.failed + 1
				print(indent .. "  " .. colorize("red", "✗") .. " " .. test.name)
				table.insert(failures, {
					suite = suite.name,
					name = test.name,
					error = err,
				})
			end
		end

		for _, child in ipairs(suite.children) do
			run_suite(child, depth + 1)
		end
	end

	for _, suite in ipairs(framework.suites) do
		run_suite(suite, 0)
	end

	local elapsed = os.clock() - start_time
	print("\n" .. string.rep("─", 56))

	if #failures > 0 then
		print(colorize("bold", colorize("red", string.format("FAILURES (%d):", #failures))))
		for i, fail in ipairs(failures) do
			print(string.format("\n%d) %s -> %s:", i, fail.suite, fail.name))
			print(colorize("red", "   " .. tostring(fail.error)))
		end
		print(string.rep("─", 56))
	end

	local summary = string.format("Tests:      %s passed, %s failed, %d total",
		colorize("green", tostring(framework.stats.passed)),
		colorize(framework.stats.failed > 0 and "red" or "dim", tostring(framework.stats.failed)),
		framework.stats.passed + framework.stats.failed)
	local assert_info = string.format("Assertions: %s verified",
		colorize("cyan", tostring(framework.stats.assertions)))
	local time_info = string.format("Duration:   %.3fs", elapsed)

	print(summary)
	print(assert_info)
	print(time_info)
	print(string.rep("─", 56))

	if framework.stats.failed > 0 then
		print(colorize("bold", colorize("red", "TEST SUITE FAILED")))
		return false
	else
		print(colorize("bold", colorize("green", "ALL TESTS PASSED CLEANLY!")))
		return true
	end
end

function framework.expose_globals()
	rawset(_G, "describe", framework.describe)
	rawset(_G, "it", framework.it)
	rawset(_G, "before_each", framework.before_each)
	rawset(_G, "after_each", framework.after_each)
	rawset(_G, "assert_test", framework.assert)
	-- Also expose standard Busted-style assert table
	rawset(_G, "assert", framework.assert)
end

return framework
