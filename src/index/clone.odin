package index

import "core:mem"
import "core:fmt"
import "core:odin/tokenizer"
import "core:odin/ast"
import "core:strings"
import "core:log"

new_type :: proc($T: typeid, pos, end: tokenizer.Pos, allocator: mem.Allocator) -> ^T {
	n := mem.new(T, allocator);
	n.pos     = pos;
	n.end     = end;
	n.derived = n^;
	base: ^ast.Node = n; // dummy check
	_ = base; // "Use" type to make -vet happy
	return n;
}

clone_type :: proc{
	clone_node,
	clone_expr,
	clone_array,
	clone_dynamic_array,
};

clone_array :: proc(array: $A/[]^$T, allocator: mem.Allocator, unique_strings: ^map[string]string) -> A {
	if len(array) == 0 {
		return nil;
	}
	res := make(A, len(array), allocator);
	for elem, i in array {
		res[i] = auto_cast clone_type(elem, allocator, unique_strings);
	}
	return res;
}

clone_dynamic_array :: proc(array: $A/[dynamic]^$T, allocator: mem.Allocator, unique_strings: ^map[string]string) -> A {
	if len(array) == 0 {
		return nil;
	}
	res := make(A, len(array), allocator);
	for elem, i in array {
		res[i] = auto_cast clone_type(elem, allocator, unique_strings);
	}
	return res;
}

clone_expr :: proc(node: ^ast.Expr, allocator: mem.Allocator, unique_strings: ^map[string]string) -> ^ast.Expr {
	return cast(^ast.Expr)clone_node(node, allocator, unique_strings);
}

clone_node :: proc(node: ^ast.Node, allocator: mem.Allocator, unique_strings: ^map[string]string) -> ^ast.Node {

	using ast;

	if node == nil {
		return nil;
	}

	size  := size_of(Node);
	align := align_of(Node);
	ti    := type_info_of(node.derived.id);
	if ti != nil {
		size  = ti.size;
		align = ti.align;
	}

	res := cast(^Node)mem.alloc(size, align, allocator);
	src: rawptr = node;
	if node.derived != nil {
		src = node.derived.data;
	}
	mem.copy(res, src, size);
	res.derived.data = rawptr(res);

	if unique_strings != nil && node.pos.file != "" {
		res.pos.file = get_index_unique_string(unique_strings, allocator, node.pos.file);
	} else {
		res.pos.file = node.pos.file;
	}

	if unique_strings != nil && node.end.file != "" {
		res.end.file = get_index_unique_string(unique_strings, allocator, node.end.file);
	} else {
		res.end.file = node.end.file;
	}

	switch n in node.derived {
	case Bad_Expr:
	case Ident:
		r := cast(^Ident)res;
		if unique_strings == nil {
			r.name = strings.clone(n.name, allocator);
		} else {
			r.name = get_index_unique_string(unique_strings, allocator, n.name);
		}
	case Implicit:
	case Undef:
	case Basic_Lit:
	case Basic_Directive:
	case Ellipsis:
		r := cast(^Ellipsis)res;
		r.expr = clone_type(r.expr, allocator, unique_strings);
	case Tag_Expr:
		r := cast(^Tag_Expr)res;
		r.expr = clone_type(r.expr, allocator, unique_strings);
	case Unary_Expr:
		r := cast(^Unary_Expr)res;
		r.expr = clone_type(r.expr, allocator, unique_strings);
	case Binary_Expr:
		r := cast(^Binary_Expr)res;
		r.left  = clone_type(r.left, allocator, unique_strings);
		r.right = clone_type(r.right, allocator, unique_strings);
	case Paren_Expr:
		r := cast(^Paren_Expr)res;
		r.expr = clone_type(r.expr, allocator, unique_strings);
	case Selector_Expr:
		r := cast(^Selector_Expr)res;
		r.expr  = clone_type(r.expr, allocator, unique_strings);
		r.field = auto_cast clone_type(r.field, allocator, unique_strings);
	case Implicit_Selector_Expr:
		r := cast(^Implicit_Selector_Expr)res;
		r.field = auto_cast clone_type(r.field, allocator, unique_strings);
	case Slice_Expr:
		r := cast(^Slice_Expr)res;
		r.expr = clone_type(r.expr, allocator, unique_strings);
		r.low  = clone_type(r.low, allocator, unique_strings);
		r.high = clone_type(r.high, allocator, unique_strings);
	case Attribute:
		r := cast(^Attribute)res;
		r.elems = clone_type(r.elems, allocator, unique_strings);
	case Distinct_Type:
		r := cast(^Distinct_Type)res;
		r.type = clone_type(r.type, allocator, unique_strings);
	case Proc_Type:
		r := cast(^Proc_Type)res;
		r.params  = auto_cast clone_type(r.params, allocator, unique_strings);
		r.results = auto_cast clone_type(r.results, allocator, unique_strings);
	case Pointer_Type:
		r := cast(^Pointer_Type)res;
		r.elem = clone_type(r.elem, allocator, unique_strings);
	case Array_Type:
		r := cast(^Array_Type)res;
		r.len  = clone_type(r.len, allocator, unique_strings);
		r.elem = clone_type(r.elem, allocator, unique_strings);
		r.tag  = clone_type(r.tag, allocator, unique_strings);
	case Dynamic_Array_Type:
		r := cast(^Dynamic_Array_Type)res;
		r.elem = clone_type(r.elem, allocator, unique_strings);
		r.tag  = clone_type(r.tag, allocator, unique_strings);
	case Struct_Type:
		r := cast(^Struct_Type)res;
		r.poly_params   = auto_cast clone_type(r.poly_params, allocator, unique_strings);
		r.align         = clone_type(r.align, allocator, unique_strings);
		r.fields        = auto_cast clone_type(r.fields, allocator, unique_strings);
		r.where_clauses = clone_type(r.where_clauses, allocator, unique_strings);
	case Field:
		r := cast(^Field)res;
		r.names         = clone_type(r.names, allocator, unique_strings);
		r.type          = clone_type(r.type, allocator, unique_strings);
		r.default_value = clone_type(r.default_value, allocator, unique_strings);
	case Field_List:
		r := cast(^Field_List)res;
		r.list = clone_type(r.list, allocator, unique_strings);
	case Field_Value:
		r := cast(^Field_Value)res;
		r.field = clone_type(r.field, allocator, unique_strings);
		r.value = clone_type(r.value, allocator, unique_strings);
	case Union_Type:
		r := cast(^Union_Type)res;
		r.poly_params   = auto_cast clone_type(r.poly_params, allocator, unique_strings);
		r.align         = clone_type(r.align, allocator, unique_strings);
		r.variants      = clone_type(r.variants, allocator, unique_strings);
		r.where_clauses = clone_type(r.where_clauses, allocator, unique_strings);
	case Enum_Type:
		r := cast(^Enum_Type)res;
		r.base_type = clone_type(r.base_type, allocator, unique_strings);
		r.fields    = clone_type(r.fields, allocator, unique_strings);
	case Bit_Set_Type:
		r := cast(^Bit_Set_Type)res;
		r.elem       = clone_type(r.elem, allocator, unique_strings);
		r.underlying = clone_type(r.underlying, allocator, unique_strings);
	case Map_Type:
		r := cast(^Map_Type)res;
		r.key   = clone_type(r.key, allocator, unique_strings);
		r.value = clone_type(r.value, allocator, unique_strings);
	case Call_Expr:
		r := cast(^Call_Expr)res;
		r.expr = clone_type(r.expr, allocator, unique_strings);
		r.args = clone_type(r.args, allocator, unique_strings);
	case Typeid_Type:
		r := cast(^Typeid_Type)res;
		r.specialization = clone_type(r.specialization, allocator, unique_strings);
	case Ternary_When_Expr:
		r := cast(^Ternary_When_Expr)res;
		r.x    = clone_type(r.x, allocator, unique_strings);
		r.cond = clone_type(r.cond, allocator, unique_strings);
		r.y    = clone_type(r.y, allocator, unique_strings);
	case Poly_Type:
		r := cast(^Poly_Type)res;
		r.type           = auto_cast clone_type(r.type, allocator, unique_strings);
		r.specialization = clone_type(r.specialization, allocator, unique_strings);
	case Proc_Group:
		r := cast(^Proc_Group)res;
		r.args = clone_type(r.args, allocator, unique_strings);
	case Comp_Lit:
		r := cast(^Comp_Lit)res;
		r.type  = clone_type(r.type, allocator, unique_strings);
		r.elems = clone_type(r.elems, allocator, unique_strings);
	case Proc_Lit:
		r := cast(^Proc_Lit)res;
		r.type = cast(^Proc_Type)clone_type(cast(^Node)r.type, allocator, unique_strings);
	case Helper_Type:
		r := cast(^Helper_Type)res;
		r.type = clone_type(r.type, allocator, unique_strings);
	case:
		panic(fmt.aprintf("Clone type Unhandled node kind: %T", node.derived));
	}

	return res;
}
