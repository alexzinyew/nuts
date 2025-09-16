local sq = require "../sq_ast/sq_ast"

local indentation = -1

local function line(str: string)
	return string.rep("\t", indentation) .. str .. "\n"
end

local function write(str: string)
	return string.rep("\t", indentation) .. str
end

local function render_helpers()
	-- rewrite these in luau
	return '\
::__index__ <- function(table, key) {\
    if (!(key in table) || table == null)\
        return null\
    return table[key]\
}\
\
::__set__ <- function(table, key, value) {\
    return table[key] <- value\
}\
\
::__new_scope__ <- function(above) {\
    return delegate {\
        function _get(idx):(above) {\
            if (idx in above)\
                return above[idx]\
            if (idx in ::getroottable())\
                return ::getroottable()[idx]\
\
            return null\
        }\
        function _set(idx, val):(above) {\
            if (idx in above)\
                return above[idx] = val\
\
            return ::getroottable()[idx] <- val\
        }\
    } : {}\
}\
::__join__ <- function(left, right) {\
    local arr = []\
    foreach(v in left) {\
        arr.push(v)\
    };\
    foreach(v in right) {\
        arr.push(v)\
    };\
    return arr\
}\
::cprintl <- function(args) {\
    printl(args[0])\
}\
\
::next <- function() { throw "cannot use next outside of a for loop" }\
::pairs <- function(args) { return [::next, args[0]] }\
::ipairs <- function(args) {\
    if (!(0 in args)) throw "missing argument #1 to ipairs" \
    return [function(fargs) {\
        local a = fargs[0]\
        local i = null\
        if (1 in fargs) i = fargs[1]\
        if (i == null) \
            i = 0\
        else\
            i++\
    \
        if (i in a) {\
            return [i, a[i]]\
        }\
    }, args[0]]\
    \
}\
::__iter__ <- function(args, func) {\
    local first = args[0]\
    if (typeof first == "function") {\
        local idx = null\
        local state = null\
        if (1 in args) {\
            state = args[1]\
        } else {\
            throw "iterator function expected table"\
        }\
        if (first == ::next) {\
            if (2 in args) {\
                throw "cannot use second argument of next"\
            }\
            foreach(i, v in state) {\
                func([i, v])\
            }\
        } else {\
            if (2 in args) {\
                idx = args[2] - 1\
            }\
            while (true) {\
                local ret = first([state, idx])\
                if (ret == null || !(0 in ret) || ret[0] == null) {\
                    break\
                }\
                idx = ret[0]\
                func(ret)\
            }\
        }\
    } else {\
        foreach(i, v in first) {\
            func([i, v])\
        }\
    }\
}\
\
\n'
end

local function render_block(block: sq.Block)
	local str = ""
	indentation += 1
	for _, stat in block.stats do
		str ..= render_stat(stat)
	end
	if block.last_stat then
		str ..= render_laststat(block.last_stat)
	end
	indentation -= 1
	return str
end

function render_var(var: sq.Var)
	local str = ""

	if var.root.kind == "name" then
		str = var.root.name
	else
		str = `({render_expr(var.root.expr)})`
	end

	for _, suffix in var.suffixes do
		if suffix.kind == "nameindex" then
			str ..= `.{suffix.name}`
		elseif suffix.kind == "exprindex" then
			str ..= `[{render_expr(suffix.expr)}]`
		else
			if suffix.method then
				str ..= `:{suffix.method}`
			end

			local args = {}
			for _, arg in suffix.args do
				table.insert(args, render_expr(arg))
			end
			str ..= `({table.concat(args, ", ")})`
		end
	end

	return str
end

function render_functionbody(body: sq.FunctionBody)
	local str = ""

	str ..= `({table.concat(body.parameters, ", ")}):({table.concat(
		body.free_variables or {},
		", "
	)}) \{\n`
	str ..= render_block(body.block)
	str ..= write "}"

	return str
end

function render_expr(expr: sq.Expr)
	local str = ""

	if expr.kind == "exprglobal" then
		str ..= `::{expr.member}`
	elseif expr.kind == "exprassignment" then
		str ..= `{render_var(expr.var)} {expr.operator} {render_expr(expr.value)}`
	elseif expr.kind == "exprternary" then
        --stylua: ignore start
		str ..= `{render_expr(expr.condition)} \
            ? {render_expr(expr.then_expr)} : {render_expr(expr.else_expr)}`
		--stylua: ignore end
	elseif expr.kind == "exprbinary" then
		str ..= `{render_expr(expr.left)} {expr.operator} {render_expr(
			expr.right
		)}`
	elseif expr.kind == "exprunary" then
		str ..= `{expr.operator}{render_expr(expr.expr)}`
	elseif expr.kind == "exprincdec" then
		str ..= render_var(expr.var)
		if expr.operation == "increment" then
			str ..= "++"
		else
			str ..= "--"
		end
	elseif expr.kind == "exprin" then
		str ..= `{render_expr(expr.key)} in {render_expr(expr.table)}`
	elseif expr.kind == "exprinstanceof" then
		str ..= `{render_expr(expr.instance)} instanceof {expr.class}`
	elseif expr.kind == "exprtypeof" then
		str ..= `typeof {render_expr(expr.exp)}`
	elseif expr.kind == "exprcomma" then
		str ..= `{render_expr(expr.left)}, {render_expr(expr.right)}`
	elseif expr.kind == "exprtable" then
		if #expr.fields == 0 then
			str ..= "{}"
		else
			str ..= "{\n"
			indentation += 1

			local fields = {}
			for _, field in expr.fields do
				if field.kind == "namekey" then
					table.insert(
						fields,
						`{field.key} = {render_expr(field.expr)}`
					)
				else
					table.insert(
						fields,
						`[{render_expr(field.key)}] = {render_expr(field.expr)}`
					)
				end
			end
			str ..= table.concat(fields, ", ")
			str ..= write "}"
			indentation -= 1
		end
	elseif expr.kind == "exprfunction" then
		return "function " .. render_functionbody(expr.body)
	elseif expr.kind == "exprdelegate" then
		str ..= `delegate {render_expr(expr.parent)} : {render_expr(expr.child)}`
	elseif expr.kind == "exprclone" then
		str ..= `clone {render_expr(expr.expr)}`
	elseif expr.kind == "exprarray" then
		local exprs = {}
		for _, expr in expr.values do
			table.insert(exprs, render_expr(expr))
		end
		str ..= `[{table.concat(exprs, ", ")}]`
	elseif expr.kind == "exprdelete" then
		str ..= `delete {render_var(expr.var)}`
	elseif expr.kind == "exprvar" then
		str ..= render_var(expr.var)
	elseif expr.kind == "float" then
		str ..= expr.float
	elseif expr.kind == "int" then
		str ..= expr.int
	elseif expr.kind == "string" then
		str ..= `"{expr.string}"`
	elseif expr.kind == "null" then
		str ..= "null"
	elseif expr.kind == "bool" then
		str ..= tostring(expr.bool)
	end

	return str
end

function render_stat(stat: sq.Stat)
	local str = ""

	if stat.kind == "statexpr" then
		str ..= line(render_expr(stat.expr))
	elseif stat.kind == "if" then
		for i, branch in stat.branches do
			if i == 1 then
				str ..= line(`if ({render_expr(branch.condition)}) \{`)
			else
				str ..= line(`} else if ({render_expr(branch.condition)}) \{`)
			end

			str ..= render_block(branch.block)
		end

		if stat.else_block then
			str ..= line(`} else \{`)
			str ..= render_block(stat.else_block)
		end

		str ..= line "}"
	elseif stat.kind == "while" then
		str ..= line(`while ({render_expr(stat.condition)}) \{`)
		str ..= render_block(stat.block)
		str ..= line "}"
	elseif stat.kind == "dowhile" then
		str ..= line "do {"
		str ..= render_block(stat.block)
		str ..= line(`} while ({render_expr(stat.condition)})`)
	elseif stat.kind == "switch" then
		--TODO
	elseif stat.kind == "for" then
		local init, cond, incr

		if stat.init then
			if stat.init.kind == "localassignment" then
				init = `local {stat.init.ident} = {render_expr(stat.init.expr)}`
			else
				init = render_expr(stat.init)
			end
		end
		if stat.cond_expr then
			cond = render_expr(stat.cond_expr)
		end
		if stat.incr_expr then
			incr = render_expr(stat.incr_expr)
		end

		str ..= line(`for ({init}; {cond}; {incr}) \{`)
		str ..= render_block(stat.block)
		str ..= line "}"
	elseif stat.kind == "foreach" then
		str ..= line(
			`foreach ({stat.index_ident or "_"}, {stat.value_ident} in {render_expr(
				stat.expr
			)}) \{`
		)
		str ..= render_block(stat.block)
		str ..= line "}"
	elseif stat.kind == "yield" then
		--TODO
	elseif stat.kind == "localassignment" then
		str ..= line(`local {stat.ident} = {render_expr(stat.expr)}`)
	elseif stat.kind == "function" then
		local method = if stat.method then `:{stat.method}` else ""
		str ..= line(
			`function {stat.root}{method}{render_functionbody(stat.body)}`
		)
		return str
	elseif stat.kind == "class" then
		--TODO
	elseif stat.kind == "trycatch" then
		--TODO
	elseif stat.kind == "throw" then
		--TODO
	elseif stat.kind == "const" then
		local value: string | number
		if stat.value.kind == "float" then
			value = stat.value.float
		elseif stat.value.kind == "int" then
			value = stat.value.int
		else
			value = stat.value.string
		end

		str ..= line(`const {stat.name} = {value}`)
	elseif stat.kind == "enum" then
		--TODO
	end

	return str
end

function render_laststat(laststat: sq.LastStat)
	if laststat.kind == "return" then
		local expr = if laststat.expr then render_expr(laststat.expr) else nil
		return `return {expr}`
	elseif laststat.kind == "continue" then
		return "continue"
	else
		return "break"
	end
end

return {
	stat = render_stat,
	block = render_block,
	expr = render_expr,
	helpers = render_helpers,
}
