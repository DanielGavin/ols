package server

import "base:runtime"

import "core:log"
import "core:mem"
import "core:odin/ast"
import "core:strings"

import "src:common"

get_rename :: proc(
	document: ^Document,
	new_text: string,
	position: common.Position,
) -> (
	WorkspaceEdit,
	bool,
) {
	data := make([]byte, mem.Megabyte * 55, runtime.default_allocator())
	defer delete(data)

	arena: mem.Arena
	mem.arena_init(&arena, data)

	context.allocator = mem.arena_allocator(&arena)

	ast_context := make_ast_context(
		document.ast,
		document.imports,
		document.package_name,
		document.uri.uri,
		document.fullpath,
		context.allocator,
	)

	position_context, ok := get_document_position_context(
		document,
		position,
		.Hover,
	)

	get_globals(document.ast, &ast_context)

	ast_context.current_package = ast_context.document_package

	if position_context.function != nil {
		get_locals(
			document.ast,
			position_context.function,
			&ast_context,
			&position_context,
		)
	}

	locations, ok2 := resolve_references(&ast_context, &position_context)

	document_edits := make(
		map[string][dynamic]TextEdit,
		0,
		context.temp_allocator,
	)

	for location in locations {
		edits: ^[dynamic]TextEdit

		/*
		if location.range.start.line <= position.line &&
		   position.line <= location.range.end.line &&
		   location.range.start.character <= position.character &&
		   position.character <= location.range.end.character {
			continue
		}
		*/

		if edits = &document_edits[location.uri]; edits == nil {
			document_edits[strings.clone(location.uri, context.temp_allocator)] =
				make([dynamic]TextEdit, context.temp_allocator)
			edits = &document_edits[location.uri]
		}

		append(edits, TextEdit{newText = new_text, range = location.range})
	}

	workspace: WorkspaceEdit

	document_changes := make([dynamic]TextDocumentEdit, context.temp_allocator)

	for k, v in document_edits {
		append(
			&document_changes,
			TextDocumentEdit {
				edits = v[:],
				textDocument = {uri = k, version = document.version},
			},
		)
	}

	workspace.documentChanges = document_changes[:]

	return workspace, true
}
