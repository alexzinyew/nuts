local fs = require "@lute/fs"

local luau_parser = require "../luaup/lossless/parse"
local sq_transform = require "./sq_transformer/transform"

local args = { ... }
local file_name = assert(args[2], "expected file name")
local file_content = fs.readfiletostring(file_name)

local luau_parse_result = luau_parser(file_content)
assert(luau_parse_result.success, "Failed to parse input")

local prereqs = {}
local state = {
	prereqs = prereqs,
	move_clear_prereqs = function(destination: { any }, start: number?)
		table.move(prereqs, 1, #prereqs, start or 1, destination)
		table.clear(prereqs)
	end,
	unshift = function<T>(destination: { T }, value: { T } | T)
		local nvalue = (
			if typeof(value) == "table" then value else { value }
		) :: { T }
		table.move(destination, 1, #destination, #nvalue + 1)
		table.move(nvalue, 1, #nvalue, 1, destination)
	end,
}

-- make wrappers for indexing because of does not exist errors
-- _index <- function(table, key) {
--     if (!(key in table)) return null
--     return table[key]
-- }
--
-- or delegate all tables to one with a metamethod to handle invalid keys
--
-- make custom array class type def

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

tprint(sq_transform.block(state, luau_parse_result.cst.block))
