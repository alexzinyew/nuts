export type Stat =
	StatIf
	| StatWhile
	| StatDoWhile
	| StatSwitch
	| StatFor
	| StatForEach
	| StatYield
	| StatLocalAssignment
	| StatFunction
	| StatClass
	| StatTryCatch
	| StatThrow
	| StatConst
	| StatEnum
	| StatExpr

export type LastStat = LastStatReturn | LastStatBreak | LastStatContinue

export type Expr =
	ExprGlobal
	| ExprAssignment
	| ExprTernary
	| ExprBinary
	| ExprUnary
	| ExprIncDec
	| ExprIn
	| ExprInstanceOf
	| ExprTypeof
	| ExprComma
	| ExprTable
	| ExprFunction
	| ExprDelegate
	| ExprClone
	| ExprArray
	| ExprDelete
	| ExprVar
	| ExprFloat
	| ExprInteger
	| ExprString
	| ExprNull
	| ExprBool

export type Identifier = string

export type Var = {
	kind: "var",
	root: VarRoot,
	suffixes: { VarSuffix },
}

export type VarRoot = {
	kind: "name",
	name: Identifier,
} | {
	kind: "paren",
	expr: Expr,
}

export type VarSuffix = {
	kind: "nameindex",
	name: Identifier,
} | {
	kind: "exprindex",
	expr: Expr,
} | {
	kind: "call",
	method: Identifier?,
	args: { Expr },
}

export type ExprFloat = { kind: "float", float: number }
export type ExprInteger = { kind: "int", int: number }
export type ExprString = { kind: "string", string: string }
export type ExprBool = { kind: "bool", bool: boolean }
export type ExprNull = { kind: "null" }

export type BitwiseOperator = "<<" | ">>" | ">>>" | "&" | "^" | "|"
export type BinaryOperator =
	BitwiseOperator
	| "+"
	| "-"
	| "*"
	| "/"
	| "%"
	| "=="
	| "!="
	| "<="
	| ">="
	| "||"
	| "&&"

export type UnaryOperator = "-" | "!" | "~" | "++" | "--"

export type CompoundOperator = "+=" | "-=" | "*=" | "/=" | "%="
export type AssignmentOperator = "<-" | "=" | CompoundOperator

export type IfStatBranch = {
	condition: Expr,
	block: Block,
}

export type StatIf = {
	kind: "if",
	branches: { IfStatBranch },
	else_block: Block?,
}

export type StatWhile = {
	kind: "while",
	condition: Expr,
	block: Block,
}

export type StatDoWhile = {
	kind: "dowhile",
	block: Block,
	condition: Expr,
}

export type StatSwitch = {
	kind: "switch",
	value: Expr,
	cases: {
		case_expr: Expr,
		block: Block,
	},
	default: Block?,
}

export type StatFor = {
	kind: "for",
	init: Expr | StatLocalAssignment?,
	cond_expr: Expr?,
	incr_expr: Expr?,
	block: Block,
}

export type StatForEach = {
	kind: "foreach",
	index_ident: Identifier?,
	value_ident: Identifier,
	expr: Expr,
	block: Block,
}

export type StatYield = {
	kind: "yield",
	expr: Expr,
}

export type StatLocalAssignment = {
	kind: "localassignment",
	ident: Identifier,
	expr: Expr,
}

export type StatFunction = {
	kind: "function",

	-- this doesnt behave like a var with suffixes
	root: Identifier,
	method: Identifier?,

	parameters: { Identifier },
	free_variables: { Identifier }?,
	block: Block,
}

export type StatClass = {
	kind: "class",
	name: Identifier,
	extends: Identifier?,
	fields: {
		{
			kind: "namekey",
			key: Identifier,
			expr: Expr,
		} | {
			kind: "exprkey",
			key: Expr,
			expr: Expr,
		} | {
			kind: "function",
			func: StatFunction,
		} | {
			kind: "constructor",
			func: ExprFunction,
		}
	},
}

export type StatTryCatch = {
	kind: "trycatch",
	try: Block,
	catch_ident: Identifier,
	catch_block: Block,
}

export type StatThrow = {
	kind: "throw",
	expr: Expr,
}

export type StatConst = {
	kind: "const",
	name: Identifier,
	value: ExprInteger | ExprFloat | ExprString,
}

export type StatEnum = {
	kind: "enum",
	name: Identifier,
	enumerations: {
		{
			name: Identifier,
			value: (ExprInteger | ExprFloat | ExprString)?,
		}
	},
}

export type StatExpr = {
	kind: "statexpr",
	expr: Expr,
}

export type LastStatReturn = {
	kind: "return",
	expr: Expr?,
}

export type LastStatBreak = {
	kind: "break",
}

export type LastStatContinue = {
	kind: "continue",
}

-- expressions
export type ExprGlobal = {
	kind: "exprglobal",
	member: Identifier,
}

export type ExprAssignment = {
	kind: "exprassignment",
	var: Var,
	operator: AssignmentOperator,
	value: Expr,
}

export type ExprTernary = {
	kind: "exprternary",
	condition: Expr,
	then_expr: Expr,
	else_expr: Expr,
}

export type ExprBinary = {
	kind: "exprbinary",
	left: Expr,
	operator: BinaryOperator,
	right: Expr,
}

export type ExprUnary = {
	kind: "exprunary",
	operator: UnaryOperator,
	expr: Expr,
}

export type ExprIncDec = {
	kind: "exprincdec",
	var: Var,
	operation: "increment" | "decrement",
}

export type ExprIn = {
	kind: "exprin",
	key: Expr,
	table: Expr,
}

export type ExprInstanceOf = {
	kind: "exprinstanceof",
	instance: Expr,
	class: Identifier,
}

export type ExprTypeof = {
	kind: "exprtypeof",
	exp: Expr,
}

export type ExprComma = {
	kind: "exprcomma",
	left: Expr,
	right: Expr,
}

export type TableNameKey = {
	kind: "namekey",
	key: Identifier,
	expr: Expr,
}

export type TableExprKey = {
	kind: "exprkey",
	key: Expr,
	expr: Expr,
}

export type TableField = TableNameKey | TableExprKey

export type ExprTable = {
	kind: "exprtable",
	fields: { TableField },
}

export type ExprFunction = {
	kind: "exprfunction",
	parameters: { Identifier },
	free_variables: { Identifier }?,
	block: Block,
}

export type ExprDelegate = {
	kind: "exprdelegate",
	parent: Expr,
	child: Expr,
}

export type ExprClone = {
	kind: "exprclone",
	expr: Expr,
}

export type ExprArray = {
	kind: "exprarray",
	values: { Expr },
}

export type ExprDelete = {
	kind: "exprdelete",
	var: Var,
}

export type ExprVar = {
	kind: "exprvar",
	var: Var,
}

-- normally, blocks are statements but i dont care so most stats are blocks
export type Block = {
	stats: { Stat },
	last_stat: LastStat?,
}

return nil
