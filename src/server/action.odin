package server

import "core:fmt"
import "core:log"
import "core:odin/ast"
import path "core:path/slashpath"
import "core:slice"
import "core:strings"

import "src:common"

CodeActionKind :: string

CodeActionClientCapabilities :: struct {
	codeActionLiteralSupport: struct {
		codeActionKind: struct {
			valueSet: [dynamic]CodeActionKind,
		},
	},
}

CodeActionOptions :: struct {
	codeActionKinds: []CodeActionKind,
	resolveProvider: bool,
}

CodeActionParams :: struct {
	textDocument: TextDocumentIdentifier,
	range:        common.Range,
}

CodeAction :: struct {
	title:       string,
	kind:        CodeActionKind,
	isPreferred: bool,
	edit:        WorkspaceEdit,
}

get_code_actions :: proc(document: ^Document, range: common.Range, config: ^common.Config) -> ([]CodeAction, bool) {
	ast_context := make_ast_context(
		document.ast,
		document.imports,
		document.package_name,
		document.uri.uri,
		document.fullpath,
		context.temp_allocator,
	)

	position_context, ok := get_document_position_context(document, range.start, .Hover)
	if !ok {
		log.warn("Failed to get position context")
		return {}, false
	}

	ast_context.position_hint = position_context.hint

	get_globals(document.ast, &ast_context)

	ast_context.current_package = ast_context.document_package

	if position_context.function != nil {
		get_locals(document.ast, position_context.function, &ast_context, &position_context)
	}

	actions := make([dynamic]CodeAction, 0, context.allocator)

	if position_context.selector_expr != nil {
		if selector, ok := position_context.selector_expr.derived.(^ast.Selector_Expr); ok {
			add_missing_imports(&ast_context, selector, strings.clone(document.uri.uri), config, &actions)
		}
	} else if position_context.import_stmt != nil {
		remove_unused_imports(document, strings.clone(document.uri.uri), config, &actions)
	}

	if position_context.switch_stmt != nil || position_context.switch_type_stmt != nil {
		add_populate_switch_cases_action(
			document,
			&ast_context,
			&position_context,
			strings.clone(document.uri.uri),
			&actions,
		)
	}
	return actions[:], true
}

remove_unused_imports :: proc(
	document: ^Document,
	uri: string,
	config: ^common.Config,
	actions: ^[dynamic]CodeAction,
) {
	unused_imports := find_unused_imports(document, context.temp_allocator)

	if len(unused_imports) == 0 {
		return
	}

	textEdits := make([dynamic]TextEdit, context.temp_allocator)

	for imp in unused_imports {
		range := common.get_token_range(imp.import_decl, document.ast.src)

		import_edit := TextEdit {
			range   = range,
			newText = "",
		}

		if (range.start.line != 1) {
			if column, ok := common.get_last_column(import_edit.range.start.line - 1, document.text); ok {
				import_edit.range.start.line -= 1
				import_edit.range.start.character = column
			}

		}


		append(&textEdits, import_edit)
	}

	workspaceEdit: WorkspaceEdit
	workspaceEdit.changes = make(map[string][]TextEdit, 0, context.temp_allocator)
	workspaceEdit.changes[uri] = textEdits[:]

	append(
		actions,
		CodeAction {
			kind = "refactor.rewrite",
			isPreferred = true,
			title = fmt.tprint("remove unused imports"),
			edit = workspaceEdit,
		},
	)

}

add_missing_imports :: proc(
	ast_context: ^AstContext,
	selector: ^ast.Selector_Expr,
	uri: string,
	config: ^common.Config,
	actions: ^[dynamic]CodeAction,
) {
	if name, ok := selector.expr.derived.(^ast.Ident); ok {
		// If we already know what the name is referring to, don't prompt anything
		if _, ok := resolve_type_identifier(ast_context, name^); ok {
			return
		}
		for collection, pkgs in build_cache.pkg_aliases {
			for pkg in pkgs {
				fullpath := path.join({config.collections[collection], pkg})
				found := false

				for doc_pkg in ast_context.imports {
					if fullpath == doc_pkg.name {
						found = true
					}
				}

				if found {
					continue
				}

				if pkg == name.name {
					pkg_decl := ast_context.file.pkg_decl
					import_edit := TextEdit {
						range = {
							start = {line = pkg_decl.end.line + 1, character = 0},
							end = {line = pkg_decl.end.line + 1, character = 0},
						},
						newText = fmt.tprintf("import \"%v:%v\"\n", collection, pkg),
					}
					textEdits := make([dynamic]TextEdit, context.temp_allocator)
					append(&textEdits, import_edit)

					workspaceEdit: WorkspaceEdit
					workspaceEdit.changes = make(map[string][]TextEdit, 0, context.temp_allocator)
					workspaceEdit.changes[uri] = textEdits[:]
					append(
						actions,
						CodeAction {
							kind = "refactor.rewrite",
							isPreferred = true,
							title = fmt.tprintf(`import package "%v:%v"`, collection, pkg),
							edit = workspaceEdit,
						},
					)
				}
			}
		}
	}

	return
}

get_block_original_text :: proc(block: []^ast.Stmt, document_text: []u8) -> string {
	if len(block) == 0 {
		return ""
	}
	start := block[0].pos
	end := block[max(0, len(block) - 1)].end
	return string(document_text[start.offset:end.offset])
}

get_switch_cases_info :: proc(
	document: ^Document,
	ast_context: ^AstContext,
	position_context: ^DocumentPositionContext,
) -> (
	existing_cases: map[string]string,
	all_case_names: []string,
	is_enum: bool,
	ok: bool,
) {
	if (position_context.switch_stmt == nil && position_context.switch_type_stmt == nil) ||
	   (position_context.switch_stmt != nil && position_context.switch_stmt.cond == nil) {
		return nil, nil, false, false
	}
	switch_block: ^ast.Block_Stmt
	found_switch_block: bool
	if position_context.switch_stmt != nil {
		switch_block, found_switch_block = position_context.switch_stmt.body.derived.(^ast.Block_Stmt)
		is_enum = true
	}
	if !found_switch_block && position_context.switch_type_stmt != nil {
		switch_block, found_switch_block = position_context.switch_type_stmt.body.derived.(^ast.Block_Stmt)
	}
	if !found_switch_block {
		return nil, nil, false, false
	}
	existing_cases = make(map[string]string, 5, context.temp_allocator)
	for stmt in switch_block.stmts {
		if case_clause, ok := stmt.derived.(^ast.Case_Clause); ok {
			case_name := ""
			for name in case_clause.list {
				if is_enum {
					if implicit, ok := name.derived.(^ast.Implicit_Selector_Expr); ok {
						case_name = implicit.field.name
						break
					}
				} else {
					reset_ast_context(ast_context)
					if ty, ok := resolve_type_expression(ast_context, name); ok {
						//TODO: this is wrong for anonymous enums and structs, where the name field is "enum" or "struct" respectively but we want to use the full signature
						//we also can't use the signature all the time because type aliases need to use specifically the alias name here and not the signature
						case_name = ty.name != "" ? ty.name : get_signature(ast_context, ty)
						break
					}
				}
			}
			if case_name != "" {
				existing_cases[case_name] = get_block_original_text(case_clause.body, document.text)
			}
		}
	}
	if is_enum {
		enum_value, was_super_enum, unwrap_ok := unwrap_enum(ast_context, position_context.switch_stmt.cond)
		if !unwrap_ok {
			return nil, nil, true, false
		}
		return existing_cases, enum_value.names, !was_super_enum, true
	} else {
		st := position_context.switch_type_stmt
		if st == nil {
			return nil, nil, false, false
		}
		reset_ast_context(ast_context)
		union_value, unwrap_ok := unwrap_union(ast_context, st.tag.derived.(^ast.Assign_Stmt).rhs[0])
		if !unwrap_ok {
			return nil, nil, false, false
		}
		case_names := make([]string, len(union_value.types), context.temp_allocator)
		for t, i in union_value.types {
			reset_ast_context(ast_context)
			if ty, ok := resolve_type_expression(ast_context, t); ok {
				//TODO: this is wrong for anonymous enums and structs, where the name field is "enum" or "struct" respectively but we want to use the full signature
				//we also can't use the signature all the time because type aliases need to use specifically the alias name here and not the signature
				case_names[i] = ty.name != "" ? ty.name : get_signature(ast_context, ty)
			} else {
				case_names[i] = "invalid type expression"
			}
		}
		return existing_cases, case_names, false, true
	}
}

create_populate_switch_cases_edit :: proc(
	position_context: ^DocumentPositionContext,
	existing_cases: map[string]string,
	all_case_names: []string,
	is_enum: bool,
) -> (
	TextEdit,
	bool,
) {
	//we need to be either in a switch stmt or a switch type stmt
	if position_context.switch_stmt == nil && position_context.switch_type_stmt == nil {
		return {}, false
	}
	//entirety of the switch block
	range: common.Range
	if is_enum {
		range = common.get_token_range(position_context.switch_stmt.body.stmt_base, position_context.file.src)
	} else {
		range = common.get_token_range(position_context.switch_type_stmt.body.stmt_base, position_context.file.src)
	}
	replacement_builder := strings.builder_make()
	dot := is_enum ? "." : ""
	b := &replacement_builder
	fmt.sbprintln(b, "{")
	for name in all_case_names {
		fmt.sbprintln(b, "case ", dot, name, ":", sep = "")
		if name in existing_cases {
			case_block := existing_cases[name]
			if case_block != "" {
				fmt.sbprintln(b, existing_cases[name])
			}
		}
	}
	for name in existing_cases {
		if !slice.contains(all_case_names, name) {
			//this case probably should be deleted by the user since it's not one of the legal enum names,
			//but we shouldn't preemptively delete the user's code inside the block
			fmt.sbprintln(b, "case ", dot, name, ":", sep = "")
			case_block := existing_cases[name]
			if case_block != "" {
				fmt.sbprintln(b, existing_cases[name])
			}
		}
	}
	fmt.sbprint(b, "}")
	return TextEdit{range = range, newText = strings.to_string(replacement_builder)}, true
}
add_populate_switch_cases_action :: proc(
	document: ^Document,
	ast_context: ^AstContext,
	position_context: ^DocumentPositionContext,
	uri: string,
	actions: ^[dynamic]CodeAction,
) {
	existing_cases, all_case_names, is_enum, ok := get_switch_cases_info(document, ast_context, position_context)
	if !ok {return}
	all_cases_covered := true
	for name in all_case_names {
		if name not_in existing_cases {
			all_cases_covered = false
		}
	}
	if all_cases_covered {return} 	//action not needed
	edit, edit_ok := create_populate_switch_cases_edit(position_context, existing_cases, all_case_names, is_enum)
	if !edit_ok {return}
	textEdits := make([dynamic]TextEdit, context.temp_allocator)
	append(&textEdits, edit)

	workspaceEdit: WorkspaceEdit
	workspaceEdit.changes = make(map[string][]TextEdit, 0, context.temp_allocator)
	workspaceEdit.changes[uri] = textEdits[:]
	append(
		actions,
		CodeAction {
			kind = "refactor.rewrite",
			isPreferred = true,
			title = "populate remaining switch cases",
			edit = workspaceEdit,
		},
	)
}
