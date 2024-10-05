package server

import "core:fmt"
import "core:log"
import "core:mem"
import "core:odin/ast"
import "core:odin/parser"
import "core:odin/tokenizer"
import "core:path/filepath"
import path "core:path/slashpath"
import "core:reflect"
import "core:slice"
import "core:sort"
import "core:strconv"
import "core:strings"
import "core:unicode/utf8"

import "src:common"

resolve_poly :: proc(
	ast_context: ^AstContext,
	call_node: ^ast.Expr,
	call_symbol: Symbol,
	poly_node: ^ast.Expr,
	poly_map: ^map[string]^ast.Expr,
) -> bool {
	if poly_node == nil || call_node == nil {
		return false
	}

	specialization: ^ast.Expr
	type: ^ast.Expr

	poly_node := poly_node
	poly_node, _, _ = common.unwrap_pointer_expr(poly_node)

	#partial switch v in poly_node.derived {
	case ^ast.Typeid_Type:
		specialization = v.specialization
	case ^ast.Poly_Type:
		specialization = v.specialization
		type = v.type
	case:
		specialization = poly_node
	}

	if specialization == nil {
		if type != nil {
			if ident, ok := unwrap_ident(type); ok {
				if untyped_value, ok := call_symbol.value.(SymbolUntypedValue); ok {
					save_poly_map(ident, symbol_to_expr(call_symbol, call_node.pos.file), poly_map)
				} else {
					save_poly_map(
						ident,
						make_ident_ast(ast_context, call_node.pos, call_node.end, call_symbol.name),
						poly_map,
					)
				}
			}
		}
		return true
	} else if type != nil {
		if ident, ok := unwrap_ident(type); ok {
			save_poly_map(ident, specialization, poly_map)
		}
	}

	#partial switch p in specialization.derived {
	case ^ast.Matrix_Type:
		if call_matrix, ok := call_node.derived.(^ast.Matrix_Type); ok {
			found := false
			if poly_type, ok := p.row_count.derived.(^ast.Poly_Type); ok {
				if ident, ok := unwrap_ident(poly_type.type); ok {
					save_poly_map(ident, call_matrix.row_count, poly_map)
				}

				if poly_type.specialization != nil {
					return resolve_poly(ast_context, call_matrix.row_count, call_symbol, p.row_count, poly_map)
				}
				found |= true
			}

			if poly_type, ok := p.column_count.derived.(^ast.Poly_Type); ok {
				if ident, ok := unwrap_ident(poly_type.type); ok {
					save_poly_map(ident, call_matrix.column_count, poly_map)
				}

				if poly_type.specialization != nil {
					return resolve_poly(ast_context, call_matrix.column_count, call_symbol, p.column_count, poly_map)
				}
				found |= true
			}

			if poly_type, ok := p.elem.derived.(^ast.Poly_Type); ok {
				if ident, ok := unwrap_ident(poly_type.type); ok {
					save_poly_map(ident, call_matrix.elem, poly_map)
				}

				if poly_type.specialization != nil {
					return resolve_poly(ast_context, call_matrix.elem, call_symbol, p.elem, poly_map)
				}
				found |= true
			}
			return found
		}
	case ^ast.Call_Expr:
		if call_struct, ok := call_node.derived.(^ast.Struct_Type); ok {
			arg_index := 0
			struct_value := call_symbol.value.(SymbolStructValue)
			found := false
			for arg in p.args {
				if poly_type, ok := arg.derived.(^ast.Poly_Type); ok {
					if poly_type.type == nil || struct_value.poly == nil || len(struct_value.args) <= arg_index {
						return false
					}

					save_poly_map(poly_type.type, struct_value.args[arg_index], poly_map)

					arg_index += 1
					found |= true
				}
			}

			return found
		}
	case ^ast.Dynamic_Array_Type:
		if call_array, ok := call_node.derived.(^ast.Dynamic_Array_Type); ok {

			if common.dynamic_array_is_soa(p^) != common.dynamic_array_is_soa(call_array^) {
				return false
			}

			//It's not enough for them to both arrays, they also have to share soa attributes
			if p.tag != nil && call_array.tag != nil {
				a, ok1 := p.tag.derived.(^ast.Basic_Directive)
				b, ok2 := call_array.tag.derived.(^ast.Basic_Directive)

				if ok1 && ok2 && (a.name == "soa" || b.name == "soa") && a.name != b.name {
					return false
				}
			}

			if poly_type, ok := p.elem.derived.(^ast.Poly_Type); ok {
				if ident, ok := unwrap_ident(poly_type.type); ok {
					save_poly_map(ident, call_array.elem, poly_map)
				}

				if poly_type.specialization != nil {
					return resolve_poly(ast_context, call_array.elem, call_symbol, p.elem, poly_map)
				}
				return true
			}
		}
	case ^ast.Array_Type:
		if call_array, ok := call_node.derived.(^ast.Array_Type); ok {
			found := false

			if common.array_is_soa(p^) != common.array_is_soa(call_array^) {
				return false
			}

			//It's not enough for them to both arrays, they also have to share soa attributes
			if p.tag != nil && call_array.tag != nil {
				a, ok1 := p.tag.derived.(^ast.Basic_Directive)
				b, ok2 := call_array.tag.derived.(^ast.Basic_Directive)

				if ok1 && ok2 && (a.name == "soa" || b.name == "soa") && a.name != b.name {
					return false
				}
			}

			if poly_type, ok := p.elem.derived.(^ast.Poly_Type); ok {
				if ident, ok := unwrap_ident(poly_type.type); ok {
					save_poly_map(ident, call_array.elem, poly_map)
				}

				if poly_type.specialization != nil {
					return resolve_poly(ast_context, call_array.elem, call_symbol, p.elem, poly_map)
				}
				found |= true
			}
			if p.len != nil {
				if poly_type, ok := p.len.derived.(^ast.Poly_Type); ok {
					if ident, ok := unwrap_ident(poly_type.type); ok {
						save_poly_map(ident, call_array.len, poly_map)
					}

					if poly_type.specialization != nil {
						return resolve_poly(ast_context, call_array.len, call_symbol, p.len, poly_map)
					}
					found |= true
				}
			}

			return found
		}
	case ^ast.Map_Type:
		if call_map, ok := call_node.derived.(^ast.Map_Type); ok {
			found := false
			if poly_type, ok := p.key.derived.(^ast.Poly_Type); ok {
				if ident, ok := unwrap_ident(poly_type.type); ok {
					save_poly_map(ident, call_map.key, poly_map)
				}

				if poly_type.specialization != nil {
					return resolve_poly(ast_context, call_map.key, call_symbol, p.key, poly_map)
				}
				found |= true
			}

			if poly_type, ok := p.value.derived.(^ast.Poly_Type); ok {
				if ident, ok := unwrap_ident(poly_type.type); ok {
					save_poly_map(ident, call_map.value, poly_map)
				}

				if poly_type.specialization != nil {
					return resolve_poly(ast_context, call_map.value, call_symbol, p.value, poly_map)
				}
				found |= true
			}
			return found
		}
	case ^ast.Multi_Pointer_Type:
		if call_pointer, ok := call_node.derived.(^ast.Multi_Pointer_Type); ok {
			if poly_type, ok := p.elem.derived.(^ast.Poly_Type); ok {
				if ident, ok := unwrap_ident(poly_type.type); ok {
					save_poly_map(ident, call_pointer.elem, poly_map)
				}

				if poly_type.specialization != nil {
					return resolve_poly(ast_context, call_pointer.elem, call_symbol, p.elem, poly_map)
				}
				return true
			}
		}
	case ^ast.Pointer_Type:
		if call_pointer, ok := call_node.derived.(^ast.Pointer_Type); ok {
			if poly_type, ok := p.elem.derived.(^ast.Poly_Type); ok {
				if ident, ok := unwrap_ident(poly_type.type); ok {
					save_poly_map(ident, call_pointer.elem, poly_map)
				}

				if poly_type.specialization != nil {
					return resolve_poly(ast_context, call_pointer.elem, call_symbol, p.elem, poly_map)
				}
				return true
			}
		}
	case ^ast.Comp_Lit:
		if comp_lit, ok := call_node.derived.(^ast.Comp_Lit); ok {
			if poly_type, ok := p.type.derived.(^ast.Poly_Type); ok {
				if ident, ok := unwrap_ident(poly_type.type); ok {
					save_poly_map(ident, comp_lit.type, poly_map)
				}

				if poly_type.specialization != nil {
					return resolve_poly(ast_context, comp_lit.type, call_symbol, p.type, poly_map)
				}
				return true
			}
		}
	case ^ast.Struct_Type, ^ast.Proc_Type:
	case ^ast.Ident:
		return true
	case:
		return false
	}

	return false
}

is_generic_type_recursive :: proc(expr: ^ast.Expr, name: string) -> bool {
	Data :: struct {
		name:   string,
		exists: bool,
	}

	visit_function :: proc(visitor: ^ast.Visitor, node: ^ast.Node) -> ^ast.Visitor {
		if node == nil {
			return nil
		}

		data := cast(^Data)visitor.data

		if ident, ok := node.derived.(^ast.Ident); ok {
			if ident.name == data.name {
				data.exists = true
				return nil
			}
		}

		return visitor
	}

	data := Data {
		name = name,
	}

	visitor := ast.Visitor {
		data  = &data,
		visit = visit_function,
	}

	ast.walk(&visitor, expr)

	return data.exists
}

save_poly_map :: proc(ident: ^ast.Ident, expr: ^ast.Expr, poly_map: ^map[string]^ast.Expr) {
	if ident == nil || expr == nil {
		return
	}
	poly_map[ident.name] = expr
}

get_poly_map :: proc(node: ^ast.Node, poly_map: ^map[string]^ast.Expr) -> (^ast.Expr, bool) {
	if node == nil {
		return {}, false
	}

	if ident, ok := node.derived.(^ast.Ident); ok {
		if v, ok := poly_map[ident.name]; ok && !is_generic_type_recursive(v, ident.name) {
			return v, ok
		}
	}
	if poly, ok := node.derived.(^ast.Poly_Type); ok && poly.type != nil {
		if v, ok := poly_map[poly.type.name]; ok && !is_generic_type_recursive(v, poly.type.name) {
			return v, ok
		}
	}

	return nil, false
}

find_and_replace_poly_type :: proc(expr: ^ast.Expr, poly_map: ^map[string]^ast.Expr) {
	visit_function :: proc(visitor: ^ast.Visitor, node: ^ast.Node) -> ^ast.Visitor {
		if node == nil {
			return nil
		}

		poly_map := cast(^map[string]^ast.Expr)visitor.data

		#partial switch v in node.derived {
		case ^ast.Comp_Lit:
			if expr, ok := get_poly_map(v.type, poly_map); ok {
				v.type = expr
				v.pos.file = expr.pos.file
				v.end.file = expr.end.file
			}
		case ^ast.Matrix_Type:
			if expr, ok := get_poly_map(v.elem, poly_map); ok {
				v.elem = expr
				v.pos.file = expr.pos.file
				v.end.file = expr.end.file
			}
			if expr, ok := get_poly_map(v.column_count, poly_map); ok {
				v.column_count = expr
				v.pos.file = expr.pos.file
				v.end.file = expr.end.file
			}
			if expr, ok := get_poly_map(v.row_count, poly_map); ok {
				v.row_count = expr
				v.pos.file = expr.pos.file
				v.end.file = expr.end.file
			}
		case ^ast.Dynamic_Array_Type:
			if expr, ok := get_poly_map(v.elem, poly_map); ok {
				v.elem = expr
				v.pos.file = expr.pos.file
				v.end.file = expr.end.file
			}
		case ^ast.Array_Type:
			if expr, ok := get_poly_map(v.elem, poly_map); ok {
				v.elem = expr
				v.pos.file = expr.pos.file
				v.end.file = expr.end.file
			}
			if expr, ok := get_poly_map(v.len, poly_map); ok {
				v.len = expr
				v.pos.file = expr.pos.file
				v.end.file = expr.end.file
			}
		case ^ast.Multi_Pointer_Type:
			if expr, ok := get_poly_map(v.elem, poly_map); ok {
				v.elem = expr
				v.pos.file = expr.pos.file
				v.end.file = expr.end.file
			}
		case ^ast.Pointer_Type:
			if expr, ok := get_poly_map(v.elem, poly_map); ok {
				v.elem = expr
				v.pos.file = expr.pos.file
				v.end.file = expr.end.file
			}
		case ^ast.Proc_Type:
			if v.params != nil {
				for param in v.params.list {
					if expr, ok := get_poly_map(param.type, poly_map); ok {
						param.type = expr
						param.pos.file = expr.pos.file
						param.end.file = expr.end.file
					}
				}
			}

			if v.results != nil {
				for result in v.results.list {
					if expr, ok := get_poly_map(result.type, poly_map); ok {
						result.type = expr
						result.pos.file = expr.pos.file
						result.end.file = expr.end.file
					}
				}
			}
		}

		return visitor
	}

	visitor := ast.Visitor {
		data  = poly_map,
		visit = visit_function,
	}

	ast.walk(&visitor, expr)
}

resolve_generic_function :: proc {
	resolve_generic_function_ast,
	resolve_generic_function_symbol,
}

resolve_generic_function_ast :: proc(ast_context: ^AstContext, proc_lit: ast.Proc_Lit) -> (Symbol, bool) {
	if proc_lit.type.params == nil {
		return Symbol{}, false
	}

	if proc_lit.type.results == nil {
		return Symbol{}, false
	}

	if ast_context.call == nil {
		return Symbol{}, false
	}

	return resolve_generic_function_symbol(ast_context, proc_lit.type.params.list, proc_lit.type.results.list)
}


resolve_generic_function_symbol :: proc(
	ast_context: ^AstContext,
	params: []^ast.Field,
	results: []^ast.Field,
) -> (
	Symbol,
	bool,
) {
	if params == nil {
		return {}, false
	}

	if results == nil {
		return {}, false
	}

	if ast_context.call == nil {
		return {}, false
	}

	call_expr := ast_context.call

	poly_map := make(map[string]^ast.Expr, 0, context.temp_allocator)

	i := 0
	count_required_params := 0

	for param in params {
		if param.default_value == nil {
			count_required_params += 1
		}

		for name in param.names {
			if len(call_expr.args) <= i {
				break
			}

			if param.type == nil {
				continue
			}

			reset_ast_context(ast_context)

			ast_context.current_package = ast_context.document_package

			if symbol, ok := resolve_type_expression(ast_context, call_expr.args[i]); ok {
				symbol_expr := symbol_to_expr(symbol, call_expr.args[i].pos.file, context.temp_allocator)

				if symbol_expr == nil {
					return {}, false
				}

				//If we have a function call, we should instead look at the return value: bar(foo(123))
				if symbol_value, ok := symbol.value.(SymbolProcedureValue); ok && len(symbol_value.return_types) > 0 {
					if _, ok := call_expr.args[i].derived.(^ast.Call_Expr); ok {
						if symbol_value.return_types[0].type != nil {
							if symbol, ok = resolve_type_expression(ast_context, symbol_value.return_types[0].type);
							   ok {
								symbol_expr = symbol_to_expr(
									symbol,
									call_expr.args[i].pos.file,
									context.temp_allocator,
								)
								if symbol_expr == nil {
									return {}, false
								}
							}
						}
					}
				}

				symbol_expr = clone_expr(symbol_expr, ast_context.allocator, nil)
				param_type := clone_expr(param.type, ast_context.allocator, nil)

				if resolve_poly(ast_context, symbol_expr, symbol, param_type, &poly_map) {
					if poly, ok := name.derived.(^ast.Poly_Type); ok {
						poly_map[poly.type.name] = clone_expr(call_expr.args[i], ast_context.allocator, nil)
					}
				}
			}

			i += 1
		}
	}


	for k, v in poly_map {
		find_and_replace_poly_type(v, &poly_map)
	}

	if count_required_params > len(call_expr.args) || count_required_params == 0 || len(call_expr.args) == 0 {
		return {}, false
	}

	function_name := ""
	function_range: common.Range

	if ident, ok := call_expr.expr.derived.(^ast.Ident); ok {
		function_name = ident.name
		function_range = common.get_token_range(ident, ast_context.file.src)
	} else if selector, ok := call_expr.expr.derived.(^ast.Selector_Expr); ok {
		function_name = selector.field.name
		function_range = common.get_token_range(selector, ast_context.file.src)
	} else {
		return {}, false
	}

	symbol := Symbol {
		range = function_range,
		type  = .Function,
		name  = function_name,
		pkg   = ast_context.current_package,
	}

	return_types := make([dynamic]^ast.Field, ast_context.allocator)
	argument_types := make([dynamic]^ast.Field, ast_context.allocator)

	for result in results {
		if result.type == nil {
			continue
		}

		field := cast(^ast.Field)clone_node(result, ast_context.allocator, nil)

		if ident, ok := unwrap_ident(field.type); ok {
			if expr, ok := poly_map[ident.name]; ok {
				field.type = expr
			}
		}

		find_and_replace_poly_type(field.type, &poly_map)

		append(&return_types, field)
	}


	for param in params {
		field := cast(^ast.Field)clone_node(param, ast_context.allocator, nil)

		if field.type != nil {
			if poly_type, ok := field.type.derived.(^ast.Poly_Type); ok {
				if expr, ok := poly_map[poly_type.type.name]; ok {
					field.type = expr
				}
			} else {
				if ident, ok := unwrap_ident(field.type); ok {
					if expr, ok := poly_map[ident.name]; ok {
						field.type = expr
					}
				}

				find_and_replace_poly_type(field.type, &poly_map)
			}
		}

		if len(param.names) > 0 {
			if poly_type, ok := param.names[0].derived.(^ast.Poly_Type); ok && param.type != nil {
				if m, ok := poly_map[poly_type.type.name]; ok {
					field.type = m
				}
			}
		}

		append(&argument_types, field)
	}


	symbol.value = SymbolProcedureValue {
		return_types      = return_types[:],
		arg_types         = argument_types[:],
		orig_arg_types    = params[:],
		orig_return_types = results[:],
	}

	return symbol, true
}

is_procedure_generic :: proc(proc_type: ^ast.Proc_Type) -> bool {
	if proc_type.generic {
		return true
	}

	for param in proc_type.params.list {
		if param.type == nil {
			continue
		}

		if common.expr_contains_poly(param.type) {
			return true
		}
	}

	return false
}


resolve_poly_struct :: proc(ast_context: ^AstContext, poly_params: ^ast.Field_List, symbol: ^Symbol) {
	if ast_context.call == nil {
		return
	}

	symbol_value := &symbol.value.(SymbolStructValue)

	if symbol_value == nil {
		return
	}

	i := 0

	poly_map := make(map[string]^ast.Expr, 0, context.temp_allocator)
	args := make([dynamic]^ast.Expr, 0, context.temp_allocator)

	for param in poly_params.list {
		for name in param.names {
			if len(ast_context.call.args) <= i {
				break
			}

			if param.type == nil {
				continue
			}

			if poly, ok := param.type.derived.(^ast.Typeid_Type); ok {
				if ident, ok := name.derived.(^ast.Ident); ok {
					poly_map[ident.name] = ast_context.call.args[i]
				} else if poly, ok := name.derived.(^ast.Poly_Type); ok {
					if poly.type != nil {
						poly_map[poly.type.name] = ast_context.call.args[i]
					}
				}
			}

			append(&args, ast_context.call.args[i])

			i += 1
		}
	}

	Visit_Data :: struct {
		poly_map:     map[string]^ast.Expr,
		symbol_value: ^SymbolStructValue,
		parent:       ^ast.Node,
		i:            int,
		poly_index:   int,
	}

	visit :: proc(visitor: ^ast.Visitor, node: ^ast.Node) -> ^ast.Visitor {
		if node == nil || visitor == nil {
			return nil
		}

		data := cast(^Visit_Data)visitor.data

		if ident, ok := node.derived.(^ast.Ident); ok {
			if expr, ok := data.poly_map[ident.name]; ok {
				if data.parent != nil {
					#partial switch &v in data.parent.derived {
					case ^ast.Array_Type:
						v.elem = expr
					case ^ast.Dynamic_Array_Type:
						v.elem = expr
					case ^ast.Pointer_Type:
						v.elem = expr
					}
				} else {
					data.symbol_value.types[data.i] = expr
					data.poly_index += 1
				}
			}
		}

		#partial switch v in node.derived {
		case ^ast.Array_Type, ^ast.Dynamic_Array_Type, ^ast.Selector_Expr, ^ast.Pointer_Type:
			data.parent = node
		}

		return visitor
	}

	for type, i in symbol_value.types {
		data := Visit_Data {
			poly_map     = poly_map,
			symbol_value = symbol_value,
			i            = i,
		}

		visitor := ast.Visitor {
			data  = &data,
			visit = visit,
		}

		ast.walk(&visitor, type)
	}

	symbol_value.args = args[:]
}


resolve_poly_union :: proc(ast_context: ^AstContext, poly_params: ^ast.Field_List, symbol: ^Symbol) {
	if ast_context.call == nil {
		return
	}

	symbol_value := &symbol.value.(SymbolUnionValue)

	if symbol_value == nil {
		return
	}

	i := 0

	poly_map := make(map[string]^ast.Expr, 0, context.temp_allocator)

	for param in poly_params.list {
		for name in param.names {
			if len(ast_context.call.args) <= i {
				break
			}

			if param.type == nil {
				continue
			}

			if poly, ok := param.type.derived.(^ast.Typeid_Type); ok {
				if ident, ok := name.derived.(^ast.Ident); ok {
					poly_map[ident.name] = ast_context.call.args[i]
				} else if poly, ok := name.derived.(^ast.Poly_Type); ok {
					if poly.type != nil {
						poly_map[poly.type.name] = ast_context.call.args[i]
					}
				}
			}

			i += 1
		}
	}

	for type, i in symbol_value.types {
		if ident, ok := type.derived.(^ast.Ident); ok {
			if expr, ok := poly_map[ident.name]; ok {
				symbol_value.types[i] = expr
			}
		} else if call_expr, ok := type.derived.(^ast.Call_Expr); ok {
			if call_expr.args == nil {
				continue
			}

			for arg, i in call_expr.args {
				if ident, ok := arg.derived.(^ast.Ident); ok {
					if expr, ok := poly_map[ident.name]; ok {
						symbol_value.types[i] = expr
					}
				}
			}
		}
	}
}
