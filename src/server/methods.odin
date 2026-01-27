package server

import "core:fmt"
import "core:log"
import "core:mem"
import "core:odin/ast"
import "core:odin/parser"
import "core:odin/tokenizer"
import "core:os"
import "core:path/filepath"
import path "core:path/slashpath"
import "core:slice"
import "core:sort"
import "core:strconv"
import "core:strings"


import "src:common"


@(private)
create_remove_edit :: proc(
	position_context: ^DocumentPositionContext,
	strip_leading_period := false,
) -> (
	[]TextEdit,
	bool,
) {
	range, ok := get_range_from_selection_start_to_dot(position_context)

	if !ok {
		return {}, false
	}

	remove_range := common.Range {
		start = range.start,
		end   = range.end,
	}

	if strip_leading_period {
		remove_range.end.character -= 1
	}

	remove_edit := TextEdit {
		range   = remove_range,
		newText = "",
	}

	additionalTextEdits := make([]TextEdit, 1, context.temp_allocator)
	additionalTextEdits[0] = remove_edit

	return additionalTextEdits, true
}

append_method_completion :: proc(
	ast_context: ^AstContext,
	selector_symbol: Symbol,
	position_context: ^DocumentPositionContext,
	results: ^[dynamic]CompletionResult,
	receiver: string,
) {
	if selector_symbol.type != .Variable && selector_symbol.type != .Struct {
		return
	}

	remove_edit, ok := create_remove_edit(position_context)
	if !ok {
		return
	}

	if value, ok := selector_symbol.value.(SymbolUntypedValue); ok {
		cases := untyped_map[value.type]
		for c in cases {
			method := Method {
				name = c,
				pkg  = "$builtin", // Untyped values are always builtin types
			}
			collect_methods(
				ast_context,
				position_context,
				method,
				selector_symbol.pointers,
				receiver,
				remove_edit,
				results,
			)
		}
	} else {
		// For typed values, check if it's a builtin type
		method_pkg := selector_symbol.pkg
		if is_builtin_type_name(selector_symbol.name) {
			method_pkg = "$builtin"
		}
		method := Method {
			name = selector_symbol.name,
			pkg  = method_pkg,
		}
		collect_methods(
			ast_context,
			position_context,
			method,
			selector_symbol.pointers,
			receiver,
			remove_edit,
			results,
		)
	}

}

@(private = "file")
collect_methods :: proc(
	ast_context: ^AstContext,
	position_context: ^DocumentPositionContext,
	method: Method,
	pointers: int,
	receiver: string,
	remove_edit: []TextEdit,
	results: ^[dynamic]CompletionResult,
) {
	for k, v in indexer.index.collection.packages {
		symbols, ok := &v.methods[method]
		if !ok {
			continue
		}

		for &symbol in symbols {
			if should_skip_private_symbol(symbol, ast_context.current_package, ast_context.fullpath) {
				continue
			}
			resolve_unresolved_symbol(ast_context, &symbol)

			#partial switch &sym_value in symbol.value {
			case SymbolProcedureValue:
				add_proc_method_completion(
					ast_context,
					position_context,
					&symbol,
					sym_value,
					pointers,
					receiver,
					remove_edit,
					results,
				)
			case SymbolProcedureGroupValue:
				add_proc_group_method_completion(
					ast_context,
					position_context,
					&symbol,
					sym_value,
					pointers,
					receiver,
					remove_edit,
					results,
				)
			}
		}
	}
}

@(private = "file")
add_proc_method_completion :: proc(
	ast_context: ^AstContext,
	position_context: ^DocumentPositionContext,
	symbol: ^Symbol,
	value: SymbolProcedureValue,
	pointers: int,
	receiver: string,
	remove_edit: []TextEdit,
	results: ^[dynamic]CompletionResult,
) {
	if len(value.arg_types) == 0 || value.arg_types[0].type == nil {
		return
	}

	range, ok := get_range_from_selection_start_to_dot(position_context)
	if !ok {
		return
	}

	first_arg: Symbol
	first_arg, ok = resolve_type_expression(ast_context, value.arg_types[0].type)
	if !ok {
		return
	}

	references, dereferences := compute_pointer_adjustments(first_arg.pointers, pointers)

	new_text := build_method_call_text(
		ast_context,
		symbol,
		receiver,
		references,
		dereferences,
		len(value.arg_types) > 1,
	)

	item := CompletionItem {
		label = symbol.name,
		kind = symbol_type_to_completion_kind(symbol.type),
		detail = get_short_signature(ast_context, symbol^),
		additionalTextEdits = remove_edit,
		textEdit = TextEdit{newText = new_text, range = {start = range.end, end = range.end}},
		insertTextFormat = .Snippet,
		InsertTextMode = .adjustIndentation,
		documentation = construct_symbol_docs(symbol^),
	}

	append(results, CompletionResult{completion_item = item})
}

@(private = "file")
add_proc_group_method_completion :: proc(
	ast_context: ^AstContext,
	position_context: ^DocumentPositionContext,
	symbol: ^Symbol,
	value: SymbolProcedureGroupValue,
	pointers: int,
	receiver: string,
	remove_edit: []TextEdit,
	results: ^[dynamic]CompletionResult,
) {
	proc_group, is_group := value.group.derived.(^ast.Proc_Group)
	if !is_group || len(proc_group.args) == 0 {
		return
	}

	range, ok := get_range_from_selection_start_to_dot(position_context)
	if !ok {
		return
	}

	// Get first member to determine pointer adjustments
	first_member: Symbol
	first_member, ok = resolve_type_expression(ast_context, proc_group.args[0])
	if !ok {
		return
	}

	member_proc, is_proc := first_member.value.(SymbolProcedureValue)
	if !is_proc || len(member_proc.arg_types) == 0 || member_proc.arg_types[0].type == nil {
		return
	}

	first_arg: Symbol
	first_arg, ok = resolve_type_expression(ast_context, member_proc.arg_types[0].type)
	if !ok {
		return
	}

	references, dereferences := compute_pointer_adjustments(first_arg.pointers, pointers)

	// Check if any member of the proc group has additional arguments beyond the receiver
	has_additional_args := false
	for member_expr in proc_group.args {
		member: Symbol
		member, ok = resolve_type_expression(ast_context, member_expr)
		if !ok {
			continue
		}
		if proc_val, is_proc_val := member.value.(SymbolProcedureValue); is_proc_val {
			if len(proc_val.arg_types) > 1 {
				has_additional_args = true
				break
			}
		}
	}

	new_text := build_method_call_text(ast_context, symbol, receiver, references, dereferences, has_additional_args)

	item := CompletionItem {
		label = symbol.name,
		kind = symbol_type_to_completion_kind(symbol.type),
		detail = get_short_signature(ast_context, symbol^),
		additionalTextEdits = remove_edit,
		textEdit = TextEdit{newText = new_text, range = {start = range.end, end = range.end}},
		insertTextFormat = .Snippet,
		InsertTextMode = .adjustIndentation,
		documentation = construct_symbol_docs(symbol^),
	}

	append(results, CompletionResult{completion_item = item})
}

@(private = "file")
compute_pointer_adjustments :: proc(
	first_arg_pointers: int,
	current_pointers: int,
) -> (
	references: string,
	dereferences: string,
) {
	pointers_to_add := first_arg_pointers - current_pointers

	if pointers_to_add > 0 {
		for _ in 0 ..< pointers_to_add {
			references = fmt.tprintf("%v&", references)
		}
	} else if pointers_to_add < 0 {
		for _ in pointers_to_add ..< 0 {
			dereferences = fmt.tprintf("%v^", dereferences)
		}
	}

	return references, dereferences
}

@(private = "file")
build_method_call_text :: proc(
	ast_context: ^AstContext,
	symbol: ^Symbol,
	receiver: string,
	references: string,
	dereferences: string,
	has_additional_args: bool,
) -> string {
	new_text: string

	if symbol.pkg != ast_context.document_package {
		new_text = fmt.tprintf(
			"%v.%v",
			path.base(get_symbol_pkg_name(ast_context, symbol), false, ast_context.allocator),
			symbol.name,
		)
	} else {
		new_text = fmt.tprintf("%v", symbol.name)
	}

	if has_additional_args {
		new_text = fmt.tprintf("%v(%v%v%v$0)", new_text, references, receiver, dereferences)
	} else {
		new_text = fmt.tprintf("%v(%v%v%v)$0", new_text, references, receiver, dereferences)
	}

	return new_text
}
