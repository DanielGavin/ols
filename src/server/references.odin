package server 


import "shared:common"

import "core:strings"
import "core:odin/ast"
import "core:encoding/json"
import path "core:path/slashpath"
import "core:log"

get_references :: proc(document: ^Document, position: common.Position) -> ([]common.Location, bool) {
	locations := make([dynamic]common.Location, context.temp_allocator)

	ast_context := make_ast_context(document.ast, document.imports, document.package_name, document.uri.uri)

	position_context, ok := get_document_position_context(document, position, .Hover)

	get_globals(document.ast, &ast_context)

	if position_context.function != nil {
		get_locals(document.ast, position_context.function, &ast_context, &position_context)
	}

	/*
	if position_context.identifier != nil { 
		ast_context.use_locals = true
		ast_context.use_globals = true
		ast_context.current_package = ast_context.document_package

		ident := position_context.identifier.derived.(^ast.Ident)^
		
		if resolved, ok := resolve_type_identifier(&ast_context, ident); ok {	
			reference, _ := lookup_reference(resolved.name, resolved.pkg)

			for ident in reference.identifiers {
				uri := common.create_uri(ident.uri, context.temp_allocator)
				append(&locations, common.Location { uri = uri.uri, range = ident.range })
			}
		}
	

	}
	*/

	return locations[:], true
}