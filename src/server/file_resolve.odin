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
	Variable,
	Constant,
	StructElement,
	EnumElement,
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

	get_globals(document.ast, &ast_context)

	ast_context.current_package = ast_context.document_package

	symbols := make(map[uintptr]SymbolAndNode, 10000, allocator)

	for decl in document.ast.decls {
		if _, is_value := decl.derived.(^ast.Value_Decl); !is_value {
			continue
		}

		resolve_decl(&ast_context, document, decl, &symbols, allocator)
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
}

@(private = "file")
resolve_decl :: proc(
	ast_context: ^AstContext,
	document: ^Document,
	decl: ^ast.Node,
	symbols: ^map[uintptr]SymbolAndNode,
	allocator := context.allocator,
) {
	data := FileResolveData {
		ast_context = ast_context,
		symbols     = symbols,
		document    = document,
	}

	resolve_node(decl, &data)
}

@(private = "file")
resolve_node :: proc(node: ^ast.Node, data: ^FileResolveData) {
	using ast

	if node == nil {
		return
	}


	#partial switch n in node.derived {
	case ^Bad_Expr:
	case ^Ident:
		data.position_context.identifier = node
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
	case ^Proc_Lit:
		resolve_node(n.type, data)

		data.position_context.function = cast(^Proc_Lit)node
		append(
			&data.position_context.functions,
			data.position_context.function,
		)
		resolve_node(n.body, data)
	case ^Comp_Lit:
		//only set this for the parent comp literal, since we will need to walk through it to infer types.
		if data.position_context.parent_comp_lit == nil {
			data.position_context.parent_comp_lit = cast(^Comp_Lit)node
		}

		data.position_context.comp_lit = cast(^Comp_Lit)node

		resolve_node(n.type, data)
		resolve_nodes(n.elems, data)
	case ^Tag_Expr:
		resolve_node(n.expr, data)
	case ^Unary_Expr:
		resolve_node(n.expr, data)
	case ^Binary_Expr:
		if data.position_context.parent_binary == nil {
			data.position_context.parent_binary = cast(^Binary_Expr)node
		}
		data.position_context.binary = cast(^Binary_Expr)node
		resolve_node(n.left, data)
		resolve_node(n.right, data)
	case ^Paren_Expr:
		resolve_node(n.expr, data)
	case ^Call_Expr:
		data.position_context.call = cast(^Expr)node
		resolve_node(n.expr, data)
		resolve_nodes(n.args, data)
	case ^Selector_Call_Expr:
		data.position_context.selector = n.expr
		data.position_context.field = n.call
		data.position_context.selector_expr = cast(^Selector_Expr)node

		if _, ok := n.call.derived.(^ast.Call_Expr); ok {
			data.position_context.call = n.call
		}

		resolve_node(n.expr, data)
		resolve_node(n.call, data)

	case ^Selector_Expr:
		data.position_context.selector = n.expr
		data.position_context.field = n.field
		data.position_context.selector_expr = cast(^Selector_Expr)node
		resolve_node(n.expr, data)
		resolve_node(n.field, data)
	case ^Index_Expr:
		resolve_node(n.expr, data)
		resolve_node(n.index, data)
	case ^Deref_Expr:
		resolve_node(n.expr, data)
	case ^Slice_Expr:
		resolve_node(n.expr, data)
		resolve_node(n.low, data)
		resolve_node(n.high, data)
	case ^Field_Value:
		data.position_context.field_value = cast(^Field_Value)node
		resolve_node(n.field, data)
		resolve_node(n.value, data)
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
	case ^Assign_Stmt:
		data.position_context.assign = cast(^Assign_Stmt)node
		resolve_nodes(n.lhs, data)
		resolve_nodes(n.rhs, data)
	case ^Block_Stmt:
		resolve_node(n.label, data)
		resolve_nodes(n.stmts, data)
	case ^If_Stmt:
		resolve_node(n.label, data)
		resolve_node(n.init, data)
		resolve_node(n.cond, data)
		resolve_node(n.body, data)
		resolve_node(n.else_stmt, data)
	case ^When_Stmt:
		resolve_node(n.cond, data)
		resolve_node(n.body, data)
		resolve_node(n.else_stmt, data)
	case ^Return_Stmt:
		data.position_context.returns = cast(^Return_Stmt)node
		resolve_nodes(n.results, data)
	case ^Defer_Stmt:
		resolve_node(n.stmt, data)
	case ^For_Stmt:
		resolve_node(n.label, data)
		resolve_node(n.init, data)
		resolve_node(n.cond, data)
		resolve_node(n.post, data)
		resolve_node(n.body, data)
	case ^Range_Stmt:
		resolve_node(n.label, data)
		resolve_nodes(n.vals, data)
		resolve_node(n.expr, data)
		resolve_node(n.body, data)
	case ^Case_Clause:
		resolve_nodes(n.list, data)
		resolve_nodes(n.body, data)
	case ^Switch_Stmt:
		data.position_context.switch_stmt = cast(^Switch_Stmt)node
		resolve_node(n.label, data)
		resolve_node(n.init, data)
		resolve_node(n.cond, data)
		resolve_node(n.body, data)
	case ^Type_Switch_Stmt:
		data.position_context.switch_type_stmt = cast(^Type_Switch_Stmt)node
		resolve_node(n.label, data)
		resolve_node(n.tag, data)
		resolve_node(n.expr, data)
		resolve_node(n.body, data)
	case ^Branch_Stmt:
		resolve_node(n.label, data)
	case ^Using_Stmt:
		resolve_nodes(n.list, data)
	case ^Bad_Decl:
	case ^Value_Decl:
		data.position_context.value_decl = cast(^Value_Decl)node

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
		data.position_context.struct_type = cast(^Struct_Type)node
		resolve_node(n.poly_params, data)
		resolve_node(n.align, data)
		resolve_node(n.fields, data)
	case ^Union_Type:
		data.position_context.union_type = cast(^Union_Type)node
		resolve_node(n.poly_params, data)
		resolve_node(n.align, data)
		resolve_nodes(n.variants, data)
	case ^Enum_Type:
		data.position_context.enum_type = cast(^Enum_Type)node
		resolve_node(n.base_type, data)
		resolve_nodes(n.fields, data)
	case ^Bit_Set_Type:
		data.position_context.bitset_type = cast(^Bit_Set_Type)node
		resolve_node(n.elem, data)
		resolve_node(n.underlying, data)
	case ^Map_Type:
		resolve_node(n.key, data)
		resolve_node(n.value, data)
	case ^Implicit_Selector_Expr:
		data.position_context.implicit = true
		data.position_context.implicit_selector_expr = n
		resolve_node(n.field, data)
	case ^ast.Or_Else_Expr:
		resolve_node(n.x, data)
		resolve_node(n.y, data)
	case ^ast.Or_Return_Expr:
		resolve_node(n.expr, data)
	case ^ast.Bit_Field_Type:
		data.position_context.bit_field_type = cast(^Bit_Field_Type)node
		resolve_node(n.backing_type, data)
		resolve_nodes(n.fields, data)
	case ^ast.Bit_Field_Field:
		resolve_node(n.name, data)
		resolve_node(n.type, data)
		resolve_node(n.bit_size, data)
	case ^ast.Or_Branch_Expr:
		resolve_node(n.expr, data)
		resolve_node(n.label, data)
	case:
	}


}

@(private = "file")
resolve_nodes :: proc(array: []$T/^ast.Node, data: ^FileResolveData) {
	for elem in array {
		resolve_node(elem, data)
	}
}
