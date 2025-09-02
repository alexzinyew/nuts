local cst = require "../luaup/lossless/cst"
local parser = require "../luaup/lossless/parse"
local visit = require "../luaup/lossless/visit"

local fs = require "@lute/fs"

local input = 'a, b, c, d = 1, { enum = {}, a = 0,"no key"},false, nil\
b.case = "meow"; b.nameindex = {}\
e, f = `hello`, `first {\'middle\'} {({})} last`\
a = function(a: string, b: number, ...) h = 2\
j = 0\
end\
a = if 0 then 1 elseif 2 then 3 elseif 4 then 5 elseif 6 then 7 else 8\
a, b, c, d = -1, +1, not 0, #e\
a, b, c = true == true, true ~= true, true or true\
a = 5 // 2\
'

--input = fs.read(fs.open("luaup/bench/cases/jecs.luau", ""))

local parsed = parser(input)

local keywords = {
	"base",
	"break",
	"case",
	"catch",
	"class",
	"clone",
	"continue",
	"const",
	"default",
	"delete",
	"else",
	"enum",
	"extends",
	"for",
	"foreach",
	"function",
	"if",
	"in",
	"local",
	"null",
	"resume",
	"return",
	"switch",
	"this",
	"throw",
	"try",
	"typeof",
	"while",
	"yield",
	"constructor",
	"instanceof",
	"true",
	"false",
	"static",
}

local function valid_identifier(input: string)
	if table.find(keywords, input) then
		return false
	end
	return true
end

-- multi returns only return the last variable in squirrel
-- make arrays for this
--
-- a <- ({}) tables ned to be wrapped in new slots
--
-- tables r evil
--
-- FREE VARIABLES ARE FROZEN

local current_block_vars = {}

function unique_var(name: string, iter: number?)
	if table.find(current_block_vars, name) then
		return unique_var(name, (iter or 0) + 1)
	end
	return `_{name}_{iter or 0}`
end

local function safe_nameindex(text: string)
	if not valid_identifier(text) then
		return `["{text}"]`, true
	else
		return `{text}`, false
	end
end

local function double_quote_string(str: string)
	return `"{string.sub(str, 2, #str - 1)}"`
end

local str = ""
local indentation = -1
local function write(...: string)
	if string.sub(str, #str, #str) == "\n" then
		str = str .. string.rep("\t", indentation)
	end
	str = str .. ...
end
local function comment(...: string)
	write(` /* {...} */ `)
end
local function indent()
	indentation += 1
end
local function unindent()
	indentation -= 1
end

function gen_token(token: cst.Token, trivia: boolean?)
	-- trivia is not worth maintaining

	if trivia then
		for _, trivia in token.trivia :: any do
			write(trivia.text)
		end
	end

	if (token :: any).text then
		write((token :: any).text :: any)
	elseif token.kind ~= "eof" then
		write(token.kind)
	end
end

local function gen_expr_truthy(expr: cst.Expr)
	-- dont make a variable for numbers, strings, and nil
	if expr.kind == "number" or expr.kind == "string" or expr.kind == "nil" then
		write(`({expr.tok.text} == 0 || {expr.tok.text})`)
	end
	local var_name = unique_var "value"
	write(`local {var_name} = `)
	gen_expr(expr)
	write "\n"

	-- this wont work, the variable needs to be defined before the comparisons
end

function gen_expr(expr: cst.Expr)
	if expr.kind == "nil" then
		write "null"
	elseif expr.kind == "boolean" then
		gen_token(expr.tok)
	elseif expr.kind == "number" then
		-- handle octs or hex whatever
		gen_token(expr.tok)
	elseif expr.kind == "string" then
		write(double_quote_string(expr.tok.text))
	elseif expr.kind == "varargs" then
		local var = unique_var "result"
		-- penis
		write(`local {var} = ::__vararghelper(varargc, varargv)\n`)
		write(``)
	elseif expr.kind == "istring" then
		if expr.istring.kind == "simple" then
			write(double_quote_string(expr.istring.tok.text))
		else
			write(double_quote_string(expr.istring.first.text) .. " + ")

			for i, pair in expr.istring.middle do
				write "("
				gen_expr(pair.node)
				write ") + "
				if pair.sep then
					write(double_quote_string(pair.sep.text) .. " + ")
				end
			end

			write(double_quote_string(expr.istring.last.text))
		end
	elseif expr.kind == "table" then
		-- wrapped in parens because sq parser errors sometimes with table literal closing
		write "({"

		local nokey_index = 1
		for i, pair in expr.table.fields do
			if pair.node.kind == "namekey" then
				write(safe_nameindex(pair.node.name.text))
				write " = "
				gen_expr(pair.node.value)
			elseif pair.node.kind == "exprkey" then
				write "["
				gen_expr(pair.node.key)
				write "] = "
				gen_expr(pair.node.value)
			elseif pair.node.kind == "nokey" then
				-- these arent allowed in sq, so i set the key to the number lua would have

				write(`[{nokey_index}] = `)
				nokey_index += 1

				gen_expr(pair.node.value)
			end

			if pair.sep then
				gen_token(pair.sep)
				write " "
			end
		end

		write "})"
	elseif expr.kind == "function" then
		for i, attribute in expr.attributes do
			comment(attribute.text)
			write "\n"
		end
		write "function("
		for i, pair in expr.body.params do
			local param, sep = pair.node, pair.sep
			gen_token(param.name)
			if sep then
				gen_token(sep)
				write " "
			end
		end
		if expr.body.varargs then
			write "..."
		end
		write "):("
		-- this is the hard part
		write ") {\n"
		gen_block(expr.body.block)
		write "}"
	elseif expr.kind == "ifelse" then
		for i, pair in expr.branches do
			if i > 1 then
				write "("
			end
			gen_expr(pair.node.condition)
			write " ? "
			gen_expr(pair.node.body)
			write " : "
		end
		gen_expr(expr.else_body)
		write(string.rep(")", #expr.branches - 1))
	elseif expr.kind == "var" then
		gen_var(expr.var)
	elseif expr.kind == "assertion" then
		gen_expr(expr.expr)
	elseif expr.kind == "unary" then
		if expr.operator.kind == "not" then
			write "!"
			gen_expr(expr.expr)
		elseif expr.operator.kind == "#" then
			gen_expr(expr.expr)
			write ".len()"
		else
			gen_token(expr.operator)
			gen_expr(expr.expr)
		end
	elseif expr.kind == "binary" then
		local op = expr.operator.kind
		if op == "//" then
			write "floor("
			gen_expr(expr.left)
			write " / "
			gen_expr(expr.right)
			write ")"
			return
		end

		gen_expr(expr.left)
		write " "
		if op == "~=" then
			write "!="
		elseif op == "and" then
			write "&&"
		elseif op == "or" then
			write "||"
		else
			write(expr.operator.kind)
		end

		write " "
		gen_expr(expr.right)
	end
end

function gen_var(var: cst.Var)
	if var.root.kind == "name" then
		if not valid_identifier(var.root.tok.text) then
			error(`Invalid Identifier: {var.root.tok.text}`)
		end
		gen_token(var.root.tok)
	else
		gen_expr(var.root.expr)
	end

	for i, suffix in var.suffixes do
		if suffix.kind == "exprindex" then
			write(`[{suffix.name.text}]`)
		elseif suffix.kind == "nameindex" then
			local index, changed = safe_nameindex(suffix.name.text)
			if not changed then
				write "."
			end
			write(index)
		elseif suffix.kind == "call" then
			error "unimpl"
		end
	end
end

function gen_stat(stat: cst.Stat)
	if stat.kind == "assign" then
		for i, pair in stat.left do
			gen_var(pair.node)
			write " <- "
			gen_expr(stat.right[i].node)
			if i ~= #stat.left then
				write "; "
			end
		end
	elseif stat.kind == "compoundassign" then
		if stat.operator.kind == "//=" then
			error "Cant use floor division compound assignment!"
		else
			gen_var(stat.left)
			write(` {stat.operator.text} `)
			gen_expr(stat.right)
		end
	end
end

function gen_block(block: cst.Block)
	indent()
	for _, pair in block.stats do
		local node, sep = pair.node, pair.sep

		gen_stat(node)

		if sep then
			gen_token(sep)
			write " "
		else
			write "\n"
		end
	end

	local last_stat = block.last_stat
	if last_stat then
		--visit_last_stat(last_stat.stat)

		local semicolon = last_stat.semicolon
		if semicolon then
			gen_token(semicolon)
		end
	end
	unindent()
end

gen_block(parsed.cst.block)
write "\n"
gen_expr {
	kind = "varargs",
	tok = { kind = "..." } :: any,
}
print(input)
print()
print(str)
