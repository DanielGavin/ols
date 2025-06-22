#+feature dynamic-literals
package server

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:odin/ast"
import "core:strconv"

import "src:common"

When_Expr :: union {
	int, //Integers types
	bool, //Boolean types
	string, //Enum types - those are the hardcoded options from i.e. ODIN_OS
	^ast.Expr,
}

//Because we use configuration with os names that match the files instead of the enum, i.e. my_file_windows.odin, we have to convert back and fourth.
@(private = "file")
convert_os_string: map[string]string = {
	"windows"      = "Windows",
	"darwin"       = "Darwin",
	"linux"        = "Linux",
	"essence"      = "Essence",
	"freebsd"      = "FreeBSD",
	"wasi"         = "WASI",
	"js"           = "JS",
	"freestanding" = "Freestanding",
	"haiku"        = "Haiku",
	"openbsd"      = "OpenBSD",
	"netbsd"       = "NetBSD",
	"freebsd"      = "FreeBSD",
}

resolve_when_ident :: proc(when_expr_map: map[string]When_Expr, ident: string) -> (When_Expr, bool) {
	switch ident {
	case "ODIN_OS":
		if common.config.profile.os != "" {
			os, ok := convert_os_string[common.config.profile.os]
			if ok {
				return os, true
			} else {
				return fmt.tprint(ODIN_OS), true
			}
		} else {
			return fmt.tprint(ODIN_OS), true
		}
	case "ODIN_ARCH":
		if common.config.profile.arch != "" {
			return common.config.profile.arch, true
		} else {
			return fmt.tprint(ODIN_ARCH), true
		}
	}

	if ident in when_expr_map {
		value := when_expr_map[ident]
		return value, true
	}

	if v, ok := strconv.parse_int(ident); ok {
		return v, true
	} else if v, ok := strconv.parse_bool(ident); ok {
		return v, true
	}

	//If nothing is found we return it as false boolean
	return false, true
}

resolve_when_expr :: proc(
	when_expr_map: map[string]When_Expr,
	when_expr: When_Expr,
) -> (
	_when_expr: When_Expr,
	ok: bool,
) {

	switch expr in when_expr {
	case int:
		return expr, true
	case bool:
		return expr, true
	case string:
		return expr, true
	case ^ast.Expr:
		#partial switch odin_expr in expr.derived {
		case ^ast.Ident:
			return resolve_when_ident(when_expr_map, odin_expr.name)
		case ^ast.Basic_Lit:
			return resolve_when_ident(when_expr_map, odin_expr.tok.text)
		case ^ast.Implicit_Selector_Expr:
			return odin_expr.field.name, true
		case ^ast.Unary_Expr:
			if odin_expr.op.kind == .Not {
				expr := resolve_when_expr(when_expr_map, odin_expr.expr) or_return
				b := expr.(bool) or_return
				return !b, true
			}
		case ^ast.Binary_Expr:
			lhs := resolve_when_expr(when_expr_map, odin_expr.left) or_return
			rhs := resolve_when_expr(when_expr_map, odin_expr.right) or_return

			lhs_bool, lhs_is_bool := lhs.(bool)
			rhs_bool, rhs_is_bool := rhs.(bool)

			lhs_int, lhs_is_int := lhs.(int)
			rhs_int, rhs_is_int := rhs.(int)

			lhs_string, lhs_is_string := lhs.(string)
			rhs_string, rhs_is_string := rhs.(string)

			if lhs_is_string && rhs_is_string {
				#partial switch odin_expr.op.kind {
				case .Cmp_Eq:
					return lhs_string == rhs_string, true
				case .Not_Eq:
					return lhs_string != rhs_string, true
				}
			} else if lhs_is_bool && rhs_is_bool {
				#partial switch odin_expr.op.kind {
				case .Cmp_And:
					return lhs_bool && rhs_bool, true
				case .Cmp_Or:
					return lhs_bool || rhs_bool, true
				}
			}

			return {}, false
		}
	}


	return {}, false
}


resolve_when_condition :: proc(condition: ^ast.Expr) -> bool {
	when_expr_map := make(map[string]When_Expr, context.temp_allocator)

	for key, value in common.config.profile.defines {
		when_expr_map[key] = resolve_when_ident(when_expr_map, value) or_continue
	}

	if when_expr, ok := resolve_when_expr(when_expr_map, condition); ok {
		b, is_bool := when_expr.(bool)
		return is_bool && b
	}

	return false
}
