package server 

import "shared:common"

import "core:log"
import "core:odin/ast"

get_rename :: proc(document: ^Document, new_text: string, position: common.Position) -> (WorkspaceEdit, bool) {
	workspace: WorkspaceEdit

	document_changes := make([dynamic]TextDocumentEdit, context.temp_allocator)

	edits := make([dynamic]TextEdit, context.temp_allocator)


	/*
	symbol_and_nodes := resolve_entire_file(document)

	ast_context := make_ast_context(document.ast, document.imports, document.package_name, document.uri.uri)

	position_context, ok := get_document_position_context(document, position, .Hover)

	get_globals(document.ast, &ast_context)

	if position_context.function != nil {
		get_locals(document.ast, position_context.function, &ast_context, &position_context)
	}

	if position_context.identifier != nil { 
		ast_context.use_locals = true
		ast_context.use_globals = true
		ast_context.current_package = ast_context.document_package

		ident := position_context.identifier.derived.(^ast.Ident)^

		if resolved, ok := resolve_type_identifier(&ast_context, ident); ok {	
			for k, v in symbol_and_nodes {	
				if ident2, ok := v.node.derived.(^ast.Ident); ok {
					log.error(ident2)
				}
				if ident2, ok := v.node.derived.(^ast.Ident); ok && resolved.pkg == v.symbol.pkg && ident2.name == ident.name {
					edit := TextEdit {
						newText = new_text,
						range = common.get_token_range(v.node^, position_context.file.src),
					}
					append(&edits, edit)
				}
			}
			
			


		}

	}

	document_change := TextDocumentEdit {
		edits = edits[:],
		textDocument = {
			uri = document.uri.uri,
			version = document.version,
		},
	}

	append(&document_changes, document_change)

	workspace.documentChanges = document_changes[:]
	*/

	return workspace, true
}