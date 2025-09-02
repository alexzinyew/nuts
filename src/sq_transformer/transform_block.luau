local luau = require "../../luaup/lossless/cst"
local sq = require "../sq_ast/sq_ast"

local transform_statement = require "./transform_statement"

return function(state, block: luau.Block)
	local stats = {}

	for _, pair in block.stats do
        local stat = pair.node

        local result = transform_statement(state, stat)
        for _, v in result do table.insert(stats, v) end
	end

	return {
		stats = stats,
	} :: sq.Block
end
