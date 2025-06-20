package server

import "core:fmt"
import "core:log"
import "core:mem"
import "core:odin/ast"
import "core:strings"

import "src:common"

@(private = "file")
append_symbol_to_locations :: proc(locations: ^[dynamic]common.Location, document: ^Document, symbol: Symbol) {
	if symbol.range == {} {
		return
	}
	location := common.Location{}
	location.range = symbol.range
	if symbol.uri == "" {
		location.uri = document.uri.uri
	} else {
		location.uri = symbol.uri
	}
	append(locations, location)
}

get_type_definition_locations :: proc(document: ^Document, position: common.Position) -> ([]common.Location, bool) {
	uri: string
	locations := make([dynamic]common.Location, context.temp_allocator)

	position_context, ok := get_document_position_context(document, position, .Definition)

	if !ok {
		log.warn("Failed to get position context")
		return {}, false
	}

	ast_context := make_ast_context(
		document.ast,
		document.imports,
		document.package_name,
		document.uri.uri,
		document.fullpath,
	)

	ast_context.position_hint = position_context.hint

	get_globals(document.ast, &ast_context)

	if position_context.function != nil {
		get_locals(document.ast, position_context.function, &ast_context, &position_context)
	}

	if position_context.import_stmt != nil {
		return {}, false
	}

	if position_context.identifier != nil {
		if ident, ok := position_context.identifier.derived.(^ast.Ident); ok {
			if _, ok := keyword_map[ident.name]; ok {
				return {}, false
			}

			if str, ok := builtin_identifier_hover[ident.name]; ok {
				return {}, false
			}
		}
	}

	if position_context.call != nil {
		if call, ok := position_context.call.derived.(^ast.Call_Expr); ok {
			if !position_in_exprs(call.args, position_context.position) {
				if call_symbol, ok := resolve_type_expression(&ast_context, position_context.call); ok {
					if symbol, ok := resolve_symbol_proc_first_return_symbol(&ast_context, call_symbol); ok {
						append_symbol_to_locations(&locations, document, symbol)
						return locations[:], true
					}
					return {}, false
				}
			}
		}
	}

	if position_context.struct_type != nil {
		for field in position_context.struct_type.fields.list {
			for name in field.names {
				if position_in_node(name, position_context.position) {
					if identifier, ok := name.derived.(^ast.Ident); ok && field.type != nil {
						if position_context.value_decl != nil && len(position_context.value_decl.names) != 0 {
							if symbol, ok := resolve_location_type_expression(&ast_context, field.type); ok {
								append_symbol_to_locations(&locations, document, symbol)
								return locations[:], true
							}
						}
					}
				}
			}
		}
	}

	if position_context.field_value != nil && position_context.comp_lit != nil {
		if comp_symbol, ok := resolve_comp_literal(&ast_context, &position_context); ok {
			if field, ok := position_context.field_value.field.derived.(^ast.Ident); ok {
				if position_in_node(field, position_context.position) {
					if v, ok := comp_symbol.value.(SymbolStructValue); ok {
						for name, i in v.names {
							if name == field.name {
								if symbol, ok := resolve_location_type_expression(&ast_context, v.types[i]); ok {
									append_symbol_to_locations(&locations, document, symbol)
									return locations[:], true
								}
							}
						}
					}
				} else if v, ok := comp_symbol.value.(SymbolBitFieldValue); ok {
					for name, i in v.names {
						if name == field.name {
							if symbol, ok := resolve_type_expression(&ast_context, v.types[i]); ok {
								append_symbol_to_locations(&locations, document, symbol)
								return locations[:], true
							}
						}
					}
				}
			}
		}
	}

	if position_context.selector != nil &&
	   position_context.identifier != nil &&
	   position_context.field == position_context.identifier {
		reset_ast_context(&ast_context)

		ast_context.current_package = ast_context.document_package

		//if the base selector is the client wants to go to.
		if base, ok := position_context.selector.derived.(^ast.Ident); ok && position_context.identifier != nil {
			ident := position_context.identifier.derived.(^ast.Ident)^

			if position_in_node(base, position_context.position) {
				if symbol, ok := resolve_location_type_identifier(&ast_context, ident); ok {
					append_symbol_to_locations(&locations, document, symbol)
					return locations[:], true
				}
			}
		}

		selector: Symbol

		selector, ok = resolve_type_expression(&ast_context, position_context.selector)

		if !ok {
			return {}, false
		}

		field: string

		if position_context.field != nil {
			#partial switch v in position_context.field.derived {
			case ^ast.Ident:
				field = v.name
			}
		}

		if v, is_proc := selector.value.(SymbolProcedureValue); is_proc {
			if len(v.return_types) == 0 || v.return_types[0].type == nil {
				return {}, false
			}

			set_ast_package_set_scoped(&ast_context, selector.pkg)

			if selector, ok = resolve_location_type_expression(&ast_context, v.return_types[0].type); !ok {
				return {}, false
			}
		}

		ast_context.current_package = selector.pkg

		#partial switch v in selector.value {
		case SymbolStructValue:
			for name, i in v.names {
				if name == field {
					if symbol, ok := resolve_location_type_expression(&ast_context, v.types[i]); ok {
						append_symbol_to_locations(&locations, document, symbol)
						return locations[:], true
					}
				}
			}
		case SymbolBitFieldValue:
			for name, i in v.names {
				if name == field {
					if symbol, ok := resolve_type_expression(&ast_context, v.types[i]); ok {
						append_symbol_to_locations(&locations, document, symbol)
						return locations[:], true
					}
				}
			}
		case SymbolPackageValue:
			if position_context.field != nil {
				if ident, ok := position_context.field.derived.(^ast.Ident); ok {
					// check to see if we are in a position call context
					if position_context.call != nil && ast_context.call == nil {
						if call, ok := position_context.call.derived.(^ast.Call_Expr); ok {
							if !position_in_exprs(call.args, position_context.position) {
								ast_context.call = call
							}
						}
					}
					if symbol, ok := resolve_type_identifier(&ast_context, ident^); ok {
						append_symbol_to_locations(&locations, document, symbol)
						return locations[:], true
					}
				}
			}
		}
	} else if position_context.identifier != nil {
		reset_ast_context(&ast_context)

		ast_context.current_package = ast_context.document_package

		ident := position_context.identifier.derived.(^ast.Ident)^

		if position_context.value_decl != nil {
			ident.pos = position_context.value_decl.end
			ident.end = position_context.value_decl.end
		}

		if position_context.call != nil {
			if call, ok := position_context.call.derived.(^ast.Call_Expr); ok {
				if !position_in_exprs(call.args, position_context.position) {
					ast_context.call = call
				}
			}
		}

		if symbol, ok := resolve_location_type_identifier(&ast_context, ident); ok {
			if symbol, ok := resolve_symbol_proc_first_return_symbol(&ast_context, symbol); ok {
				append_symbol_to_locations(&locations, document, symbol)
				return locations[:], true
			}
			append_symbol_to_locations(&locations, document, symbol)
			return locations[:], true
		}
	}

	return {}, false
}
