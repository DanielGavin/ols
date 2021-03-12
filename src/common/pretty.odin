package common

import "core:odin/ast"
import "core:fmt"

/*
	Ast visualization to help in debugging and development
*/

print_ast :: proc {
print_ast_array, 
print_ast_dynamic_array, 
print_ast_node};

print_ast_array :: proc (array: $A/[]^$T, depth: int, src: []byte, newline := false) {

	for elem, i in array {
		print_ast(elem, depth, src);
	}
}

print_ast_dynamic_array :: proc (array: $A/[dynamic]^$T, depth: int, src: []byte, newline := false) {

	for elem, i in array {
		print_ast(elem, depth, src);
	}
}

/*
	Not fully printed out, filling it in as needed.
*/

print_ast_node :: proc (node: ^ast.Node, depth: int, src: []byte, newline := false) {

	using ast;

	if node == nil {
		return;
	}

	if newline {
		fmt.println();

		for i := 0; i < depth; i += 1 {
			fmt.printf(" ");
		}
	}

	name := string(src[node.pos.offset:node.end.offset]);

	switch n in node.derived {
	case Bad_Expr:
	case Ident:
		fmt.printf(" %v ", n.name);
	case Implicit:
	case Undef:
	case Basic_Lit:
	case Ellipsis:
		print_ast(n.expr, depth + 1, src);
	case Proc_Lit:
		fmt.printf("function");
		print_ast(n.type, depth + 1, src);
		print_ast(n.body, depth + 1, src, true);
	case Comp_Lit:
		print_ast(n.type, depth + 1, src);
		print_ast(n.elems, depth + 1, src);
	case Tag_Expr:
		print_ast(n.expr, depth + 1, src);
	case Unary_Expr:
		print_ast(n.expr, depth + 1, src);
	case Binary_Expr:
		print_ast(n.left, depth + 1, src);
		fmt.printf("%v", n.op.text);
		print_ast(n.right, depth + 1, src);
	case Paren_Expr:
		print_ast(n.expr, depth + 1, src);
	case Call_Expr:
		fmt.printf("call");
		print_ast(n.expr, depth + 1, src);
		fmt.printf("(");
		print_ast(n.args, depth + 1, src);
		fmt.printf(")");
	case Selector_Expr:
		print_ast(n.expr, depth + 1, src);
		fmt.printf(".");
		print_ast(n.field, depth + 1, src);
	case Index_Expr:
		print_ast(n.expr, depth + 1, src);
		print_ast(n.index, depth + 1, src);
	case Deref_Expr:
		print_ast(n.expr, depth + 1, src);
	case Slice_Expr:
		print_ast(n.expr, depth + 1, src);
		print_ast(n.low, depth + 1, src);
		print_ast(n.high, depth + 1, src);
	case Field_Value:
		print_ast(n.field, depth + 1, src);
		print_ast(n.value, depth + 1, src);
	case Ternary_Expr:
		print_ast(n.cond, depth + 1, src);
		print_ast(n.x, depth + 1, src);
		print_ast(n.y, depth + 1, src);
	case Ternary_If_Expr:
		print_ast(n.x, depth + 1, src);
		print_ast(n.cond, depth + 1, src);
		print_ast(n.y, depth + 1, src);
	case Ternary_When_Expr:
		print_ast(n.x, depth + 1, src);
		print_ast(n.cond, depth + 1, src);
		print_ast(n.y, depth + 1, src);
	case Type_Assertion:
		print_ast(n.expr, depth + 1, src);
		print_ast(n.type, depth + 1, src);
	case Type_Cast:
		print_ast(n.type, depth + 1, src);
		print_ast(n.expr, depth + 1, src);
	case Auto_Cast:
		print_ast(n.expr, depth + 1, src);
	case Bad_Stmt:
	case Empty_Stmt:
	case Expr_Stmt:
		print_ast(n.expr, depth + 1, src);
	case Tag_Stmt:
		r := cast(^Expr_Stmt)node;
		print_ast(r.expr, depth + 1, src);
	case Assign_Stmt:
		print_ast(n.lhs, depth + 1, src);
		print_ast(n.rhs, depth + 1, src);
	case Block_Stmt:
		print_ast(n.label, depth + 1, src);
		print_ast(n.stmts, depth + 1, src);
	case If_Stmt:
		print_ast(n.label, depth + 1, src);
		print_ast(n.init, depth + 1, src);
		print_ast(n.cond, depth + 1, src);
		print_ast(n.body, depth + 1, src);
		print_ast(n.else_stmt, depth + 1, src);
	case When_Stmt:
		print_ast(n.cond, depth + 1, src);
		print_ast(n.body, depth + 1, src);
		print_ast(n.else_stmt, depth + 1, src);
	case Return_Stmt:
		print_ast(n.results, depth + 1, src);
	case Defer_Stmt:
		print_ast(n.stmt, depth + 1, src);
	case For_Stmt:
		print_ast(n.label, depth + 1, src);
		print_ast(n.init, depth + 1, src);
		print_ast(n.cond, depth + 1, src);
		print_ast(n.post, depth + 1, src);
		print_ast(n.body, depth + 1, src);
	case Range_Stmt:
		print_ast(n.label, depth + 1, src);
		print_ast(n.val0, depth + 1, src);
		print_ast(n.val1, depth + 1, src);
		print_ast(n.expr, depth + 1, src);
		print_ast(n.body, depth + 1, src);
	case Case_Clause:
		print_ast(n.list, depth + 1, src);
		print_ast(n.body, depth + 1, src);
	case Switch_Stmt:
		print_ast(n.label, depth + 1, src);
		print_ast(n.init, depth + 1, src);
		print_ast(n.cond, depth + 1, src);
		print_ast(n.body, depth + 1, src);
	case Type_Switch_Stmt:
		print_ast(n.label, depth + 1, src);
		print_ast(n.tag, depth + 1, src);
		print_ast(n.expr, depth + 1, src);
		print_ast(n.body, depth + 1, src);
	case Branch_Stmt:
		print_ast(n.label, depth + 1, src);
	case Using_Stmt:
		print_ast(n.list, depth + 1, src);
	case Bad_Decl:
	case Value_Decl:
		print_ast(n.attributes, depth + 1, src);
		print_ast(n.names, depth + 1, src);
		print_ast(n.type, depth + 1, src);
		print_ast(n.values, depth + 1, src);
		fmt.println();
	case Package_Decl:
	case Import_Decl:
	case Foreign_Block_Decl:
		print_ast(n.attributes, depth + 1, src);
		print_ast(n.foreign_library, depth + 1, src);
		print_ast(n.body, depth + 1, src);
	case Foreign_Import_Decl:
		print_ast(n.name, depth + 1, src);
	case Proc_Group:
		print_ast(n.args, depth + 1, src);
	case Attribute:
		print_ast(n.elems, depth + 1, src);
	case Field:
		print_ast(n.names, depth + 1, src);
		print_ast(n.type, depth + 1, src);
		print_ast(n.default_value, depth + 1, src);
	case Field_List:
		print_ast(n.list, depth + 1, src);
	case Typeid_Type:
		print_ast(n.specialization, depth + 1, src);
	case Helper_Type:
		print_ast(n.type, depth + 1, src);
	case Distinct_Type:
		print_ast(n.type, depth + 1, src);
	case Poly_Type:
		print_ast(n.type, depth + 1, src);
		print_ast(n.specialization, depth + 1, src);
	case Proc_Type:
		print_ast(n.params, depth + 1, src);
		print_ast(n.results, depth + 1, src);
	case Pointer_Type:
		print_ast(n.elem, depth + 1, src);
	case Array_Type:
		print_ast(n.len, depth + 1, src);
		print_ast(n.elem, depth + 1, src);
	case Dynamic_Array_Type:
		print_ast(n.elem, depth + 1, src);
	case Struct_Type:
		fmt.printf("struct");
		print_ast(n.poly_params, depth + 1, src);
		print_ast(n.align, depth + 1, src);
		print_ast(n.fields, depth + 1, src);
	case Union_Type:
		print_ast(n.poly_params, depth + 1, src);
		print_ast(n.align, depth + 1, src);
		print_ast(n.variants, depth + 1, src);
	case Enum_Type:
		print_ast(n.base_type, depth + 1, src);
		print_ast(n.fields, depth + 1, src);
	case Bit_Set_Type:
		print_ast(n.elem, depth + 1, src);
		print_ast(n.underlying, depth + 1, src);
	case Map_Type:
		print_ast(n.key, depth + 1, src);
		print_ast(n.value, depth + 1, src);
	case:
		fmt.panicf("Unhandled node kind: %T", n);
	}
}