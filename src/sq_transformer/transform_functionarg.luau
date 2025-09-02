local luau = require "../../luaup/lossless/cst"
local sq = require "../sq_ast/sq_ast"

local create = require "../sq_ast/create"
local transform_expr = require "./transform_expression"

return function(state, arg: luau.FunctionArg): { sq.Expr }
	if arg.kind == "pack" then
		local exprs = {}
		for _, pair in arg.exprs do
			table.insert(exprs, transform_expr(state, pair.node))
		end
		return exprs
	elseif arg.kind == "string" then
		return { create.string(arg.tok.text) }
	elseif arg.kind == "table" then
		local table_expr = { kind = "table", table = arg.table } :: luau.Expr_Table
		return { transform_expr(state, table_expr) }
	end
    error ""
end
