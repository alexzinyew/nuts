local fs = require "@lune/fs"

local luau_parser = require "../luaup/lossless/parse"
local sq_transform = require "./sq_transformer/transform"
local sq = require "./sq_ast/sq_ast"


local renderer = require "./sq_renderer/render"

local args = { ... }
local file_name = assert(args[2], "expected file name")
local output_name = assert(args[3], "expected output")
local file_content = fs.readFile(file_name)

local luau_parse_result = luau_parser(file_content)
assert(luau_parse_result.success, "Failed to parse input")


-- make custom array class type def
--
-- insert include files in dir and with IncludeScript opt
--

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

local now = os.clock()
local result = sq_transform.cst(luau_parse_result.cst)
local time = os.clock() - now
--tprint(result)
print(time)
local rendered = renderer.block(result)
rendered = renderer.helpers() .. rendered

fs.writestringtofile(output_name, rendered)
