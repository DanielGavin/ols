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

/*
	TODOS: Making the signature details is really annoying and not that nice - try to see if this can be refractored.

*/

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
) -> (
	CompletionList,
	bool,
) {
	list: CompletionList

	position_context, ok := get_document_position_context(
		document,
		position,
		.Completion,
	)

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
		   position_context.position ==
			   position_context.import_stmt.end.offset &&
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

	get_globals(document.ast, &ast_context)

	ast_context.current_package = ast_context.document_package
	ast_context.value_decl = position_context.value_decl

	if position_context.function != nil {
		get_locals(
			document.ast,
			position_context.function,
			&ast_context,
			&position_context,
		)
	}

	completion_type: Completion_Type = .Identifier

	if position_context.comp_lit != nil && is_lhs_comp_lit(&position_context) {
		completion_type = .Comp_Lit
	}

	if position_context.selector != nil {
		completion_type = .Selector
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

	done: if position_context.switch_type_stmt != nil &&
	   position_context.case_clause != nil {

		if position_context.switch_stmt != nil &&
		   position_context.switch_type_stmt.pos.offset <=
			   position_context.switch_stmt.pos.offset {
			break done
		}

		if assign, ok := position_context.switch_type_stmt.tag.derived.(^ast.Assign_Stmt);
		   ok && assign.rhs != nil && len(assign.rhs) == 1 {
			ast_context.use_locals = true

			if symbol, ok := resolve_type_expression(
				&ast_context,
				assign.rhs[0],
			); ok {
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

	switch completion_type {
	case .Comp_Lit:
		get_comp_lit_completion(&ast_context, &position_context, &list)
	case .Identifier:
		get_identifier_completion(&ast_context, &position_context, &list)
	case .Implicit:
		get_implicit_completion(&ast_context, &position_context, &list)
	case .Selector:
		get_selector_completion(&ast_context, &position_context, &list)
	case .Switch_Type:
		get_type_switch_completion(&ast_context, &position_context, &list)
	case .Directive:
		get_directive_completion(&ast_context, &position_context, &list)
	case .Package:
		get_package_completion(&ast_context, &position_context, &list)
	}

	if common.config.enable_label_details {
		format_to_label_details(&list)
	}

	return list, true
}

get_attribute_completion :: proc(
	ast_context: ^AstContext,
	position_context: ^DocumentPositionContext,
	list: ^CompletionList,
) {


}

get_directive_completion :: proc(
	ast_context: ^AstContext,
	position_context: ^DocumentPositionContext,
	list: ^CompletionList,
) {

	list.isIncomplete = false

	items := make([dynamic]CompletionItem, context.temp_allocator)

	/*
		Right now just return all the possible completions, but later on I should give the context specific ones
	*/

	directive_list := []string {
		"file",
		"line",
		"packed",
		"raw_union",
		"align",
		"no_nil",
		"shared_nil",
		"complete",
		"no_alias",
		"caller_location",
		"require_results",
		"type",
		"bounds_check",
		"no_bounds_check",
		"assert",
		"defined",
		"procedure",
		"load",
		"partial",
		"force_inline",
	}

	for elem in directive_list {
		item := CompletionItem {
			detail = elem,
			label  = elem,
			kind   = .Constant,
		}

		append(&items, item)
	}

	list.items = items[:]
}

get_comp_lit_completion :: proc(
	ast_context: ^AstContext,
	position_context: ^DocumentPositionContext,
	list: ^CompletionList,
) {
	items := make([dynamic]CompletionItem, context.temp_allocator)


	if symbol, ok := resolve_comp_literal(ast_context, position_context); ok {
		//ast_context.current_package = comp_symbol.pkg
		#partial switch v in symbol.value {
		case SymbolStructValue:
			for name, i in v.names {
				if name == "_" {
					continue
				}

				ast_context.current_package = symbol.pkg

				if resolved, ok := resolve_type_expression(
					ast_context,
					v.types[i],
				); ok {
					if field_exists_in_comp_lit(
						position_context.comp_lit,
						name,
					) {
						continue
					}

					item := CompletionItem {
						label         = name,
						kind          = .Field,
						detail        = fmt.tprintf(
							"%v.%v: %v",
							symbol.name,
							name,
							common.node_to_string(v.types[i]),
						),
						documentation = resolved.doc,
					}

					append(&items, item)
				}
			}
		case SymbolBitFieldValue:
			for name, i in v.names {
				if name == "_" {
					continue
				}

				ast_context.current_package = symbol.pkg

				if resolved, ok := resolve_type_expression(
					ast_context,
					v.types[i],
				); ok {
					if field_exists_in_comp_lit(
						position_context.comp_lit,
						name,
					) {
						continue
					}

					item := CompletionItem {
						label         = name,
						kind          = .Field,
						detail        = fmt.tprintf(
							"%v.%v: %v",
							symbol.name,
							name,
							common.node_to_string(v.types[i]),
						),
						documentation = resolved.doc,
					}

					append(&items, item)
				}
			}
		}
	}

	list.items = items[:]
}

get_selector_completion :: proc(
	ast_context: ^AstContext,
	position_context: ^DocumentPositionContext,
	list: ^CompletionList,
) {
	items := make([dynamic]CompletionItem, context.temp_allocator)

	ast_context.current_package = ast_context.document_package

	selector: Symbol
	ok: bool

	reset_ast_context(ast_context)

	selector, ok = resolve_type_expression(
		ast_context,
		position_context.selector,
	)

	if !ok {
		return
	}

	if selector.type != .Variable &&
	   selector.type != .Package &&
	   selector.type != .Enum &&
	   selector.type != .Function {
		return
	}

	if selector.pkg != "" {
		ast_context.current_package = selector.pkg
	} else {
		ast_context.current_package = ast_context.document_package
	}

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
			if selector, ok = resolve_type_expression(
				ast_context,
				s.return_types[0].type,
			); !ok {
				return
			}
		}
	}

	if common.config.enable_fake_method {
		append_method_completion(
			ast_context,
			selector,
			position_context,
			&items,
			receiver,
		)
	}

	#partial switch v in selector.value {
	case SymbolFixedArrayValue:
		list.isIncomplete = true

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
					detail = fmt.tprintf(
						"%v%v: %v",
						field,
						k,
						common.node_to_string(v.expr),
					),
				}
				append(&items, item)
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
					detail = fmt.tprintf(
						"%v%v: %v",
						field,
						k,
						common.node_to_string(v.expr),
					),
				}
				append(&items, item)
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
					detail = fmt.tprintf(
						"%v%v: [%v]%v",
						field,
						k,
						containsColor,
						common.node_to_string(v.expr),
					),
				}
				append(&items, item)
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
					detail = fmt.tprintf(
						"%v%v: [%v]%v",
						field,
						k,
						containsCoord,
						common.node_to_string(v.expr),
					),
				}
				append(&items, item)
			}
		}
	case SymbolUnionValue:
		list.isIncomplete = false

		append_magic_union_completion(position_context, selector, &items)

		for type in v.types {
			if symbol, ok := resolve_type_expression(ast_context, type); ok {
				base := get_symbol_pkg_name(ast_context, symbol)

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
				   is_selector {
					item.label = fmt.aprintf(
						"(%v%v)",
						common.repeat(
							"^",
							symbol.pointers,
							context.temp_allocator,
						),
						common.node_to_string(type, true),
					)
				} else {
					item.label = fmt.aprintf(
						"(%v%v.%v)",
						common.repeat(
							"^",
							symbol.pointers,
							context.temp_allocator,
						),
						get_symbol_pkg_name(ast_context, symbol),
						common.node_to_string(type, true),
					)
				}

				append(&items, item)
			}
		}

	case SymbolEnumValue:
		list.isIncomplete = false

		for name in v.names {
			item := CompletionItem {
				label  = name,
				kind   = .EnumMember,
				detail = fmt.tprintf("%v.%v", selector.name, name),
			}
			append(&items, item)
		}

	case SymbolBitSetValue:
		list.isIncomplete = false

		enumv, ok := unwrap_bitset(ast_context, selector)
		if !ok {break}

		range, rok := get_range_from_selection_start_to_dot(position_context)
		if !rok {break}

		range.end.character -= 1

		variable, vok := position_context.selector.derived_expr.(^ast.Ident)
		if !vok {break}

		remove_edit := TextEdit {
			range = {start = range.start, end = range.end},
			newText = "",
		}

		additionalTextEdits := make([]TextEdit, 1, context.temp_allocator)
		additionalTextEdits[0] = remove_edit

		for name in enumv.names {
			append(
				&items,
				CompletionItem {
					label = fmt.tprintf(".%s", name),
					kind = .EnumMember,
					detail = fmt.tprintf("%s.%s", selector.name, name),
					additionalTextEdits = additionalTextEdits,
				},
			)
		}

	case SymbolStructValue:
		list.isIncomplete = false

		for name, i in v.names {
			if name == "_" {
				continue
			}

			if selector.pkg != "" {
				ast_context.current_package = selector.pkg
			} else {
				ast_context.current_package = ast_context.document_package
			}

			if symbol, ok := resolve_type_expression(ast_context, v.types[i]);
			   ok {
				if expr, ok := position_context.selector.derived.(^ast.Selector_Expr);
				   ok {
					if expr.op.text == "->" && symbol.type != .Function {
						continue
					}
				}

				if position_context.arrow {
					if symbol.type != .Function {
						continue
					}
					if .ObjCIsClassMethod in symbol.flags {
						assert(.ObjC in symbol.flags)
						continue
					}
				}
				if !position_context.arrow && .ObjC in symbol.flags {
					continue
				}


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

				append(&items, item)
			} else {
				//just give some generic symbol with name.
				item := CompletionItem {
					label         = symbol.name,
					kind          = .Field,
					detail        = fmt.tprintf(
						"%v: %v",
						name,
						common.node_to_string(v.types[i]),
					),
					documentation = symbol.doc,
				}

				append(&items, item)
			}
		}

	case SymbolBitFieldValue:
		list.isIncomplete = false

		for name, i in v.names {
			if name == "_" {
				continue
			}

			if selector.pkg != "" {
				ast_context.current_package = selector.pkg
			} else {
				ast_context.current_package = ast_context.document_package
			}

			if symbol, ok := resolve_type_expression(ast_context, v.types[i]);
			   ok {
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

				append(&items, item)
			} else {
				//just give some generic symbol with name.
				item := CompletionItem {
					label         = symbol.name,
					kind          = .Field,
					detail        = fmt.tprintf(
						"%v: %v",
						name,
						common.node_to_string(v.types[i]),
					),
					documentation = symbol.doc,
				}

				append(&items, item)
			}
		}

	case SymbolPackageValue:
		list.isIncomplete = true

		pkg := selector.pkg

		if searched, ok := fuzzy_search(field, {pkg}); ok {
			for search in searched {
				symbol := search.symbol

				if .PrivatePackage in symbol.flags {
					continue
				}

				resolve_unresolved_symbol(ast_context, &symbol)
				build_procedure_symbol_signature(&symbol)

				item := CompletionItem {
					label         = symbol.name,
					kind          = symbol_type_to_completion_kind(
						symbol.type,
					),
					detail        = concatenate_symbol_information(
						ast_context,
						symbol,
						true,
					),
					documentation = symbol.doc,
				}

				if symbol.type == .Function &&
				   common.config.enable_snippets &&
				   common.config.enable_procedure_snippet {
					item.insertText = fmt.tprintf("%v($0)", item.label)
					item.insertTextFormat = .Snippet
					item.command = Command {
						command = "editor.action.triggerParameterHints",
					}
					item.deprecated = .Deprecated in symbol.flags
				}

				append(&items, item)
			}
		} else {
			log.errorf(
				"Failed to fuzzy search, field: %v, package: %v",
				field,
				selector.pkg,
			)
			return
		}
	case SymbolDynamicArrayValue:
		list.isIncomplete = false
		append_magic_dynamic_array_completion(
			position_context,
			selector,
			&items,
		)
	case SymbolSliceValue:
		list.isIncomplete = false
		append_magic_dynamic_array_completion(
			position_context,
			selector,
			&items,
		)

	case SymbolMapValue:
		list.isIncomplete = false
		append_magic_map_completion(position_context, selector, &items)
	}

	list.items = items[:]
}

get_implicit_completion :: proc(
	ast_context: ^AstContext,
	position_context: ^DocumentPositionContext,
	list: ^CompletionList,
) {
	items := make([dynamic]CompletionItem, context.temp_allocator)

	list.isIncomplete = false

	selector: Symbol

	reset_ast_context(ast_context)

	if selector.pkg != "" {
		ast_context.current_package = selector.pkg
	} else {
		ast_context.current_package = ast_context.document_package
	}

	//value decl infer a : My_Enum = .*
	if position_context.value_decl != nil &&
	   position_context.value_decl.type != nil {
		enum_value: Maybe(SymbolEnumValue)

		if _enum_value, ok := unwrap_enum(
			ast_context,
			position_context.value_decl.type,
		); ok {
			enum_value = _enum_value
		}

		if position_context.comp_lit != nil {
			if bitset_symbol, ok := resolve_type_expression(
				ast_context,
				position_context.value_decl.type,
			); ok {
				if _enum_value, ok := unwrap_bitset(
					ast_context,
					bitset_symbol,
				); ok {
					enum_value = _enum_value
				}
			}
		}

		if ev, ok := enum_value.?; ok {
			for name in ev.names {
				item := CompletionItem {
					label  = name,
					kind   = .EnumMember,
					detail = name,
				}
				append(&items, item)
			}

			list.items = items[:]
			return
		}
	}

	//enum switch infer
	if position_context.switch_stmt != nil &&
	   position_context.case_clause != nil &&
	   position_context.switch_stmt.cond != nil {
		used_enums := make(map[string]bool, 5, context.temp_allocator)

		if block, ok := position_context.switch_stmt.body.derived.(^ast.Block_Stmt);
		   ok {
			for stmt in block.stmts {
				if case_clause, ok := stmt.derived.(^ast.Case_Clause); ok {
					for name in case_clause.list {
						if implicit, ok := name.derived.(^ast.Implicit_Selector_Expr);
						   ok {
							used_enums[implicit.field.name] = true
						}
					}
				}
			}
		}

		if enum_value, ok := unwrap_enum(
			ast_context,
			position_context.switch_stmt.cond,
		); ok {
			for name in enum_value.names {
				if name in used_enums {
					continue
				}

				item := CompletionItem {
					label  = name,
					kind   = .EnumMember,
					detail = name,
				}

				append(&items, item)
			}

			list.items = items[:]
			return
		}
	}

	if position_context.assign != nil &&
	   position_context.assign.lhs != nil &&
	   len(position_context.assign.lhs) == 1 &&
	   is_bitset_assignment_operator(position_context.assign.op.text) {
		//bitsets
		if symbol, ok := resolve_type_expression(
			ast_context,
			position_context.assign.lhs[0],
		); ok {
			ast_context.current_package = symbol.pkg
			if value, ok := unwrap_bitset(ast_context, symbol); ok {
				for name in value.names {

					item := CompletionItem {
						label  = name,
						kind   = .EnumMember,
						detail = name,
					}

					append(&items, item)
				}

				list.items = items[:]
				return
			}
		}

		reset_ast_context(ast_context)
	}

	if position_context.comp_lit != nil &&
	   position_context.parent_binary != nil &&
	   is_bitset_binary_operator(position_context.binary.op.text) {
		//bitsets
		if symbol, ok := resolve_first_symbol_from_binary_expression(
			ast_context,
			position_context.parent_binary,
		); ok {
			ast_context.current_package = symbol.pkg
			if value, ok := unwrap_bitset(ast_context, symbol); ok {
				for name in value.names {
					item := CompletionItem {
						label  = name,
						kind   = .EnumMember,
						detail = name,
					}

					append(&items, item)
				}

				list.items = items[:]
				return
			}
		}

		reset_ast_context(ast_context)
	}

	//infer bitset and enums based on the identifier comp_lit, i.e. a := My_Struct { my_ident = . } 
	if position_context.comp_lit != nil {
		if position_context.parent_comp_lit.type != nil {
			field_name: string

			if position_context.field_value != nil {
				if field, ok := position_context.field_value.field.derived.(^ast.Ident);
				   ok {
					field_name = field.name
				} else {
					return
				}
			}

			if symbol, ok := resolve_type_expression(
				ast_context,
				position_context.parent_comp_lit.type,
			); ok {
				if comp_symbol, comp_lit, ok := resolve_type_comp_literal(
					ast_context,
					position_context,
					symbol,
					position_context.parent_comp_lit,
				); ok {
					if s, ok := comp_symbol.value.(SymbolStructValue); ok {
						ast_context.current_package = comp_symbol.pkg

						//We can either have the final 
						elem_index := -1

						for elem, i in comp_lit.elems {
							if position_in_node(
								elem,
								position_context.position,
							) {
								elem_index = i
							}
						}

						type: ^ast.Expr

						for name, i in s.names {
							if name != field_name {
								continue
							}

							type = s.types[i]
							break
						}

						if type == nil &&
						   len(s.types) > elem_index &&
						   elem_index != -1 {
							type = s.types[elem_index]
						}

						if enum_value, ok := unwrap_enum(ast_context, type);
						   ok {
							for enum_name in enum_value.names {
								item := CompletionItem {
									label  = enum_name,
									kind   = .EnumMember,
									detail = enum_name,
								}

								append(&items, item)
							}

							list.items = items[:]
							return
						} else if bitset_symbol, ok := resolve_type_expression(
							ast_context,
							type,
						); ok {
							ast_context.current_package = bitset_symbol.pkg

							if value, ok := unwrap_bitset(
								ast_context,
								bitset_symbol,
							); ok {
								for name in value.names {

									item := CompletionItem {
										label  = name,
										kind   = .EnumMember,
										detail = name,
									}

									append(&items, item)
								}
								list.items = items[:]
								return
							}
						}
					} else if s, ok := unwrap_bitset(ast_context, comp_symbol);
					   ok {
						for enum_name in s.names {
							item := CompletionItem {
								label  = enum_name,
								kind   = .EnumMember,
								detail = enum_name,
							}

							append(&items, item)
						}

						list.items = items[:]
						return
					}
				}
			}

			reset_ast_context(ast_context)
		}
	}

	if position_context.binary != nil &&
	   (position_context.binary.op.text == "==" ||
			   position_context.binary.op.text == "!=") {
		context_node: ^ast.Expr
		enum_node: ^ast.Expr

		if position_in_node(
			position_context.binary.right,
			position_context.position,
		) {
			context_node = position_context.binary.right
			enum_node = position_context.binary.left
		} else if position_in_node(
			position_context.binary.left,
			position_context.position,
		) {
			context_node = position_context.binary.left
			enum_node = position_context.binary.right
		}

		if context_node != nil && enum_node != nil {
			if enum_value, ok := unwrap_enum(ast_context, enum_node); ok {
				for name in enum_value.names {
					item := CompletionItem {
						label  = name,
						kind   = .EnumMember,
						detail = name,
					}

					append(&items, item)
				}

				list.items = items[:]
				return
			}
		}

		reset_ast_context(ast_context)
	}

	if position_context.assign != nil &&
	   position_context.assign.rhs != nil &&
	   position_context.assign.lhs != nil {
		rhs_index: int

		for elem in position_context.assign.rhs {
			if position_in_node(elem, position_context.position) {
				break
			} else {
				//procedures are the only types that can return more than one value
				if symbol, ok := resolve_type_expression(ast_context, elem);
				   ok {
					if procedure, ok := symbol.value.(SymbolProcedureValue);
					   ok {
						if procedure.return_types == nil {
							return
						}

						rhs_index += len(procedure.return_types)
					} else {
						rhs_index += 1
					}
				}
			}
		}

		if len(position_context.assign.lhs) > rhs_index {
			if enum_value, ok := unwrap_enum(
				ast_context,
				position_context.assign.lhs[rhs_index],
			); ok {
				for name in enum_value.names {
					item := CompletionItem {
						label  = name,
						kind   = .EnumMember,
						detail = name,
					}

					append(&items, item)
				}

				list.items = items[:]
				return
			}
		}

		reset_ast_context(ast_context)
	}

	if position_context.returns != nil && position_context.function != nil {
		return_index: int

		if position_context.returns.results == nil {
			return
		}

		for result, i in position_context.returns.results {
			if position_in_node(result, position_context.position) {
				return_index = i
				break
			}
		}

		if position_context.function.type == nil {
			return
		}

		if position_context.function.type.results == nil {
			return
		}

		if len(position_context.function.type.results.list) > return_index {
			if enum_value, ok := unwrap_enum(
				ast_context,
				position_context.function.type.results.list[return_index].type,
			); ok {
				for name in enum_value.names {
					item := CompletionItem {
						label  = name,
						kind   = .EnumMember,
						detail = name,
					}

					append(&items, item)
				}

				list.items = items[:]
				return
			}
		}

		reset_ast_context(ast_context)
	}

	if position_context.call != nil {
		if call, ok := position_context.call.derived.(^ast.Call_Expr); ok {
			parameter_index, parameter_ok := find_position_in_call_param(
				position_context,
				call^,
			)
			if symbol, ok := resolve_type_expression(ast_context, call.expr);
			   ok && parameter_ok {
				ast_context.current_package = symbol.pkg

				//Selector call expression always set the first argument to be the type of struct called, so increment it.
				if position_context.selector_expr != nil {
					if selector_call, ok := position_context.selector_expr.derived.(^ast.Selector_Call_Expr);
					   ok {
						if selector_call.call == position_context.call {
							parameter_index += 1
						}
					}
				}

				if proc_value, ok := symbol.value.(SymbolProcedureValue); ok {
					if len(proc_value.arg_types) <= parameter_index {
						return
					}

					if enum_value, ok := unwrap_enum(
						ast_context,
						proc_value.arg_types[parameter_index].type,
					); ok {
						for name in enum_value.names {
							item := CompletionItem {
								label  = name,
								kind   = .EnumMember,
								detail = name,
							}

							append(&items, item)
						}

						list.items = items[:]
						return
					}

					// Bitset comp literal in parameter, eg: `hello({ . })`.
					if position_context.comp_lit != nil {
						if bitset_symbol, ok := resolve_type_expression(
							ast_context,
							proc_value.arg_types[parameter_index].type,
						); ok {
							ast_context.current_package = bitset_symbol.pkg
							if enum_value, ok := unwrap_bitset(
								ast_context,
								bitset_symbol,
							); ok {
								for name in enum_value.names {
									item := CompletionItem {
										label  = name,
										kind   = .EnumMember,
										detail = name,
									}

									append(&items, item)
								}

								list.items = items[:]
								return
							}
						}
					}

				} else if enum_value, ok := symbol.value.(SymbolEnumValue);
				   ok {
					for name in enum_value.names {
						item := CompletionItem {
							label  = name,
							kind   = .EnumMember,
							detail = name,
						}

						append(&items, item)
					}

					list.items = items[:]
					return
				}
			}
		}
	}
}

get_identifier_completion :: proc(
	ast_context: ^AstContext,
	position_context: ^DocumentPositionContext,
	list: ^CompletionList,
) {
	CombinedResult :: struct {
		score:     f32,
		snippet:   Snippet_Info,
		name:      string,
		type:      SymbolType,
		doc:       string,
		pkg:       string,
		signature: string,
		flags:     SymbolFlags,
	}

	items := make([dynamic]CompletionItem, context.temp_allocator)

	list.isIncomplete = true

	combined := make([dynamic]CombinedResult, context.temp_allocator)

	lookup_name := ""

	if position_context.identifier != nil {
		if ident, ok := position_context.identifier.derived.(^ast.Ident); ok {
			lookup_name = ident.name
		}
	}

	pkgs := make([dynamic]string, context.temp_allocator)

	usings := get_using_packages(ast_context)

	for u in usings {
		append(&pkgs, u)
	}

	append(&pkgs, ast_context.document_package)
	append(&pkgs, "$builtin")

	if results, ok := fuzzy_search(lookup_name, pkgs[:]); ok {
		for r in results {
			r := r
			resolve_unresolved_symbol(ast_context, &r.symbol)
			build_procedure_symbol_signature(&r.symbol)

			uri, _ := common.parse_uri(r.symbol.uri, context.temp_allocator)
			if uri.path != ast_context.fullpath {
				append(
					&combined,
					CombinedResult {
						score = r.score,
						type = r.symbol.type,
						name = r.symbol.name,
						doc = r.symbol.doc,
						flags = r.symbol.flags,
						signature = r.symbol.signature,
						pkg = r.symbol.pkg,
					},
				)
			}
		}
	}

	matcher := common.make_fuzzy_matcher(lookup_name)

	global: for k, v in ast_context.globals {
		if position_context.global_lhs_stmt {
			break
		}

		//combined is sorted and should do binary search instead.
		for result in combined {
			if result.name == k {
				continue global
			}
		}

		reset_ast_context(ast_context)
		ast_context.current_package = ast_context.document_package

		ident := new_type(
			ast.Ident,
			v.expr.pos,
			v.expr.end,
			context.temp_allocator,
		)
		ident.name = k

		if symbol, ok := resolve_type_identifier(ast_context, ident^); ok {
			symbol.signature = get_signature(ast_context, ident^, symbol)

			build_procedure_symbol_signature(&symbol)

			if score, ok := common.fuzzy_match(matcher, ident.name); ok == 1 {
				append(
					&combined,
					CombinedResult {
						score = score * 1.1,
						type = symbol.type,
						name = ident.name,
						doc = symbol.doc,
						flags = symbol.flags,
						pkg = symbol.pkg,
						signature = symbol.signature,
					},
				)
			}
		}
	}

	for _, local in ast_context.locals {
		for k, v in local {
			if position_context.global_lhs_stmt {
				break
			}

			local_offset := get_local_offset(
				ast_context,
				position_context.position,
				k,
			)

			reset_ast_context(ast_context)

			ast_context.current_package = ast_context.document_package

			ident := new_type(
				ast.Ident,
				{offset = local_offset},
				{offset = local_offset},
				context.temp_allocator,
			)
			ident.name = k

			if symbol, ok := resolve_type_identifier(ast_context, ident^); ok {
				symbol.signature = get_signature(ast_context, ident^, symbol)

				build_procedure_symbol_signature(&symbol)

				if score, ok := common.fuzzy_match(matcher, ident.name);
				   ok == 1 {
					append(
						&combined,
						CombinedResult {
							score = score * 1.7,
							type = symbol.type,
							name = ident.name,
							doc = symbol.doc,
							flags = symbol.flags,
							pkg = symbol.pkg,
							signature = symbol.signature,
						},
					)
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
			append(
				&combined,
				CombinedResult {
					score = score * 1.1,
					type = symbol.type,
					name = symbol.name,
					doc = symbol.doc,
					flags = symbol.flags,
					signature = symbol.signature,
					pkg = symbol.pkg,
				},
			)
		}
	}

	for keyword, _ in common.keyword_map {
		symbol := Symbol {
			name = keyword,
			type = .Keyword,
		}

		if score, ok := common.fuzzy_match(matcher, keyword); ok == 1 {
			append(
				&combined,
				CombinedResult {
					score = score,
					type = symbol.type,
					name = symbol.name,
					doc = symbol.doc,
					flags = symbol.flags,
					signature = symbol.signature,
					pkg = symbol.pkg,
				},
			)
		}
	}

	for keyword, _ in language_keywords {
		symbol := Symbol {
			name = keyword,
			type = .Keyword,
		}

		if score, ok := common.fuzzy_match(matcher, keyword); ok == 1 {
			append(
				&combined,
				CombinedResult {
					score = score * 1.1,
					type = symbol.type,
					name = symbol.name,
					doc = symbol.doc,
					flags = symbol.flags,
					signature = symbol.signature,
					pkg = symbol.pkg,
				},
			)
		}
	}

	if common.config.enable_snippets {
		for k, v in snippets {
			if score, ok := common.fuzzy_match(matcher, k); ok == 1 {
				append(
					&combined,
					CombinedResult{score = score * 1.1, snippet = v, name = k},
				)
			}
		}
	}

	slice.sort_by(combined[:], proc(i, j: CombinedResult) -> bool {
		return j.score < i.score
	})

	//hard code for now
	top_results := combined[0:(min(100, len(combined)))]

	for result in top_results {
		result := result

		//Skip procedures when the position is in proc decl
		if position_in_proc_decl(position_context) &&
		   result.type == .Function &&
		   common.config.enable_procedure_context {
			continue
		}

		if result.snippet.insert != "" && false {
			item := CompletionItem {
				label            = result.name,
				insertText       = result.snippet.insert,
				kind             = .Snippet,
				detail           = result.snippet.detail,
				insertTextFormat = .Snippet,
			}

			edits := make([dynamic]TextEdit, context.temp_allocator)

			for pkg in result.snippet.packages {
				edit, ok := get_core_insert_package_if_non_existent(
					ast_context,
					pkg,
				)
				if ok {
					append(&edits, edit)
				}
			}

			item.additionalTextEdits = edits[:]

			append(&items, item)
		} else {
			item := CompletionItem {
				label         = result.name,
				documentation = result.doc,
			}

			item.kind = symbol_type_to_completion_kind(result.type)

			if result.type == .Function &&
			   common.config.enable_snippets &&
			   common.config.enable_procedure_snippet {
				item.insertText = fmt.tprintf("%v($0)", item.label)
				item.insertTextFormat = .Snippet
				item.deprecated = .Deprecated in result.flags
				item.command = Command {
					command = "editor.action.triggerParameterHints",
				}
			}

			item.detail = concatenate_symbol_information(
				ast_context,
				result.pkg,
				result.name,
				result.signature,
				result.type,
				true,
			)

			append(&items, item)
		}
	}

	list.items = items[:]
}

get_package_completion :: proc(
	ast_context: ^AstContext,
	position_context: ^DocumentPositionContext,
	list: ^CompletionList,
) {
	items := make([dynamic]CompletionItem, context.temp_allocator)

	list.isIncomplete = false

	without_quotes := position_context.import_stmt.fullpath

	// Strip the opening quote, if one exists.
	if len(without_quotes) > 0 && without_quotes[0] == '"' {
		without_quotes = without_quotes[1:]
	}

	// Strip the closing quote, if one exists.
	if len(without_quotes) > 0 &&
	   without_quotes[len(without_quotes) - 1] == '"' {
		without_quotes = without_quotes[:len(without_quotes) - 1]
	}

	absolute_path := without_quotes
	colon_index := strings.index(without_quotes, ":")

	if colon_index >= 0 {
		c := without_quotes[0:colon_index]

		if colon_index + 1 < len(without_quotes) {
			absolute_path = filepath.join(
				elems = {
					common.config.collections[c],
					filepath.dir(
						without_quotes[colon_index + 1:],
						context.temp_allocator,
					),
				},
				allocator = context.temp_allocator,
			)
		} else {
			absolute_path = common.config.collections[c]
		}
	} else {
		import_file_dir := filepath.dir(
			position_context.import_stmt.pos.file,
			context.temp_allocator,
		)
		import_dir := filepath.dir(without_quotes, context.temp_allocator)
		absolute_path = filepath.join(
			elems = {import_file_dir, import_dir},
			allocator = context.temp_allocator,
		)
	}

	if !strings.contains(position_context.import_stmt.fullpath, "/") &&
	   !strings.contains(position_context.import_stmt.fullpath, ":") {
		for key, _ in common.config.collections {
			item := CompletionItem {
				detail = "collection",
				label  = key,
				kind   = .Module,
			}

			append(&items, item)
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

		append(&items, item)
	}

	list.items = items[:]
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

get_type_switch_completion :: proc(
	ast_context: ^AstContext,
	position_context: ^DocumentPositionContext,
	list: ^CompletionList,
) {
	items := make([dynamic]CompletionItem, context.temp_allocator)
	list.isIncomplete = false

	used_unions := make(map[string]bool, 5, context.temp_allocator)

	if block, ok := position_context.switch_type_stmt.body.derived.(^ast.Block_Stmt);
	   ok {
		for stmt in block.stmts {
			if case_clause, ok := stmt.derived.(^ast.Case_Clause); ok {
				for name in case_clause.list {
					if ident, ok := name.derived.(^ast.Ident); ok {
						used_unions[ident.name] = true
					} else if selector, ok := name.derived.(^ast.Selector_Expr);
					   ok {
						used_unions[selector.field.name] = true
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
				if symbol, ok := resolve_type_expression(
					ast_context,
					union_value.types[i],
				); ok {
					name := symbol.name

					item := CompletionItem {
						kind = .EnumMember,
					}

					if symbol.pkg == ast_context.document_package {
						item.label = fmt.aprintf(
							"%v%v",
							common.repeat(
								"^",
								symbol.pointers,
								context.temp_allocator,
							),
							name,
						)
					} else {
						item.label = fmt.aprintf(
							"%v%v.%v",
							common.repeat(
								"^",
								symbol.pointers,
								context.temp_allocator,
							),
							get_symbol_pkg_name(ast_context, symbol),
							name,
						)
					}

					append(&items, item)
				}
			}
		}
	}

	list.items = items[:]
}

get_core_insert_package_if_non_existent :: proc(
	ast_context: ^AstContext,
	pkg: string,
) -> (
	TextEdit,
	bool,
) {
	builder := strings.builder_make(context.temp_allocator)

	for imp in ast_context.imports {
		if imp.base == pkg {
			return {}, false
		}
	}

	strings.write_string(&builder, fmt.tprintf("import \"core:%v\"", pkg))

	return {
			newText = strings.to_string(builder),
			range = {
				start = {
					line = ast_context.file.pkg_decl.end.line + 1,
					character = 0,
				},
				end = {
					line = ast_context.file.pkg_decl.end.line + 1,
					character = 0,
				},
			},
		},
		true
}

get_range_from_selection_start_to_dot :: proc(
	position_context: ^DocumentPositionContext,
) -> (
	common.Range,
	bool,
) {
	if position_context.selector != nil {
		range := common.get_token_range(
			position_context.selector,
			position_context.file.src,
		)
		range.end.character += 1
		return range, true
	}

	return {}, false
}

append_magic_map_completion :: proc(
	position_context: ^DocumentPositionContext,
	symbol: Symbol,
	items: ^[dynamic]CompletionItem,
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
	symbol_str := get_expression_string_from_position_context(position_context)
	//for
	{
		item := CompletionItem {
			label = "for",
			kind = .Snippet,
			detail = "for",
			additionalTextEdits = additionalTextEdits,
			textEdit = TextEdit {
				newText = fmt.tprintf(
					"for ${{1:k}}, ${{2:v}} in %v {{\n\t$0 \n}}",
					symbol_str,
				),
				range = {start = range.end, end = range.end},
			},
			insertTextFormat = .Snippet,
			InsertTextMode = .adjustIndentation,
		}

		append(items, item)
	}
}
get_expression_string_from_position_context :: proc(
	position_context: ^DocumentPositionContext,
) -> string {
	src := position_context.file.src
	if position_context.call != nil {
		return(
			src[position_context.call.pos.offset:position_context.call.end.offset] \
		)
	} else if position_context.field != nil {
		return(
			src[position_context.field.pos.offset:position_context.field.end.offset] \
		)
	} else if position_context.selector != nil {
		return(
			src[position_context.selector.pos.offset:position_context.selector.end.offset] \
		)
	}
	return ""
}
append_magic_dynamic_array_completion :: proc(
	position_context: ^DocumentPositionContext,
	symbol: Symbol,
	items: ^[dynamic]CompletionItem,
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

	symbol_str := get_expression_string_from_position_context(position_context)

	//len
	{
		text := fmt.tprintf("len(%v)", symbol_str)

		item := CompletionItem {
			label = "len",
			kind = .Function,
			detail = "len",
			textEdit = TextEdit {
				newText = text,
				range = {start = range.end, end = range.end},
			},
			additionalTextEdits = additionalTextEdits,
		}

		append(items, item)
	}

	//for
	{
		item := CompletionItem {
			label = "for",
			kind = .Snippet,
			detail = "for",
			additionalTextEdits = additionalTextEdits,
			textEdit = TextEdit {
				newText = fmt.tprintf("for i in %v {{\n\t$0 \n}}", symbol_str),
				range = {start = range.end, end = range.end},
			},
			insertTextFormat = .Snippet,
			InsertTextMode = .adjustIndentation,
		}

		append(items, item)
	}

}

append_magic_union_completion :: proc(
	position_context: ^DocumentPositionContext,
	symbol: Symbol,
	items: ^[dynamic]CompletionItem,
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
				newText = fmt.tprintf(
					"switch v in %v {{\n\t$0 \n}}",
					symbol.name,
				),
				range = {start = range.end, end = range.end},
			},
			insertTextFormat = .Snippet,
			InsertTextMode = .adjustIndentation,
		}

		append(items, item)
	}

}

//Temporary hack to support labeldetails
format_to_label_details :: proc(list: ^CompletionList) {
	// detail      = left
	// description = right

	for item in &list.items {
		// log.errorf("item:%v: %v:%v", item.kind, item.label, item.detail)
		#partial switch item.kind {
		case .Function:
			proc_index := strings.index(item.detail, ": proc")
			// check if the function return somrthing
			proc_return_index := strings.index(item.detail, "->")
			if proc_return_index > 0 {
				proc_end_index := strings.index(
					item.detail[0:proc_return_index],
					")",
				)
				if proc_return_index + 2 >= len(item.detail) {
					break
				}
				item.labelDetails = CompletionItemLabelDetails {
					detail      = item.detail[proc_index + 6:proc_return_index],
					description = item.detail[proc_return_index + 2:],
				}
				item.detail = item.label
			} else {
				if proc_index + 6 >= len(item.detail) {
					break
				}
				item.labelDetails = CompletionItemLabelDetails {
					detail      = item.detail[proc_index + 6:],
					description = "",
				}
				item.detail = ""
			}
		case .Variable, .Constant, .Field:
			type_index := strings.index(item.detail, ":")
			item.labelDetails = CompletionItemLabelDetails {
				detail      = "",
				description = item.detail[type_index + 1:],
			}
			item.detail = item.label
		case .Struct, .Enum, .Class:
			type_index := strings.index(item.detail, ":")
			item.labelDetails = CompletionItemLabelDetails {
				detail      = "",
				description = item.detail[type_index + 1:],
			}
			item.detail = item.label
		case .Keyword:
			item.detail = "keyword"
		}

		// hack for sublime text's issue
		// remove when this issue is fixed: https://github.com/sublimehq/sublime_text/issues/6033
		// or if this PR gets merged: https://github.com/sublimelsp/LSP/pull/2293
		if common.config.client_name == "Sublime Text LSP" {
			dt := &item.labelDetails.? or_else nil
			if dt == nil do continue
			if strings.contains(dt.detail, "..") &&
			   strings.contains(dt.detail, "#") {
				s, _ := strings.replace_all(
					dt.detail,
					"..",
					"ꓸꓸ",
					allocator = context.temp_allocator,
				)
				dt.detail = s
			}
		}
	}
}

bitset_operators: map[string]bool = {
	"|"  = true,
	"&"  = true,
	"~"  = true,
	"<"  = true,
	">"  = true,
	"==" = true,
}

bitset_assignment_operators: map[string]bool = {
	"|=" = true,
	"&=" = true,
	"~=" = true,
	"<=" = true,
	">=" = true,
	"="  = true,
	"+=" = true,
}

is_bitset_binary_operator :: proc(op: string) -> bool {
	return op in bitset_operators
}

is_bitset_assignment_operator :: proc(op: string) -> bool {
	return op in bitset_assignment_operators
}

language_keywords: []string = {
	"align_of",
	"case",
	"defer",
	"enum",
	"import",
	"proc",
	"transmute",
	"when",
	"auto_cast",
	"cast",
	"distinct",
	"fallthrough",
	"in",
	"not_in",
	"return",
	"type_of",
	"bit_field",
	"const",
	"do",
	"for",
	"inline",
	"offset_of",
	"size_of",
	"typeid",
	"bit_set",
	"context",
	"dynamic",
	"foreign",
	"opaque",
	"struct",
	"union",
	"break",
	"continue",
	"else",
	"if",
	"map",
	"package",
	"switch",
	"using",
	"or_return",
	"or_else",
}

swizzle_color_map: map[u8]bool = {
	'r' = true,
	'g' = true,
	'b' = true,
	'a' = true,
}

swizzle_color_components: []string = {"r", "g", "b", "a"}

swizzle_coord_map: map[u8]bool = {
	'x' = true,
	'y' = true,
	'z' = true,
	'w' = true,
}

swizzle_coord_components: []string = {"x", "y", "z", "w"}
