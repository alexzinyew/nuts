local fs = require "@lune/fs"
local process = require "@lune/process"
local net = require "@lune/net"

local luau_parser = require "@luaup/lossless/parse"
local sq_transformer = require "@src/sq_transformer/transform"
local sq_renderer = require "@src/sq_renderer/render"

local args = process.args
local tcp_port = assert(args[1], "provide netcon port")
local p2_path = assert(args[2], "provide Portal 2 path")
local vscripts = p2_path .. "/portal2/scripts/vscripts/tests"

if not fs.isDir(vscripts) then
    fs.writeDir(vscripts)
end

local test_dir = fs.readDir "src/test/tests"

print "Connecting to console"
local tcp = net.tcp.connect("localhost", tcp_port)
print "Connected!"

tcp:write("sar_con_filter 0; clear\r\n")


local function run_tests()
    local failed_tests = 0

	for _, test_name in test_dir do
		local path = "src/test/tests/" .. test_name
        test_name = string.gsub(test_name, "\.luau$", "")

		local parse_result = luau_parser(fs.readFile(path))
		if not parse_result.success then
			print(`Test "{test_name}" failed to parse`)
			print(parse_result.error)
			return
		end

		local transform_success, transform_result =
			pcall(sq_transformer.cst, parse_result.cst)
		if not transform_success then
			print(`Test "{test_name}" failed to transform`)
			print(transform_result)
			return
		end

		local render_success, render_result =
			pcall(sq_renderer.block, transform_result)
		if not render_success then
			print(`Test "{test_name}" failed to render`)
			return
		end

        render_result = sq_renderer.helpers() .. render_result

		local output_path = vscripts .. "/" .. test_name .. ".nut"
		fs.writeFile(output_path, render_result)

        local failed = false

        print()
        print(`Running test: {test_name}`)
        tcp:write(`script_execute tests/{test_name}; echo TEST_COMPLETE\r\n`)
        
        local output = ""
        while true do
            output ..= tcp:read(1024)
            if string.find(output, "TEST_COMPLETE") then
                for _, line in output:split("\r\n") do
                    if line:find("TEST_COMPLETE") then break end
                    if line:find("Error running script") then
                        failed = true
                    end
                    if #line > 0 then
                        print(line)
                    end
                end
                break
            end
        end
        
        if failed then
            failed_tests += 1
        end
	end

    print()
    print(`{#test_dir - failed_tests}/{#test_dir} tests passed`)
end

run_tests()
tcp:close()
