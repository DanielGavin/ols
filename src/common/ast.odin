package common

import "core:odin/ast"
import "core:log"
import "core:mem"

get_ast_node_string :: proc(node: ^ast.Node, src: [] byte) -> string {
    return string(src[node.pos.offset:node.end.offset]);
}

free_ast :: proc{
	free_ast_node,
    free_ast_array,
    free_ast_dynamic_array
};

free_ast_array :: proc(array: $A/[]^$T) {
	for elem, i in array {
		free_ast(elem);
	}
}

free_ast_dynamic_array :: proc(array: $A/[dynamic]^$T) {
	for elem, i in array {
		free_ast(elem);
	}
}

free_ast_node :: proc(node: ^ast.Node) {

    using ast;

    if node == nil {
        return;
    }

    switch n in node.derived {
    case Bad_Expr:
    case Ident:
    case Implicit:
    case Undef:
    case Basic_Directive:
    case Basic_Lit:
    case Ellipsis:
        free_ast(n.expr);
    case Proc_Lit:
        free_ast(n.type);
        free_ast(n.body);
    case Comp_Lit:
        free_ast(n.type);
        free_ast(n.elems);
    case Tag_Expr:
        free_ast(n.expr);
    case Unary_Expr:
        free_ast(n.expr);
    case Binary_Expr:
        free_ast(n.left);
        free_ast(n.right);
    case Paren_Expr:
        free_ast(n.expr);
    case Call_Expr:
        free_ast(n.expr);
        free_ast(n.args);
    case Selector_Expr:
        free_ast(n.expr);
        free_ast(n.field);
    case Implicit_Selector_Expr:
        free_ast(n.field);
    case Index_Expr:
        free_ast(n.expr);
        free_ast(n.index);
    case Deref_Expr:
        free_ast(n.expr);
    case Slice_Expr:
        free_ast(n.expr);
        free_ast(n.low);
        free_ast(n.high);
    case Field_Value:
        free_ast(n.field);
        free_ast(n.value);
    case Ternary_Expr:
        free_ast(n.cond);
        free_ast(n.x);
        free_ast(n.y);
    case Ternary_If_Expr:
        free_ast(n.x);
        free_ast(n.cond);
        free_ast(n.y);
    case Ternary_When_Expr:
        free_ast(n.x);
        free_ast(n.cond);
        free_ast(n.y);
    case Type_Assertion:
        free_ast(n.expr);
        free_ast(n.type);
    case Type_Cast:
        free_ast(n.type);
        free_ast(n.expr);
    case Auto_Cast:
        free_ast(n.expr);
    case Bad_Stmt:
    case Empty_Stmt:
    case Expr_Stmt:
        free_ast(n.expr);
    case Tag_Stmt:
        r := cast(^Expr_Stmt)node;
        free_ast(r.expr);
    case Assign_Stmt:
        free_ast(n.lhs);
        free_ast(n.rhs);
    case Block_Stmt:
        free_ast(n.label);
        free_ast(n.stmts);
    case If_Stmt:
        free_ast(n.label);
        free_ast(n.init);
        free_ast(n.cond);
        free_ast(n.body);
        free_ast(n.else_stmt);
    case When_Stmt:
        free_ast(n.cond);
        free_ast(n.body);
        free_ast(n.else_stmt);
    case Return_Stmt:
        free_ast(n.results);
    case Defer_Stmt:
        free_ast(n.stmt);
    case For_Stmt:
        free_ast(n.label);
        free_ast(n.init);
        free_ast(n.cond);
        free_ast(n.post);
        free_ast(n.body);
    case Range_Stmt:
        free_ast(n.label);
        free_ast(n.val0);
        free_ast(n.val1);
        free_ast(n.expr);
        free_ast(n.body);
    case Case_Clause:
        free_ast(n.list);
        free_ast(n.body);
    case Switch_Stmt:
        free_ast(n.label);
        free_ast(n.init);
        free_ast(n.cond);
        free_ast(n.body);
    case Type_Switch_Stmt:
        free_ast(n.label);
        free_ast(n.tag);
        free_ast(n.expr);
        free_ast(n.body);
    case Branch_Stmt:
        free_ast(n.label);
    case Using_Stmt:
        free_ast(n.list);
    case Bad_Decl:
    case Value_Decl:
        free_ast(n.attributes);
        free_ast(n.names);
        free_ast(n.type);
        free_ast(n.values);
    case Package_Decl:
    case Import_Decl:
    case Foreign_Block_Decl:
        free_ast(n.attributes);
        free_ast(n.foreign_library);
        free_ast(n.body);
    case Foreign_Import_Decl:
        free_ast(n.name);
    case Proc_Group:
        free_ast(n.args);
    case Attribute:
        free_ast(n.elems);
    case Field:
        free_ast(n.names);
        free_ast(n.type);
        free_ast(n.default_value);
    case Field_List:
        free_ast(n.list);
    case Typeid_Type:
        free_ast(n.specialization);
    case Helper_Type:
        free_ast(n.type);
    case Distinct_Type:
        free_ast(n.type);
    case Opaque_Type:
        free_ast(n.type);
    case Poly_Type:
        free_ast(n.type);
        free_ast(n.specialization);
    case Proc_Type:
        free_ast(n.params);
        free_ast(n.results);
    case Pointer_Type:
        free_ast(n.elem);
    case Array_Type:
        free_ast(n.len);
        free_ast(n.elem);
    case Dynamic_Array_Type:
        free_ast(n.elem);
    case Struct_Type:
        free_ast(n.poly_params);
        free_ast(n.align);
        free_ast(n.fields);
    case Union_Type:
        free_ast(n.poly_params);
        free_ast(n.align);
        free_ast(n.variants);
    case Enum_Type:
        free_ast(n.base_type);
        free_ast(n.fields);
    case Bit_Field_Type:
        free_ast(n.fields);
    case Bit_Set_Type:
        free_ast(n.elem);
        free_ast(n.underlying);
    case Map_Type:
        free_ast(n.key);
        free_ast(n.value);
    case:
        log.errorf("free Unhandled node kind: %T", n);
    }

    mem.free(node);
}



free_ast_file :: proc(file: ast.File) {

    for decl in file.decls {
        free_ast(decl);
    }

}


node_equal :: proc{
	node_equal_node,
    node_equal_array,
    node_equal_dynamic_array
};

node_equal_array :: proc(a, b: $A/[]^$T) -> bool {

    ret := true;

    if len(a) != len(b) {
        return false;
    }

	for elem, i in a {
		ret &= node_equal(elem, b[i]);
	}

    return ret;
}

node_equal_dynamic_array :: proc(a, b: $A/[dynamic]^$T) -> bool {

    ret := true;

    if len(a) != len(b) {
        return false;
    }

	for elem, i in a {
		ret &= node_equal(elem, b[i]);
	}

    return ret;
}


node_equal_node :: proc(a, b: ^ast.Node) -> bool {

    using ast;

    if a == nil || b == nil {
        return false;
    }

    switch m in b.derived {
    case Bad_Expr:
        if n, ok := a.derived.(Bad_Expr); ok {
            return true;
        }
    case Ident:
        if n, ok := a.derived.(Ident); ok {
            return n.name == m.name;
        }
    case Implicit:
        if n, ok := a.derived.(Implicit); ok {
            return true;
        }
    case Undef:
        if n, ok := a.derived.(Undef); ok {
            return true;
        }
    case Basic_Lit:
        if n, ok := a.derived.(Basic_Lit); ok {
            return true;
        }
    case Poly_Type:
        if n, ok := a.derived.(Poly_Type); ok {
            ret := node_equal(n.type, m.type);
            ret &= node_equal(n.specialization, m.specialization);
            return ret;
        }
    case Ellipsis:
        if n, ok := a.derived.(Ellipsis); ok {
            return node_equal(n.expr, m.expr);
        }
    case Tag_Expr:
        if n, ok := a.derived.(Tag_Expr); ok {
            return node_equal(n.expr, m.expr);
        }
    case Unary_Expr:
        if n, ok := a.derived.(Unary_Expr); ok {
            return node_equal(n.expr, m.expr);
        }
    case Binary_Expr:
        if n, ok := a.derived.(Binary_Expr); ok {
            ret := node_equal(n.left, m.left);
            ret &= node_equal(n.right, m.right);
            return ret;
        }
    case Paren_Expr:
        if n, ok := a.derived.(Paren_Expr); ok {
            return node_equal(n.expr, m.expr);
        }
    case Selector_Expr:
        if n, ok := a.derived.(Selector_Expr); ok {
            ret := node_equal(n.expr, m.expr);
            ret &= node_equal(n.field, m.field);
            return ret;
        }
    case Slice_Expr:
        if n, ok := a.derived.(Slice_Expr); ok {
            ret := node_equal(n.expr, m.expr);
            ret &= node_equal(n.low, m.low);
            ret &= node_equal(n.high, m.high);
            return ret;
        }
    case Distinct_Type:
        if n, ok := a.derived.(Distinct_Type); ok {
            return node_equal(n.type, m.type);
        }
    case Opaque_Type:
        if n, ok := a.derived.(Opaque_Type); ok {
            return node_equal(n.type, m.type);
        }
    case Proc_Type:
        if n, ok := a.derived.(Proc_Type); ok {
            ret := node_equal(n.params, m.params);
            ret &= node_equal(n.results, m.results);
            return ret;
        }
    case Pointer_Type:
        if n, ok := a.derived.(Pointer_Type); ok {
            return node_equal(n.elem, m.elem);
        }
    case Array_Type:
        if n, ok := a.derived.(Array_Type); ok {
            ret := node_equal(n.len, m.len);
            ret &= node_equal(n.elem, m.elem);
            return ret;
        }
    case Dynamic_Array_Type:
        if n, ok := a.derived.(Dynamic_Array_Type); ok {
            return node_equal(n.elem, m.elem);
        }
    case Struct_Type:
        if n, ok := a.derived.(Struct_Type); ok {
            ret := node_equal(n.poly_params, m.poly_params);
            ret &= node_equal(n.align, m.align);
            ret &= node_equal(n.fields, m.fields);
            return ret;
        }
    case Field:
        if n, ok := a.derived.(Field); ok {
            ret := node_equal(n.names, m.names);
            ret &= node_equal(n.type, m.type);
            ret &= node_equal(n.default_value, m.default_value);
            return ret;
        }
	case Field_List:
        if n, ok := a.derived.(Field_List); ok {
            return node_equal(n.list, m.list);
        }
    case Field_Value:
        if n, ok := a.derived.(Field_Value); ok {
            ret := node_equal(n.field, m.field);
            ret &= node_equal(n.value, m.value);
            return ret;
        }
    case Union_Type:
        if n, ok := a.derived.(Union_Type); ok {
            ret := node_equal(n.poly_params, m.poly_params);
            ret &= node_equal(n.align, m.align);
            ret &= node_equal(n.variants, m.variants);
            return ret;
        }
    case Enum_Type:
        if n, ok := a.derived.(Enum_Type); ok {
            ret := node_equal(n.base_type, m.base_type);
            ret &= node_equal(n.fields, m.fields);
            return ret;
        }
    case Bit_Field_Type:
        if n, ok := a.derived.(Bit_Field_Type); ok {
            return node_equal(n.fields, m.fields);
        }
    case Bit_Set_Type:
        if n, ok := a.derived.(Bit_Set_Type); ok {
            ret := node_equal(n.elem, m.elem);
            ret &= node_equal(n.underlying, m.underlying);
            return ret;
        }
    case Map_Type:
        if n, ok := a.derived.(Map_Type); ok {
            ret := node_equal(n.key, m.key);
            ret &= node_equal(n.value, m.value);
            return ret;
        }
    case Call_Expr:
        if n, ok := a.derived.(Call_Expr); ok {
            ret := node_equal(n.expr, m.expr);
            ret &= node_equal(n.args, m.args);
            return ret;
        }
    case Typeid_Type:
        if n, ok := a.derived.(Typeid_Type); ok {
            return node_equal(n.specialization, m.specialization);
        }
    case:
        log.error("Unhandled poly node kind: %T", m);
    }

    return false;

}