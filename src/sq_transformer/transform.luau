local luau = require "../../luaup/lossless/cst"
local sq = require "../sq_ast/sq_ast"

local create = require "../sq_ast/create"

local DO_SCOPE_TABLES = true
local SCOPE_TABLE_ROOT = "__scope"

function transform_block(state, block: luau.Block)
	local stats = {}

	for _, pair in block.stats do
		local stat = pair.node

		local result = transform_stat(state, stat)
		for _, v in result do
			table.insert(stats, v)
		end
	end

	return {
		stats = stats,
	} :: sq.Block
end

function transform_functionarg(state, arg: luau.FunctionArg): { sq.Expr }
	if arg.kind == "pack" then
		local exprs = {}
		for _, pair in arg.exprs do
			table.insert(exprs, transform_expr(state, pair.node))
		end
		return exprs
	elseif arg.kind == "string" then
		return { create.string(arg.tok.text) }
	elseif arg.kind == "table" then
		local table_expr =
			{ kind = "table", table = arg.table } :: luau.Expr_Table
		return { transform_expr(state, table_expr) }
	end
	error ""
end

function transform_var(state, var: luau.Var): sq.Var
	local root, suffixes = nil, {} :: { sq.VarSuffix }

	if DO_SCOPE_TABLES then
		root = { kind = "name", name = SCOPE_TABLE_ROOT }
		if var.root.kind == "name" then
			table.insert(
				suffixes,
				{ kind = "nameindex", name = var.root.tok.text }
			)
		else
			table.insert(suffixes, {
				kind = "exprindex",
				expr = transform_expr(state, var.root.expr),
			})
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

function transform_expr(state, expr: luau.Expr): sq.Expr
	if expr.kind == "nil" then
		return create.null()
	elseif expr.kind == "boolean" then
		local bool = if expr.tok.kind == "true" then true else false
		return create.bool(bool)
	elseif expr.kind == "number" then
		local num = tonumber(expr.tok.text)
		if string.find(num, "%D") then
			return create.float(num)
		else
			return create.int(num)
		end
	elseif expr.kind == "string" then
		return create.string(expr.tok.text)
	elseif expr.kind == "varargs" then
		error ""
	elseif expr.kind == "istring" then
		if expr.istring.kind == "simple" then
			return create.string(expr.istring.tok.text)
		else
			local exprs = {} :: { sq.Expr }

			for _, pair in expr.istring.middle do
				local node, sep = pair.node, pair.sep
				table.insert(exprs, transform_expr(state, node))
				if sep then
					table.insert(
						exprs,
						create.string(string.sub(sep.text, 2, #sep.text - 1))
					)
				end
			end

			local accumulator = create.string(expr.istring.first.text)
			for _, expr in exprs do
				accumulator = create.binary(accumulator, "+", expr)
			end
			accumulator = create.binary(
				accumulator,
				"+",
				create.string(expr.istring.last.text)
			)

			return accumulator
		end
    elseif expr.kind == "var" then
        return create.expr_var(transform_var(state, expr.var))
	end
	error("unknown expr: " .. expr.kind)
end

function transform_stat(state, stat: luau.Stat): { sq.Stat }
	if stat.kind == "assign" then
		local stats = {}
		for i, pair in stat.left do
			local var = transform_var(state, pair.node)
			local expr = transform_expr(state, stat.right[i].node)
			table.insert(
				stats,
				create.stat_expr(create.expr_assignment(var, "<-", expr))
			)
		end
		return stats
	elseif stat.kind == "compoundassign" then
		local var = transform_var(state, stat.left)
		local expr = transform_expr(state, stat.right)
		local op = stat.operator.kind

        --stylua: ignore start
		if op == "//=" then
            local floor = create.expr_var({
                kind = "var",
                root = { kind = "name", name = "floor" },
                suffixes = { { kind = "call", args = { create.binary(var, "/", expr) } } }
            } :: sq.Var )

            return { create.stat_expr(create.expr_assignment(var, "=", floor)) }
		elseif op == "^=" then
            local floor = create.expr_var({
                kind = "var",
                root = { kind = "name", name = "pow" },
                suffixes = { { kind = "call", args = { var, expr } } }
            } :: sq.Var )

            return { create.stat_expr(create.expr_assignment(var, "=", floor)) }
		elseif op == "..=" then
			op = "+"
		end
		--stylua: ignore end

		return { create.stat_expr(create.expr_assignment(var, op, expr)) }
	elseif stat.kind == "call" then
		return {
			create.stat_expr(create.expr_var(transform_var(state, stat.call))),
		}
	elseif stat.kind == "do" then
		-- maybe an anonymous function
		-- or dowhile with false condition
		return {}
	elseif stat.kind == "while" then
		return { create.stat_while(
			transform_expr(state, stat.condition),
			transform_block(state, stat.block)
		) }
	elseif stat.kind == "repeat" then
        local expr = create.unary(create.expr_var {
            kind = "var",
            root = { kind = "paren", expr = transform_expr(state, stat.condition) },
            suffixes = {},
        }, "!")

		return { create.stat_dowhile(
			transform_block(state, stat.block),
            expr
		) }
    elseif stat.kind == "if" then
        local branches, else_block = {} :: { sq.IfStatBranch }, nil

        for _, pair in stat.branches do
            local branch = pair.node
            table.insert(branches, {
                condition = transform_expr(state, branch.condition),
                block = transform_block(state, branch.block)
            })
        end

        if stat.else_branch then
            else_block = stat.else_branch.block
        end

        return { create.stat_if(branches, else_block) }
    elseif stat.kind == "numericfor" then
        -- create local assignment
        -- create binary operator
        -- create +=
        return { create.stat_for(transform_block(state, stat.block), init, cond, incr) }
    elseif stat.kind == "localvariable" then
        local stats = {}

        for i, binding in stat.bindings do
            local ident, value = binding.node.name.text, nil
            if stat.values and stat.values.exprs[i] then
                value = transform_expr(state, stat.values.exprs[i].node)
            else
                value = create.null()
            end

            if DO_SCOPE_TABLES then
                local var = {
                    kind = "var",
                    root = SCOPE_TABLE_ROOT,
                    suffixes = { { kind = "nameindex", name = ident } }
                } :: sq.Var

                table.insert(stats, create.expr_assignment(var, "<-", value))
            else
                table.insert(stats, create.stat_localvariable(ident, value))
            end
        end
        
        return stats
	end
	return {}
end

return {
	block = transform_block,
	statement = transform_stat,
	expression = transform_expr,
}
