local luau = require "../../luaup/lossless/cst"
local sq = require "../sq_ast/sq_ast"

local create = {}

function create.null(): sq.ExprNull
	return { kind = "null" }
end

function create.int(int: number): sq.ExprInteger
	return { kind = "int", int = int }
end

function create.float(float: number): sq.ExprFloat
	return { kind = "float", float = float }
end

function create.bool(bool: boolean): sq.ExprBool
	return { kind = "bool", bool = bool }
end

function create.string(string: string): sq.ExprString
	return { kind = "string", string = string }
end

function create.binary(
	left: sq.Expr,
	op: sq.BinaryOperator,
	right: sq.Expr
): sq.ExprBinary
	return {
		kind = "exprbinary",
		left = left,
		operator = op,
		right = right,
	}
end

function create.unary(expr: sq.Expr, op: sq.UnaryOperator): sq.ExprUnary
	return {
		kind = "exprunary",
		operator = op,
		expr = expr,
	}
end

function create.stat_expr(expr: sq.Expr): sq.StatExpr
	return {
		kind = "statexpr",
		expr = expr,
	}
end

function create.expr_assignment(
	left: sq.Var,
	op: sq.AssignmentOperator,
	right: sq.Expr
): sq.ExprAssignment
	return {
		kind = "exprassignment",
		var = left,
		operator = op,
		value = right,
	}
end

function create.var_nameroot(name: sq.Identifier): sq.VarRoot
	return { kind = "name", name = name }
end

function create.var_parenroot(expr: sq.Expr): sq.VarRoot
	return { kind = "paren", expr = expr }
end

function create.var_namesuffix(name: sq.Identifier): sq.VarSuffix
	return { kind = "nameindex", name = name }
end

function create.var_exprsuffix(expr: sq.Expr): sq.VarSuffix
	return { kind = "exprindex", expr = expr }
end

function create.var_callsuffix(
	method: sq.Identifier?,
	args: { sq.Expr }
): sq.VarSuffix
	return { kind = "call", method = method, args = args }
end

function create.var(root: sq.VarRoot, suffixes: { sq.VarSuffix }): sq.Var
	return {
		kind = "var",
		root = root,
		suffixes = suffixes,
	}
end

function create.expr_var(var: sq.Var): sq.ExprVar
	return {
		kind = "exprvar",
		var = var,
	}
end

function create.stat_while(condition: sq.Expr, block: sq.Block): sq.StatWhile
	return {
		kind = "while",
		condition = condition,
		block = block,
	}
end

function create.stat_dowhile(block: sq.Block, condition: sq.Expr): sq.StatDoWhile
	return {
		kind = "dowhile",
		block = block,
		condition = condition,
	}
end

function create.stat_if(
	branches: { sq.IfStatBranch },
	else_block: sq.Block?
): sq.StatIf
	return {
		kind = "if",
		branches = branches,
		else_block = else_block,
	}
end

function create.stat_for(
	block: sq.Block,
	init: sq.Expr?,
	cond: sq.Expr?,
	incr: sq.Expr?
): sq.StatFor
	return {
		kind = "for",
		init = init,
		cond_expr = cond,
		incr_expr = incr,
		block = block,
	}
end

function create.stat_localvariable(
	ident: sq.Identifier,
	value: sq.Expr
): (sq.StatLocalAssignment, sq.Var)
	return {
		kind = "localassignment",
		ident = ident,
		expr = value,
	}, {
		kind = "var",
		root = { kind = "name", name = ident },
		suffixes = {},
	}
end

function create.stat_foreach(
	i_id: sq.Identifier,
	v_id: sq.Identifier,
	expr: sq.Expr,
	block: sq.Block
): sq.StatForEach
	return {
		kind = "foreach",
		index_ident = i_id,
		value_ident = v_id,
		expr = expr,
		block = block,
	}
end

function create.stat_function(
	name: sq.Identifier,
	method: sq.Identifier?,
	params: { sq.Identifier },
	free_vars: { sq.Identifier }?,
	block: sq.Block
): sq.StatFunction
	return {
		kind = "function",
		root = name,
		method = method,
		parameters = params,
		free_variables = free_vars,
		block = block,
	}
end

function create.expr_function(
    params: { sq.Identifier },
    free_vars: { sq.Identifier }?,
    block: sq.Block
): sq.ExprFunction
	return {
		kind = "exprfunction",
		parameters = params,
		free_variables = free_vars,
		block = block,
	}
end

function create.expr_table(fields: { sq.TableField }): sq.ExprTable
	return {
		kind = "exprtable",
		fields = fields,
	}
end

function create.table_namekey(
	key: sq.Identifier,
	expr: sq.Expr
): sq.TableNameKey
	return { kind = "namekey", key = key, expr = expr }
end

function create.table_exprkey(key: sq.Expr, expr: sq.Expr): sq.TableExprKey
	return { kind = "exprkey", key = key, expr = expr }
end

function create.expr_array(values: { sq.Expr }): sq.ExprArray
	return { kind = "exprarray", values = values }
end

function create.expr_ternary(
	cond: sq.Expr,
	then_expr: sq.Expr,
	else_expr: sq.Expr
): sq.ExprTernary
	return {
		kind = "exprternary",
		condition = cond,
		then_expr = then_expr,
		else_expr = else_expr,
	}
end

function create.lstat_return(expr: sq.Expr): sq.LastStatReturn
    return {
        kind = "return",
        expr = expr
    }
end

function create.lstat_break(): sq.LastStatBreak
    return { kind = "break" }
end

function create.lstat_continue(): sq.LastStatContinue
    return { kind = "continue" }
end

return create
