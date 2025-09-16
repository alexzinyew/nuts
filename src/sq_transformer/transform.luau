local luau = require "@luaup/lossless/cst"
local sq = require "@src/sq_ast/sq_ast"

local create = require "@src/sq_ast/create"

local SCOPE_TABLE_ROOT = "__scope__"
local SCOPE_TABLE_GEN = "__new_scope__"
local INDEX_FUNC = "__index__"
local SET_FUNC = "__set__"
local JOIN_FUNC = "__join__"
local ITER_FUNC = "__iter__"

--stylua: ignore start
local KEYWORDS = {
    "break",	"case",	"catch",	"class",	"clone",	"continue",
    "const",	"default",	"delegate",	"delete",	"else",	"enum",
    "extends",	"for",	"foreach",	"function",	"if",	"in",
    "local",	"null",	"resume",	"return",	"switch",	"this",
    "throw",	"try",	"typeof",	"while",	"parent",	"yield",
    "constructor",	"vargc",	"vargv",	"instanceof",	"true",	"false",
    "static",
}
--stylua: ignore end

-- SCOPE_TABLE_ROOT = "s"
-- SCOPE_TABLE_GEN = "ns"
-- INDEX_FUNC = "i"
-- JOIN_FUNC = "j"

local possible_tuples = {} :: { [sq.Var]: true }

--TODO function defs need an args array that is unpacked
--and therefore all function calls need to pass array from transform_exprarray

local function unshift<T>(destination: { T }, value: { T })
	table.move(destination, 1, #destination, #value + 1)
	table.move(value, 1, #value, 1, destination)
end

local prereqs_stack = {}
local function capture<T>(callback: () -> T): (T, { sq.Stat })
	table.insert(prereqs_stack, {})
	local ret = callback()
	local popped = table.remove(prereqs_stack, #prereqs_stack)
	return ret, popped :: any
end

local function prereq(stat: sq.Stat)
	table.insert(prereqs_stack[#prereqs_stack], stat)
end

local function safe_ident(ident: string): string
	if table.find(KEYWORDS, ident) then
		return unique_id(ident .. "_1")
	end
	return ident
end

function transform_cst(cst: luau.Cst): sq.Block
	local block = transform_block(cst.block)

	-- this is done so the first scope creation doesnt error
	unshift(
		block.stats,
		{ (create.stat_localvariable(SCOPE_TABLE_ROOT, create.null())) }
	)
	-- insert index helper function here
	-- parse a new luau cst here to get it idc i wouldnt wanna type it out

	return block
end

function new_scope(name: string?, prev: string?)
	return create.stat_localvariable(
		name or SCOPE_TABLE_ROOT,
		create.expr_var(create.var(create.var_nameroot(SCOPE_TABLE_GEN), {
			create.var_callsuffix(nil, {
				create.expr_var(
					create.var(
						create.var_nameroot(prev or SCOPE_TABLE_ROOT),
						{}
					)
				),
			}),
		}))
	)
end

function transform_block(block: luau.Block, dont_make_scope: boolean?)
	local stats = {} :: { sq.Stat }
	if not dont_make_scope then
		table.insert(stats, (new_scope()))
	end

	for _, pair in block.stats do
		local stat = pair.node

		local result, captured = capture(function()
			return transform_stat(stat)
		end)

		for _, v in captured do
			table.insert(stats, v)
		end
		for _, v in result do
			table.insert(stats, v)
		end
	end

	local last_stat
	if block.last_stat then
		local stat, captured = capture(function()
			return transform_laststat(block.last_stat.stat)
		end)

		last_stat = stat

		for _, v in captured do
			table.insert(stats, v)
		end
	end

	return {
		stats = stats,
		last_stat = last_stat,
	} :: sq.Block
end

function transform_functionarg(arg: luau.FunctionArg): sq.Expr
	if arg.kind == "pack" then
		local exprs = {}
		for _, pair in arg.exprs do
			table.insert(exprs, pair.node)
		end
		return (transform_exprarray(exprs))
	elseif arg.kind == "string" then
		return create.expr_array { create.string(trim_string(arg.tok.text)) }
	elseif arg.kind == "table" then
		local table_expr =
			{ kind = "table", table = arg.table } :: luau.Expr_Table
		return create.expr_array { transform_expr(table_expr) }
	end
	error ""
end

function trim_string(str: string)
	return (string.gsub(string.sub(str, 2, #str - 1), '"', '\\"'))
end

function wrap_index(var: sq.Var, index: sq.Expr)
	return create.var(create.var_nameroot(INDEX_FUNC), {
		create.var_callsuffix(nil, {
			create.expr_var(var),
			index,
		}),
	})
end

function unwrap_index(var: sq.Var)
	if var.root.kind == "name" and var.root.name == INDEX_FUNC then
		local call = var.suffixes[1]
		assert(call.kind == "call")
		local expr, index = call.args[1], call.args[2]

		assert(expr.kind == "exprvar")

		table.insert(expr.var.suffixes, create.var_exprsuffix(index))
		var = expr.var
	end
	return var
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

function can_be_tuple(var: sq.Var): boolean
	return possible_tuples[var] ~= nil
end

function unpack_tuple(
	tuple: sq.Identifier,
	vars: { sq.Var },
	local_variable: boolean
): { sq.Stat }
	local stats = {}

	for i, var in vars do
		local assignment

		local value = create.expr_var(
			wrap_index(
				create.var(create.var_nameroot(tuple), {}),
				create.int(i - 1)
			)
		)

		local operator = "="
		if #var.suffixes > 1 or local_variable then
			operator = "<-"
		end

		assignment = create.stat_expr(
			create.expr_assignment(var, operator :: any, value)
		)

		table.insert(stats, assignment)
	end

	return stats
end

function transform_exprarray(
	exprs: { luau.Expr }
): (sq.Expr, number, sq.ExprVar?)
	local transformed = {} :: { sq.Expr }
	local tuple

	for i, lexpr in exprs do
		local expr = transform_expr(lexpr)

		if
			expr.kind == "exprvar"
			and can_be_tuple(expr.var)
			and i == #exprs
		then
			tuple = tuple_var(expr.var)
		else
			table.insert(transformed, expr)
		end
	end

	local array = create.expr_array(transformed)

	if tuple then
		local var = create.expr_var(create.var(create.var_nameroot(JOIN_FUNC), {
			create.var_callsuffix(nil, {
				array,
				tuple,
			}),
		}))

		return var, #transformed, tuple
	end

	return array, #transformed, tuple
end

--TODO __index__(a, b) <-
--obv work ofc
function transform_assignments(
	local_assignment: boolean,
	left: { luau.Var | string },
	right: { luau.Expr }
): { sq.Stat }
	local stats = {} :: { sq.Stat }

	local array, expr_amount, tuple = transform_exprarray(right)

	local vars = {}
	for i = 1, #left do
		local leftv, other_lvar: sq.Var = left[i], nil

		-- local variables are identifiers, not vars
		if typeof(leftv) == "string" then
			other_lvar = scope_var(
				create.var(create.var_nameroot(safe_ident(leftv)), {})
			)
		else
			other_lvar = unwrap_index(transform_var(leftv))
		end
		table.insert(vars, other_lvar)
	end

	local temp_name = unique_id "tuple"
	local assignments = unpack_tuple(temp_name, vars, local_assignment)

	table.insert(stats, (create.stat_localvariable(temp_name, array)))
	for _, v in assignments do
		table.insert(stats, v)
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

		-- to avoid (x) becoming scope.scope.x
		if var.root.kind == "paren" then
			return var
		end

		table.insert(init_suffixes, create.var_exprsuffix(var.root.expr))
	end

	local accumulator =
		create.var(create.var_nameroot(SCOPE_TABLE_ROOT), init_suffixes)

	for _, suffix in var.suffixes do
		if suffix.kind == "nameindex" then
			accumulator = wrap_index(accumulator, create.string(suffix.name))
		elseif suffix.kind == "exprindex" then
			accumulator = wrap_index(accumulator, suffix.expr)
		elseif suffix.kind == "call" then
			table.insert(accumulator.suffixes, suffix)
		end
	end

	return accumulator
end

function transform_var(var: luau.Var): sq.Var
	local root, suffixes = nil, {}
	if var.root.kind == "name" then
		root = create.var_nameroot(safe_ident(var.root.tok.text))
	else
		local expr = transform_expr(var.root.expr)

		-- (x()) needs to become (x()[0]) because it wont be done in assignments
		if expr.kind == "exprvar" then
			local rvar = expr.var

			if
				#rvar.suffixes > 0
				and rvar.suffixes[#rvar.suffixes].kind == "call"
			then
				-- TODO turn into a nameroot ideally cuz the parens here are unecessary
				-- anyway
				-- table.insert(
				-- 	rvar.suffixes,
				-- 	create.var_exprsuffix(create.int(0))
				-- )
			end
		end

		root = create.var_parenroot(expr)
	end

	for _, suffix in var.suffixes do
		if suffix.kind == "nameindex" then
			table.insert(
				suffixes,
				create.var_namesuffix(safe_ident(suffix.name.text))
			)
		elseif suffix.kind == "exprindex" then
			table.insert(
				suffixes,
				create.var_exprsuffix(transform_expr(suffix.expr))
			)
		else
			local method = if suffix.method
				then suffix.method.name.text
				else nil
			local array = transform_functionarg(suffix.arg)

			table.insert(suffixes, create.var_callsuffix(method, { array }))
		end
	end

	local possible_tuple
	if #suffixes > 0 and suffixes[#suffixes].kind == "call" then
		possible_tuple = true
	end

	local sqvar = create.var(root, suffixes)

	local scoped = scope_var(sqvar)

	if possible_tuple then
		scoped = wrap_index(scoped, create.int(0))
		possible_tuples[scoped :: any] = true
	end

	return scoped
end

-- mutates
function tuple_var(var: sq.Var): sq.ExprVar
	local suffixes = var.suffixes
	if possible_tuples[var] then
		local popped = table.remove(suffixes, #suffixes)
		assert(popped and popped.kind == "call")
		assert(popped.args[1] and popped.args[1].kind == "exprvar")
		return popped.args[1] :: any
	end
	error "not a tuple"
end

function transform_functionbody(body: luau.FunctionBody): sq.FunctionBody
	local block = transform_block(body.block)

	local array_name = unique_id "args"
	local vars = {}
	for _, pair in body.params do
		table.insert(
			vars,
			create.var(create.var_nameroot(pair.node.name.text), {})
		)
	end
	local param_assignments = unpack_tuple(array_name, vars, true)

	local new_block = {
		stats = param_assignments,
		last_stat = block.last_stat,
	} :: sq.Block

	for i, stat in block.stats do
		if i == 1 then
			unshift(new_block.stats, { stat })
			continue
		end
		table.insert(new_block.stats, stat)
	end

	return create.functionbody({ array_name }, { SCOPE_TABLE_ROOT }, new_block)
end

function transform_expr(expr: luau.Expr): sq.Expr
	if expr.kind == "nil" then
		return create.null()
	elseif expr.kind == "boolean" then
		local bool = if expr.tok.kind == "true" then true else false
		return create.bool(bool)
	elseif expr.kind == "number" then
		local text = string.gsub(expr.tok.text, "_", "")
		local num = tonumber(text)

		if not num then
			if string.find(string.lower(text), "^0b") then
				local binary = string.sub(text, 3, #text)
				num = tonumber(binary, 2)
			elseif string.find(string.lower(text), "^0x") then
				local hex = string.sub(text, 3, #text)
				num = tonumber(hex, 16)
			end
		end

		assert(num)

		if string.find(tostring(num), "%D") then
			return create.float(num)
		else
			return create.int(num)
		end
	elseif expr.kind == "string" then
		return create.string(trim_string(expr.tok.text))
	elseif expr.kind == "varargs" then
		--error ""
		return create.null()
	elseif expr.kind == "istring" then
		if expr.istring.kind == "simple" then
			return create.string(trim_string(expr.istring.tok.text))
		else
			local exprs = {} :: { sq.Expr }

			for _, pair in expr.istring.middle do
				local node, sep = pair.node, pair.sep
				table.insert(exprs, transform_expr(node))
				if sep then
					table.insert(exprs, create.string(trim_string(sep.text)))
				end
			end

			local accumulator: any =
				create.string(trim_string(expr.istring.first.text))
			for _, expr in exprs do
				accumulator = create.binary(accumulator, "+", expr)
			end
			accumulator = create.binary(
				accumulator,
				"+",
				create.string(trim_string(expr.istring.last.text))
			)

			return accumulator
		end
	elseif expr.kind == "var" then
		return create.expr_var(transform_var(expr.var))
	elseif expr.kind == "assertion" then
		return transform_expr(expr.expr)
	elseif expr.kind == "unary" then
		local op = expr.operator.kind
		if op == "#" then
			return create.expr_var(
				create.var(create.var_parenroot(transform_expr(expr.expr)), {
					create.var_namesuffix "len",
					create.var_callsuffix(nil, {}),
				})
			)
		elseif op == "not" then
			op = "!"
		elseif op == "+" then
			error "???"
		end

		return create.unary(transform_expr(expr.expr), op :: any)
	elseif expr.kind == "binary" then
		local left, right =
			transform_expr(expr.left), transform_expr(expr.right)

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

		return create.binary(left, op :: any, right)
	elseif expr.kind == "table" then
		local fields = {} :: { sq.TableField }
		local tbl = expr.table

		local nokeys = 0
		for _, pair in tbl.fields do
			local field = pair.node
			if field.kind == "namekey" then
				table.insert(
					fields,
					create.table_namekey(
						field.name.text,
						transform_expr(field.value)
					)
				)
			elseif field.kind == "exprkey" then
				table.insert(
					fields,
					create.table_exprkey(
						transform_expr(field.key),
						transform_expr(field.value)
					)
				)
				-- TODO figure out tuples
			else
				nokeys += 1
				table.insert(
					fields,
					create.table_exprkey(
						create.int(nokeys),
						transform_expr(field.value)
					)
				)
			end
		end

		return create.expr_table(fields)
	elseif expr.kind == "ifelse" then
		local accumulator
		for i = #expr.branches, 1, -1 do
			local branch = expr.branches[i].node
			if not accumulator then
				accumulator = create.expr_ternary(
					transform_expr(branch.condition),
					transform_expr(branch.body),
					transform_expr(expr.else_body)
				)
			else
				accumulator = create.expr_ternary(
					transform_expr(branch.condition),
					transform_expr(branch.body),
					accumulator
				)
			end
		end
		return accumulator
	elseif expr.kind == "function" then
		return create.expr_function(transform_functionbody(expr.body))
	end
	error("unknown expr: " .. expr.kind)
end

function transform_stat(stat: luau.Stat): { sq.Stat }
	if stat.kind == "assign" then
		local left, right = {}, {}

		for _, pair in stat.left do
			table.insert(left, pair.node)
		end
		for _, pair in stat.right do
			table.insert(right, pair.node)
		end

		return transform_assignments(false, left, right)
	elseif stat.kind == "compoundassign" then
		local var = transform_var(stat.left)
		local expr = transform_expr(stat.right)
		local op = stat.operator.kind

		var = unwrap_index(var)

		if op == "//=" then
			local floored = floor_div(create.expr_var(var), expr)
			return {
				create.stat_expr(create.expr_assignment(var, "=", floored)),
			}
		elseif op == "^=" then
			local powed = pow(create.expr_var(var), expr)
			return { create.stat_expr(create.expr_assignment(var, "=", powed)) }
		elseif op == "..=" then
			op = "+"
		end

		return { create.stat_expr(create.expr_assignment(var, op :: any, expr)) }
	elseif stat.kind == "call" then
		return {
			create.stat_expr(create.expr_var(transform_var(stat.call))),
		}
	elseif stat.kind == "do" then
		return {
			create.stat_dowhile(
				transform_block(stat.block),
				create.bool(false)
			),
		}
	elseif stat.kind == "while" then
		return {
			create.stat_while(
				transform_expr(stat.condition),
				transform_block(stat.block)
			),
		}
	elseif stat.kind == "repeat" then
		local expr = create.unary(
			create.expr_var(
				create.var(
					create.var_parenroot(transform_expr(stat.condition)),
					{}
				)
			),
			"!"
		)

		return {
			create.stat_dowhile(transform_block(stat.block), expr),
		}
	elseif stat.kind == "if" then
		local branches, else_block = {} :: { sq.IfStatBranch }, nil

		for _, pair in stat.branches do
			local branch = pair.node
			table.insert(branches, {
				condition = transform_expr(branch.condition),
				block = transform_block(branch.block),
			})
		end

		if stat.else_branch then
			else_block = transform_block(stat.else_branch.block)
		end

		return { create.stat_if(branches, else_block) }
	elseif stat.kind == "numericfor" then
		local var_name, start_value =
			stat.binding.name.text, transform_expr(stat.start_expr)
		local cond = transform_expr(stat.end_expr)
		local incr_amount = if stat.step
			then transform_expr(stat.step.expr)
			else create.int(1)

		var_name = safe_ident(var_name)

		local var = scope_var(create.var(create.var_nameroot(var_name), {}))
		local init = create.expr_assignment(var, "<-", start_value)
		local expr_var = create.expr_var(var)

		local cond_comparison = create.expr_var(
			create.var(
				create.var_parenroot(create.binary(expr_var, "-", incr_amount)),
				{}
			)
		)

		local cond_expr = create.binary(cond_comparison, "!=", cond)
		local incr_expr = create.expr_assignment(var, "+=", incr_amount)

		local backup_name = unique_id "backup"
		local backup, backup_var = create.stat_localvariable(
			backup_name,
			create.expr_var(
				create.var(create.var_nameroot(SCOPE_TABLE_ROOT), {})
			)
		)

        --this whole backup stuff could just be replaced with a function similar to iter

		prereq(backup)
		prereq((new_scope()))

		local block = transform_block(stat.block, true)

		return {
			create.stat_for(block, init, cond_expr, incr_expr),
			create.stat_localvariable(
				SCOPE_TABLE_ROOT,
				create.expr_var(backup_var)
			),
		}
	elseif stat.kind == "forin" then
		local left, right = {}, {}

		for _, pair in stat.bindings do
			table.insert(left, pair.node.name.text)
		end
		for _, pair in stat.exprs do
			table.insert(right, pair.node)
		end

		-- iterator func always returns i, ...
		if #left == 1 then
			unshift(left, { unique_id "_" })
		end

		local array = transform_exprarray(right)

		local tuple_name = unique_id "args"
		local block = transform_block(stat.block)

		local vars = {}
		for _, param in left do
			table.insert(vars, create.var(create.var_nameroot(param), {}))
		end
		local assignments = unpack_tuple(tuple_name, vars, true)

		local new_block = {
			stats = assignments,
			last_stat = block.last_stat,
		} :: sq.Block

		for i, stat in block.stats do
			if i == 1 then
				unshift(new_block.stats, { stat })
				continue
			end
			table.insert(new_block.stats, stat)
		end

		local block_fn = create.expr_function(
			create.functionbody({ tuple_name }, { SCOPE_TABLE_ROOT }, new_block)
		)

		local fn_call = create.var(
			create.var_nameroot(ITER_FUNC),
			{ create.var_callsuffix(nil, { array, block_fn }) }
		)

		return { create.stat_expr(create.expr_var(fn_call)) }
	elseif stat.kind == "localvariable" then
		local left, right = {}, {}

		for _, pair in stat.bindings do
			table.insert(left, pair.node.name.text)
		end
		if stat.values then
			for _, pair in stat.values.exprs do
				table.insert(right, pair.node)
			end
		end

		return transform_assignments(true, left, right)
	elseif stat.kind == "function" then
		-- function a.b.c:method()
		-- a.b.c.method <- function(self)

		if #stat.names > 1 then
			-- assignment
			local root, suffixes = nil, {}
			for i, pair in stat.names do
				local node = pair.node
				local name = safe_ident(node.text)
				if not root then
					root = create.var_nameroot(name)
				else
					table.insert(suffixes, create.var_namesuffix(name))
				end
			end

			local params = {}
			for _, pair in stat.body.params do
				table.insert(params, pair.node.name.text)
			end

			local func = create.expr_function(
				create.functionbody(
					params,
					{},
					transform_block(stat.body.block)
				)
			)

			local var = unwrap_index(scope_var(create.var(root, suffixes)))
			return { create.stat_expr(create.expr_assignment(var, "<-", func)) }
		else
			-- statement

			local name = safe_ident(stat.names[1].node.text)
			local method = if stat.method then stat.method.name.text else nil

			--TODO varargs

			return {
				create.stat_function(
					name,
					method, --TODO add self to params
					transform_functionbody(stat.body)
				),
			}
		end
	elseif stat.kind == "localfunction" then
		local params = {}
		for _, pair in stat.body.params do
			table.insert(params, safe_ident(pair.node.name.text))
		end

		local func = create.expr_function(transform_functionbody(stat.body))

		local var = unwrap_index(
			scope_var(
				create.var(create.var_nameroot(safe_ident(stat.name.text)), {})
			)
		)
		return { create.stat_expr(create.expr_assignment(var, "<-", func)) }
	elseif stat.kind == "typefunction" then
		return {}
	elseif stat.kind == "type" then
		return {}
	end
	error("unknown stat: " .. stat.kind)
end

function transform_laststat(stat: luau.LastStat): sq.LastStat
	if stat.kind == "return" then
		local exprs = {}
		for _, pair in stat.exprs do
			table.insert(exprs, pair.node)
		end

		return create.lstat_return((transform_exprarray(exprs)))
	elseif stat.kind == "break" then
		return create.lstat_break()
	else
		return create.lstat_continue()
	end
end

return {
	cst = transform_cst,
	block = transform_block,
	statement = transform_stat,
	expression = transform_expr,
}
