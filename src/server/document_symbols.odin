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

get_document_symbols :: proc(document: ^Document) -> []DocumentSymbol {
	ast_context := make_ast_context(
		document.ast,
		document.imports,
		document.package_name,
		document.uri.uri,
		document.fullpath,
	)

	get_globals(document.ast, &ast_context)

	symbols := make([dynamic]DocumentSymbol, context.temp_allocator)

	package_symbol: DocumentSymbol

	if len(document.ast.decls) == 0 {
		return {}
	}

	for k, global in ast_context.globals {
		symbol: DocumentSymbol
		symbol.range = common.get_token_range(global.expr, ast_context.file.src)
		symbol.selectionRange = symbol.range
		symbol.name = k

		#partial switch v in global.expr.derived {
		case ^ast.Struct_Type, ^ast.Bit_Field_Type:
			symbol.kind = .Struct
		case ^ast.Proc_Lit, ^ast.Proc_Group:
			symbol.kind = .Function
		case ^ast.Enum_Type, ^ast.Union_Type:
			symbol.kind = .Enum
		case:
			symbol.kind = .Variable
		}

		append(&symbols, symbol)
	}


	return symbols[:]
}
