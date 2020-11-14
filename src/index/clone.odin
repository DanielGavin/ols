package index

import "core:mem"
import "core:fmt"
import "core:odin/tokenizer"
import "core:odin/ast"
import "core:strings"

clone_type :: proc{
    clone_node,
    clone_expr,
    clone_array,
    clone_dynamic_array,
};

clone_array :: proc(array: $A/[]^$T, allocator := context.allocator) -> A {
    if len(array) == 0 {
        return nil;
    }
    res := make(A, len(array));
    for elem, i in array {
        res[i] = auto_cast clone_type(elem, allocator);
    }
    return res;
}

clone_dynamic_array :: proc(array: $A/[dynamic]^$T, allocator := context.allocator) -> A {
    if len(array) == 0 {
        return nil;
    }
    res := make(A, len(array));
    for elem, i in array {
        res[i] = auto_cast clone_type(elem, allocator);
    }
    return res;
}

clone_expr :: proc(node: ^ast.Expr, allocator := context.allocator) -> ^ast.Expr {
    return cast(^ast.Expr)clone_node(node, allocator);
}

clone_node :: proc(node: ^ast.Node, allocator := context.allocator) -> ^ast.Node {

    using ast;

    if node == nil {
        return nil;
    }

    size := size_of(Node);
    align := align_of(Node);
    ti := type_info_of(node.derived.id);
    if ti != nil {
        size = ti.size;
        align = ti.align;
    }

    res := cast(^Node)mem.alloc(size, align, allocator);
    src: rawptr = node;
    if node.derived != nil {
        src = node.derived.data;
    }
    mem.copy(res, src, size);
    res.derived.data = rawptr(res);

    switch n in node.derived {
    case Bad_Expr:
    case Ident:
        r := cast(^Ident)res;
        r.name = strings.clone(n.name, allocator);
    case Implicit:
    case Undef:
    case Basic_Lit:

    case Ellipsis:
        r := cast(^Ellipsis)res;
        r.expr = clone_type(r.expr, allocator);
    case Tag_Expr:
        r := cast(^Tag_Expr)res;
        r.expr = clone_type(r.expr, allocator);
    case Unary_Expr:
        r := cast(^Unary_Expr)res;
        r.expr = clone_type(r.expr, allocator);
    case Binary_Expr:
        r := cast(^Binary_Expr)res;
        r.left  = clone_type(r.left, allocator);
        r.right = clone_type(r.right, allocator);
    case Paren_Expr:
        r := cast(^Paren_Expr)res;
        r.expr = clone_type(r.expr, allocator);
    case Selector_Expr:
        r := cast(^Selector_Expr)res;
        r.expr = clone_type(r.expr, allocator);
        r.field = auto_cast clone_type(r.field, allocator);
    case Slice_Expr:
        r := cast(^Slice_Expr)res;
        r.expr = clone_type(r.expr, allocator);
        r.low  = clone_type(r.low, allocator);
        r.high = clone_type(r.high, allocator);
    case Attribute:
        r := cast(^Attribute)res;
        r.elems = clone_type(r.elems, allocator);
    case Distinct_Type:
        r := cast(^Distinct_Type)res;
        r.type = clone_type(r.type, allocator);
    case Opaque_Type:
        r := cast(^Opaque_Type)res;
        r.type = clone_type(r.type, allocator);
    case Proc_Type:
        r := cast(^Proc_Type)res;
        r.params  = auto_cast clone_type(r.params, allocator);
        r.results = auto_cast clone_type(r.results, allocator);
    case Pointer_Type:
        r := cast(^Pointer_Type)res;
        r.elem = clone_type(r.elem, allocator);
    case Array_Type:
        r := cast(^Array_Type)res;
        r.len  = clone_type(r.len, allocator);
        r.elem = clone_type(r.elem, allocator);
    case Dynamic_Array_Type:
        r := cast(^Dynamic_Array_Type)res;
        r.elem = clone_type(r.elem, allocator);
    case Struct_Type:
        r := cast(^Struct_Type)res;
        r.poly_params = auto_cast clone_type(r.poly_params, allocator);
        r.align = clone_type(r.align, allocator);
        r.fields = auto_cast clone_type(r.fields, allocator);
    case Field:
		r := cast(^Field)res;
		r.names         = clone_type(r.names, allocator);
		r.type          = clone_type(r.type, allocator);
		r.default_value = clone_type(r.default_value, allocator);
	case Field_List:
		r := cast(^Field_List)res;
        r.list = clone_type(r.list, allocator);
    case Field_Value:
		r := cast(^Field_Value)res;
		r.field = clone_type(r.field, allocator);
		r.value = clone_type(r.value, allocator);
    case Union_Type:
        r := cast(^Union_Type)res;
        r.poly_params = auto_cast clone_type(r.poly_params, allocator);
        r.align = clone_type(r.align, allocator);
        r.variants = clone_type(r.variants, allocator);
    case Enum_Type:
        r := cast(^Enum_Type)res;
        r.base_type = clone_type(r.base_type, allocator);
        r.fields = clone_type(r.fields, allocator);
    case Bit_Field_Type:
        r := cast(^Bit_Field_Type)res;
        r.fields = clone_type(r.fields, allocator);
    case Bit_Set_Type:
        r := cast(^Bit_Set_Type)res;
        r.elem = clone_type(r.elem, allocator);
        r.underlying = clone_type(r.underlying, allocator);
    case Map_Type:
        r := cast(^Map_Type)res;
        r.key = clone_type(r.key, allocator);
        r.value = clone_type(r.value, allocator);
    case Call_Expr:
        r := cast(^Call_Expr)res;
        r.expr = clone_type(r.expr, allocator);
        r.args = clone_type(r.args, allocator);
    case Typeid_Type:
		r := cast(^Typeid_Type)res;
		r.specialization = clone_type(r.specialization, allocator);
    case:
        fmt.panicf("Unhandled node kind: %T", n);
    }

    return res;
}


