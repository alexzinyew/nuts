local fs = require "@lute/fs"

local luau_parser = require "../luaup/lossless/parse"
local sq_transform = require "./sq_transformer/transform"

local args = { ... }
local file_name = assert(args[2], "expected file name")
local file_content = fs.readfiletostring(file_name)

local luau_parse_result = luau_parser(file_content)
assert(luau_parse_result.success, "Failed to parse input")

local prereqs, postreqs = {}, {}
local state = {
	prereqs = prereqs,
    postreqs = postreqs,
    tuple = {},
	move_clear_prereqs = function(destination: { any }, start: number?)
		table.move(prereqs, 1, #prereqs, start or 1, destination)
		table.clear(prereqs)
	end,
}

-- make custom array class type def
--
-- insert include files in dir and with IncludeScript opt
--
-- local a, b, c = tuple_func()
--
-- local _tuple_result = tuple_func()
-- local a = _tuple_result[0]
-- local b = _tuple_result[1]
-- local c = _tuple_result[2]
--
-- for i, x, y, z in fn() do
-- 
-- foreach(i, result in fn()) {
--      local x = result[0]
--      local y = result[1]
--      local z = result[2]
-- }

function tprint(tbl, indent)
	if not indent then
		indent = 0
	end
	for k, v in pairs(tbl) do
		local formatting = string.rep("  ", indent) .. k .. ": "
		if type(v) == "table" then
			print(formatting)
			tprint(v, indent + 1)
		elseif type(v) == "boolean" then
			print(formatting .. tostring(v))
		else
			print(formatting .. v)
		end
	end
end

tprint(sq_transform.cst(state, luau_parse_result.cst))
