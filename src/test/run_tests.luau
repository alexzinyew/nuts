local fs = require "@lune/fs"
local process = require "@lune/process"
local net = require "@lune/net"

local luau_parser = require "@luaup/lossless/parse"
local sq_transformer = require "@src/sq_transformer/transform"
local sq_renderer = require "@src/sq_renderer/render"

local args = { ... }
local tests_path = assert(args[2], "provide tests path")
local p2_path = assert(args[3], "provide Portal 2 path")
local vscripts = p2_path .. "/portal2/scripts/vscripts"

local function run_tests()
	for _, entry in fs.listdir(tests_path) do
		if entry.type == "file" then
			local path = tests_path .. "/" .. entry.name

			local parse_result = luau_parser(fs.readfiletostring(path))
			if not parse_result.success then
				print(`Test "{entry.name}" failed to parse`)
				print(parse_result.error)
				return
			end

			local transform_success, transform_result =
				pcall(sq_transformer.cst, parse_result.cst)
			if not transform_success then
				print(`Test "{entry.name}" failed to transform`)
				print(transform_result)
				return
			end

			local render_success, render_result =
				pcall(sq_renderer.block, transform_result)
			if not render_success then
				print(`Test "{entry.name}" failed to render`)
				print(render_result)
				return
			end

			local output_path = vscripts .. "/" .. entry.name .. ".nut"
			fs.writestringtofile(output_path, render_result)

            -- how to send tcp
		end
	end
end

run_tests()
