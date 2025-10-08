package server

import "base:intrinsics"

import "core:fmt"
import "core:log"
import "core:mem"
import "core:odin/ast"
import "core:odin/tokenizer"
import "core:reflect"
import "core:strings"

_ :: intrinsics

new_type :: proc($T: typeid, pos, end: tokenizer.Pos, allocator: mem.Allocator) -> ^T {
	n, _ := mem.new(T, allocator)
	n.pos = pos
	n.end = end
	n.derived = n
	base: ^ast.Node = n // dummy check
	_ = base // "Use" type to make -vet happy
	when intrinsics.type_has_field(T, "derived_expr") {
		n.derived_expr = n
	}
	when intrinsics.type_has_field(T, "derived_stmt") {
		n.derived_stmt = n
	}
	return n
}

// Recursively deduplicate strings in AST nodes without cloning the structure
deduplicate_node_strings :: proc(node: ^ast.Node, unique_strings: ^map[string]string, allocator: mem.Allocator) {
	using ast
	if node == nil || unique_strings == nil {
		return
	}

	// Deduplicate position file names
	if node.pos.file != "" {
		node.pos.file = get_index_unique_string(unique_strings, allocator, node.pos.file)
	}
	if node.end.file != "" {
		node.end.file = get_index_unique_string(unique_strings, allocator, node.end.file)
	}

	// Deduplicate strings in the specific node type
	#partial switch n in node.derived {
	case ^Ident:
		n.name = get_index_unique_string(unique_strings, allocator, n.name)
	case ^Basic_Lit:
		n.tok.text = get_index_unique_string(unique_strings, allocator, n.tok.text)
	case ^Basic_Directive:
		n.name = get_index_unique_string(unique_strings, allocator, n.name)
	case ^Implicit:
		n.tok.text = get_index_unique_string(unique_strings, allocator, n.tok.text)
	case ^Unary_Expr:
		n.op.text = get_index_unique_string(unique_strings, allocator, n.op.text)
		deduplicate_node_strings(n.expr, unique_strings, allocator)
	case ^Binary_Expr:
		n.op.text = get_index_unique_string(unique_strings, allocator, n.op.text)
		deduplicate_node_strings(n.left, unique_strings, allocator)
		deduplicate_node_strings(n.right, unique_strings, allocator)
	case ^Ellipsis:
		deduplicate_node_strings(n.expr, unique_strings, allocator)
	case ^Tag_Expr:
		deduplicate_node_strings(n.expr, unique_strings, allocator)
	case ^Paren_Expr:
		deduplicate_node_strings(n.expr, unique_strings, allocator)
	case ^Selector_Expr:
		deduplicate_node_strings(n.expr, unique_strings, allocator)
		deduplicate_node_strings(n.field, unique_strings, allocator)
	case ^Implicit_Selector_Expr:
		deduplicate_node_strings(n.field, unique_strings, allocator)
	case ^Slice_Expr:
		deduplicate_node_strings(n.expr, unique_strings, allocator)
		deduplicate_node_strings(n.low, unique_strings, allocator)
		deduplicate_node_strings(n.high, unique_strings, allocator)
	case ^Attribute:
		deduplicate_array_strings(n.elems, unique_strings, allocator)
	case ^Distinct_Type:
		deduplicate_node_strings(n.type, unique_strings, allocator)
	case ^Proc_Type:
		deduplicate_node_strings(n.params, unique_strings, allocator)
		deduplicate_node_strings(n.results, unique_strings, allocator)
	case ^Pointer_Type:
		deduplicate_node_strings(n.tag, unique_strings, allocator)
		deduplicate_node_strings(n.elem, unique_strings, allocator)
	case ^Array_Type:
		deduplicate_node_strings(n.len, unique_strings, allocator)
		deduplicate_node_strings(n.elem, unique_strings, allocator)
		deduplicate_node_strings(n.tag, unique_strings, allocator)
	case ^Dynamic_Array_Type:
		deduplicate_node_strings(n.elem, unique_strings, allocator)
		deduplicate_node_strings(n.tag, unique_strings, allocator)
	case ^Struct_Type:
		deduplicate_node_strings(n.poly_params, unique_strings, allocator)
		deduplicate_node_strings(n.align, unique_strings, allocator)
		deduplicate_node_strings(n.fields, unique_strings, allocator)
		deduplicate_array_strings(n.where_clauses, unique_strings, allocator)
		deduplicate_node_strings(n.max_field_align, unique_strings, allocator)
		deduplicate_node_strings(n.min_field_align, unique_strings, allocator)
	case ^Field:
		deduplicate_array_strings(n.names, unique_strings, allocator)
		deduplicate_node_strings(n.type, unique_strings, allocator)
		deduplicate_node_strings(n.default_value, unique_strings, allocator)
		deduplicate_node_strings(n.docs, unique_strings, allocator)
		deduplicate_node_strings(n.comment, unique_strings, allocator)
	case ^Field_List:
		deduplicate_array_strings(n.list, unique_strings, allocator)
	case ^Field_Value:
		deduplicate_node_strings(n.field, unique_strings, allocator)
		deduplicate_node_strings(n.value, unique_strings, allocator)
	case ^Union_Type:
		deduplicate_node_strings(n.poly_params, unique_strings, allocator)
		deduplicate_node_strings(n.align, unique_strings, allocator)
		deduplicate_array_strings(n.variants, unique_strings, allocator)
		deduplicate_array_strings(n.where_clauses, unique_strings, allocator)
	case ^Enum_Type:
		deduplicate_node_strings(n.base_type, unique_strings, allocator)
		deduplicate_array_strings(n.fields, unique_strings, allocator)
	case ^Bit_Set_Type:
		deduplicate_node_strings(n.elem, unique_strings, allocator)
		deduplicate_node_strings(n.underlying, unique_strings, allocator)
	case ^Map_Type:
		deduplicate_node_strings(n.key, unique_strings, allocator)
		deduplicate_node_strings(n.value, unique_strings, allocator)
	case ^Call_Expr:
		deduplicate_node_strings(n.expr, unique_strings, allocator)
		deduplicate_array_strings(n.args, unique_strings, allocator)
	case ^Typeid_Type:
		deduplicate_node_strings(n.specialization, unique_strings, allocator)
	case ^Ternary_When_Expr:
		deduplicate_node_strings(n.x, unique_strings, allocator)
		deduplicate_node_strings(n.cond, unique_strings, allocator)
		deduplicate_node_strings(n.y, unique_strings, allocator)
	case ^Ternary_If_Expr:
		deduplicate_node_strings(n.x, unique_strings, allocator)
		deduplicate_node_strings(n.cond, unique_strings, allocator)
		deduplicate_node_strings(n.y, unique_strings, allocator)
	case ^Poly_Type:
		deduplicate_node_strings(n.type, unique_strings, allocator)
		deduplicate_node_strings(n.specialization, unique_strings, allocator)
	case ^Proc_Group:
		deduplicate_array_strings(n.args, unique_strings, allocator)
	case ^Comp_Lit:
		deduplicate_node_strings(n.type, unique_strings, allocator)
		deduplicate_array_strings(n.elems, unique_strings, allocator)
	case ^Proc_Lit:
		deduplicate_node_strings(n.type, unique_strings, allocator)
		deduplicate_array_strings(n.where_clauses, unique_strings, allocator)
	case ^Helper_Type:
		deduplicate_node_strings(n.type, unique_strings, allocator)
	case ^Type_Cast:
		deduplicate_node_strings(n.type, unique_strings, allocator)
		deduplicate_node_strings(n.expr, unique_strings, allocator)
	case ^Deref_Expr:
		deduplicate_node_strings(n.expr, unique_strings, allocator)
	case ^Index_Expr:
		deduplicate_node_strings(n.expr, unique_strings, allocator)
		deduplicate_node_strings(n.index, unique_strings, allocator)
	case ^Multi_Pointer_Type:
		deduplicate_node_strings(n.elem, unique_strings, allocator)
	case ^Matrix_Type:
		deduplicate_node_strings(n.elem, unique_strings, allocator)
		deduplicate_node_strings(n.column_count, unique_strings, allocator)
		deduplicate_node_strings(n.row_count, unique_strings, allocator)
	case ^Type_Assertion:
		deduplicate_node_strings(n.expr, unique_strings, allocator)
		deduplicate_node_strings(n.type, unique_strings, allocator)
	case ^Relative_Type:
		deduplicate_node_strings(n.tag, unique_strings, allocator)
		deduplicate_node_strings(n.type, unique_strings, allocator)
	case ^Bit_Field_Type:
		deduplicate_node_strings(n.backing_type, unique_strings, allocator)
		deduplicate_array_strings(n.fields, unique_strings, allocator)
	case ^Bit_Field_Field:
		deduplicate_node_strings(n.name, unique_strings, allocator)
		deduplicate_node_strings(n.type, unique_strings, allocator)
		deduplicate_node_strings(n.bit_size, unique_strings, allocator)
		deduplicate_node_strings(n.docs, unique_strings, allocator)
		deduplicate_node_strings(n.comments, unique_strings, allocator)
	case ^Or_Else_Expr:
		deduplicate_node_strings(n.x, unique_strings, allocator)
		deduplicate_node_strings(n.y, unique_strings, allocator)
	case ^Comment_Group:
		for &token in n.list {
			token.text = get_index_unique_string(unique_strings, allocator, token.text)
			token.pos.file = get_index_unique_string(unique_strings, allocator, token.pos.file)
		}
	}
}

// Helper to deduplicate strings in arrays - overloaded for different types
deduplicate_array_strings :: proc {
	deduplicate_expr_array_strings,
	deduplicate_field_array_strings,
	deduplicate_bit_field_array_strings,
}

deduplicate_expr_array_strings :: proc(array: []^ast.Expr, unique_strings: ^map[string]string, allocator: mem.Allocator) {
	for elem in array {
		deduplicate_node_strings(elem, unique_strings, allocator)
	}
}

deduplicate_field_array_strings :: proc(array: []^ast.Field, unique_strings: ^map[string]string, allocator: mem.Allocator) {
	for elem in array {
		deduplicate_node_strings(cast(^ast.Node)elem, unique_strings, allocator)
	}
}

deduplicate_bit_field_array_strings :: proc(array: []^ast.Bit_Field_Field, unique_strings: ^map[string]string, allocator: mem.Allocator) {
	for elem in array {
		deduplicate_node_strings(cast(^ast.Node)elem, unique_strings, allocator)
	}
}

clone_type :: proc {
	clone_node,
	clone_expr,
	clone_array,
	clone_dynamic_array,
	clone_comment_group,
}

clone_array :: proc(array: $A/[]^$T, allocator: mem.Allocator, unique_strings: ^map[string]string, clone_ast := true) -> A {
	if len(array) == 0 {
		return nil
	}
	res := make(A, len(array), allocator)
	for elem, i in array {
		res[i] = cast(^T)clone_type(elem, allocator, unique_strings, clone_ast)
	}
	return res
}

clone_dynamic_array :: proc(
	array: $A/[dynamic]^$T,
	allocator: mem.Allocator,
	unique_strings: ^map[string]string,
	clone_ast := true,
) -> A {
	if len(array) == 0 {
		return nil
	}
	res := make(A, len(array), allocator)
	for elem, i in array {
		res[i] = auto_cast clone_type(elem, allocator, unique_strings, clone_ast)
	}
	return res
}

clone_expr :: proc(node: ^ast.Expr, allocator: mem.Allocator, unique_strings: ^map[string]string, clone_ast := true) -> ^ast.Expr {
	return cast(^ast.Expr)clone_node(node, allocator, unique_strings, clone_ast)
}

clone_node :: proc(node: ^ast.Node, allocator: mem.Allocator, unique_strings: ^map[string]string, clone_ast := true) -> ^ast.Node {
	using ast
	if node == nil {
		return nil
	}

	// If clone_ast is false, just deduplicate strings in-place and return the original node
	if !clone_ast {
		deduplicate_node_strings(node, unique_strings, allocator)
		return node
	}

	size := size_of(Node)
	align := align_of(Node)
	ti := reflect.union_variant_type_info(node.derived)
	if ti != nil {
		elem := ti.variant.(reflect.Type_Info_Pointer).elem
		size = elem.size
		align = elem.align
	}

	#partial switch _ in node.derived {
	case ^Package, ^File:
		panic("Cannot clone this node type")
	}

	res := cast(^Node)(mem.alloc(size, align, allocator) or_else panic("OOM"))
	src: rawptr = node
	if node.derived != nil {
		src = (^rawptr)(&node.derived)^
	}
	mem.copy(res, src, size)
	res_ptr_any: any
	res_ptr_any.data = &res
	res_ptr_any.id = ti.id

	if unique_strings != nil && node.pos.file != "" {
		res.pos.file = get_index_unique_string(unique_strings, allocator, node.pos.file)
	} else {
		res.pos.file = node.pos.file
	}

	if unique_strings != nil && node.end.file != "" {
		res.end.file = get_index_unique_string(unique_strings, allocator, node.end.file)
	} else {
		res.end.file = node.end.file
	}

	reflect.set_union_value(res.derived, res_ptr_any)

	res_ptr := reflect.deref(res_ptr_any)

	if de := reflect.struct_field_value_by_name(res_ptr, "derived_expr", true); de != nil {
		reflect.set_union_value(de, res_ptr_any)
	}
	if ds := reflect.struct_field_value_by_name(res_ptr, "derived_stmt", true); ds != nil {
		reflect.set_union_value(ds, res_ptr_any)
	}

	if res.derived != nil do #partial switch r in res.derived {
	case ^Ident:
		n := node.derived.(^Ident)

		if unique_strings == nil {
			r.name = strings.clone(n.name, allocator)
		} else {
			r.name = get_index_unique_string(unique_strings, allocator, n.name)
		}
	case ^Implicit:
		n := node.derived.(^Implicit)
		if unique_strings == nil {
			r.tok.text = strings.clone(n.tok.text, allocator)
		} else {
			r.tok.text = get_index_unique_string(unique_strings, allocator, n.tok.text)
		}
	case ^Undef:
	case ^Basic_Lit:
		n := node.derived.(^Basic_Lit)
		if unique_strings == nil {
			r.tok.text = strings.clone(n.tok.text, allocator)
		} else {
			r.tok.text = get_index_unique_string(unique_strings, allocator, n.tok.text)
		}
	case ^Basic_Directive:
		n := node.derived.(^Basic_Directive)
		if unique_strings == nil {
			r.name = strings.clone(n.name, allocator)
		} else {
			r.name = get_index_unique_string(unique_strings, allocator, n.name)
		}
	case ^Ellipsis:
		r.expr = clone_type(r.expr, allocator, unique_strings, clone_ast)
	case ^Tag_Expr:
		r.expr = clone_type(r.expr, allocator, unique_strings, clone_ast)
	case ^Unary_Expr:
		n := node.derived.(^Unary_Expr)
		r.expr = clone_type(r.expr, allocator, unique_strings, clone_ast)
		if unique_strings == nil {
			r.op.text = strings.clone(n.op.text, allocator)
		} else {
			r.op.text = get_index_unique_string(unique_strings, allocator, n.op.text)
		}
	case ^Binary_Expr:
		n := node.derived.(^Binary_Expr)
		r.left = clone_type(r.left, allocator, unique_strings, clone_ast)
		r.right = clone_type(r.right, allocator, unique_strings, clone_ast)
		//Todo: Replace this with some constant table for operator text
		if unique_strings == nil {
			r.op.text = strings.clone(n.op.text, allocator)
		} else {
			r.op.text = get_index_unique_string(unique_strings, allocator, n.op.text)
		}
	case ^Paren_Expr:
		r.expr = clone_type(r.expr, allocator, unique_strings, clone_ast)
	case ^Selector_Expr:
		r.expr = clone_type(r.expr, allocator, unique_strings, clone_ast)
		r.field = auto_cast clone_type(r.field, allocator, unique_strings, clone_ast)
	case ^Implicit_Selector_Expr:
		r.field = auto_cast clone_type(r.field, allocator, unique_strings, clone_ast)
	case ^Slice_Expr:
		r.expr = clone_type(r.expr, allocator, unique_strings, clone_ast)
		r.low = clone_type(r.low, allocator, unique_strings, clone_ast)
		r.high = clone_type(r.high, allocator, unique_strings, clone_ast)
	case ^Attribute:
		r.elems = clone_type(r.elems, allocator, unique_strings, clone_ast)
	case ^Distinct_Type:
		r.type = clone_type(r.type, allocator, unique_strings, clone_ast)
	case ^Proc_Type:
		r.params = auto_cast clone_type(r.params, allocator, unique_strings, clone_ast)
		r.results = auto_cast clone_type(r.results, allocator, unique_strings, clone_ast)
		r.calling_convention = clone_calling_convention(r.calling_convention, allocator, unique_strings)
	case ^Pointer_Type:
		r.tag = clone_type(r.tag, allocator, unique_strings, clone_ast)
		r.elem = clone_type(r.elem, allocator, unique_strings, clone_ast)
	case ^Array_Type:
		r.len = clone_type(r.len, allocator, unique_strings, clone_ast)
		r.elem = clone_type(r.elem, allocator, unique_strings, clone_ast)
		r.tag = clone_type(r.tag, allocator, unique_strings, clone_ast)
	case ^Dynamic_Array_Type:
		r.elem = clone_type(r.elem, allocator, unique_strings, clone_ast)
		r.tag = clone_type(r.tag, allocator, unique_strings, clone_ast)
	case ^Struct_Type:
		r.poly_params = auto_cast clone_type(r.poly_params, allocator, unique_strings, clone_ast)
		r.align = clone_type(r.align, allocator, unique_strings, clone_ast)
		r.fields = auto_cast clone_type(r.fields, allocator, unique_strings, clone_ast)
		r.where_clauses = clone_type(r.where_clauses, allocator, unique_strings, clone_ast)
		r.max_field_align = clone_type(r.max_field_align, allocator, unique_strings, clone_ast)
		r.min_field_align = clone_type(r.min_field_align, allocator, unique_strings, clone_ast)
	case ^Field:
		r.names = clone_type(r.names, allocator, unique_strings, clone_ast)
		r.type = clone_type(r.type, allocator, unique_strings, clone_ast)
		r.default_value = clone_type(r.default_value, allocator, unique_strings, clone_ast)
		r.docs = clone_type(r.docs, allocator, unique_strings, clone_ast)
		r.comment = clone_type(r.comment, allocator, unique_strings, clone_ast)
	case ^Field_List:
		r.list = clone_type(r.list, allocator, unique_strings, clone_ast)
	case ^Field_Value:
		r.field = clone_type(r.field, allocator, unique_strings, clone_ast)
		r.value = clone_type(r.value, allocator, unique_strings, clone_ast)
	case ^Union_Type:
		r.poly_params = auto_cast clone_type(r.poly_params, allocator, unique_strings, clone_ast)
		r.align = clone_type(r.align, allocator, unique_strings, clone_ast)
		r.variants = clone_type(r.variants, allocator, unique_strings, clone_ast)
		r.where_clauses = clone_type(r.where_clauses, allocator, unique_strings, clone_ast)
	case ^Enum_Type:
		r.base_type = clone_type(r.base_type, allocator, unique_strings, clone_ast)
		r.fields = clone_type(r.fields, allocator, unique_strings, clone_ast)
	case ^Bit_Set_Type:
		r.elem = clone_type(r.elem, allocator, unique_strings, clone_ast)
		r.underlying = clone_type(r.underlying, allocator, unique_strings, clone_ast)
	case ^Map_Type:
		r.key = clone_type(r.key, allocator, unique_strings, clone_ast)
		r.value = clone_type(r.value, allocator, unique_strings, clone_ast)
	case ^Call_Expr:
		r.expr = clone_type(r.expr, allocator, unique_strings, clone_ast)
		r.args = clone_type(r.args, allocator, unique_strings, clone_ast)
	case ^Typeid_Type:
		r.specialization = clone_type(r.specialization, allocator, unique_strings, clone_ast)
	case ^Ternary_When_Expr:
		r.x = clone_type(r.x, allocator, unique_strings, clone_ast)
		r.cond = clone_type(r.cond, allocator, unique_strings, clone_ast)
		r.y = clone_type(r.y, allocator, unique_strings, clone_ast)
	case ^Ternary_If_Expr:
		r.x = clone_type(r.x, allocator, unique_strings, clone_ast)
		r.cond = clone_type(r.cond, allocator, unique_strings, clone_ast)
		r.y = clone_type(r.y, allocator, unique_strings, clone_ast)
	case ^Poly_Type:
		r.type = auto_cast clone_type(r.type, allocator, unique_strings, clone_ast)
		r.specialization = clone_type(r.specialization, allocator, unique_strings, clone_ast)
	case ^Proc_Group:
		r.args = clone_type(r.args, allocator, unique_strings, clone_ast)
	case ^Comp_Lit:
		r.type = clone_type(r.type, allocator, unique_strings, clone_ast)
		r.elems = clone_type(r.elems, allocator, unique_strings, clone_ast)
	case ^Proc_Lit:
		r.type = cast(^Proc_Type)clone_type(cast(^Node)r.type, allocator, unique_strings, clone_ast)
		r.body = nil
		r.where_clauses = clone_type(r.where_clauses, allocator, unique_strings, clone_ast)
	case ^Helper_Type:
		r.type = clone_type(r.type, allocator, unique_strings, clone_ast)
	case ^Type_Cast:
		r.type = clone_type(r.type, allocator, unique_strings, clone_ast)
		r.expr = clone_type(r.expr, allocator, unique_strings, clone_ast)
	case ^Deref_Expr:
		r.expr = clone_type(r.expr, allocator, unique_strings, clone_ast)
	case ^Index_Expr:
		r.expr = clone_type(r.expr, allocator, unique_strings, clone_ast)
		r.index = clone_type(r.index, allocator, unique_strings, clone_ast)
	case ^Multi_Pointer_Type:
		r.elem = clone_type(r.elem, allocator, unique_strings, clone_ast)
	case ^Matrix_Type:
		r.elem = clone_type(r.elem, allocator, unique_strings, clone_ast)
		r.column_count = clone_type(r.column_count, allocator, unique_strings, clone_ast)
		r.row_count = clone_type(r.row_count, allocator, unique_strings, clone_ast)
	case ^Type_Assertion:
		r.expr = clone_type(r.expr, allocator, unique_strings, clone_ast)
		r.type = clone_type(r.type, allocator, unique_strings, clone_ast)
	case ^Relative_Type:
		r.tag = clone_type(r.tag, allocator, unique_strings, clone_ast)
		r.type = clone_type(r.type, allocator, unique_strings, clone_ast)
	case ^Bit_Field_Type:
		r.backing_type = clone_type(r.backing_type, allocator, unique_strings, clone_ast)
		r.fields = clone_type(r.fields, allocator, unique_strings, clone_ast)
	case ^Bit_Field_Field:
		r.name = clone_type(r.name, allocator, unique_strings, clone_ast)
		r.type = clone_type(r.type, allocator, unique_strings, clone_ast)
		r.bit_size = clone_type(r.bit_size, allocator, unique_strings, clone_ast)
		r.docs = clone_type(r.docs, allocator, unique_strings, clone_ast)
		r.comments = clone_type(r.comments, allocator, unique_strings, clone_ast)
	case ^Or_Else_Expr:
		r.x = clone_type(r.x, allocator, unique_strings, clone_ast)
		r.y = clone_type(r.y, allocator, unique_strings, clone_ast)
	case ^Comment_Group:
		list := make([dynamic]tokenizer.Token, 0, len(r.list), allocator)
		for t in r.list {
			append(&list, tokenizer.Token{text = strings.clone(t.text, allocator), kind = t.kind, pos = tokenizer.Pos{file = strings.clone(t.pos.file, allocator), offset = t.pos.offset, line = t.pos.line, column = t.pos.column}})
		}
		r.list = list[:]
	case:
	}

	return res
}

clone_comment_group :: proc(
	node: ^ast.Comment_Group,
	allocator: mem.Allocator,
	unique_strings: ^map[string]string,
	clone_ast := true,
) -> ^ast.Comment_Group {
	return cast(^ast.Comment_Group)clone_node(node, allocator, unique_strings, clone_ast)
}

clone_calling_convention :: proc(
	cc: ast.Proc_Calling_Convention, allocator: mem.Allocator, unique_strings: ^map[string]string,
) -> ast.Proc_Calling_Convention {
	if cc == nil {
		return nil
	}

	switch v in cc {
	case string:
		if unique_strings != nil {
			return get_index_unique_string(unique_strings, allocator, v)
		}
		return strings.clone(v, allocator)
	case ast.Proc_Calling_Convention_Extra:
		return v
	}
	return nil
}
