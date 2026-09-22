#+private file

package server

import "core:odin/ast"
import "core:strings"

import "src:common"


ObjcBlockTarget :: struct {
	proc_type: ^ast.Proc_Type,
	pkg:       string,
	qualifier: string,
}

get_objc_block_import_qualifier :: proc(ast_context: ^AstContext, expr: ^ast.Expr) -> string {
	if expr == nil {
		return ""
	}
	#partial switch value in expr.derived {
	case ^ast.Ident:
		for imp in ast_context.imports {
			if imp.base == value.name || imp.name == value.name {
				return imp.base
			}
		}
	case ^ast.Selector_Expr:
		return get_objc_block_import_qualifier(ast_context, value.expr)
	case ^ast.Selector_Call_Expr:
		return get_objc_block_import_qualifier(ast_context, value.expr)
	case ^ast.Call_Expr:
		return get_objc_block_import_qualifier(ast_context, value.expr)
	case ^ast.Paren_Expr:
		return get_objc_block_import_qualifier(ast_context, value.expr)
	}
	return ""
}


get_objc_block_at_position :: proc(
	ast_context: ^AstContext,
	position_context: ^DocumentPositionContext,
) -> (
	^ast.Call_Expr,
	int,
	bool,
) {
	#reverse for call, i in position_context.calls {
		if is_objc_block_call(ast_context, call) {
			return call, i, true
		}
	}
	if position_context.call != nil {
		if call, ok := position_context.call.derived.(^ast.Call_Expr); ok && is_objc_block_call(ast_context, call) {
			return call, -1, true
		}
	}
	if position_context.value_decl != nil {
		for value in position_context.value_decl.values {
			if call, ok := value.derived.(^ast.Call_Expr); ok && is_objc_block_call(ast_context, call) {
				return call, -1, true
			}
		}
	}
	return nil, -1, false
}

get_objc_block_target_proc_type :: proc(
	ast_context: ^AstContext,
	position_context: ^DocumentPositionContext,
	call_index: int,
) -> (
	ObjcBlockTarget,
	bool,
) {
	if position_context.value_decl != nil && position_context.value_decl.type != nil {
		if proc_type, ok := resolve_objc_block_proc_type(ast_context, position_context.value_decl.type); ok {
			return ObjcBlockTarget{proc_type = proc_type}, true
		}
	}

	if call_index <= 0 {
		return {}, false
	}
	for i := call_index - 1; i >= 0; i -= 1 {
		parent := position_context.calls[i]
		for selector_call in position_context.selector_calls {
			if selector_call.call != parent {
				continue
			}
			selector, selector_ok := selector_call.expr.derived.(^ast.Selector_Expr)
			if !selector_ok || selector.field == nil {
				break
			}
			// Resolve the receiver outside the incomplete objc_block call's generic context.
			old_call := ast_context.call
			ast_context.call = nil
			receiver_expr := selector.expr
			qualifier := ""
			if ident, ok := selector.expr.derived.(^ast.Ident); ok {
				if local, ok := get_local(ast_context^, ident^); ok {
					qualifier = get_objc_block_import_qualifier(ast_context, local.initializer)
					if local.type_expr != nil {
						receiver_expr = local.type_expr
					} else if local.rhs != nil {
						receiver_expr = local.rhs
					}
				}
			}
			if qualifier == "" {
				qualifier = get_objc_block_import_qualifier(ast_context, receiver_expr)
			}
			receiver, receiver_ok := resolve_type_expression(ast_context, receiver_expr)
			ast_context.call = old_call
			if !receiver_ok {
				break
			}
			if qualifier == "" {
				for imp in ast_context.imports {
					if imp.name == receiver.pkg {
						qualifier = imp.base
						break
					}
				}
			}
			receiver_value, receiver_value_ok := receiver.value.(SymbolStructValue)
			if !receiver_value_ok {
				break
			}
			method: Symbol
			method_ok := false
			for name, field_index in receiver_value.names {
				if name != selector.field.name {
					continue
				}
				method, method_ok = resolve_type_expression(ast_context, receiver_value.types[field_index])
				break
			}
			if !method_ok {
				break
			}
			procedure, procedure_ok := method.value.(SymbolProcedureValue)
			if !procedure_ok {
				break
			}
			parameter_index, parameter_ok := find_position_in_call_param(position_context, parent^)
			if !parameter_ok {
				break
			}
			// Objective-C method symbols include the receiver as their first parameter.
			field, field_ok := get_proc_arg_type_from_index(procedure, parameter_index + 1)
			if !field_ok {
				break
			}
			type_expr, _ := proc_field_type_for_call(field)
			if proc_type, ok := resolve_objc_block_proc_type(ast_context, type_expr); ok {
				return ObjcBlockTarget {
					proc_type = proc_type,
					pkg = method.pkg,
					qualifier = qualifier,
				}, true
			}
			break
		}

		parent_context := position_context^
		parent_context.call = parent
		target, target_ok := get_target_symbol(ast_context, &parent_context).(Symbol)
		if !target_ok {
			continue
		}
		if proc_type, ok := get_objc_block_proc_type_from_symbol(target); ok {
			return ObjcBlockTarget{proc_type = proc_type}, true
		}
	}
	return {}, false
}

write_objc_block_target_type :: proc(
	sb: ^strings.Builder,
	ast_context: ^AstContext,
	expr: ^ast.Expr,
	target: ObjcBlockTarget,
) {
	if target.pkg != "" && target.qualifier != "" {
		// Indexed method types use names local to their package; emit the alias visible here.
		old_call := ast_context.call
		old_package := ast_context.current_package
		ast_context.call = nil
		ast_context.current_package = target.pkg
		symbol, ok := resolve_type_expression(ast_context, expr)
		ast_context.call = old_call
		ast_context.current_package = old_package
		if ok &&
		   symbol.name != "" &&
		   symbol.pkg != "" &&
		   !is_builtin_pkg(symbol.pkg) &&
		   !is_builtin_type_name(symbol.name) {
			for _ in 0 ..< symbol.pointers {
				strings.write_string(sb, "^")
			}
			strings.write_string(sb, target.qualifier)
			strings.write_string(sb, ".")
			strings.write_string(sb, symbol.name)
			return
		}
	}
	build_string_node(expr, sb, false)
}

write_objc_block_proc_fields :: proc(
	sb: ^strings.Builder,
	ast_context: ^AstContext,
	fields: []^ast.Field,
	target: ObjcBlockTarget,
) {
	for field, i in fields {
		if i > 0 {
			strings.write_string(sb, ", ")
		}
		for name, name_index in field.names {
			if name_index > 0 {
				strings.write_string(sb, ", ")
			}
			build_string_node(name, sb, false)
		}
		if len(field.names) > 0 {
			strings.write_string(sb, ": ")
		}
		type_expr, _ := proc_field_type_for_call(field)
		write_objc_block_target_type(sb, ast_context, type_expr, target)
	}
}

create_objc_block_handler_edit :: proc(
	document: ^Document,
	ast_context: ^AstContext,
	position_context: ^DocumentPositionContext,
	position: common.Position,
	call: ^ast.Call_Expr,
	call_index: int,
) -> (
	TextEdit,
	bool,
) {
	if _, has_handler := get_objc_block_handler(ast_context, call); has_handler {
		return {}, false
	}

	captures := make([dynamic]^ast.Expr, 0, len(call.args), context.temp_allocator)
	for arg in call.args {
		if _, bad := arg.derived.(^ast.Bad_Expr); !bad {
			append(&captures, arg)
		}
	}
	target, has_target := get_objc_block_target_proc_type(ast_context, position_context, call_index)
	if len(captures) == 0 && !has_target {
		return {}, false
	}

	src := string(document.text)
	offset := position_context.position
	previous := offset - 1
	for previous >= 0 &&
	    (src[previous] == ' ' || src[previous] == '\t' || src[previous] == '\r' || src[previous] == '\n') {
		previous -= 1
	}
	prefix := ""
	if previous >= 0 && src[previous] != '(' && src[previous] != ',' {
		prefix = ", "
	}

	next := offset
	for next < len(src) && (src[next] == ' ' || src[next] == '\t' || src[next] == '\r' || src[next] == '\n') {
		next += 1
	}
	suffix := ""
	if next >= len(src) || src[next] != ')' {
		suffix = ")"
	}

	sb := strings.builder_make(context.temp_allocator)
	strings.write_string(&sb, prefix)
	strings.write_string(&sb, "proc(")
	wrote_param := false
	if has_target && target.proc_type.params != nil {
		write_objc_block_proc_fields(&sb, ast_context, target.proc_type.params.list, target)
		wrote_param = len(target.proc_type.params.list) > 0
	}
	for capture, i in captures {
		if wrote_param {
			strings.write_string(&sb, ", ")
		}
		name := get_objc_block_capture_name(capture, i)
		type_name := get_objc_block_capture_type(ast_context, capture)
		strings.write_string(&sb, name)
		strings.write_string(&sb, ":")
		if type_name != "" {
			strings.write_string(&sb, " ")
			strings.write_string(&sb, type_name)
		}
		wrote_param = true
	}
	strings.write_string(&sb, ")")
	if has_target && target.proc_type.results != nil && len(target.proc_type.results.list) > 0 {
		strings.write_string(&sb, " -> ")
		if len(target.proc_type.results.list) > 1 {
			strings.write_string(&sb, "(")
		}
		write_objc_block_proc_fields(&sb, ast_context, target.proc_type.results.list, target)
		if len(target.proc_type.results.list) > 1 {
			strings.write_string(&sb, ")")
		}
	}

	indent := get_line_indentation(src, offset)
	strings.write_string(&sb, " {\n")
	strings.write_string(&sb, indent)
	strings.write_string(&sb, "\t\n")
	strings.write_string(&sb, indent)
	strings.write_string(&sb, "}")
	strings.write_string(&sb, suffix)

	return TextEdit{range = {start = position, end = position}, newText = strings.to_string(sb)}, true
}

@(private = "package")
add_objc_block_handler_action :: proc(
	document: ^Document,
	ast_context: ^AstContext,
	position_context: ^DocumentPositionContext,
	position: common.Position,
	uri: string,
	actions: ^[dynamic]CodeAction,
) {
	call, call_index, call_ok := get_objc_block_at_position(ast_context, position_context)
	if !call_ok {
		return
	}
	edit, edit_ok := create_objc_block_handler_edit(
		document,
		ast_context,
		position_context,
		position,
		call,
		call_index,
	)
	if !edit_ok {
		return
	}

	workspace_edit: WorkspaceEdit
	workspace_edit.changes = make(map[string][]TextEdit, 0, context.temp_allocator)
	// The edit slice must remain valid until the response is serialized.
	edits := make([dynamic]TextEdit, 0, 1, context.temp_allocator)
	append(&edits, edit)
	workspace_edit.changes[uri] = edits[:]
	append(
		actions,
		CodeAction {
			title = "complete Objective-C block handler",
			kind = "refactor.rewrite",
			isPreferred = true,
			edit = workspace_edit,
		},
	)
}
