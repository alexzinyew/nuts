local fs = require "@lune/fs"
local process = require "@lune/process"
local net = require "@lune/net"
local luau = require "@lune/luau"

local luau_parser = require "@luaup/lossless/parse"
local sq_transformer = require "@src/sq_transformer/transform"
local sq_renderer = require "@src/sq_renderer/render"

local testkit = require "@vendor/testkit"
local TEST, CASE, CHECK, FINISH, SKIP = testkit.test()

local args = process.args
local tcp_port = assert(args[1], "provide netcon port")
local p2_path = assert(args[2], "provide Portal 2 path")
local vscripts = p2_path .. "/portal2/scripts/vscripts/tests"

if not fs.isDir(vscripts) then
	fs.writeDir(vscripts)
end

local test_dir = fs.readDir "src/test/tests"

local function run_tests()
	local scripts: { string } = {}

	for _, test_name in test_dir do
		TEST(`{test_name} compilation`, function()
			CASE "parsing"

			local path = "src/test/tests/" .. test_name
			test_name = string.gsub(test_name, ".luau$", "")

			local parse_result = luau_parser(fs.readFile(path))
			if not parse_result.success then
				error(parse_result.error)
				return
			end
			CHECK(true)

			CASE "transforming"
			local transform_success, transform_result =
				pcall(sq_transformer.cst, parse_result.cst)
			if not transform_success then
				print(`Test "{test_name}" failed to transform`)
				error(transform_result)
			end
			CHECK(true)

			CASE "rendering"
			local render_success, render_result =
				pcall(sq_renderer.block, transform_result)
			if not render_success then
				print(`Test "{test_name}" failed to render`)
				error(render_result)
			end
			CHECK(true)

			render_result = sq_renderer.helpers() .. render_result
			render_result = '::CASE <- function(args) {printl("TEST_CASE " + args[0]);return []}\n'
				.. render_result
			render_result = '::CHECK <- function(args) {\
                printl("TEST_CHECK " + (args[0] ? "pass" : "fail")\
                + " " + getstackinfos(2).line); return []\
            }\n' .. render_result

			local output_path = vscripts .. "/" .. test_name .. ".nut"
			fs.writeFile(output_path, render_result)

			table.insert(scripts, test_name)
		end)
	end
	FINISH()

	for _, test_name in test_dir do
		TEST(`{test_name} luau`, function()
			local path = "src/test/tests/" .. test_name
			local compiled = luau.compile(fs.readFile(path))
			luau.load(compiled, {
				debugName = test_name,
				environment = {
					CHECK = CHECK,
					CASE = CASE,
					cprintl = print,
				},
			})()
		end)
	end
	FINISH()

	print ""
	print "Connecting to console"
	print ""
	local tcp = net.tcp.connect("localhost", tcp_port)

	tcp:write "sar_con_filter_reset; sar_con_filter 1\r\n"
	tcp:write "sar_con_filter_block TEST_CHECK\r\n"
    tcp:write "sar_con_filter_block TEST_CASE\r\n"
	tcp:write "sar_con_filter_block TEST_COMPLETE\r\n"
	tcp:write "clear\r\n"

	for _, test in scripts do
		TEST(`{test} squirrel`, function()
			tcp:write(`script_execute tests/{test}; echo TEST_COMPLETE\r\n`)

			local test = testkit.ctest()

			local output = ""
			local error_message
			local callstack = ""
			local in_callstack = false

			while true do
				output ..= tcp:read(1024)
				if string.find(output, "TEST_COMPLETE") then
					for _, line in output:split "\r\n" do
						line = line:gsub("\r\n", "")

						if line:find "TEST_CASE" then
							local split = string.split(line, "TEST_CASE ")
							CASE(split[2])
							continue
						end
						if line:find "TEST_CHECK" then
							if test.case.result ~= 2 then
								local split = string.split(line, " ")
								test.case.result = split[2] == "pass" and 1 or 2
								test.case.line = split[3]
							end
						end
						if line:find "AN ERROR HAS OCCURED" then
							error_message =
								line:split("AN ERROR HAS OCCURED ")[2]
						end
						if line:find "CALLSTACK" then
							in_callstack = true
							continue
						end
						if line:find "LOCALS" then
							in_callstack = false
						end
						if in_callstack then
							callstack ..= line
						end
						if #line > 0 then
							--print(line)
						end
						if line:find "TEST_COMPLETE" then
							if error_message then
								test.case.result = 4
								test.error = {
									message = error_message,
									trace = callstack,
								}
							end
							break
						end
					end
					break
				end
			end
		end)
	end
	tcp:close()
end

run_tests()
FINISH()
