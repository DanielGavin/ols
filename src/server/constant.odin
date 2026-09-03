package server

import "core:odin/ast"
import "core:odin/tokenizer"
import "core:strconv"

@(private = "file")
Integer_Constant_Resolver :: struct {
	ast_context:  ^AstContext,
	local_values: map[string]int,
	visiting:     map[rawptr]struct{},
}

resolve_integer_constant :: proc(
	ast_context: ^AstContext,
	expr: ^ast.Expr,
	local_values: map[string]int = nil,
) -> (
	int,
	bool,
) {
	resolver := Integer_Constant_Resolver {
		ast_context  = ast_context,
		local_values = local_values,
		visiting     = make(map[rawptr]struct{}, context.temp_allocator),
	}

	return resolve_integer_constant_internal(&resolver, expr, 0)
}

@(private = "file")
resolve_rune_constant :: proc(tok: tokenizer.Token) -> (int, bool) {
	text := tok.text
	if len(text) < 2 || text[0] != '\'' || text[len(text) - 1] != '\'' {
		return 0, false
	}

	r, _, tail, ok := strconv.unquote_char(text[1:len(text) - 1], '\'')
	return int(r), ok && len(tail) == 0
}

@(private = "file")
get_indexed_constant_expression :: proc(symbol: Symbol) -> (^ast.Expr, bool) {
	if .Mutable in symbol.flags {
		return nil, false
	}

	if symbol.value_expr != nil {
		return symbol.value_expr, true
	}

	if value, ok := symbol.value.(SymbolGenericValue); ok && value.expr != nil {
		return value.expr, true
	}

	return nil, false
}

@(private = "file")
resolve_identifier_constant_expression :: proc(
	resolver: ^Integer_Constant_Resolver,
	ident: ^ast.Ident,
) -> (
	^ast.Expr,
	bool,
) {
	ast_context := resolver.ast_context
	package_name := get_package_from_node(ident.node)

	if package_name == "" || package_name == ast_context.document_package {
		if local, ok := get_local(ast_context^, ident^); ok && .Mutable not_in local.flags {
			if local.value_expr != nil {
				return local.value_expr, true
			}
			if local.rhs != nil {
				return local.rhs, true
			}
		}

		if global, ok := ast_context.globals[ident.name]; ok && .Mutable not_in global.flags {
			if global.value_expr != nil {
				return global.value_expr, true
			}

			if global.expr != nil {
				return global.expr, true
			}
		}
	}

	if package_name == "" {
		package_name = ast_context.current_package
	}

	if symbol, ok := lookup(ident.name, package_name, ident.pos.file); ok {
		return get_indexed_constant_expression(symbol)
	}

	return nil, false
}

@(private = "file")
resolve_selector_constant_expression :: proc(
	resolver: ^Integer_Constant_Resolver,
	selector: ^ast.Selector_Expr,
) -> (
	^ast.Expr,
	bool,
) {
	package_symbol, ok := resolve_type_expression(resolver.ast_context, selector.expr)
	if !ok {
		return nil, false
	}

	_, is_package := package_symbol.value.(SymbolPackageValue)
	if !is_package || selector.field == nil {
		return nil, false
	}

	symbol, found := lookup(selector.field.name, package_symbol.pkg, selector.pos.file)
	if !found {
		return nil, false
	}

	return get_indexed_constant_expression(symbol)
}

@(private = "file")
resolve_integer_constant_internal :: proc(
	resolver: ^Integer_Constant_Resolver,
	expr: ^ast.Expr,
	depth: int,
) -> (
	result: int,
	ok: bool,
) {
	if expr == nil || depth > 64 {
		return 0, false
	}

	raw := cast(rawptr)expr
	if raw in resolver.visiting {
		return 0, false
	}

	resolver.visiting[raw] = {}
	defer delete_key(&resolver.visiting, raw)

	#partial switch value in expr.derived {
	case ^ast.Paren_Expr:
		return resolve_integer_constant_internal(resolver, value.expr, depth + 1)
	case ^ast.Basic_Lit:
		if value.tok.kind == .Rune {
			return resolve_rune_constant(value.tok)
		}

		return strconv.parse_int(value.tok.text)
	case ^ast.Ident:
		if local_value, found := resolver.local_values[value.name]; found {
			return local_value, true
		}

		constant_expr := resolve_identifier_constant_expression(resolver, value) or_return
		return resolve_integer_constant_internal(resolver, constant_expr, depth + 1)
	case ^ast.Implicit_Selector_Expr:
		if local_value, found := resolver.local_values[value.field.name]; found {
			return local_value, true
		}

		return 0, false
	case ^ast.Selector_Expr:
		constant_expr := resolve_selector_constant_expression(resolver, value) or_return
		return resolve_integer_constant_internal(resolver, constant_expr, depth + 1)
	case ^ast.Unary_Expr:
		operand := resolve_integer_constant_internal(resolver, value.expr, depth + 1) or_return

		#partial switch value.op.kind {
		case .Add:
			return operand, true
		case .Sub:
			if operand == min(int) {
				return 0, false
			}

			return -operand, true
		case .Xor:
			return ~operand, true
		}

		return 0, false
	case ^ast.Binary_Expr:
		left := resolve_integer_constant_internal(resolver, value.left, depth + 1) or_return
		right := resolve_integer_constant_internal(resolver, value.right, depth + 1) or_return

		wide: i128
		#partial switch value.op.kind {
		case .Add:
			wide = i128(left) + i128(right)
		case .Sub:
			wide = i128(left) - i128(right)
		case .Mul:
			wide = i128(left) * i128(right)
		case .Quo:
			if right == 0 || left == min(int) && right == -1 {
				return 0, false
			}

			return left / right, true
		case .Mod:
			if right == 0 || left == min(int) && right == -1 {
				return 0, false
			}

			return left % right, true
		case .And:
			return left & right, true
		case .Or:
			return left | right, true
		case .Xor:
			return left ~ right, true
		case .And_Not:
			return left &~ right, true
		case .Shl:
			if right < 0 || right >= size_of(int) * 8 {
				return 0, left == 0
			}

			wide = i128(left) << uint(right)
		case .Shr:
			if right < 0 || right >= size_of(int) * 8 {
				return 0, false
			}

			return left >> uint(right), true
		case:
			return 0, false
		}

		if wide < i128(min(int)) || wide > i128(max(int)) {
			return 0, false
		}

		return int(wide), true
	}

	return 0, false
}
