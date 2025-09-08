local luau = require "../../luaup/lossless/cst"
local sq = require "../sq_ast/sq_ast"

local create = require "../sq_ast/create"

local SCOPE_TABLE_ROOT = "__scope__"
local SCOPE_TABLE_GEN = "__new_scope__"
local INDEX_FUNC = "__index__"

local function unshift<T>(destination: { T }, value: { T })
	table.move(destination, 1, #destination, #value + 1)
	table.move(value, 1, #value, 1, destination)
end

function transform_cst(state, cst: luau.Cst)
	local block = transform_block(state, cst.block)

	-- this is done so the first scope creation doesnt error
	unshift(
		block.stats,
		{ (create.stat_localvariable(SCOPE_TABLE_ROOT, create.null())) }
	)
	-- insert index helper function here
	-- parse a new luau cst here to get it idc i wouldnt wanna type it out

	return block.stats
end

function transform_block(state, block: luau.Block)
	local stats = {
		(create.stat_localvariable(
			SCOPE_TABLE_ROOT,
			create.expr_var(create.var(create.var_nameroot(SCOPE_TABLE_GEN), {
				create.var_callsuffix(nil, {
					create.expr_var(
						create.var(create.var_nameroot(SCOPE_TABLE_ROOT), {})
					),
				}),
			}))
		)),
	}

	for _, pair in block.stats do
		local stat = pair.node

		local result = transform_stat(state, stat)

		table.insert(stats, state.postreqs)
		table.clear(state.postreqs)

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

function wrap_index(var: sq.Expr, index: sq.Expr)
	return create.var(create.var_nameroot(INDEX_FUNC), {
		create.var_callsuffix(nil, {
			var,
			index,
		}),
	})
end

function floor_div(expr1: sq.Expr, expr2: sq.Expr)
	return create.expr_var(
		create.var(
			create.var_nameroot "floor",
			{ create.var_callsuffix(nil, { create.binary(expr1, "/", expr2) }) }
		)
	)
end

function pow(expr1: sq.Expr, expr2: sq.Expr)
	return create.expr_var(
		create.var(
			create.var_nameroot "pow",
			{ create.var_callsuffix(nil, { expr1, expr2 }) }
		)
	)
end

function unique_id(ident: sq.Identifier)
	--TODO track vars in scope and rename if necessary
	return ident
end

function unpack_tuple(
	state,
	tuple: sq.Identifier,
	vars: { sq.Var },
	local_variable: boolean
): { sq.Stat }
	local stats = {}

	for i, var in vars do
		local assignment

		local value = scope_var(
			create.var(
				create.var_nameroot(tuple),
				{ create.var_callsuffix(nil, { create.int(i) }) }
			)
		)

		if local_variable then
			assert(var.root.kind == "name")
			assignment = create.stat_localvariable(var.root.name, value)
		else
			assignment =
				create.stat_expr(create.expr_assignment(var, "=", value))
		end

		table.insert(state.postreqs, assignment)
		table.insert(stats, assignment)
	end

	return stats
end

function scope_var(var: sq.Var): sq.Var
	local init_suffixes = {}

	if var.root.kind == "name" then
		table.insert(init_suffixes, create.var_namesuffix(var.root.name))
	else
		-- to avoid literals becoming indexed
		if var.root.expr.kind ~= "exprvar" then
			return var
		end

		table.insert(init_suffixes, create.var_exprsuffix(var.root.expr))
	end

	local accumulator =
		create.var(create.var_nameroot(SCOPE_TABLE_ROOT), init_suffixes)

	for _, suffix in var.suffixes do
		if suffix.kind == "nameindex" then
			accumulator =
				wrap_index(accumulator, create.string(suffix.name.text))
		elseif suffix.kind == "exprindex" then
			accumulator = wrap_index(accumulator, suffix.expr)
		elseif suffix.kind == "call" then
			table.insert(accumulator.suffixes, suffix)

			-- If this isnt a tuple assignment:
			--  insert [0] index
		end
	end

	return accumulator
end

function transform_var(state, var: luau.Var): sq.Var
	local root, suffixes = nil, {}
	if var.root.kind == "name" then
		root = create.var_nameroot(var.root.tok.text)
	else
		root = create.var_parenroot(transform_expr(state, var.root.expr))
	end

	for _, suffix in var.suffixes do
		if suffix.kind == "nameindex" then
			table.insert(suffixes, create.var_namesuffix(suffix.name))
		elseif suffix.kind == "exprindex" then
			table.insert(suffixes, create.var_exprsuffix(suffix.name))
		else
			local method = if suffix.method then suffix.method.name else nil
			local args = transform_functionarg(state, suffix.arg)

			table.insert(suffixes, create.var_callsuffix(method, args))
		end
	end

	local sqvar = create.var(root, suffixes)

	return scope_var(sqvar)
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
	elseif expr.kind == "assertion" then
		return transform_expr(state, expr.expr)
	elseif expr.kind == "unary" then
		local op = expr.operator.kind
		if op == "#" then
			return create.expr_var(
				create.var(
					create.var_parenroot(transform_expr(state, expr.expr)),
					{
						create.var_namesuffix "len",
						create.var_callsuffix(nil, {}),
					}
				)
			)
		elseif op == "not" then
			op = "!"
		elseif op == "+" then
			error "???"
		end

		return create.unary(transform_expr(state, expr.expr), op)
	elseif expr.kind == "binary" then
		local left, right =
			transform_expr(state, expr.left), transform_expr(state, expr.right)

		local op = expr.operator.kind
		if op == ".." then
			op = "+"
		elseif op == "and" then
			op = "&&"
		elseif op == "or" then
			op = "||"
		elseif op == "~=" then
			op = "!="
		elseif op == "//" then
			return floor_div(left, right)
		elseif op == "^" then
			return pow(left, right)
		end

		return create.binary(left, op, right)
	end
	error("unknown expr: " .. expr.kind)
end

function transform_stat(state, stat: luau.Stat): { sq.Stat }
	if stat.kind == "assign" then
		local stats = {}

		-- tuple
		-- tuples only assign to more than one variable IF its a function and
		-- it is the rightmost or not in parens
		--
		-- all function calls and iterators need to be wrapped in a handler
		-- to return the first value
		-- unless we are assigning a tuple which we know from the ast
		--

		for i, pair in stat.right do
			local expr = transform_expr(state, pair.node)

			if expr.kind == "exprvar" then
				if #expr.var.suffixes > 0 then
					if expr.var.suffixes[#expr.var.suffixes].kind == "call" then
						if i == #stat.right then
							-- function call as the last var, can assign multiple!

							local temp_name = unique_id "tuple"
							local temp_var =
								create.var(create.var_nameroot(temp_name), {})

							state.tuple[expr.var] = { temp = temp_name }

							-- set state so unpacking can happen
							local vars = {}
							for j = #stat.left - i, #stat.left do
								local var =
									transform_var(state, stat.left[j].node)

								table.insert(vars, var)
							end

							unpack_tuple(state, temp_name, vars, false)

							-- tuple_result = expr()
							table.insert(
								stats,
								create.stat_expr(
									create.expr_assignment(temp_var, "=", expr)
								)
							)
						else
							local var = transform_var(state, stat.left[i].node)
                            -- not a multi-assignment on a function call, so assign the
                            -- first
                            --
                            -- TODO there is a mysteroius empty statement

							table.insert(
								expr.var.suffixes,
								create.var_exprsuffix(create.int(0))
							)

							table.insert(
								stats,
								create.stat_expr(
									create.expr_assignment(var, "=", expr)
								)
							)
						end
					end
				end
			end
		end
		return stats
	elseif stat.kind == "compoundassign" then
		local var = transform_var(state, stat.left)
		local expr = transform_expr(state, stat.right)
		local op = stat.operator.kind

		if op == "//=" then
			local floored = floor_div(var, expr)
			return {
				create.stat_expr(create.expr_assignment(var, "=", floored)),
			}
		elseif op == "^=" then
			local powed = pow(var, expr)
			return { create.stat_expr(create.expr_assignment(var, "=", powed)) }
		elseif op == "..=" then
			op = "+"
		end

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
		return {
			create.stat_while(
				transform_expr(state, stat.condition),
				transform_block(state, stat.block)
			),
		}
	elseif stat.kind == "repeat" then
		local expr = create.unary(
			create.expr_var(
				create.var(
					create.var_parenroot(transform_expr(state, stat.condition)),
					{}
				)
			),
			"!"
		)

		return {
			create.stat_dowhile(transform_block(state, stat.block), expr),
		}
	elseif stat.kind == "if" then
		local branches, else_block = {} :: { sq.IfStatBranch }, nil

		for _, pair in stat.branches do
			local branch = pair.node
			table.insert(branches, {
				condition = transform_expr(state, branch.condition),
				block = transform_block(state, branch.block),
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
		local var_name, start_value =
			stat.binding.name.text, transform_expr(state, stat.start_expr)
		local cond = transform_expr(state, stat.end_expr)
		local incr_amount = if stat.step
			then transform_expr(state, stat.step.expr)
			else nil

		-- create.localvariable should return a var as well

		local init, var = create.stat_localvariable(var_name, start_value)
		local expr_var = create.expr_var(var)

		local cond_expr = create.binary(expr_var, ">=", cond)
		local incr_expr = create.expr_assignment(expr_var, "+=", incr_amount)

		return {
			create.stat_for(
				transform_block(state, stat.block),
				init,
				cond_expr,
				incr_expr
			),
		}
	elseif stat.kind == "forin" then
		return {
			-- create.stat_foreach(i_id, v_id, expr, block)
		}
	elseif stat.kind == "localvariable" then
		local stats = {} :: { sq.Stat }

		for i, binding in stat.bindings do
			local ident, value = binding.node.name.text, nil
			if stat.values and stat.values.exprs[i] then
				value = transform_expr(state, stat.values.exprs[i].node)
			else
				value = create.null()
			end

			local var = create.var(
				create.var_nameroot(SCOPE_TABLE_ROOT),
				{ create.var_namesuffix(ident) }
			)

			table.insert(
				stats,
				create.stat_expr(create.expr_assignment(var, "<-", value))
			)
		end

		return stats
	elseif stat.kind == "function" then
	end
	return {}
end

return {
	cst = transform_cst,
	block = transform_block,
	statement = transform_stat,
	expression = transform_expr,
}
