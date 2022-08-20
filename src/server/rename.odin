package server

import "shared:common"

import "core:log"
import "core:odin/ast"

get_rename :: proc(
	document: ^Document,
	new_text: string,
	position: common.Position,
) -> (
	WorkspaceEdit,
	bool,
) {
	workspace: WorkspaceEdit

	document_changes := make([dynamic]TextDocumentEdit, context.temp_allocator)

	edits := make([dynamic]TextEdit, context.temp_allocator)


	document_change := TextDocumentEdit {
		edits = edits[:],
		textDocument = {uri = document.uri.uri, version = document.version},
	}

	append(&document_changes, document_change)

	workspace.documentChanges = document_changes[:]


	return workspace, true
}
