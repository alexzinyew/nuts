local luau = require "../../luaup/lossless/cst"
local sq = require "../sq_ast/sq_ast"

local create = require "../sq_ast/create"
local transform_expr = require "./transform_expression"
local transform_functionarg = require "./transform_functionarg"

local DO_SCOPE_TABLES = false

return function(state, var: luau.Var): sq.Var
	local root, suffixes = nil, {} :: { sq.VarSuffix }

	if DO_SCOPE_TABLES then
		root = { kind = "name", name = "__scope" }
		if var.root.kind == "name" then
			table.insert(
				suffixes,
				{ kind = "nameindex", name = var.root.tok.text }
			)
		else
			table.insert(
				suffixes,
				{
					kind = "exprindex",
					expr = transform_expr(state, var.root.expr),
				}
			)
		end
	else
		if var.root.kind == "name" then
			root = { kind = "name", name = var.root.tok.text }
		else
			root =
				{ kind = "paren", expr = transform_expr(state, var.root.expr) }
		end
	end

	for _, suffix in var.suffixes do
		if suffix.kind == "nameindex" then
			table.insert(suffixes, {
				kind = "nameindex",
				name = suffix.name.text,
			})
		elseif suffix.kind == "exprindex" then
			table.insert(suffixes, {
				kind = "exprindex",
				expr = transform_expr(state, suffix.expr),
			})
		elseif suffix.kind == "call" then
			table.insert(suffixes, {
				kind = "call",
				args = transform_functionarg(state, suffix.arg),
			})
		end
	end

	return create.var(root, suffixes)
end
