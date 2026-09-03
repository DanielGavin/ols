package server

import "core:fmt"
import "core:log"
import "core:odin/ast"
import path "core:path/slashpath"
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
	context_:     CodeActionContext,
}

CodeActionContext :: struct {
	only: []CodeActionKind,
}

CodeAction :: struct {
	title:       string,
	kind:        CodeActionKind,
	isPreferred: bool,
	edit:        WorkspaceEdit,
}

get_code_actions :: proc(
	document: ^Document,
	ctx: CodeActionContext,
	range: common.Range,
	config: ^common.Config,
) -> (
	[]CodeAction,
	bool,
) {
	ast_context := make_ast_context(
		document.ast,
		document.imports,
		document.package_name,
		document.uri.uri,
		document.fullpath,
		context.temp_allocator,
	)

	actions := make([dynamic]CodeAction, 0, context.allocator)

	for action in ctx.only {
		//For some reason on vscode it returns "source", so check for both kinds
		if action == "source" || action == "source.organizeImports" {
			source_organize_imports(
				document,
				&ast_context,
				strings.clone(document.uri.uri, context.temp_allocator),
				config,
				&actions,
			)
			return actions[:], true
		}
	}

	position_context, ok := get_document_position_context(document, range.start, .Hover)

	if !ok {
		log.warn("Failed to get position context")
		return {}, false
	}

	ast_context.position_hint = position_context.hint
	ast_context.current_package = ast_context.document_package

	get_globals(document.ast, &ast_context)
	get_locals(&ast_context, &position_context)

	if position_context.selector_expr != nil {
		if selector, ok := position_context.selector_expr.derived.(^ast.Selector_Expr); ok {
			add_missing_imports(
				&ast_context,
				selector,
				strings.clone(document.uri.uri, context.temp_allocator),
				config,
				&actions,
			)
		}
	} else if position_context.import_stmt != nil {
		remove_unused_imports(document, strings.clone(document.uri.uri, context.temp_allocator), config, &actions)
	}

	if position_context.switch_stmt != nil || position_context.switch_type_stmt != nil {
		add_populate_switch_cases_action(
			&ast_context,
			&position_context,
			strings.clone(document.uri.uri, context.temp_allocator),
			&actions,
		)
	}

	if config.enable_code_action_invert_if {
		add_invert_if_action(
			document,
			position_context.position,
			strings.clone(document.uri.uri, context.temp_allocator),
			&actions,
		)
	}

	return actions[:], true
}


make_unused_import_edits :: proc(
	document: ^Document,
	removed_lines: ^map[int]struct{} = nil,
	allocator := context.temp_allocator,
) -> [dynamic]TextEdit {
	unused_imports := find_unused_imports(document, context.temp_allocator)

	textEdits := make([dynamic]TextEdit, 0, len(unused_imports), allocator)

	for imp in unused_imports {
		range := common.get_token_range(imp.import_decl, document.ast.src)

		import_edit := TextEdit {
			range = {
				start = {line = range.start.line, character = 0},
				end = {line = range.end.line + 1, character = 0},
			},
			newText = "",
		}

		//The last line of the document has no trailing newline to consume.
		if _, ok := common.get_last_column(range.end.line + 1, document.text); !ok {
			if column, ok := common.get_last_column(range.end.line, document.text); ok {
				import_edit.range.end = {
					line      = range.end.line,
					character = column,
				}
			}
		}

		if removed_lines != nil {
			for line in range.start.line ..= range.end.line {
				removed_lines[line] = {}
			}
		}

		append(&textEdits, import_edit)
	}

	return textEdits
}

source_organize_imports :: proc(
	document: ^Document,
	ast_context: ^AstContext,
	uri: string,
	config: ^common.Config,
	actions: ^[dynamic]CodeAction,
) {
	removed_lines := make(map[int]struct{}, 0, context.temp_allocator)

	textEdits := make_unused_import_edits(document, &removed_lines, context.temp_allocator)

	used_unimported := find_used_not_imported(document, config, context.temp_allocator)

	// Anchor new imports at the end of an existing line and prefix the text with a newline, so
	// the insert can never land inside a line that a removal edit deletes. The ast positions are
	// one indexed, while the lsp positions are zero indexed.

	pkg_line := document.ast.pkg_decl.end.line - 1

	//The line above the first import, so new imports end up at the top of the import block.
	insert_line := pkg_line

	first_import_line := max(int)

	for imp in document.ast.imports {
		first_import_line = min(first_import_line, imp.pos.line)
	}

	if len(document.ast.imports) > 0 {
		insert_line = max(first_import_line - 1, pkg_line)
	}

	insert_col := 0

	if config.enable_add_import_to_bottom {
		most_bottom_line, _ := find_most_bottom_line_number(ast_context) 
		most_bottom_line -= 1 //go to zero based indexing
		insert_line = max(most_bottom_line, pkg_line)
	}

	//Walk past any line that is being removed, the package declaration is never removed.
	for insert_line > pkg_line {
		if _, is_removed := removed_lines[insert_line]; !is_removed {
			break
		}

		insert_line -= 1
	}

	if col, ok := common.get_last_column(insert_line, document.text); ok {
		insert_col = col
	}

	for imp in used_unimported {
		import_edit := TextEdit {
			range = {
				start = {line = insert_line, character = insert_col},
				end = {line = insert_line, character = insert_col},
			},
			newText = fmt.tprintf("\nimport \"%v\"", imp.original),
		}

		append(&textEdits, import_edit)
	}

	workspaceEdit: WorkspaceEdit
	workspaceEdit.changes = make(map[string][]TextEdit, 0, context.temp_allocator)
	workspaceEdit.changes[uri] = textEdits[:]

	append(
		actions,
		CodeAction {
			kind = "source.organizeImports",
			isPreferred = true,
			title = fmt.tprint("organize imports"),
			edit = workspaceEdit,
		},
	)
}


remove_unused_imports :: proc(
	document: ^Document,
	uri: string,
	config: ^common.Config,
	actions: ^[dynamic]CodeAction,
) {
	textEdits := make_unused_import_edits(document, nil, context.temp_allocator)

	if len(textEdits) == 0 {
		return
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
					import_edit: TextEdit
					if config.enable_add_import_to_bottom {
						most_bottom_line, is_import := find_most_bottom_line_number(ast_context)

						import_edit = TextEdit {
							range = {
								start = {line = most_bottom_line, character = 0},
								end = {line = most_bottom_line, character = 0},
							},
							newText = is_import ? fmt.tprintf("import \"%v:%v\"\n", collection, pkg) : fmt.tprintf("\nimport \"%v:%v\"", collection, pkg),
						}
					} else {
						pkg_decl := ast_context.file.pkg_decl
						import_edit = TextEdit {
							range = {
								start = {line = pkg_decl.end.line + 1, character = 0},
								end = {line = pkg_decl.end.line + 1, character = 0},
							},
							newText = fmt.tprintf("import \"%v:%v\"\n", collection, pkg),
						}
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
