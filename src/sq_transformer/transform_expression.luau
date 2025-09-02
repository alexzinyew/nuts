local luau = require "../../luaup/lossless/cst"
local sq = require "../sq_ast/sq_ast"

local create = require "../sq_ast/create"

function transform_expression(state, expr: luau.Expr): sq.Expr
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
				table.insert(exprs, transform_expression(state, node))
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
	end
	error("unknown expr: " .. expr.kind)
end

return transform_expression
