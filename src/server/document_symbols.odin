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
		symbol.range = common.get_token_range(global.name_expr, ast_context.file.src)
		symbol.selectionRange = symbol.range
		symbol.name = k

		#partial switch v in global.expr.derived {
		case ^ast.Struct_Type, ^ast.Bit_Field_Type:
			// TODO: this only does the top level fields, we may want to travers all the way down in the future
			if s, ok := resolve_type_expression(&ast_context, global.expr); ok {
				#partial switch v in s.value {
				case SymbolStructValue:
					children := make([dynamic]DocumentSymbol, context.temp_allocator)
					for name, i in v.names {
						child: DocumentSymbol
						child.range = v.ranges[i]
						child.selectionRange = v.ranges[i]
						child.name = name
						child.kind = .Field
						append(&children, child)
					}
					symbol.children = children[:]
				case SymbolBitFieldValue:
					children := make([dynamic]DocumentSymbol, context.temp_allocator)
					for name, i in v.names {
						child: DocumentSymbol
						child.range = v.ranges[i]
						child.selectionRange = v.ranges[i]
						child.name = name
						child.kind = .Field
						append(&children, child)
					}
					symbol.children = children[:]
				}
			}
			symbol.kind = .Struct
		case ^ast.Proc_Lit, ^ast.Proc_Group:
			symbol.kind = .Function
		case ^ast.Enum_Type, ^ast.Union_Type:
			symbol.kind = .Enum
		case ^ast.Comp_Lit:
			if s, ok := resolve_type_expression(&ast_context, v); ok {
				name_map := make(map[string]common.Range)
				for elem in v.elems {
					if field_value, ok := elem.derived.(^ast.Field_Value); ok {
						if name, ok := field_value.field.derived.(^ast.Ident); ok {
							name_map[name.name] = common.get_token_range(name, ast_context.file.src)
						}
					}
				}
				#partial switch v in s.value {
				case SymbolStructValue:
					children := make([dynamic]DocumentSymbol, context.temp_allocator)
					for name, i in v.names {
						child: DocumentSymbol
						if range, ok := name_map[name]; ok {
							child.range = range
							child.selectionRange = range
							child.name = name
							child.kind = .Field
							append(&children, child)
						}
					}
					symbol.children = children[:]
				case SymbolBitFieldValue:
					children := make([dynamic]DocumentSymbol, context.temp_allocator)
					for name, i in v.names {
						child: DocumentSymbol
						if range, ok := name_map[name]; ok {
							child.range = range
							child.selectionRange = range
							child.name = name
							child.kind = .Field
							append(&children, child)
						}
					}
					symbol.children = children[:]
				}
			}
		case:
			symbol.kind = .Variable
		}

		append(&symbols, symbol)
	}


	return symbols[:]
}
