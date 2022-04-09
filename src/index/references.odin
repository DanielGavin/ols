package index 

/*
import "shared:common"
import "shared:analysis"

import "core:strings"
import "core:odin/ast"


Reference :: struct {
	identifiers: [dynamic]^ast.Ident, 
	selectors: [dynamic]^ast.Selector_Expr, 
}

collect_references :: proc(collection: ^SymbolCollection, file: ast.File, uri: string) -> common.Error {
	document := common.Document {
		ast = file,
	
	}

	uri, ok := common.parse_uri(uri, context.temp_allocator) 

	if !ok {
		return .ParseError
	}

	when ODIN_OS == .Windows  {
		document.package_name = strings.to_lower(path.dir(document.uri.path, context.temp_allocator))
	} else {
		document.package_name = path.dir(document.uri.path)
	}


	return {}

}
*/

