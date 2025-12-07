#+feature dynamic-literals
package server

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:odin/ast"
import "core:odin/tokenizer"
import "core:os"
import "core:path/filepath"
import path "core:path/slashpath"
import "core:reflect"
import "core:slice"
import "core:strconv"
import "core:strings"

import "src:common"

CompletionResult :: struct {
	symbol:          Symbol,
	snippet:         Snippet_Info,
	completion_item: Maybe(CompletionItem), // if we provide the completion item it will just use that
	detail:          string,
	score:           f32,
}

Completion_Type :: enum {
	Implicit,
	Selector,
	Switch_Type,
	Identifier,
	Comp_Lit,
	Directive,
	Package,
}

get_completion_list :: proc(
	document: ^Document,
	position: common.Position,
	completion_context: CompletionContext,
	config: ^common.Config,
) -> (
	CompletionList,
	bool,
) {
	list: CompletionList

	position_context, ok := get_document_position_context(document, position, .Completion)

	if !ok || position_context.abort_completion {
		return list, true
	}

	if position_context.import_stmt == nil {
		if strings.contains_any(completion_context.triggerCharacter, "/:\"") {
			return list, true
		}
	} else {
		// Check only when the import fullpath length is > 1, to allow
		// completion of modules when the initial '"' quote is entered.
		if len(position_context.import_stmt.fullpath) > 1 &&
		   position_context.position == position_context.import_stmt.end.offset &&
		   completion_context.triggerCharacter == "\"" {
			// The completion was called for an import statement where the
			// cursor is on the ending quote, so abort early to prevent
			// performing another completion.
			return list, true
		}
	}

	ast_context := make_ast_context(
		document.ast,
		document.imports,
		document.package_name,
		document.uri.uri,
		document.fullpath,
	)
	ast_context.position_hint = position_context.hint

	get_globals(document.ast, &ast_context)

	ast_context.current_package = ast_context.document_package
	ast_context.value_decl = position_context.value_decl

	if position_context.function != nil {
		get_locals(document.ast, position_context.function, &ast_context, &position_context)
	}

	completion_type: Completion_Type = .Identifier

	if position_context.comp_lit != nil && is_lhs_comp_lit(&position_context) {
		completion_type = .Comp_Lit
	}

	if position_context.selector != nil {
		if position_context.selector_expr != nil {
			if selector_call, ok := position_context.selector_expr.derived.(^ast.Selector_Call_Expr); ok {
				if !position_in_node(selector_call.call, position_context.position) {
					completion_type = .Selector
				}
			} else if selector, ok := position_context.selector_expr.derived.(^ast.Selector_Expr); ok {
				completion_type = .Selector
			}
		} else if _, ok := position_context.selector.derived.(^ast.Implicit_Selector_Expr); !ok {
			// variadic args seem to work by setting it as an implicit selector expr, in that case
			// we want an identifier (eg. foo :: proc(args: ..{*}))

			// Otherwise it's a selector
			completion_type = .Selector
		}
	}

	if position_context.tag != nil {
		completion_type = .Directive
	}

	if position_context.implicit {
		completion_type = .Implicit
	}

	if position_context.import_stmt != nil {
		completion_type = .Package
	}

	done: if position_context.switch_type_stmt != nil && position_context.case_clause != nil {

		if position_context.switch_stmt != nil &&
		   position_context.switch_type_stmt.pos.offset <= position_context.switch_stmt.pos.offset {
			break done
		}

		if assign, ok := position_context.switch_type_stmt.tag.derived.(^ast.Assign_Stmt);
		   ok && assign.rhs != nil && len(assign.rhs) == 1 {
			ast_context.use_locals = true

			if symbol, ok := resolve_type_expression(&ast_context, assign.rhs[0]); ok {
				if union_value, ok := symbol.value.(SymbolUnionValue); ok {
					completion_type = .Switch_Type
				}
			}
		}
	}

	//Currently we do not do any completion in string literals, but it could be possible in the future for formatted strings
	if position_context.basic_lit != nil {
		if _, ok := position_context.basic_lit.derived.(^ast.Basic_Lit); ok {
			return list, true
		}
	}

	arg_symbol := get_target_symbol(&ast_context, &position_context)

	results := make([dynamic]CompletionResult, 0, allocator = context.temp_allocator)
	is_incomplete := false

	// TODO: as these are mutally exclusive, should probably just make them return a slice?
	switch completion_type {
	case .Comp_Lit:
		is_incomplete = get_comp_lit_completion(&ast_context, &position_context, &results, config)
	case .Identifier:
		is_incomplete = get_identifier_completion(&ast_context, &position_context, &results, config)
	case .Implicit:
		is_incomplete = get_implicit_completion(&ast_context, &position_context, &results)
	case .Selector:
		is_incomplete = get_selector_completion(&ast_context, &position_context, &results, config)
	case .Switch_Type:
		is_incomplete = get_type_switch_completion(&ast_context, &position_context, &results)
	case .Directive:
		is_incomplete = get_directive_completion(&ast_context, &position_context, &results)
	case .Package:
		is_incomplete = get_package_completion(&ast_context, &position_context, &results, config)
	}

	items := convert_completion_results(
		&ast_context,
		&position_context,
		results[:],
		completion_type,
		arg_symbol,
		config,
	)
	list.items = items
	list.isIncomplete = is_incomplete
	return list, true
}

get_target_symbol :: proc(ast_context: ^AstContext, position_context: ^DocumentPositionContext) -> Maybe(Symbol) {
	if position_context.call != nil {
		if call, ok := position_context.call.derived.(^ast.Call_Expr); ok {
			if param_index, ok := find_position_in_call_param(position_context, call^); ok {
				// Manually check this so we handle the pointer case of the first argument
				if ident, ok := call.expr.derived.(^ast.Ident); ok && param_index == 0 {
					switch ident.name {
					case "append", "non_zero_append":
						return Symbol{value = SymbolDynamicArrayValue{}, pointers = 1}
					}
				}
				if call_symbol, ok := resolve_type_expression(ast_context, call.expr); ok {
					if value, ok := call_symbol.value.(SymbolProcedureValue); ok {
						if arg_type, arg_type_ok := get_proc_arg_type_from_index(value, param_index); ok {
							if position_context.field_value != nil {
								// we are using a named param so we want to ensure we use that type and not the
								// type at the index
								if name, ok := position_context.field_value.field.derived.(^ast.Ident); ok {
									if i, ok := get_field_list_name_index(name.name, value.arg_types); ok {
										arg_type = value.arg_types[i]
									}
								}
							}
							if arg_type != nil {
								if arg_type.type != nil {
									if resolved_arg_symbol, ok := resolve_type_expression(ast_context, arg_type.type);
									   ok {
										return resolved_arg_symbol
									}
								} else if arg_type.default_value != nil {
									if resolved_arg_symbol, ok := resolve_type_expression(
										ast_context,
										arg_type.default_value,
									); ok {
										return resolved_arg_symbol
									}
								}
							}
						}
					}
				}
			}
		}
	}
	return nil
}

convert_completion_results :: proc(
	ast_context: ^AstContext,
	position_context: ^DocumentPositionContext,
	results: []CompletionResult,
	completion_type: Completion_Type,
	target_symbol: Maybe(Symbol),
	config: ^common.Config,
) -> []CompletionItem {
	for &result in results {
		score_completion_item(&result, ast_context.current_package)
	}

	slice.sort_by(results, proc(i, j: CompletionResult) -> bool {
		if j.score != i.score {
			return j.score < i.score
		}
		return j.symbol.name > i.symbol.name
	})

	top_results := results
	// Just to keep consistency to what it was before these changes
	if completion_type == .Identifier {
		//hard code for now
		top_results = results[0:(min(100, len(results)))]
	}

	items := make([dynamic]CompletionItem, 0, len(top_results), allocator = context.temp_allocator)

	for result, i in top_results {
		result := result
		if item, ok := result.completion_item.?; ok {
			if config.enable_label_details {
				item.labelDetails = CompletionItemLabelDetails {
					description = item.detail,
				}
			}
			// temporary as we move things to use the symbols directly
			if item.documentation == nil {
				item.documentation = MarkupContent {
					kind  = "markdown",
					value = fmt.tprintf("```odin\n%v\n```", item.detail),
				}
				item.detail = ""
			} else if s, ok := item.documentation.(string); ok && s == "" {
				item.documentation = MarkupContent {
					kind  = "markdown",
					value = fmt.tprintf("```odin\n%v\n```", item.detail),
				}
				item.detail = ""
			}
			if item.sortText == nil {
				item.sortText = fmt.tprintf("%05d", i)
			}
			append(&items, item)
			continue
		}

		//Skip procedures when the position is in proc decl
		if position_in_proc_decl(position_context) &&
		   result.symbol.type == .Function &&
		   config.enable_procedure_context {
			continue
		}

		if position_in_struct_decl(position_context) {
			to_skip: bit_set[SymbolType] = {.Function, .Variable, .Constant, .Field}
			if result.symbol.type in to_skip {
				continue
			}
		}

		if result.snippet.insert != "" {
			item := CompletionItem {
				label            = result.symbol.name,
				insertText       = result.snippet.insert,
				kind             = .Snippet,
				detail           = result.snippet.detail,
				documentation    = result.symbol.doc,
				insertTextFormat = .Snippet,
				sortText         = fmt.tprintf("%05d", i),
			}

			edits := make([dynamic]TextEdit, context.temp_allocator)

			for pkg in result.snippet.packages {
				edit, ok := get_core_insert_package_if_non_existent(ast_context, pkg)
				if ok {
					append(&edits, edit)
				}
			}

			item.additionalTextEdits = edits[:]

			append(&items, item)
			continue
		}

		build_documentation(ast_context, &result.symbol, true)
		item := CompletionItem {
			label         = result.symbol.name,
			documentation = write_hover_content(ast_context, result.symbol),
			sortText      = fmt.tprintf("%05d", i),
		}

		if config.enable_completion_matching {
			if s, ok := target_symbol.(Symbol);
			   ok && (completion_type == .Selector || completion_type == .Identifier) {
				handle_matching(ast_context, position_context, result.symbol, s, &item, completion_type)
			}
		}

		if config.enable_label_details {
			// detail      = left
			// description = right
			details := CompletionItemLabelDetails{}
			if result.detail != "" {
				details.description = result.detail
				item.detail = result.detail
			} else {
				details.detail = get_completion_details(ast_context, result.symbol)
				details.description = get_completion_description(ast_context, result.symbol)
				if details.detail != "" {
					item.detail = details.detail
				} else if details.description != "" {
					item.detail = details.description
				}
			}
			// hack for sublime text's issue
			// remove when this issue is fixed: https://github.com/sublimehq/sublime_text/issues/6033
			// or if this PR gets merged: https://github.com/sublimelsp/LSP/pull/2293
			if config.client_name == "Sublime Text LSP" {
				if strings.contains(details.detail, "..") && strings.contains(details.detail, "#") {
					s, _ := strings.replace_all(details.detail, "..", "ꓸꓸ", allocator = context.temp_allocator)
					details.detail = s
				}
			}
			item.labelDetails = details
		}

		item.kind = symbol_type_to_completion_kind(result.symbol.type)
		if result.symbol.type == .Function && config.enable_snippets && config.enable_procedure_snippet {
			item.insertText = fmt.tprintf("%v($0)", item.label)
			item.insertTextFormat = .Snippet
			item.deprecated = .Deprecated in result.symbol.flags
			item.command = Command {
				command = "editor.action.triggerParameterHints",
			}
		}

		append(&items, item)
	}

	if completion_type == .Identifier {
		append_non_imported_packages(ast_context, position_context, &items, config)
	}

	return items[:]
}

score_completion_item :: proc(item: ^CompletionResult, curr_pkg: string) {
	if _, ok := item.completion_item.?; ok {
		return
	}

	if .Local in item.symbol.flags {
		item.score += 1
	}

	if item.symbol.type == .Variable {
		item.score += 1
	}

	if item.symbol.type == .Field {
		item.score += 2
	}

	if item.symbol.pkg == curr_pkg {
		item.score += 1
	}
}

@(private = "file")
handle_matching :: proc(
	ast_context: ^AstContext,
	position_context: ^DocumentPositionContext,
	result_symbol: Symbol,
	arg_symbol: Symbol,
	item: ^CompletionItem,
	completion_type: Completion_Type,
) {
	should_skip :: proc(arg_symbol, result_symbol: Symbol) -> bool {
		if v, ok := arg_symbol.value.(SymbolBasicValue); ok {
			if v.ident.name == "any" {
				return true
			}
		}

		if _, ok := result_symbol.value.(SymbolUntypedValue); ok && arg_symbol.type == .Keyword {
			if _, ok := are_symbol_untyped_basic_same_typed(arg_symbol, result_symbol); !ok {
				if _, ok := are_symbol_untyped_basic_same_typed(result_symbol, arg_symbol); !ok {
					return true
				}
				return false
			}
			return false
		}

		if r, ok := result_symbol.value.(SymbolBasicValue); ok {
			if a, ok := arg_symbol.value.(SymbolBasicValue); ok {
				return r.ident.name != a.ident.name
			}
		}

		if _, ok := arg_symbol.value.(SymbolSliceValue); ok {
			if _, ok := result_symbol.value.(SymbolDynamicArrayValue); ok {
				return false
			}
		}

		a_id := reflect.union_variant_typeid(arg_symbol.value)
		b_id := reflect.union_variant_typeid(result_symbol.value)

		if a_id != b_id {
			return true
		}

		#partial switch v in arg_symbol.value {
		case SymbolMapValue, SymbolDynamicArrayValue, SymbolSliceValue, SymbolMultiPointerValue, SymbolFixedArrayValue:
			return false
		}

		if result_symbol.uri != arg_symbol.uri || result_symbol.range != arg_symbol.range {
			return true
		}

		return false
	}

	contains_unary :: proc(arg: ^ast.Expr) -> bool {
		if arg == nil {
			return false
		}

		#partial switch n in arg.derived {
		case ^ast.Unary_Expr:
			return true
		case ^ast.Field_Value:
			return contains_unary(n.value)
		}

		return false
	}

	if should_skip(arg_symbol, result_symbol) {
		return
	}

	suffix := ""
	prefix := ""

	if _, ok := arg_symbol.value.(SymbolSliceValue); ok {
		if _, ok := result_symbol.value.(SymbolDynamicArrayValue); ok {
			suffix = "[:]"
		}
	}

	diff := result_symbol.pointers - arg_symbol.pointers
	if diff > 0 {
		suffix = repeat("^", diff, context.temp_allocator)
	}

	if diff < 0 && !contains_unary(position_context.call_arg) {
		prefix = "&"
	}

	if completion_type == .Identifier {
		item.insertText = fmt.tprint(prefix, item.label, suffix, sep = "")
	} else if completion_type == .Selector {
		item.insertText = fmt.tprint(item.label, suffix, sep = "")
		if prefix != "" {
			if range, ok := get_range_from_selection_start_to_dot(position_context); ok {
				prefix_edit := TextEdit {
					range = {start = range.start, end = range.start},
					newText = "&",
				}

				additionalTextEdits := make([]TextEdit, 1, context.temp_allocator)
				additionalTextEdits[0] = prefix_edit
				item.additionalTextEdits = additionalTextEdits
			}
		}
	}
}

get_completion_details :: proc(ast_context: ^AstContext, symbol: Symbol) -> string {
	#partial switch v in symbol.value {
	case SymbolProcedureValue:
		sb := strings.builder_make(ast_context.allocator)
		write_proc_param_list_and_return(&sb, v)
		return strings.to_string(sb)
	case SymbolAggregateValue:
		return "(..)"
	}
	return ""
}

get_completion_description :: proc(ast_context: ^AstContext, symbol: Symbol) -> string {
	#partial switch v in symbol.value {
	case SymbolProcedureValue:
		return ""
	case SymbolAggregateValue:
		return ""
	}
	sb := strings.builder_make()
	if write_symbol_type_information(&sb, ast_context, symbol) {
		return strings.to_string(sb)
	}
	return get_short_signature(ast_context, symbol)
}

get_attribute_completion :: proc(
	ast_context: ^AstContext,
	position_context: ^DocumentPositionContext,
	list: ^CompletionList,
) {


}

DIRECTIVE_NAME_LIST :: []string {
	// basic directives
	"file",
	"directory",
	"line",
	"procedure",
	"caller_location",
	"reverse",
	// call directives
	"location",
	"caller_expression",
	"exists",
	"load",
	"load_directory",
	"load_hash",
	"hash",
	"assert",
	"panic",
	"defined",
	"config",
	/* type helper */
	"type",
	/* struct type */
	"packed",
	"raw_union",
	"align",
	"all_or_none",
	/* union type */
	"no_nil",
	"shared_nil",
	/* array type */
	"simd",
	"soa",
	"sparse",
	/* ptr type */
	"relative",
	/* field flags */
	"no_alias",
	"c_vararg",
	"const",
	"any_int",
	"subtype",
	"by_ptr",
	"no_broadcast",
	"no_capture",
	/* swich flags */
	"partial",
	/* block flags */
	"bounds_check",
	"no_bounds_check",
	"type_assert",
	"no_type_assert",
	/* proc inlining */
	"force_inline",
	"force_no_inline",
	/* return values flags */
	"optional_ok",
	"optional_allocator_error",
}

completion_items_directives: []CompletionResult

@(init)
_init_completion_items_directives :: proc "contextless" () {
	context = runtime.default_context()
	completion_items_directives = slice.mapper(DIRECTIVE_NAME_LIST, proc(name: string) -> CompletionResult {
		return CompletionResult {
			completion_item = CompletionItem {
				detail = strings.concatenate({"#", name}) or_else name,
				label = name,
				kind = .Constant,
			},
		}
	})
}

get_directive_completion :: proc(
	ast_context: ^AstContext,
	position_context: ^DocumentPositionContext,
	results: ^[dynamic]CompletionResult,
) -> bool {
	is_incomplete := false

	// Right now just return all the possible completions, but later on I should give the context specific ones
	append(results, ..completion_items_directives[:])
	return is_incomplete
}

get_comp_lit_completion :: proc(
	ast_context: ^AstContext,
	position_context: ^DocumentPositionContext,
	results: ^[dynamic]CompletionResult,
	config: ^common.Config,
) -> bool {
	if symbol, ok := resolve_comp_literal(ast_context, position_context); ok {
		#partial switch v in symbol.value {
		case SymbolStructValue:
			for name, i in v.names {
				if name == "_" {
					continue
				}

				set_ast_package_set_scoped(ast_context, symbol.pkg)

				if resolved, ok := resolve_type_expression(ast_context, v.types[i]); ok {
					if field_exists_in_comp_lit(position_context.comp_lit, name) {
						continue
					}

					construct_struct_field_symbol(&resolved, symbol.name, v, i)
					append(results, CompletionResult{symbol = resolved})
				}
			}
			return false
		case SymbolBitFieldValue:
			for name, i in v.names {
				if name == "_" {
					continue
				}

				set_ast_package_set_scoped(ast_context, symbol.pkg)

				if resolved, ok := resolve_type_expression(ast_context, v.types[i]); ok {
					if field_exists_in_comp_lit(position_context.comp_lit, name) {
						continue
					}

					construct_bit_field_field_symbol(&resolved, symbol.name, v, i)
					append(results, CompletionResult{symbol = resolved})
				}
			}
			return false
		case SymbolFixedArrayValue:
			if symbol, ok := resolve_type_expression(ast_context, v.len); ok {
				if v, ok := symbol.value.(SymbolEnumValue); ok {
					for name, i in v.names {
						if field_exists_in_comp_lit(position_context.comp_lit, name) {
							continue
						}

						construct_enum_field_symbol(&symbol, v, i)
						append(results, CompletionResult{symbol = symbol})
					}
					return false
				}
			}
		}
		return get_identifier_completion(ast_context, position_context, results, config)
	}

	return false
}

add_soa_field_completion :: proc(
	ast_context: ^AstContext,
	selector: Symbol,
	expr: ^ast.Expr,
	size: ^ast.Expr,
	results: ^[dynamic]CompletionResult,
	parent_name: string,
) {
	if .Soa not_in selector.flags && .SoaPointer not_in selector.flags {
		return
	}
	if symbol, ok := resolve_type_expression(ast_context, expr); ok {
		if v, ok := symbol.value.(SymbolStructValue); ok {
			for name, i in v.names {
				if name == "_" {
					continue
				}

				resolved := Symbol {
					type  = .Field,
					range = v.ranges[i],
					pkg   = parent_name,
				}
				if .SoaPointer in selector.flags {
					if s, ok := resolve_type_expression(ast_context, v.types[i]); ok {
						resolved.value = s.value
						resolved.pkg = symbol.name
					} else {
						continue
					}
				} else if size != nil {
					resolved.value = SymbolFixedArrayValue {
						expr = v.types[i],
						len  = size,
					}
				} else {
					resolved.value = SymbolMultiPointerValue {
						expr = v.types[i],
					}
				}
				resolved.name = name
				build_documentation(ast_context, &resolved)
				append(results, CompletionResult{symbol = resolved})
			}
		}
	}
}

get_selector_completion :: proc(
	ast_context: ^AstContext,
	position_context: ^DocumentPositionContext,
	results: ^[dynamic]CompletionResult,
	config: ^common.Config,
) -> bool {
	ast_context.current_package = ast_context.document_package

	selector: Symbol
	ok: bool
	is_incomplete := false

	reset_ast_context(ast_context)

	selector, ok = resolve_type_expression(ast_context, position_context.selector)

	if !ok {
		return is_incomplete
	}

	if selector.type != .Variable &&
	   selector.type != .Field &&
	   selector.type != .Package &&
	   selector.type != .Enum &&
	   selector.type != .Function &&
	   (selector.type == .Struct && .Variable not_in selector.flags) {
		// We don't want completions for struct types, but we do want completions for constant variables.
		// See tests `ast_global_non_mutable_completion` vs `ast_completion_global_selector_from_local_scope`
		return is_incomplete
	}

	set_ast_package_from_symbol_scoped(ast_context, selector)

	field: string

	if position_context.field != nil {
		#partial switch v in position_context.field.derived {
		case ^ast.Ident:
			field = v.name
		}
	}

	receiver_start := position_context.selector.expr_base.pos.offset
	receiver_end := position_context.selector.expr_base.end.offset
	receiver := position_context.file.src[receiver_start:receiver_end]

	if s, ok := selector.value.(SymbolProcedureValue); ok {
		if len(s.return_types) == 1 {
			if selector, ok = resolve_type_expression(ast_context, s.return_types[0].type); !ok {
				return false
			}
		}
	}

	if config.enable_fake_method {
		append_method_completion(ast_context, selector, position_context, results, receiver)
	}

	#partial switch v in selector.value {
	case SymbolFixedArrayValue:
		is_incomplete = true
		append_magic_array_like_completion(position_context, selector, results)

		containsColor := 1
		containsCoord := 1

		expr_len := 0

		if v.len != nil {
			if basic, ok := v.len.derived.(^ast.Basic_Lit); ok {
				if expr_len, ok = strconv.parse_int(basic.tok.text); !ok {
					expr_len = 0
				}
			}
		}

		if field != "" {
			for i := 0; i < len(field); i += 1 {
				c := field[i]
				if _, ok := swizzle_color_map[c]; ok {
					containsColor += 1
				} else if _, ok := swizzle_coord_map[c]; ok {
					containsCoord += 1
				} else {
					return is_incomplete
				}
			}
		}

		if containsColor == 1 && containsCoord == 1 {
			save := expr_len
			for k in swizzle_color_components {
				if expr_len <= 0 {
					break
				}

				expr_len -= 1

				item := CompletionItem {
					label  = fmt.tprintf("%v%v", field, k),
					kind   = .Property,
					detail = fmt.tprintf("%v%v: %v", field, k, node_to_string(v.expr)),
				}
				append(results, CompletionResult{completion_item = item})
			}

			expr_len = save

			for k in swizzle_coord_components {
				if expr_len <= 0 {
					break
				}

				expr_len -= 1

				item := CompletionItem {
					label  = fmt.tprintf("%v%v", field, k),
					kind   = .Property,
					detail = fmt.tprintf("%v%v: %v", field, k, node_to_string(v.expr)),
				}
				append(results, CompletionResult{completion_item = item})
			}
		}

		if containsColor > 1 {
			for k in swizzle_color_components {
				if expr_len <= 0 {
					break
				}

				expr_len -= 1

				item := CompletionItem {
					label  = fmt.tprintf("%v%v", field, k),
					kind   = .Property,
					detail = fmt.tprintf("%v%v: [%v]%v", field, k, containsColor, node_to_string(v.expr)),
				}
				append(results, CompletionResult{completion_item = item})
			}
		} else if containsCoord > 1 {
			for k in swizzle_coord_components {
				if expr_len <= 0 {
					break
				}

				expr_len -= 1

				item := CompletionItem {
					label  = fmt.tprintf("%v%v", field, k),
					kind   = .Property,
					detail = fmt.tprintf("%v%v: [%v]%v", field, k, containsCoord, node_to_string(v.expr)),
				}
				append(results, CompletionResult{completion_item = item})
			}
		}
		add_soa_field_completion(ast_context, selector, v.expr, v.len, results, selector.name)
	case SymbolUnionValue:
		is_incomplete = false

		append_magic_union_completion(position_context, selector, results)

		for type in v.types {
			if symbol, ok := resolve_type_expression(ast_context, type); ok {
				base := get_symbol_pkg_name(ast_context, &symbol)

				item := CompletionItem {
					kind          = .EnumMember,
					detail        = fmt.tprintf("%v", selector.name),
					documentation = symbol.doc,
				}

				//Might be a hack...
				_, is_selector := type.derived.(^ast.Selector_Expr)

				if symbol.pkg == ast_context.document_package ||
				   base == "runtime" ||
				   base == "$builtin" ||
				   is_selector ||
				   is_using_package(ast_context, symbol.pkg) {
					item.label = fmt.aprintf(
						"(%v%v)",
						repeat("^", symbol.pointers, context.temp_allocator),
						node_to_string(type, true),
					)
				} else {
					item.label = fmt.aprintf(
						"(%v%v.%v)",
						repeat("^", symbol.pointers, context.temp_allocator),
						get_symbol_pkg_name(ast_context, &symbol),
						node_to_string(type, true),
					)
				}
				append(results, CompletionResult{completion_item = item})
			}
		}

	case SymbolEnumValue:
		is_incomplete = false

		for name in v.names {
			item := CompletionItem {
				label  = name,
				kind   = .EnumMember,
				detail = fmt.tprintf("%v.%v", selector.name, name),
			}
			append(results, CompletionResult{completion_item = item})
		}

	case SymbolBitSetValue:
		is_incomplete = false

		enumv, ok := unwrap_bitset(ast_context, selector)
		if !ok {break}

		remove_edit, rok := create_remove_edit(position_context, true)
		if !rok {break}

		for name in enumv.names {
			append(
				results,
				CompletionResult {
					completion_item = CompletionItem {
						label = fmt.tprintf(".%s", name),
						kind = .EnumMember,
						detail = fmt.tprintf("%s.%s", selector.name, name),
						additionalTextEdits = remove_edit,
					},
				},
			)
			in_text := fmt.tprintf(".%s in %s", name, receiver)
			append(
				results,
				CompletionResult {
					completion_item = CompletionItem {
						label = fmt.tprintf(".%s in", name),
						kind = .EnumMember,
						detail = in_text,
						insertText = in_text[1:],
						additionalTextEdits = remove_edit,
					},
				},
			)
			not_in_text := fmt.tprintf(".%s not_in %s", name, receiver)
			append(
				results,
				CompletionResult {
					completion_item = CompletionItem {
						label = fmt.tprintf(".%s not_in", name),
						kind = .EnumMember,
						detail = not_in_text,
						insertText = not_in_text[1:],
						additionalTextEdits = remove_edit,
					},
				},
			)
		}

	case SymbolStructValue:
		is_incomplete = false
		for name, i in v.names {
			if name == "_" {
				continue
			}

			if symbol, ok := resolve_type_expression(ast_context, v.types[i]); ok {
				if expr, ok := position_context.selector.derived.(^ast.Selector_Expr); ok {
					if expr.op.kind == .Arrow_Right {
						if symbol.type != .Function && symbol.type != .Type_Function {
							continue
						}
						if .ObjCIsClassMethod in symbol.flags {
							assert(.ObjC in symbol.flags)
							continue
						}
					} else if .ObjC in selector.flags {
						continue
					}
				}

				construct_struct_field_symbol(&symbol, selector.name, v, i)
				append(results, CompletionResult{symbol = symbol})
			} else {
				//just give some generic symbol with name.
				item := CompletionItem {
					label         = symbol.name,
					kind          = .Field,
					detail        = fmt.tprintf("%v: %v", name, node_to_string(v.types[i])),
					documentation = symbol.doc,
				}

				append(results, CompletionResult{completion_item = item})
			}
		}
	case SymbolBitFieldValue:
		is_incomplete = false

		for name, i in v.names {
			if name == "_" {
				continue
			}

			set_ast_package_from_symbol_scoped(ast_context, selector)

			if symbol, ok := resolve_type_expression(ast_context, v.types[i]); ok {
				item := CompletionItem {
					label         = name,
					kind          = .Field,
					detail        = fmt.tprintf(
						"%v.%v: %v",
						selector.name,
						name,
						type_to_string(ast_context, v.types[i]),
					),
					documentation = symbol.doc,
				}

				append(results, CompletionResult{completion_item = item})
			} else {
				//just give some generic symbol with name.
				item := CompletionItem {
					label         = symbol.name,
					kind          = .Field,
					detail        = fmt.tprintf("%v: %v", name, node_to_string(v.types[i])),
					documentation = symbol.doc,
				}
				append(results, CompletionResult{completion_item = item})
			}
		}

	case SymbolPackageValue:
		is_incomplete = true

		pkg := selector.pkg

		if searched, ok := fuzzy_search(field, {pkg}, ast_context.fullpath); ok {
			for search in searched {
				symbol := search.symbol

				if .PrivatePackage in symbol.flags {
					continue
				}

				resolve_unresolved_symbol(ast_context, &symbol)
				append(results, CompletionResult{symbol = symbol})
			}
		} else {
			log.errorf("Failed to fuzzy search, field: %v, package: %v", field, selector.pkg)
			return is_incomplete
		}
	case SymbolDynamicArrayValue:
		is_incomplete = false
		append_magic_array_like_completion(position_context, selector, results)
		add_soa_field_completion(ast_context, selector, v.expr, nil, results, selector.name)
	case SymbolSliceValue:
		is_incomplete = false
		append_magic_array_like_completion(position_context, selector, results)
		add_soa_field_completion(ast_context, selector, v.expr, nil, results, selector.name)
	case SymbolMapValue:
		is_incomplete = false
		append_magic_map_completion(position_context, selector, results)

	case SymbolBasicValue:
		if selector.signature == "string" {
			append_magic_array_like_completion(position_context, selector, results)
		}
	case SymbolUntypedValue:
		if v.type == .String {
			append_magic_array_like_completion(position_context, selector, results)
		}
	}

	return is_incomplete
}

get_implicit_completion :: proc(
	ast_context: ^AstContext,
	position_context: ^DocumentPositionContext,
	results: ^[dynamic]CompletionResult,
) -> bool {
	is_incomplete := false

	selector: Symbol

	reset_ast_context(ast_context)

	set_ast_package_from_symbol_scoped(ast_context, selector)

	//value decl infer a : My_Enum = .*
	if position_context.value_decl != nil && position_context.value_decl.type != nil {
		if enum_value, unwrapped_super_enum, ok := unwrap_enum(ast_context, position_context.value_decl.type); ok {
			for name in enum_value.names {
				if position_context.comp_lit != nil && field_exists_in_comp_lit(position_context.comp_lit, name) {
					continue
				}
				item := CompletionItem {
					label  = name,
					kind   = .EnumMember,
					detail = name,
				}
				if unwrapped_super_enum {
					add_implicit_selector_remove_edit(position_context, &item, name, enum_value.names)
				}
				append(results, CompletionResult{completion_item = item})
			}

			return is_incomplete
		}

		if position_context.comp_lit != nil {
			if symbol, ok := resolve_comp_literal(ast_context, position_context); ok {
				if v, ok := symbol.value.(SymbolFixedArrayValue); ok {
					if symbol, ok := resolve_type_expression(ast_context, v.len); ok {
						if v, ok := symbol.value.(SymbolEnumValue); ok {
							for name, i in v.names {
								if field_exists_in_comp_lit(position_context.comp_lit, name) {
									continue
								}

								item := CompletionItem {
									label         = name,
									detail        = name,
									documentation = symbol.doc,
								}

								append(results, CompletionResult{completion_item = item})
							}
							return is_incomplete
						}
					}
				} else if v, ok := symbol.value.(SymbolStructValue); ok {
					if position_context.field_value != nil {
						if symbol, ok := resolve_implicit_selector_comp_literal(ast_context, position_context, symbol);
						   ok {
							if enum_value, ok := symbol.value.(SymbolEnumValue); ok {
								for name in enum_value.names {
									if position_context.comp_lit != nil &&
									   field_exists_in_comp_lit(position_context.comp_lit, name) {
										continue
									}
									item := CompletionItem {
										label  = name,
										kind   = .EnumMember,
										detail = name,
									}
									append(results, CompletionResult{completion_item = item})
								}

								return is_incomplete
							}
						}
					}
				}
			}
		}
	}

	//enum switch infer
	if position_context.switch_stmt != nil &&
	   position_context.case_clause != nil &&
	   position_context.switch_stmt.cond != nil {
		used_enums := make(map[string]struct{}, 5, context.temp_allocator)

		if block, ok := position_context.switch_stmt.body.derived.(^ast.Block_Stmt); ok {
			for stmt in block.stmts {
				if case_clause, ok := stmt.derived.(^ast.Case_Clause); ok {
					for name in case_clause.list {
						if implicit, ok := name.derived.(^ast.Implicit_Selector_Expr); ok {
							used_enums[implicit.field.name] = {}
						}
					}
				}
			}
		}

		if enum_value, unwrapped_super_enum, ok := unwrap_enum(ast_context, position_context.switch_stmt.cond); ok {
			for name in enum_value.names {
				if name in used_enums {
					continue
				}

				item := CompletionItem {
					label  = name,
					kind   = .EnumMember,
					detail = name,
				}
				if unwrapped_super_enum {
					add_implicit_selector_remove_edit(position_context, &item, name, enum_value.names)
				}

				append(results, CompletionResult{completion_item = item})
			}

			return is_incomplete
		}
	}

	if position_context.assign != nil &&
	   position_context.assign.lhs != nil &&
	   len(position_context.assign.lhs) == 1 &&
	   is_bitset_assignment_operator(position_context.assign.op.text) {
		//bitsets
		if symbol, ok := resolve_type_expression(ast_context, position_context.assign.lhs[0]); ok {
			set_ast_package_set_scoped(ast_context, symbol.pkg)
			if value, ok := unwrap_bitset(ast_context, symbol); ok {
				for name in value.names {
					if position_context.comp_lit != nil && field_exists_in_comp_lit(position_context.comp_lit, name) {
						continue
					}

					item := CompletionItem {
						label  = name,
						kind   = .EnumMember,
						detail = name,
					}

					append(results, CompletionResult{completion_item = item})
				}

				return is_incomplete
			}
		}

		reset_ast_context(ast_context)
	}

	if position_context.comp_lit != nil &&
	   position_context.parent_binary != nil &&
	   is_bitset_binary_operator(position_context.binary.op.text) {
		//bitsets
		if symbol, ok := resolve_first_symbol_from_binary_expression(ast_context, position_context.parent_binary); ok {
			set_ast_package_set_scoped(ast_context, symbol.pkg)
			if value, ok := unwrap_bitset(ast_context, symbol); ok {
				for name in value.names {
					item := CompletionItem {
						label  = name,
						kind   = .EnumMember,
						detail = name,
					}

					append(results, CompletionResult{completion_item = item})
				}

				return is_incomplete
			}
		}

		reset_ast_context(ast_context)
	}

	//infer bitset and enums based on the identifier comp_lit, i.e. a := My_Struct { my_ident = . }
	if position_context.comp_lit != nil && position_context.parent_comp_lit != nil {
		if symbol, ok := resolve_comp_literal(ast_context, position_context); ok {
			if comp_symbol, ok := resolve_implicit_selector_comp_literal(ast_context, position_context, symbol); ok {
				if enum_value, ok := comp_symbol.value.(SymbolEnumValue); ok {
					for enum_name in enum_value.names {
						item := CompletionItem {
							label  = enum_name,
							kind   = .EnumMember,
							detail = enum_name,
						}

						append(results, CompletionResult{completion_item = item})
					}

					return is_incomplete
				} else if s, ok := unwrap_bitset(ast_context, comp_symbol); ok {
					for enum_name in s.names {
						if field_exists_in_comp_lit(position_context.comp_lit, enum_name) {
							continue
						}
						item := CompletionItem {
							label  = enum_name,
							kind   = .EnumMember,
							detail = enum_name,
						}

						append(results, CompletionResult{completion_item = item})
					}

					return is_incomplete
				}
			}
		}
	}

	if position_context.binary != nil {
		#partial switch position_context.binary.op.kind {
		case .Cmp_Eq, .Not_Eq, .In, .Not_In, .Lt, .Lt_Eq, .Gt, .Gt_Eq:
			context_node: ^ast.Expr
			enum_node: ^ast.Expr

			if position_in_node(position_context.binary.right, position_context.position) {
				context_node = position_context.binary.right
				enum_node = position_context.binary.left
			} else if position_in_node(position_context.binary.left, position_context.position) {
				context_node = position_context.binary.left
				enum_node = position_context.binary.right
			}

			if context_node != nil && enum_node != nil {
				if enum_value, unwrapped_super_enum, ok := unwrap_enum(ast_context, enum_node); ok {
					for name in enum_value.names {
						item := CompletionItem {
							label  = name,
							kind   = .EnumMember,
							detail = name,
						}
						if unwrapped_super_enum {
							add_implicit_selector_remove_edit(position_context, &item, name, enum_value.names)
						}

						append(results, CompletionResult{completion_item = item})
					}

					return is_incomplete
				}
			}

			reset_ast_context(ast_context)
		}
	}

	if position_context.assign != nil && position_context.assign.rhs != nil && position_context.assign.lhs != nil {
		rhs_index: int

		for elem in position_context.assign.rhs {
			if position_in_node(elem, position_context.position) {
				break
			} else {
				//procedures are the only types that can return more than one value
				if symbol, ok := resolve_type_expression(ast_context, elem); ok {
					if procedure, ok := symbol.value.(SymbolProcedureValue); ok {
						if procedure.return_types == nil {
							return is_incomplete
						}

						rhs_index += len(procedure.return_types)
					} else {
						rhs_index += 1
					}
				}
			}
		}

		if len(position_context.assign.lhs) > rhs_index {
			if enum_value, unwrapped_super_enum, ok := unwrap_enum(
				ast_context,
				position_context.assign.lhs[rhs_index],
			); ok {
				for name in enum_value.names {
					item := CompletionItem {
						label  = name,
						kind   = .EnumMember,
						detail = name,
					}
					if unwrapped_super_enum {
						add_implicit_selector_remove_edit(position_context, &item, name, enum_value.names)
					}

					append(results, CompletionResult{completion_item = item})
				}

				return is_incomplete
			}
		}

		reset_ast_context(ast_context)
	}

	if position_context.returns != nil && position_context.function != nil {
		return_index: int

		if position_context.returns.results == nil {
			return is_incomplete
		}

		for result, i in position_context.returns.results {
			if position_in_node(result, position_context.position) {
				return_index = i
				break
			}
		}

		if position_context.function.type == nil {
			return is_incomplete
		}

		if position_context.function.type.results == nil {
			return is_incomplete
		}

		if len(position_context.function.type.results.list) > return_index {
			if enum_value, unwrapped_super_enum, ok := unwrap_enum(
				ast_context,
				position_context.function.type.results.list[return_index].type,
			); ok {
				for name in enum_value.names {
					item := CompletionItem {
						label  = name,
						kind   = .EnumMember,
						detail = name,
					}

					if unwrapped_super_enum {
						add_implicit_selector_remove_edit(position_context, &item, name, enum_value.names)
					}
					append(results, CompletionResult{completion_item = item})
				}

				return is_incomplete
			}
		}

		reset_ast_context(ast_context)
	}

	if position_context.index != nil {
		symbol: Symbol
		ok := false
		if position_context.previous_index != nil {
			symbol, ok = resolve_type_expression(ast_context, position_context.previous_index)
			if !ok {
				return is_incomplete
			}
		} else {
			symbol, ok = resolve_type_expression(ast_context, position_context.index.expr)
		}

		#partial switch v in symbol.value {
		case SymbolFixedArrayValue:
			if enum_value, unwrapped_super_enum, ok := unwrap_enum(ast_context, v.len); ok {
				for name in enum_value.names {
					item := CompletionItem {
						label  = name,
						kind   = .EnumMember,
						detail = name,
					}
					if unwrapped_super_enum {
						add_implicit_selector_remove_edit(position_context, &item, name, enum_value.names)
					}

					append(results, CompletionResult{completion_item = item})
				}

				return is_incomplete
			}
		case SymbolMapValue:
			if enum_value, unwrapped_super_enum, ok := unwrap_enum(ast_context, v.key); ok {
				for name in enum_value.names {
					item := CompletionItem {
						label  = name,
						kind   = .EnumMember,
						detail = name,
					}
					if unwrapped_super_enum {
						add_implicit_selector_remove_edit(position_context, &item, name, enum_value.names)
					}

					append(results, CompletionResult{completion_item = item})
				}

				return is_incomplete
			}
		}
	}

	if position_context.call != nil {
		if call, ok := position_context.call.derived.(^ast.Call_Expr); ok {
			parameter_index, parameter_ok := find_position_in_call_param(position_context, call^)
			if symbol, ok := resolve_type_expression(ast_context, call.expr); ok && parameter_ok {
				set_ast_package_set_scoped(ast_context, symbol.pkg)

				//Selector call expression always set the first argument to be the type of struct called, so increment it.
				if position_context.selector_expr != nil {
					if selector_call, ok := position_context.selector_expr.derived.(^ast.Selector_Call_Expr); ok {
						if selector_call.call == position_context.call {
							parameter_index += 1
						}
					}
				}

				if proc_value, ok := symbol.value.(SymbolProcedureValue); ok {
					arg_type, arg_type_ok := get_proc_arg_type_from_index(proc_value, parameter_index)
					if !arg_type_ok {
						return is_incomplete
					}
					if position_context.field_value != nil {
						// we are using a named param so we want to ensure we use that type and not the
						// type at the index
						if name, ok := position_context.field_value.field.derived.(^ast.Ident); ok {
							if i, ok := get_field_list_name_index(name.name, proc_value.arg_types); ok {
								arg_type = proc_value.arg_types[i]
							}
						}
					}
					type := arg_type.type
					if type == nil {
						if comp_lit, ok := arg_type.default_value.derived.(^ast.Comp_Lit); ok {
							type = comp_lit.type
						} else if selector, ok := arg_type.default_value.derived.(^ast.Selector_Expr); ok {
							type = selector.expr
						}
					}

					if enum_value, unwrapped_super_enum, ok := unwrap_enum(ast_context, type); ok {
						for name in enum_value.names {
							if position_context.comp_lit != nil &&
							   field_exists_in_comp_lit(position_context.comp_lit, name) {
								continue
							}
							item := CompletionItem {
								label  = name,
								kind   = .EnumMember,
								detail = name,
							}
							if unwrapped_super_enum {
								add_implicit_selector_remove_edit(position_context, &item, name, enum_value.names)
							}

							append(results, CompletionResult{completion_item = item})
						}
						return is_incomplete
					}
				} else if enum_value, ok := symbol.value.(SymbolEnumValue); ok {
					for name in enum_value.names {
						item := CompletionItem {
							label  = name,
							kind   = .EnumMember,
							detail = name,
						}

						append(results, CompletionResult{completion_item = item})
					}

					return is_incomplete
				}
			}
		}

		reset_ast_context(ast_context)
	}
	return is_incomplete
}

add_implicit_selector_remove_edit :: proc(
	position_context: ^DocumentPositionContext,
	item: ^CompletionItem,
	name: string,
	valid_names: []string,
) {
	get_name :: proc(full_name: string) -> string {
		split_name := strings.split(full_name, ".")
		return split_name[len(split_name) - 1]
	}

	enum_variant_name := get_name(name)
	found_match := false
	for valid_name in valid_names {
		if name == valid_name {
			continue
		}
		if enum_variant_name == get_name(valid_name) {
			found_match = true
			break
		}
	}

	if found_match {
		remove_edit, ok := create_implicit_selector_remove_edit(position_context)
		if !ok {
			return
		}
		item.additionalTextEdits = remove_edit
	} else {
		item.insertText = enum_variant_name
	}
}

create_implicit_selector_remove_edit :: proc(position_context: ^DocumentPositionContext) -> ([]TextEdit, bool) {
	if position_context.implicit_selector_expr != nil {
		range := common.get_token_range(position_context.implicit_selector_expr, position_context.file.src)

		end := range.start
		end.character += len(position_context.implicit_selector_expr.field.name)
		remove_range := common.Range {
			start = range.start,
			end   = end,
		}

		remove_edit := TextEdit {
			range   = remove_range,
			newText = "",
		}

		additionalTextEdits := make([]TextEdit, 1, context.temp_allocator)
		additionalTextEdits[0] = remove_edit

		return additionalTextEdits, true
	}

	return nil, false
}

get_identifier_completion :: proc(
	ast_context: ^AstContext,
	position_context: ^DocumentPositionContext,
	results: ^[dynamic]CompletionResult,
	config: ^common.Config,
) -> bool {
	lookup_name := ""
	is_incomplete := true

	if position_context.value_decl != nil {
		for value in position_context.value_decl.values {
			if struct_type, ok := value.derived.(^ast.Struct_Type); ok {
				if struct_type.fields != nil {
					for field in struct_type.fields.list {
						for name in field.names {
							if position_in_node(name, position_context.position) {
								return false
							}
						}
					}
				}
			} else if bit_field_type, ok := value.derived.(^ast.Bit_Field_Type); ok {
				for field in bit_field_type.fields {
					if position_in_node(field.name, position_context.position) {
						return false
					}
				}
			}
		}
	}

	if position_context.identifier != nil {
		if ident, ok := position_context.identifier.derived.(^ast.Ident); ok {
			lookup_name = ident.name
		} else if poly, ok := position_context.identifier.derived.(^ast.Poly_Type); ok {
			if poly.specialization != nil {
				if ident, ok := poly.specialization.derived.(^ast.Ident); ok {
					lookup_name = ident.name
				}
			}
		}
	}

	pkgs := make([dynamic]string, context.temp_allocator)

	usings := get_using_packages(ast_context)

	for u in usings {
		append(&pkgs, u)
	}

	append(&pkgs, ast_context.document_package)
	append(&pkgs, "$builtin")

	if fuzzy_results, ok := fuzzy_search(lookup_name, pkgs[:], ast_context.fullpath); ok {
		for r in fuzzy_results {
			r := r
			resolve_unresolved_symbol(ast_context, &r.symbol)
			uri, _ := common.parse_uri(r.symbol.uri, context.temp_allocator)
			if uri.path != ast_context.fullpath {
				append(results, CompletionResult{score = r.score, symbol = r.symbol})
			}
		}
	}

	matcher := common.make_fuzzy_matcher(lookup_name)


	if position_context.call != nil {
		if call, ok := position_context.call.derived.(^ast.Call_Expr); ok {
			if call_symbol, ok := resolve_type_expression(ast_context, call.expr); ok {
				if value, ok := call_symbol.value.(SymbolProcedureValue); ok {
					for arg in value.orig_arg_types {
						// For now we just add params with default values, could add everything we more logic in the future
						if arg.default_value != nil {
							for name in arg.names {
								if ident, ok := name.derived.(^ast.Ident); ok {
									if symbol, ok := resolve_type_expression(ast_context, arg.default_value); ok {
										if score, ok := common.fuzzy_match(matcher, ident.name); ok == 1 {
											symbol.type_name = symbol.name
											symbol.type_pkg = symbol.pkg
											symbol.name = clean_ident(ident.name)
											symbol.type = .Field
											append(results, CompletionResult{score = score * 1.1, symbol = symbol})
										}
									}
								}
							}
						}
					}
				}
			}
		}
	}

	global: for k, v in ast_context.globals {
		if position_context.global_lhs_stmt {
			break
		}

		//combined is sorted and should do binary search instead.
		for result in results {
			if result.symbol.name == k {
				continue global
			}
		}

		reset_ast_context(ast_context)

		ast_context.current_package = ast_context.document_package

		ident := new_type(ast.Ident, v.expr.pos, v.expr.end, context.temp_allocator)
		ident.name = k

		if symbol, ok := resolve_type_identifier(ast_context, ident^); ok {
			if score, ok := common.fuzzy_match(matcher, ident.name); ok == 1 {
				symbol.type_name = symbol.name
				symbol.type_pkg = symbol.pkg
				symbol.name = clean_ident(ident.name)
				append(results, CompletionResult{score = score * 1.1, symbol = symbol})
			}
		}
	}

	#reverse for local in ast_context.locals {
		for k, v in local {
			if position_context.global_lhs_stmt {
				break
			}

			local_offset := get_local_offset(ast_context, position_context.position, k)

			if local_offset == -1 {
				continue
			}

			reset_ast_context(ast_context)

			ast_context.current_package = ast_context.document_package

			ident := new_type(ast.Ident, {offset = local_offset}, {offset = local_offset}, context.temp_allocator)
			ident.name = k

			if symbol, ok := resolve_type_identifier(ast_context, ident^); ok {
				if score, ok := common.fuzzy_match(matcher, ident.name); ok == 1 {
					construct_ident_symbol_info(&symbol, clean_ident(ident.name), ast_context.document_package)
					append(results, CompletionResult{score = score * 1.7, symbol = symbol})
				}
			}
		}
	}

	for pkg in ast_context.imports {
		if position_context.global_lhs_stmt {
			break
		}

		symbol := Symbol {
			name = pkg.base,
			type = .Package,
		}

		if score, ok := common.fuzzy_match(matcher, symbol.name); ok == 1 {
			append(results, CompletionResult{score = score * 1.1, symbol = symbol})
		}
	}

	for keyword, docs in keywords_docs {
		item := CompletionItem {
			label         = keyword,
			kind          = .Keyword,
			documentation = docs,
		}

		if score, ok := common.fuzzy_match(matcher, keyword); ok == 1 {
			append(results, CompletionResult{score = score * 1.1, completion_item = item})
		}
	}

	if config.enable_snippets {
		for k, v in snippets {
			if score, ok := common.fuzzy_match(matcher, k); ok == 1 {
				symbol := Symbol {
					name = k,
				}
				append(results, CompletionResult{score = score * 1.1, snippet = v, symbol = symbol})
			}
		}
	}

	return is_incomplete
}

get_package_completion :: proc(
	ast_context: ^AstContext,
	position_context: ^DocumentPositionContext,
	results: ^[dynamic]CompletionResult,
	config: ^common.Config,
) -> bool {
	is_incomplete := false

	without_quotes := position_context.import_stmt.fullpath

	// Strip the opening quote, if one exists.
	if len(without_quotes) > 0 && without_quotes[0] == '"' {
		without_quotes = without_quotes[1:]
	}

	// Strip the closing quote, if one exists.
	if len(without_quotes) > 0 && without_quotes[len(without_quotes) - 1] == '"' {
		without_quotes = without_quotes[:len(without_quotes) - 1]
	}

	absolute_path := without_quotes
	colon_index := strings.index(without_quotes, ":")

	if colon_index >= 0 {
		c := without_quotes[0:colon_index]

		if colon_index + 1 < len(without_quotes) {
			absolute_path = filepath.join(
				elems = {
					config.collections[c],
					filepath.dir(without_quotes[colon_index + 1:], context.temp_allocator),
				},
				allocator = context.temp_allocator,
			)
		} else {
			absolute_path = config.collections[c]
		}
	} else {
		import_file_dir := filepath.dir(position_context.import_stmt.pos.file, context.temp_allocator)
		import_dir := filepath.dir(without_quotes, context.temp_allocator)
		absolute_path = filepath.join(elems = {import_file_dir, import_dir}, allocator = context.temp_allocator)
	}

	if !strings.contains(position_context.import_stmt.fullpath, "/") &&
	   !strings.contains(position_context.import_stmt.fullpath, ":") {
		for key, _ in config.collections {
			item := CompletionItem {
				detail = "collection",
				label  = key,
				kind   = .Module,
			}

			append(results, CompletionResult{completion_item = item})
		}
	}

	for pkg in search_for_packages(absolute_path) {
		item := CompletionItem {
			detail = pkg,
			label  = filepath.base(pkg),
			kind   = .Folder,
		}

		if item.label[0] == '.' {
			continue
		}

		append(results, CompletionResult{completion_item = item})
	}

	return is_incomplete
}

clean_ident :: proc(ident: string) -> string {
	//Identifiers can be attached with $ for poly types, but we don't want to show those on completion.
	name, _ := strings.replace(ident, "$", "", 1, context.temp_allocator)
	return name
}

search_for_packages :: proc(fullpath: string) -> []string {
	packages := make([dynamic]string, context.temp_allocator)

	fh, err := os.open(fullpath)

	if err != 0 {
		return {}
	}

	if files, err := os.read_dir(fh, 0, context.temp_allocator); err == 0 {
		for file in files {
			if file.is_dir {
				append(&packages, file.fullpath)
			}
		}

	}

	return packages[:]
}

get_used_switch_name :: proc(node: ^ast.Expr) -> (string, bool) {
	#partial switch n in node.derived {
	case ^ast.Ident:
		return n.name, true
	case ^ast.Selector_Expr:
		return n.field.name, true
	case ^ast.Pointer_Type:
		return get_used_switch_name(n.elem)
	}
	return "", false
}

get_type_switch_completion :: proc(
	ast_context: ^AstContext,
	position_context: ^DocumentPositionContext,
	results: ^[dynamic]CompletionResult,
) -> bool {
	is_incomplete := false

	used_unions := make(map[string]struct{}, 5, context.temp_allocator)

	if block, ok := position_context.switch_type_stmt.body.derived.(^ast.Block_Stmt); ok {
		for stmt in block.stmts {
			if case_clause, ok := stmt.derived.(^ast.Case_Clause); ok {
				for name in case_clause.list {
					if n, ok := get_used_switch_name(name); ok {
						used_unions[n] = {}
					}
				}
			}
		}
	}

	reset_ast_context(ast_context)

	if assign, ok := position_context.switch_type_stmt.tag.derived.(^ast.Assign_Stmt);
	   ok && assign.rhs != nil && len(assign.rhs) == 1 {
		if union_value, ok := unwrap_union(ast_context, assign.rhs[0]); ok {
			for type, i in union_value.types {
				if symbol, ok := resolve_type_expression(ast_context, union_value.types[i]); ok {

					name := symbol.name
					if _, ok := used_unions[name]; ok {
						continue
					}

					item := CompletionItem {
						kind = .EnumMember,
					}

					if symbol.pkg == ast_context.document_package {
						item.label = fmt.aprintf("%v%v", repeat("^", symbol.pointers, context.temp_allocator), name)
						item.detail = item.label
					} else {
						item.label = fmt.aprintf(
							"%v%v.%v",
							repeat("^", symbol.pointers, context.temp_allocator),
							get_symbol_pkg_name(ast_context, &symbol),
							name,
						)
						item.detail = item.label
					}
					if position_context.implicit_selector_expr != nil {
						if remove_edit, ok := create_implicit_selector_remove_edit(position_context); ok {
							item.additionalTextEdits = remove_edit
						}
					}

					append(results, CompletionResult{completion_item = item})
				}
			}
		}
	}

	return is_incomplete
}

get_core_insert_package_if_non_existent :: proc(ast_context: ^AstContext, pkg: string) -> (TextEdit, bool) {
	builder := strings.builder_make(context.temp_allocator)

	for imp in ast_context.imports {
		if imp.base == pkg {
			return {}, false
		}
	}

	strings.write_string(&builder, fmt.tprintf("import \"core:%v\" \n", pkg))

	return {
			newText = strings.to_string(builder),
			range = {
				start = {line = ast_context.file.pkg_decl.end.line + 1, character = 0},
				end = {line = ast_context.file.pkg_decl.end.line + 1, character = 0},
			},
		},
		true
}

get_range_from_selection_start_to_dot :: proc(position_context: ^DocumentPositionContext) -> (common.Range, bool) {
	if position_context.selector != nil {
		range := common.get_token_range(position_context.selector, position_context.file.src)
		range.end.character += 1
		return range, true
	}

	return {}, false
}

append_non_imported_packages :: proc(
	ast_context: ^AstContext,
	position_context: ^DocumentPositionContext,
	items: ^[dynamic]CompletionItem,
	config: ^common.Config,
) {
	// Keep these as is for now with the completion items as they are a special case
	if !config.enable_auto_import {
		return
	}

	i := len(items)
	for collection, pkgs in build_cache.pkg_aliases {
		for pkg in pkgs {
			fullpath := path.join({config.collections[collection], pkg})
			found := false

			for doc_pkg in ast_context.imports {
				if fullpath == doc_pkg.name {
					found = true
				}
			}

			if !found {
				pkg_decl := ast_context.file.pkg_decl

				import_edit := TextEdit {
					range = {
						start = {line = pkg_decl.end.line + 1, character = 0},
						end = {line = pkg_decl.end.line + 1, character = 0},
					},
					newText = fmt.tprintf("import \"%v:%v\"\n", collection, pkg),
				}

				additionalTextEdits := make([]TextEdit, 1, context.temp_allocator)
				additionalTextEdits[0] = import_edit

				item := CompletionItem {
					label = pkg,
					kind = .Module,
					documentation = MarkupContent {
						kind = "markdown",
						value = fmt.tprintf("```odin\n%v\n```", import_edit.newText),
					},
					insertText = path.base(pkg),
					additionalTextEdits = additionalTextEdits,
					insertTextFormat = .PlainText,
					InsertTextMode = .adjustIndentation,
					sortText = fmt.tprintf("%05d", i),
				}

				append(items, item)
				i += 1
			}
		}
	}
}

append_magic_map_completion :: proc(
	position_context: ^DocumentPositionContext,
	symbol: Symbol,
	results: ^[dynamic]CompletionResult,
) {
	range, ok := get_range_from_selection_start_to_dot(position_context)

	if !ok {
		return
	}

	// allocator
	{
		item := CompletionItem {
			label  = "allocator",
			kind   = .Field,
			detail = fmt.tprintf("%v.%v: %v", "Raw_Map", "allocator", "runtime.Allocator"),
		}
		append(results, CompletionResult{completion_item = item})
	}

	remove_range := common.Range {
		start = range.start,
		end   = range.end,
	}

	remove_edit := TextEdit {
		range   = remove_range,
		newText = "",
	}

	additionalTextEdits := make([]TextEdit, 1, context.temp_allocator)
	additionalTextEdits[0] = remove_edit

	symbol_str := get_expression_string_from_position_context(position_context)
	deref_suffix := ""
	if symbol.pointers > 1 {
		deref_suffix = repeat("^", symbol.pointers - 1, context.temp_allocator)
	}
	dereferenced_symbol_str := fmt.tprint(symbol_str, deref_suffix, sep = "")

	//for
	{
		item := CompletionItem {
			label = "for",
			kind = .Snippet,
			detail = "for",
			additionalTextEdits = additionalTextEdits,
			textEdit = TextEdit {
				newText = fmt.tprintf("for ${{1:k}}, ${{2:v}} in %v {{\n\t$0 \n}}", dereferenced_symbol_str),
				range = {start = range.end, end = range.end},
			},
			insertTextFormat = .Snippet,
			InsertTextMode = .adjustIndentation,
		}

		append(results, CompletionResult{completion_item = item})
	}

	//len
	{
		text := fmt.tprintf("len(%v)", dereferenced_symbol_str)

		item := CompletionItem {
			label = "len",
			kind = .Function,
			detail = "len",
			textEdit = TextEdit{newText = text, range = {start = range.end, end = range.end}},
			additionalTextEdits = additionalTextEdits,
		}

		append(results, CompletionResult{completion_item = item})
	}

	//cap
	{
		text := fmt.tprintf("cap(%v)", dereferenced_symbol_str)

		item := CompletionItem {
			label = "cap",
			kind = .Function,
			detail = "cap",
			textEdit = TextEdit{newText = text, range = {start = range.end, end = range.end}},
			additionalTextEdits = additionalTextEdits,
		}

		append(results, CompletionResult{completion_item = item})
	}

	prefix := "&"
	suffix := ""
	if symbol.pointers > 0 {
		prefix = ""
		suffix = repeat("^", symbol.pointers - 1, context.temp_allocator)
	}
	ptr_symbol_str := fmt.tprint(prefix, symbol_str, suffix, sep = "")

	map_builtins_no_arg := []string{"clear", "shrink"}

	for name in map_builtins_no_arg {
		item := CompletionItem {
			label = name,
			kind = .Function,
			detail = name,
			textEdit = TextEdit {
				newText = fmt.tprintf("%s(%v)", name, ptr_symbol_str),
				range = {start = range.end, end = range.end},
			},
			additionalTextEdits = additionalTextEdits,
		}

		append(results, CompletionResult{completion_item = item})
	}

	map_builtins_with_args := []string{"delete_key", "reserve", "map_insert", "map_upsert", "map_entry"}

	for name in map_builtins_with_args {
		item := CompletionItem {
			label = name,
			kind = .Snippet,
			detail = name,
			additionalTextEdits = additionalTextEdits,
			textEdit = TextEdit {
				newText = fmt.tprintf("%s(%v, $0)", name, ptr_symbol_str),
				range = {start = range.end, end = range.end},
			},
			insertTextFormat = .Snippet,
			InsertTextMode = .adjustIndentation,
		}

		append(results, CompletionResult{completion_item = item})
	}
}

get_expression_string_from_position_context :: proc(position_context: ^DocumentPositionContext) -> string {
	src := position_context.file.src
	if position_context.call != nil {
		if call_expr, ok := position_context.call.derived.(^ast.Call_Expr); ok {
			if position_in_node(call_expr.expr, position_context.position) {
				return src[position_context.call.pos.offset:position_context.call.end.offset]
			}
		}

	}

	if position_context.selector != nil {
		return src[position_context.selector.pos.offset:position_context.selector.end.offset]
	}

	if position_context.field != nil {
		return src[position_context.field.pos.offset:position_context.field.end.offset]
	}

	return ""
}

append_magic_array_like_completion :: proc(
	position_context: ^DocumentPositionContext,
	symbol: Symbol,
	results: ^[dynamic]CompletionResult,
) {
	// Can't iterate over an soa pointer
	// eg foos: #soa^#soa[]struct{}
	if .SoaPointer in symbol.flags {
		return
	}

	range, ok := get_range_from_selection_start_to_dot(position_context)

	if !ok {
		return
	}

	remove_range := common.Range {
		start = range.start,
		end   = range.end,
	}

	remove_edit := TextEdit {
		range   = remove_range,
		newText = "",
	}

	additionalTextEdits := make([]TextEdit, 1, context.temp_allocator)
	additionalTextEdits[0] = remove_edit

	symbol_str := get_expression_string_from_position_context(position_context)
	deref_suffix := ""
	if symbol.pointers > 1 {
		deref_suffix = repeat("^", symbol.pointers - 1, context.temp_allocator)
	}
	dereferenced_symbol_str := fmt.tprint(symbol_str, deref_suffix, sep = "")

	//len
	{
		text := fmt.tprintf("len(%v)", dereferenced_symbol_str)

		item := CompletionItem {
			label = "len",
			kind = .Function,
			detail = "len",
			textEdit = TextEdit{newText = text, range = {start = range.end, end = range.end}},
			additionalTextEdits = additionalTextEdits,
		}

		append(results, CompletionResult{completion_item = item})
	}

	//for
	{
		item := CompletionItem {
			label = "for",
			kind = .Snippet,
			detail = "for",
			additionalTextEdits = additionalTextEdits,
			textEdit = TextEdit {
				newText = fmt.tprintf("for i in %v {{\n\t$0 \n}}", dereferenced_symbol_str),
				range = {start = range.end, end = range.end},
			},
			insertTextFormat = .Snippet,
			InsertTextMode = .adjustIndentation,
		}

		append(results, CompletionResult{completion_item = item})
	}

	// This proc is shared between slices and dynamic arrays.
	if _, ok := symbol.value.(SymbolDynamicArrayValue); !ok {
		return
	}

	//cap
	{
		text := fmt.tprintf("cap(%v)", dereferenced_symbol_str)

		item := CompletionItem {
			label = "cap",
			kind = .Function,
			detail = "cap",
			textEdit = TextEdit{newText = text, range = {start = range.end, end = range.end}},
			additionalTextEdits = additionalTextEdits,
		}

		append(results, CompletionResult{completion_item = item})
	}

	// allocator
	{
		item := CompletionItem {
			label  = "allocator",
			kind   = .Field,
			detail = fmt.tprintf("%v.%v: %v", "Raw_Dynamic_Array", "allocator", "runtime.Allocator"),
		}
		append(results, CompletionResult{completion_item = item})
	}

	prefix := "&"
	suffix := ""
	if symbol.pointers > 0 {
		prefix = ""
		suffix = repeat("^", symbol.pointers - 1, context.temp_allocator)
	}
	ptr_symbol_str := fmt.tprint(prefix, symbol_str, suffix, sep = "")

	dynamic_array_builtins_no_arg := []string{"pop", "pop_safe", "pop_front", "pop_front_safe", "clear"}

	for name in dynamic_array_builtins_no_arg {
		item := CompletionItem {
			label = name,
			kind = .Function,
			detail = name,
			textEdit = TextEdit {
				newText = fmt.tprintf("%s(%v)", name, ptr_symbol_str),
				range = {start = range.end, end = range.end},
			},
			additionalTextEdits = additionalTextEdits,
		}

		append(results, CompletionResult{completion_item = item})
	}

	dynamic_array_builtins := []string {
		"append",
		"unordered_remove",
		"ordered_remove",
		"remove_range",
		"resize",
		"reserve",
		"shrink",
		"inject_at",
		"assign_at",
		"non_zero_append",
		"non_zero_reserve",
		"non_zero_resize",
	}

	for name in dynamic_array_builtins {
		item := CompletionItem {
			label = name,
			kind = .Snippet,
			detail = name,
			additionalTextEdits = additionalTextEdits,
			textEdit = TextEdit {
				newText = fmt.tprintf("%s(%v, $0)", name, ptr_symbol_str),
				range = {start = range.end, end = range.end},
			},
			insertTextFormat = .Snippet,
			InsertTextMode = .adjustIndentation,
		}

		append(results, CompletionResult{completion_item = item})
	}
}

append_magic_union_completion :: proc(
	position_context: ^DocumentPositionContext,
	symbol: Symbol,
	items: ^[dynamic]CompletionResult,
) {
	range, ok := get_range_from_selection_start_to_dot(position_context)

	if !ok {
		return
	}

	remove_range := common.Range {
		start = range.start,
		end   = range.end,
	}

	remove_edit := TextEdit {
		range   = remove_range,
		newText = "",
	}

	additionalTextEdits := make([]TextEdit, 1, context.temp_allocator)
	additionalTextEdits[0] = remove_edit

	//switch
	{
		item := CompletionItem {
			label = "switch",
			kind = .Snippet,
			detail = "switch",
			additionalTextEdits = additionalTextEdits,
			textEdit = TextEdit {
				newText = fmt.tprintf("switch v in %v {{\n\t$0 \n}}", symbol.name),
				range = {start = range.end, end = range.end},
			},
			insertTextFormat = .Snippet,
			InsertTextMode = .adjustIndentation,
		}

		append(items, CompletionResult{completion_item = item})
	}

}

bitset_operators: map[string]struct{} = {
	"|"  = {},
	"&"  = {},
	"~"  = {},
	"<"  = {},
	">"  = {},
	"==" = {},
}

bitset_assignment_operators: map[string]struct{} = {
	"|=" = {},
	"&=" = {},
	"~=" = {},
	"<=" = {},
	">=" = {},
	"="  = {},
	"+=" = {},
}

is_bitset_binary_operator :: proc(op: string) -> bool {
	return op in bitset_operators
}

is_bitset_assignment_operator :: proc(op: string) -> bool {
	return op in bitset_assignment_operators
}

swizzle_color_map: map[u8]struct{} = {
	'r' = {},
	'g' = {},
	'b' = {},
	'a' = {},
}

swizzle_color_components: []string = {"r", "g", "b", "a"}

swizzle_coord_map: map[u8]struct{} = {
	'x' = {},
	'y' = {},
	'z' = {},
	'w' = {},
}

swizzle_coord_components: []string = {"x", "y", "z", "w"}
