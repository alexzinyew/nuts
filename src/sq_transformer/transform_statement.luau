local luau = require "../../luaup/lossless/cst"
local sq = require "../sq_ast/sq_ast"

local create = require "../sq_ast/create"
local transform_expr = require "./transform_expression"
local transform_var = require "./transform_var"

return function(state, stat: luau.Stat): { sq.Stat }
	print(stat.kind)
	if stat.kind == "assign" then
		local stats = {}
		for i, pair in stat.left do
			local var = transform_var(state, pair.node)
			local expr = transform_expr(state, stat.right[i].node)
			table.insert(
				stats,
				create.stat_expr(create.expr_assignment(var, "=", expr))
			)
		end
		return stats
	elseif stat.kind == "compoundassign" then
		local var = transform_var(state, stat.left)
		local expr = transform_expr(state, stat.right)
		local op = stat.operator.kind

		if op == "//=" then
			error "dont use //="
		elseif op == "^=" then
			error "dont use ^="
		elseif op == "..=" then
			op = "+"
		end

		return { create.stat_expr(create.expr_assignment(var, op, expr)) }
	elseif stat.kind == "call" then
		return { create.expr_var(transform_var(state, stat.call)) }
	elseif stat.kind == "do" then
		-- maybe an anonymous function
		return {}
	elseif stat.kind == "while" then
	end
	return {}
end
