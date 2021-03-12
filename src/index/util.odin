package index

import "core:odin/ast"
import "core:strings"
import "core:path"

/*
	Returns the string representation of a type. This allows us to print the signature without storing it in the indexer as a string(saving memory).
*/
node_to_string :: proc (node: ^ast.Node) -> string {

	builder := strings.make_builder(context.temp_allocator);

	build_string(node, &builder);

	return strings.to_string(builder);
}

build_string :: proc {
build_string_ast_array, 
build_string_dynamic_array, 
build_string_node};

build_string_dynamic_array :: proc (array: $A/[]^$T, builder: ^strings.Builder) {

	for elem, i in array {
		build_string(elem, builder);
	}
}

build_string_ast_array :: proc (array: $A/[dynamic]^$T, builder: ^strings.Builder) {

	for elem, i in array {
		build_string(elem, builder);
	}
}

build_string_node :: proc (node: ^ast.Node, builder: ^strings.Builder) {

	using ast;

	if node == nil {
		return;
	}

	switch n in node.derived {
	case Bad_Expr:
	case Ident:
		if strings.contains(n.name, "/") {
			strings.write_string(builder, path.base(n.name, false, context.temp_allocator));
		} else {
			strings.write_string(builder, n.name);
		}
	case Implicit:
	case Undef:
	case Basic_Lit:
			//strings.write_string(builder, n.tok.text);
	case Ellipsis:
		build_string(n.expr, builder);
	case Proc_Lit:
		build_string(n.type, builder);
		build_string(n.body, builder);
	case Comp_Lit:
		build_string(n.type, builder);
		build_string(n.elems, builder);
	case Tag_Expr:
		build_string(n.expr, builder);
	case Unary_Expr:
		build_string(n.expr, builder);
	case Binary_Expr:
		build_string(n.left, builder);
		build_string(n.right, builder);
	case Paren_Expr:
		strings.write_string(builder, "(");
		build_string(n.expr, builder);
		strings.write_string(builder, ")");
	case Call_Expr:
		build_string(n.expr, builder);
		strings.write_string(builder, "(");
		build_string(n.args, builder);
		strings.write_string(builder, ")");
	case Selector_Expr:
		build_string(n.expr, builder);
		strings.write_string(builder, ".");
		build_string(n.field, builder);
	case Index_Expr:
		build_string(n.expr, builder);
		strings.write_string(builder, "[");
		build_string(n.index, builder);
		strings.write_string(builder, "]");
	case Deref_Expr:
		build_string(n.expr, builder);
	case Slice_Expr:
		build_string(n.expr, builder);
		build_string(n.low, builder);
		build_string(n.high, builder);
	case Field_Value:
		build_string(n.field, builder);
		strings.write_string(builder, ": ");
		build_string(n.value, builder);
	case Type_Cast:
		build_string(n.type, builder);
		build_string(n.expr, builder);
	case Bad_Stmt:
	case Bad_Decl:
	case Attribute:
		build_string(n.elems, builder);
	case Field:
		build_string(n.names, builder);
		if len(n.names) > 0 {
			strings.write_string(builder, ": ");
		}
		build_string(n.type, builder);
		build_string(n.default_value, builder);
	case Field_List:
		for field, i in n.list {
			build_string(field, builder);
			if len(n.list) - 1 != i {
				strings.write_string(builder, ",");
			}
		}
	case Typeid_Type:
		build_string(n.specialization, builder);
	case Helper_Type:
		build_string(n.type, builder);
	case Distinct_Type:
		build_string(n.type, builder);
	case Poly_Type:
		build_string(n.type, builder);
		build_string(n.specialization, builder);
	case Proc_Type:
		strings.write_string(builder, "proc(");
		build_string(n.params, builder);
		strings.write_string(builder, ") -> ");
		build_string(n.results, builder);
	case Pointer_Type:
		strings.write_string(builder, "^");
		build_string(n.elem, builder);
	case Array_Type:
		strings.write_string(builder, "[");
		build_string(n.len, builder);
		strings.write_string(builder, "]");
		build_string(n.elem, builder);
	case Dynamic_Array_Type:
		strings.write_string(builder, "[dynamic]");
		build_string(n.elem, builder);
	case Struct_Type:
		build_string(n.poly_params, builder);
		build_string(n.align, builder);
		build_string(n.fields, builder);
	case Union_Type:
		build_string(n.poly_params, builder);
		build_string(n.align, builder);
		build_string(n.variants, builder);
	case Enum_Type:
		build_string(n.base_type, builder);
		build_string(n.fields, builder);
	case Bit_Set_Type:
		build_string(n.elem, builder);
		build_string(n.underlying, builder);
	case Map_Type:
		strings.write_string(builder, "map");
		strings.write_string(builder, "[");
		build_string(n.key, builder);
		strings.write_string(builder, "]");
		build_string(n.value, builder);
	}
}