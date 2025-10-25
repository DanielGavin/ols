package server

import "core:fmt"
import "core:log"
import "core:odin/ast"
import "core:strconv"

// Attempts to resolve the type of the builtin proc by following the rules of the odin type checker
// defined in `check_builtin.cpp`.
// We don't need to worry about whether the inputs to the procs are valid which eliminates most edge cases.
// The basic rules are as follows:
//    - For values not known at compile time (eg values return from procs), just return that type.
//        The correct value will either be that type or a compiler error.
//    - If all values are known at compile time, then we essentially compute the relevant value
//        and return that type.
// There is a difference in the returned types between constants and variables. Constants will use an untyped
// value whereas variables will be typed.
check_builtin_proc_return_type :: proc(
	ast_context: ^AstContext,
	symbol: Symbol,
	call: ^ast.Call_Expr,
	is_mutable: bool,
) -> (
	^ast.Expr,
	bool,
) {
	if symbol.pkg == "$builtin" {
		switch symbol.name {
		case "max", "min":
			curr_candidate: ^ast.Basic_Lit
			curr_value := 0.0
			for arg, i in call.args {
				if lit, value, ok := get_basic_lit_value(arg); ok {
					if i != 0 {
						if compare_basic_lit_value(value, curr_value, symbol.name) {
							curr_candidate = lit
							curr_value = value
						}
					} else {
						curr_candidate = lit
						curr_value = value
					}
				} else {
					return get_return_expr(ast_context, arg, is_mutable), true
				}
			}
			if curr_candidate != nil {
				return convert_candidate(curr_candidate, is_mutable), true
			}
		case "abs":
			for arg in call.args {
				if lit, _, ok := get_basic_lit_value(arg); ok {
					return convert_candidate(lit, is_mutable), true
				}
				return get_return_expr(ast_context, arg, is_mutable), true
			}
		case "clamp":
			if len(call.args) == 3 {
				value_lit, value_value, value_ok := get_basic_lit_value(call.args[0])
				if !value_ok {
					return get_return_expr(ast_context, call.args[0], is_mutable), true
				}

				minimum_lit, minimum_value, minimum_ok := get_basic_lit_value(call.args[1])
				if !minimum_ok {
					return get_return_expr(ast_context, call.args[1], is_mutable), true
				}

				maximum_lit, maximum_value, maximum_ok := get_basic_lit_value(call.args[2])
				if !maximum_ok {
					return get_return_expr(ast_context, call.args[2], is_mutable), true
				}

				if value_value < minimum_value {
					return convert_candidate(minimum_lit, is_mutable), true
				}
				if value_value > maximum_value {
					return convert_candidate(maximum_lit, is_mutable), true
				}

				return convert_candidate(value_lit, is_mutable), true
			}
		case "complex":
			candidate: ^ast.Basic_Lit
			for arg in call.args {
				if lit, _, ok := get_basic_lit_value(arg); ok {
					candidate = lit
				} else {
					expr := get_complex_return_expr(ast_context, arg)
					if ident, ok := expr.derived.(^ast.Ident); ok {
						switch ident.name {
						case "f16":
							ident.name = "complex32"
							return ident, true
						case "f32":
							ident.name = "complex64"
							return ident, true
						case "f64":
							ident.name = "complex128"
							return ident, true
						}
					}
				}
			}
			if candidate != nil {
				return convert_complex_candidate(candidate, is_mutable), true
			}
		case "quaternion":
			candidate: ^ast.Basic_Lit
			for arg in call.args {
				if lit, _, ok := get_basic_lit_value(arg); ok {
					candidate = lit
				} else {
					expr := get_quaternion_return_expr(ast_context, arg)
					if ident, ok := expr.derived.(^ast.Ident); ok {
						switch ident.name {
						case "f16":
							ident.name = "quaternion64"
							return ident, true
						case "f32":
							ident.name = "quaternion128"
							return ident, true
						case "f64":
							ident.name = "quaternion256"
							return ident, true
						}
					}
				}
			}
			if candidate != nil {
				return convert_quaternion_candidate(candidate, is_mutable), true
			}
		}
	}

	return nil, false
}

@(private = "file")
get_return_expr :: proc(ast_context: ^AstContext, expr: ^ast.Expr, is_mutable: bool) -> ^ast.Expr {
if v, ok := expr.derived.(^ast.Field_Value); ok {
		return get_return_expr(ast_context, v.value, is_mutable)
	}
	if ident, ok := expr.derived.(^ast.Ident); ok {
		symbol := Symbol{}
		if ok := internal_resolve_type_expression(ast_context, ident, &symbol); ok {
			if v, ok := symbol.value.(SymbolBasicValue); ok {
				return v.ident
			} else if v, ok := symbol.value.(SymbolUntypedValue); ok {
				lit := ast.new(ast.Basic_Lit, expr.pos, expr.end)
				lit.tok = v.tok
				return convert_candidate(lit, is_mutable)
			}
		}
	}
	return expr
}

@(private = "file")
convert_candidate :: proc(candidate: ^ast.Basic_Lit, is_mutable: bool) -> ^ast.Expr {
	if is_mutable {
		ident := ast.new(ast.Ident, candidate.pos, candidate.end)
		if candidate.tok.kind == .Integer {
			ident.name = "int"
		} else {
			ident.name = "f64"
		}
		return ident
	}

	return candidate
}

@(private = "file")
get_complex_return_expr :: proc(ast_context: ^AstContext, expr: ^ast.Expr) -> ^ast.Expr {
	if v, ok := expr.derived.(^ast.Field_Value); ok {
		return get_complex_return_expr(ast_context, v.value)
	}
	if ident, ok := expr.derived.(^ast.Ident); ok {
		symbol := Symbol{}
		if ok := internal_resolve_type_expression(ast_context, ident, &symbol); ok {
			if v, ok := symbol.value.(SymbolBasicValue); ok {
				return v.ident
			} else if v, ok := symbol.value.(SymbolUntypedValue); ok {
				// There isn't a token for `Complex` so we just set it to `f64` instead
				ident := ast.new(ast.Ident, expr.pos, expr.end)
				ident.name = "f64"
				return ident
			}
		}
	}
	return expr
}

@(private = "file")
convert_complex_candidate :: proc(candidate: ^ast.Basic_Lit, is_mutable: bool) -> ^ast.Expr {
	if is_mutable {
		ident := ast.new(ast.Ident, candidate.pos, candidate.end)
		ident.name = "complex128"
		return ident
	}

	return candidate
}

@(private = "file")
get_quaternion_return_expr :: proc(ast_context: ^AstContext, expr: ^ast.Expr) -> ^ast.Expr {
	if v, ok := expr.derived.(^ast.Field_Value); ok {
		return get_quaternion_return_expr(ast_context, v.value)
	}
	if ident, ok := expr.derived.(^ast.Ident); ok {
		symbol := Symbol{}
		if ok := internal_resolve_type_expression(ast_context, ident, &symbol); ok {
			if v, ok := symbol.value.(SymbolBasicValue); ok {
				return v.ident
			} else if v, ok := symbol.value.(SymbolUntypedValue); ok {
				// There isn't a token for `Quaternion` so we just set it to `quaternion256` instead
				ident := ast.new(ast.Ident, expr.pos, expr.end)
				ident.name = "f64"
				return ident
			}
		}
	}
	return expr
}

@(private = "file")
convert_quaternion_candidate :: proc(candidate: ^ast.Basic_Lit, is_mutable: bool) -> ^ast.Expr {
	if is_mutable {
		ident := ast.new(ast.Ident, candidate.pos, candidate.end)
		ident.name = "quaternion256"
		return ident
	}

	return candidate
}

@(private = "file")
get_basic_lit_value :: proc(n: ^ast.Expr) -> (^ast.Basic_Lit, f64, bool) {
	n := n
	if v, ok := n.derived.(^ast.Field_Value); ok {
		return get_basic_lit_value(v.value)
	}

	op := ""
	if u, ok := n.derived.(^ast.Unary_Expr); ok {
		op = u.op.text
		n = u.expr
	}

	if lit, ok := n.derived.(^ast.Basic_Lit); ok {
		text := lit.tok.text
		if op != "" {
			text = fmt.tprintf("%s%s", op, text)
		}
		value, ok := strconv.parse_f64(text)
		if !ok {
			return nil, 0, false
		}

		return lit, value, true
	}

	return nil, 0, false
}

@(private = "file")
compare_basic_lit_value :: proc(a, b: f64, name: string) -> bool {
	if name == "max" {
		return a > b
	} else if name == "min" {
		return a < b
	}
	return a > b
}
