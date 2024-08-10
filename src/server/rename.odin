package server

import "base:runtime"

import "core:log"
import "core:mem"
import "core:odin/ast"
import "core:strings"

import "src:common"

get_rename :: proc(document: ^Document, new_text: string, position: common.Position) -> (WorkspaceEdit, bool) {
	ast_context := make_ast_context(
		document.ast,
		document.imports,
		document.package_name,
		document.uri.uri,
		document.fullpath,
		context.temp_allocator,
	)

	position_context, ok := get_document_position_context(document, position, .Hover)

	get_globals(document.ast, &ast_context)

	ast_context.current_package = ast_context.document_package

	if position_context.function != nil {
		get_locals(document.ast, position_context.function, &ast_context, &position_context)
	}

	locations, ok2 := resolve_references(document, &ast_context, &position_context)

	changes := make(map[string][dynamic]TextEdit, 0, context.temp_allocator)

	for location in locations {
		edits: ^[dynamic]TextEdit

		if edits = &changes[location.uri]; edits == nil {
			changes[strings.clone(location.uri, context.temp_allocator)] = make(
				[dynamic]TextEdit,
				context.temp_allocator,
			)
			edits = &changes[location.uri]
		}

		append(edits, TextEdit{newText = new_text, range = location.range})
	}

	workspace: WorkspaceEdit

	workspace.changes = make(map[string][]TextEdit, len(changes), context.temp_allocator)

	for k, v in changes {
		workspace.changes[k] = v[:]
	}

	return workspace, true
}


get_prepare_rename :: proc(document: ^Document, position: common.Position) -> (common.Range, bool) {
	ast_context := make_ast_context(
		document.ast,
		document.imports,
		document.package_name,
		document.uri.uri,
		document.fullpath,
		context.temp_allocator,
	)

	position_context, ok := get_document_position_context(document, position, .Hover)

	get_globals(document.ast, &ast_context)

	ast_context.current_package = ast_context.document_package

	if position_context.function != nil {
		get_locals(document.ast, position_context.function, &ast_context, &position_context)
	}

	symbol, _, ok2 := prepare_references(document, &ast_context, &position_context)


	return symbol.range, ok2
}
