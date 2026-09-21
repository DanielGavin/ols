package server

import "core:fmt"
import "core:odin/ast"
import "core:strings"


is_objc_block_call :: proc(ast_context: ^AstContext, call: ^ast.Call_Expr) -> bool {
	if call == nil || call.expr == nil {
		return false
	}
	// Identify the intrinsic without inferring generic arguments from an unfinished call.
	old_call := ast_context.call
	ast_context.call = nil
	defer ast_context.call = old_call
	symbol, ok := resolve_type_expression(ast_context, call.expr)
	// A user procedure named objc_block must not receive the intrinsic's special handling.
	return ok && symbol.name == "objc_block" && is_objc_intrinsics_package(symbol.pkg)
}

get_objc_block_handler :: proc(ast_context: ^AstContext, call: ^ast.Call_Expr) -> (SymbolProcedureValue, bool) {
	if !is_objc_block_call(ast_context, call) || len(call.args) == 0 {
		return {}, false
	}
	if _, bad := call.args[len(call.args) - 1].derived.(^ast.Bad_Expr); bad {
		return {}, false
	}
	handler_symbol, handler_symbol_ok := resolve_type_expression(ast_context, call.args[len(call.args) - 1])
	if !handler_symbol_ok {
		return {}, false
	}
	handler, handler_ok := handler_symbol.value.(SymbolProcedureValue)
	return handler, handler_ok
}

get_objc_block_proc_type_from_expr :: proc(expr: ^ast.Expr) -> (^ast.Proc_Type, bool) {
	expr, _, ok := unwrap_pointer_expr(expr)
	if !ok {
		return nil, false
	}
	call, call_ok := expr.derived.(^ast.Call_Expr)
	if !call_ok || len(call.args) == 0 {
		return nil, false
	}
	name := ""
	if ident, ok := call.expr.derived.(^ast.Ident); ok {
		name = ident.name
	} else if selector, ok := call.expr.derived.(^ast.Selector_Expr); ok && selector.field != nil {
		name = selector.field.name
	}
	if name != "Objc_Block" {
		return nil, false
	}
	proc_type, proc_type_ok := call.args[0].derived.(^ast.Proc_Type)
	return proc_type, proc_type_ok
}

get_objc_block_proc_type_from_symbol :: proc(symbol: Symbol) -> (^ast.Proc_Type, bool) {
	if symbol.name != "Objc_Block" {
		return nil, false
	}
	value, value_ok := symbol.value.(SymbolStructValue)
	if !value_ok || len(value.args) == 0 {
		return nil, false
	}
	proc_type, proc_type_ok := value.args[0].derived.(^ast.Proc_Type)
	return proc_type, proc_type_ok
}

resolve_objc_block_proc_type :: proc(
	ast_context: ^AstContext,
	expr: ^ast.Expr,
) -> (
	^ast.Proc_Type,
	bool,
) {
	if proc_type, ok := get_objc_block_proc_type_from_expr(expr); ok {
		return proc_type, true
	}
	symbol, ok := resolve_type_expression(ast_context, expr)
	if !ok {
		return nil, false
	}
	return get_objc_block_proc_type_from_symbol(symbol)
}

write_objc_block_param_types :: proc(sb: ^strings.Builder, fields: []^ast.Field, start, end: int) {
	for i in start ..< end {
		if i > start {
			strings.write_string(sb, ", ")
		}
		field := proc_field_from_list_at(fields, i) or_continue
		type_expr, _ := proc_field_type_for_call(field)
		build_string_node(type_expr, sb, false)
	}
}

get_objc_block_hover_content :: proc(
	ast_context: ^AstContext,
	symbol: Symbol,
	initializer: ^ast.Expr,
) -> (content: MarkupContent, ok: bool) {
	if initializer == nil {
		return {}, false
	}
	call := initializer.derived.(^ast.Call_Expr) or_return
	handler := get_objc_block_handler(ast_context, call) or_return

	capture_count := len(call.args) - 1
	param_count := proc_total_arg_count(handler)
	if capture_count < 0 || capture_count > param_count {
		return {}, false
	}
	callback_count := param_count - capture_count

	sb := strings.builder_make(ast_context.allocator)
	write_symbol_name(&sb, symbol)
	strings.write_string(&sb, ": ^Objc_Block(")
	write_objc_block_param_types(&sb, handler.arg_types, 0, callback_count)
	if capture_count > 0 {
		if callback_count > 0 {
			strings.write_string(&sb, ", ")
		}
		strings.write_string(&sb, "[")
		write_objc_block_param_types(&sb, handler.arg_types, callback_count, param_count)
		strings.write_string(&sb, "]")
	}
	strings.write_string(&sb, ")")

	if len(handler.return_types) > 0 {
		strings.write_string(&sb, " -> ")
		if len(handler.return_types) > 1 {
			strings.write_string(&sb, "(")
		}
		for field, i in handler.return_types {
			if i > 0 {
				strings.write_string(&sb, ", ")
			}
			build_string_node(field, &sb, false)
		}
		if len(handler.return_types) > 1 {
			strings.write_string(&sb, ")")
		}
	}

	return build_markup_content(strings.to_string(sb), ""), true
}

get_objc_block_capture_name :: proc(expr: ^ast.Expr, fallback_index: int) -> string {
	if expr != nil {
		#partial switch value in expr.derived {
		case ^ast.Ident:
			return value.name
		case ^ast.Selector_Expr:
			if value.field != nil {
				return value.field.name
			}
		case ^ast.Unary_Expr:
			return get_objc_block_capture_name(value.expr, fallback_index)
		case ^ast.Paren_Expr:
			return get_objc_block_capture_name(value.expr, fallback_index)
		}
	}
	return fmt.tprintf("capture_%d", fallback_index + 1)
}

get_objc_block_capture_type :: proc(ast_context: ^AstContext, expr: ^ast.Expr) -> string {
	if ident, ok := expr.derived.(^ast.Ident); ok {
		if local, ok := get_local(ast_context^, ident^); ok {
			type_expr := local.type_expr
			if type_expr == nil {
				type_expr = local.rhs
			}
			if type_expr != nil {
				return node_to_string(type_expr)
			}
		}
	}
	if unary, ok := expr.derived.(^ast.Unary_Expr); ok && unary.op.kind == .And {
		type_name := get_objc_block_capture_type(ast_context, unary.expr)
		if type_name != "" {
			return fmt.tprintf("^%s", type_name)
		}
	}

	symbol, ok := resolve_type_expression(ast_context, expr)
	if !ok {
		return ""
	}
	if symbol.type_expr != nil {
		return node_to_string(symbol.type_expr)
	}
	type_expr := symbol_to_expr(symbol, expr.pos.file, context.temp_allocator)
	if type_expr == nil {
		return ""
	}
	return node_to_string(type_expr)
}
