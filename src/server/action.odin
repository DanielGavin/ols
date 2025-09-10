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
	}

	return actions[:], true
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
