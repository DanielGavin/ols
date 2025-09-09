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
		symbol.selectionRange = common.get_token_range(global.name_expr, ast_context.file.src)
		symbol.range = common.get_token_range(global.expr, ast_context.file.src)
		ensure_selection_range_contained(&symbol.range, symbol.selectionRange)
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
				ranges :: struct {
					range: common.Range,
					selection_range: common.Range,
				}
				name_map := make(map[string]ranges)
				for elem in v.elems {
					if field_value, ok := elem.derived.(^ast.Field_Value); ok {
						if name, ok := field_value.field.derived.(^ast.Ident); ok {
							selection_range := common.get_token_range(name, ast_context.file.src)
							range := common.get_token_range(field_value, ast_context.file.src)
							ensure_selection_range_contained(&range, selection_range)
							name_map[name.name] = {
								range = range,
								selection_range = selection_range,
							}
						}
					}
				}
				#partial switch v in s.value {
				case SymbolStructValue:
					children := make([dynamic]DocumentSymbol, context.temp_allocator)
					for name, i in v.names {
						child: DocumentSymbol
						if range, ok := name_map[name]; ok {
							child.range = range.range
							child.selectionRange = range.selection_range
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
							child.range = range.range
							child.selectionRange = range.selection_range
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

@(private="file")
ensure_selection_range_contained :: proc(range: ^common.Range, selection_range: common.Range) {
	// selection range must be contained with range, so we set the range start to be the selection range start
	range.start = selection_range.start

	// if the range end is somehow before the selection_range end, we set it to the end of the selection range
	if range.end.line < selection_range.end.line {
		range.end = selection_range.end
	} else if range.end.line == selection_range.end.line && range.end.character < selection_range.end.character {
		range.end = selection_range.end
	}
}
