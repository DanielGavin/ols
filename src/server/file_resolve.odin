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

ResolveReferenceFlag :: enum {
	None,
	Identifier,
	Base,
	Field,
}

@(private = "file")
reset_position_context :: proc(position_context: ^DocumentPositionContext) {
	position_context.comp_lit = nil
	position_context.parent_comp_lit = nil
	position_context.identifier = nil
	position_context.call = nil
	position_context.binary = nil
	position_context.parent_binary = nil
	position_context.previous_index = nil
	position_context.index = nil
}

resolve_entire_file :: proc(
	document: ^Document,
	flag := ResolveReferenceFlag.None,
	allocator := context.allocator,
) -> map[uintptr]SymbolAndNode {
	ast_context := make_ast_context(
		document.ast,
		document.imports,
		document.package_name,
		document.uri.uri,
		document.fullpath,
		allocator,
	)

	position_context: DocumentPositionContext

	get_globals(document.ast, &ast_context)

	ast_context.current_package = ast_context.document_package

	symbols := make(map[uintptr]SymbolAndNode, 10000, allocator)

	for decl in document.ast.decls {
		if _, is_value := decl.derived.(^ast.Value_Decl); !is_value {
			continue
		}

		resolve_decl(&position_context, &ast_context, document, decl, &symbols, flag, allocator)
		clear(&ast_context.locals)
	}

	return symbols
}

FileResolveData :: struct {
	ast_context:      ^AstContext,
	symbols:          ^map[uintptr]SymbolAndNode,
	id_counter:       int,
	document:         ^Document,
	position_context: ^DocumentPositionContext,
	flag:             ResolveReferenceFlag,
}

@(private = "file")
resolve_decl :: proc(
	position_context: ^DocumentPositionContext,
	ast_context: ^AstContext,
	document: ^Document,
	decl: ^ast.Node,
	symbols: ^map[uintptr]SymbolAndNode,
	flag: ResolveReferenceFlag,
	allocator := context.allocator,
) {
	data := FileResolveData {
		position_context = position_context,
		ast_context      = ast_context,
		symbols          = symbols,
		document         = document,
		flag             = flag,
	}

	resolve_node(decl, &data)
}


@(private = "file")
local_scope_deferred :: proc(data: ^FileResolveData, stmt: ^ast.Stmt) {
	pop_local_group(data.ast_context)
}

@(deferred_in = local_scope_deferred)
@(private = "file")
local_scope :: proc(data: ^FileResolveData, stmt: ^ast.Stmt) {
	add_local_group(data.ast_context)

	if stmt == nil {
		return
	}

	data.position_context.position = stmt.end.offset
	data.position_context.nested_position = data.position_context.position

	data.ast_context.non_mutable_only = true

	get_locals_stmt(data.ast_context.file, stmt, data.ast_context, data.position_context)

	data.ast_context.non_mutable_only = false

	get_locals_stmt(data.ast_context.file, stmt, data.ast_context, data.position_context)
}

@(private = "file")
resolve_node :: proc(node: ^ast.Node, data: ^FileResolveData) {
	using ast

	if node == nil {
		return
	}

	reset_ast_context(data.ast_context)

	#partial switch n in node.derived {
	case ^Bad_Expr:
	case ^Ident:
		data.position_context.identifier = node
		if data.flag != .None {
			if symbol, ok := resolve_location_identifier(data.ast_context, n^); ok {
				data.symbols[cast(uintptr)node] = SymbolAndNode {
					node   = n,
					symbol = symbol,
				}
			}
		} else {
			if symbol, ok := resolve_type_identifier(data.ast_context, n^); ok {
				data.symbols[cast(uintptr)node] = SymbolAndNode {
					node   = n,
					symbol = symbol,
				}
			}
		}
	case ^Selector_Call_Expr:
		data.position_context.selector = n.expr
		data.position_context.field = n.call
		data.position_context.selector_expr = node

		if _, ok := n.call.derived.(^ast.Call_Expr); ok {
			data.position_context.call = n.call
		}

		resolve_node(n.expr, data)
		resolve_node(n.call, data)
	case ^Implicit_Selector_Expr:
		data.position_context.implicit = true
		data.position_context.implicit_selector_expr = n
		if data.flag != .None {
			data.position_context.position = n.pos.offset
			if symbol, ok := resolve_location_implicit_selector(data.ast_context, data.position_context, n); ok {
				data.symbols[cast(uintptr)node] = SymbolAndNode {
					node   = n,
					symbol = symbol,
				}
			}
		}
		resolve_node(n.field, data)
	case ^Selector_Expr:
		data.position_context.selector = n.expr
		data.position_context.field = n.field
		data.position_context.selector_expr = node

		if data.flag != .None {
			if symbol, ok := resolve_location_selector(data.ast_context, n); ok {
				if data.flag != .Base {
					data.symbols[cast(uintptr)node] = SymbolAndNode {
						node   = n.field,
						symbol = symbol,
					}
				} else {
					data.symbols[cast(uintptr)node] = SymbolAndNode {
						node   = n,
						symbol = symbol,
					}
				}
			}

			#partial switch v in n.expr.derived {
			// TODO: Should there be more here?
			case ^ast.Selector_Expr, ^ast.Index_Expr, ^ast.Ident, ^ast.Paren_Expr, ^ast.Call_Expr:
				resolve_node(n.expr, data)
			}
		} else {
			if symbol, ok := resolve_type_expression(data.ast_context, &n.node); ok {
				data.symbols[cast(uintptr)node] = SymbolAndNode {
					node   = n,
					symbol = symbol,
				}
			}

			resolve_node(n.expr, data)
			resolve_node(n.field, data)
		}


	case ^Field_Value:
		data.position_context.field_value = n

		if data.flag != .None && data.position_context.comp_lit != nil {
			data.position_context.position = n.pos.offset

			if symbol, ok := resolve_location_comp_lit_field(data.ast_context, data.position_context); ok {
				data.symbols[cast(uintptr)node] = SymbolAndNode {
					node   = n.field,
					symbol = symbol,
				}
			}

			resolve_node(n.value, data)
		} else {
			resolve_node(n.field, data)
			resolve_node(n.value, data)
		}
	case ^Proc_Lit:
		local_scope(data, n.body)

		get_locals_proc_param_and_results(data.ast_context.file, n^, data.ast_context, data.position_context)

		resolve_node(n.type, data)

		data.position_context.function = cast(^Proc_Lit)node

		append(&data.position_context.functions, data.position_context.function)

		resolve_node(n.body, data)
	case ^ast.Inline_Range_Stmt:
		local_scope(data, n)
		resolve_node(n.val0, data)
		resolve_node(n.val1, data)
		resolve_node(n.expr, data)
		resolve_node(n.body, data)
	case ^For_Stmt:
		local_scope(data, n)
		resolve_node(n.label, data)
		resolve_node(n.init, data)
		resolve_node(n.cond, data)
		resolve_node(n.post, data)
		resolve_node(n.body, data)
	case ^Range_Stmt:
		local_scope(data, n)
		resolve_node(n.label, data)
		resolve_nodes(n.vals, data)
		resolve_node(n.expr, data)
		resolve_node(n.body, data)
	case ^Switch_Stmt:
		local_scope(data, n)
		data.position_context.switch_stmt = n
		resolve_node(n.label, data)
		resolve_node(n.init, data)
		resolve_node(n.cond, data)
		resolve_node(n.body, data)
	case ^If_Stmt:
		local_scope(data, n)
		resolve_node(n.label, data)
		resolve_node(n.init, data)
		resolve_node(n.cond, data)
		resolve_node(n.body, data)
		resolve_node(n.else_stmt, data)
	case ^When_Stmt:
		local_scope(data, n)
		resolve_node(n.cond, data)
		resolve_node(n.body, data)
		resolve_node(n.else_stmt, data)
	case ^Block_Stmt:
		local_scope(data, n)
		resolve_node(n.label, data)
		resolve_nodes(n.stmts, data)
	case ^Implicit:
		if n.tok.text == "context" {
			data.position_context.implicit_context = n
		}
	case ^Undef:
	case ^Basic_Lit:
		data.position_context.basic_lit = cast(^Basic_Lit)node
	case ^Matrix_Index_Expr:
		resolve_node(n.expr, data)
		resolve_node(n.row_index, data)
		resolve_node(n.column_index, data)
	case ^Matrix_Type:
		resolve_node(n.row_count, data)
		resolve_node(n.column_count, data)
		resolve_node(n.elem, data)
	case ^Ellipsis:
		resolve_node(n.expr, data)
	case ^Comp_Lit:
		// We only want to resolve the values, not the types
		resolve_node(n.type, data)

		//only set this for the parent comp literal, since we will need to walk through it to infer types.
		set := false
		if data.position_context.parent_comp_lit == nil {
			set = true
			data.position_context.parent_comp_lit = n
		}
		defer if set {
			data.position_context.parent_comp_lit = nil
		}

		data.position_context.comp_lit = n
		resolve_nodes(n.elems, data)
	case ^Tag_Expr:
		resolve_node(n.expr, data)
	case ^Unary_Expr:
		resolve_node(n.expr, data)
	case ^Binary_Expr:
		if data.position_context.parent_binary == nil {
			data.position_context.parent_binary = cast(^Binary_Expr)node
		}
		data.position_context.binary = n
		resolve_node(n.left, data)
		resolve_node(n.right, data)
	case ^Paren_Expr:
		resolve_node(n.expr, data)
	case ^Call_Expr:
		old_call := data.ast_context.call

		data.position_context.call = n
		data.ast_context.call = n

		defer {
			data.position_context.call = old_call
		}

		resolve_node(n.expr, data)

		data.ast_context.call = old_call

		for arg in n.args {
			data.position_context.position = arg.pos.offset
			resolve_node(arg, data)
		}
	case ^Index_Expr:
		data.position_context.previous_index = data.position_context.index
		data.position_context.index = n
		resolve_node(n.expr, data)
		resolve_node(n.index, data)
	case ^Deref_Expr:
		resolve_node(n.expr, data)
	case ^Slice_Expr:
		resolve_node(n.expr, data)
		resolve_node(n.low, data)
		resolve_node(n.high, data)
	case ^Ternary_If_Expr:
		resolve_node(n.x, data)
		resolve_node(n.cond, data)
		resolve_node(n.y, data)
	case ^Ternary_When_Expr:
		resolve_node(n.x, data)
		resolve_node(n.cond, data)
		resolve_node(n.y, data)
	case ^Type_Assertion:
		resolve_node(n.expr, data)
		resolve_node(n.type, data)
	case ^Type_Cast:
		resolve_node(n.type, data)
		resolve_node(n.expr, data)
	case ^Auto_Cast:
		resolve_node(n.expr, data)
	case ^Bad_Stmt:
	case ^Empty_Stmt:
	case ^Expr_Stmt:
		resolve_node(n.expr, data)
	case ^Tag_Stmt:
		r := cast(^Tag_Stmt)node
		resolve_node(r.stmt, data)
	case ^Return_Stmt:
		data.position_context.returns = n
		resolve_nodes(n.results, data)
	case ^Defer_Stmt:
		resolve_node(n.stmt, data)
	case ^Case_Clause:
		local_scope(data, n)
		resolve_nodes(n.list, data)
		resolve_nodes(n.body, data)
	case ^Type_Switch_Stmt:
		data.position_context.switch_type_stmt = n
		resolve_node(n.label, data)
		resolve_node(n.tag, data)
		resolve_node(n.expr, data)
		resolve_node(n.body, data)
	case ^Branch_Stmt:
		resolve_node(n.label, data)
	case ^Using_Stmt:
		resolve_nodes(n.list, data)
	case ^Bad_Decl:
	case ^Assign_Stmt:
		data.position_context.assign = n
		reset_position_context(data.position_context)
		resolve_nodes(n.lhs, data)
		resolve_nodes(n.rhs, data)
	case ^Value_Decl:
		data.position_context.value_decl = n

		reset_position_context(data.position_context)
		resolve_nodes(n.names, data)
		resolve_node(n.type, data)
		resolve_nodes(n.values, data)
	case ^Package_Decl:
	case ^Import_Decl:
	case ^Foreign_Block_Decl:
		resolve_node(n.foreign_library, data)
		resolve_node(n.body, data)
	case ^Foreign_Import_Decl:
		resolve_node(n.name, data)
	case ^Proc_Group:
		resolve_nodes(n.args, data)
	case ^Attribute:
		resolve_nodes(n.elems, data)
	case ^Field:
		resolve_nodes(n.names, data)
		resolve_node(n.type, data)
		resolve_node(n.default_value, data)
	case ^Field_List:
		resolve_nodes(n.list, data)
	case ^Typeid_Type:
		resolve_node(n.specialization, data)
	case ^Helper_Type:
		resolve_node(n.type, data)
	case ^Distinct_Type:
		resolve_node(n.type, data)
	case ^Poly_Type:
		resolve_node(n.type, data)
		resolve_node(n.specialization, data)
	case ^Proc_Type:
		resolve_node(n.params, data)
		resolve_node(n.results, data)
	case ^Pointer_Type:
		resolve_node(n.elem, data)
	case ^Array_Type:
		resolve_node(n.len, data)
		resolve_node(n.elem, data)
	case ^Dynamic_Array_Type:
		resolve_node(n.elem, data)
	case ^Multi_Pointer_Type:
		resolve_node(n.elem, data)
	case ^Struct_Type:
		data.position_context.struct_type = n
		resolve_node(n.poly_params, data)
		resolve_node(n.align, data)
		resolve_node(n.fields, data)

		if data.flag != .None {
			for field in n.fields.list {
				for name in field.names {
					data.symbols[cast(uintptr)name] = SymbolAndNode {
						node = name,
						symbol = Symbol{
							range = common.get_token_range(name, string(data.document.text)),
							uri = strings.clone(common.create_uri(field.pos.file, data.ast_context.allocator).uri, data.ast_context.allocator),
						},
					}
				}
			}
		}
	case ^Union_Type:
		data.position_context.union_type = n
		resolve_node(n.poly_params, data)
		resolve_node(n.align, data)
		resolve_nodes(n.variants, data)
	case ^Enum_Type:
		data.position_context.enum_type = n
		resolve_node(n.base_type, data)
		resolve_nodes(n.fields, data)

		if data.flag != .None {
			for field in n.fields {
				data.symbols[cast(uintptr)field] = SymbolAndNode {
					node = field,
					symbol = Symbol{
						range = common.get_token_range(field, string(data.document.text)),
						uri = strings.clone(common.create_uri(field.pos.file, data.ast_context.allocator).uri, data.ast_context.allocator),
					},
				}
				// In the case of a Field_Value, we explicitly add them so we can find the LHS correctly for things like renaming
				if field, ok := field.derived.(^ast.Field_Value); ok {
					if ident, ok := field.field.derived.(^ast.Ident); ok {
						data.symbols[cast(uintptr)ident] = SymbolAndNode {
							node = ident,
							symbol = Symbol{
								name = ident.name,
								range = common.get_token_range(ident, string(data.document.text)),
								uri = strings.clone(common.create_uri(field.pos.file, data.ast_context.allocator).uri, data.ast_context.allocator),
							},
						}
					} else if binary, ok := field.field.derived.(^ast.Binary_Expr); ok {
						data.symbols[cast(uintptr)binary] = SymbolAndNode {
							node = binary,
							symbol = Symbol{
								name = "binary",
								range = common.get_token_range(binary, string(data.document.text)),
								uri = strings.clone(common.create_uri(field.pos.file, data.ast_context.allocator).uri, data.ast_context.allocator),
							},
						}
					}
				}
			}
		}
	case ^Bit_Set_Type:
		data.position_context.bitset_type = n
		resolve_node(n.elem, data)
		resolve_node(n.underlying, data)
	case ^Map_Type:
		resolve_node(n.key, data)
		resolve_node(n.value, data)
	case ^Or_Else_Expr:
		resolve_node(n.x, data)
		resolve_node(n.y, data)
	case ^Or_Return_Expr:
		resolve_node(n.expr, data)
	case ^Or_Branch_Expr:
		resolve_node(n.expr, data)
		resolve_node(n.label, data)
	case ^Bit_Field_Type:
		data.position_context.bit_field_type = n
		resolve_node(n.backing_type, data)
		resolve_nodes(n.fields, data)
	case ^Bit_Field_Field:
		resolve_node(n.name, data)
		resolve_node(n.type, data)
		resolve_node(n.bit_size, data)
	case:
	}


}

@(private = "file")
resolve_nodes :: proc(array: []$T/^ast.Node, data: ^FileResolveData) {
	for elem in array {
		resolve_node(elem, data)
	}
}
