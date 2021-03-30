package common

import "core:odin/ast"
import "core:log"
import "core:mem"
import "core:fmt"

keyword_map: map[string]bool = {
	"int" = true,
	"uint" = true,
	"string" = true,
	"u64" = true,
	"f32" = true,
	"f64" = true,
	"i64" = true,
	"i32" = true,
	"bool" = true,
	"rawptr" = true,
	"any" = true,
	"u32" = true,
	"true" = true,
	"false" = true,
	"nil" = true,
	"byte" = true,
	"u8" = true,
	"i8" = true,
	"rune" = true,
};

GlobalExpr :: struct {
	name:    string,
	expr:    ^ast.Expr,
	mutable: bool,
	docs:    ^ast.Comment_Group,
}

collect_value_decl :: proc(exprs: ^[dynamic]GlobalExpr, file: ast.File, stmt: ^ast.Node) {
	if value_decl, ok := stmt.derived.(ast.Value_Decl); ok {
		for name, i in value_decl.names {
			str := get_ast_node_string(name, file.src);

			if value_decl.type != nil {
				append(exprs, GlobalExpr {name = str, expr = value_decl.type, mutable = value_decl.is_mutable, docs = value_decl.docs});
			} else {
				if len(value_decl.values) > i {
					append(exprs, GlobalExpr {name = str, expr = value_decl.values[i], docs = value_decl.docs});
				}
			}
		}
	}
}

//TODO(add a sub procedure to avoid repeating the value decl work)
collect_globals :: proc(file: ast.File) -> []GlobalExpr {

	exprs := make([dynamic]GlobalExpr, context.temp_allocator);

	for decl in file.decls {

		if value_decl, ok := decl.derived.(ast.Value_Decl); ok {
			collect_value_decl(&exprs, file, decl);
		} else if when_decl, ok := decl.derived.(ast.When_Stmt); ok {

			if when_decl.cond == nil {
				continue;
			}

			if when_decl.body == nil {
				continue;
			}

			if binary, ok := when_decl.cond.derived.(ast.Binary_Expr); ok {

				if binary.left == nil || binary.right == nil {
					continue;
				}

				ident:     ^ast.Ident;
				basic_lit: ^ast.Basic_Lit;

				if t, ok := binary.left.derived.(ast.Ident); ok {
					ident = cast(^ast.Ident)binary.left;
				} else if t, ok := binary.left.derived.(ast.Basic_Lit); ok {
					basic_lit = cast(^ast.Basic_Lit)binary.left;
				}

				if t, ok := binary.right.derived.(ast.Ident); ok {
					ident = cast(^ast.Ident)binary.right;
				} else if t, ok := binary.right.derived.(ast.Basic_Lit); ok {
					basic_lit = cast(^ast.Basic_Lit)binary.right;
				}

				if ident != nil && basic_lit != nil {

					//hardcode for windows for now
					if ident.name == "ODIN_OS" && basic_lit.tok.text == "\"windows\"" {

						if block, ok := when_decl.body.derived.(ast.Block_Stmt); ok {
							for stmt in block.stmts {
								collect_value_decl(&exprs, file, stmt);
							}
						}
					} else if ident.name != "ODIN_OS" {
						if block, ok := when_decl.body.derived.(ast.Block_Stmt); ok {
							for stmt in block.stmts {
								collect_value_decl(&exprs, file, stmt);
							}
						}
					}
				}
			}

			else {
				if block, ok := when_decl.body.derived.(ast.Block_Stmt); ok {
					for stmt in block.stmts {
						collect_value_decl(&exprs, file, stmt);
					}
				}
			}
		} else if foreign_decl, ok := decl.derived.(ast.Foreign_Block_Decl); ok {

			if foreign_decl.body == nil {
				continue;
			}

			if block, ok := foreign_decl.body.derived.(ast.Block_Stmt); ok {
				for stmt in block.stmts {
					collect_value_decl(&exprs, file, stmt);
				}
			}
		}
	}

	return exprs[:];
}

get_ast_node_string :: proc(node: ^ast.Node, src: []byte) -> string {
	return string(src[node.pos.offset:node.end.offset]);
}

free_ast :: proc{
	free_ast_node,
	free_ast_array,
	free_ast_dynamic_array,
	free_ast_comment,
};

free_ast_comment :: proc(a: ^ast.Comment_Group, allocator: mem.Allocator) {
	if a == nil {
		return;
	}

	if len(a.list) > 0 {
		delete(a.list, allocator);
	}

	free(a, allocator);
}

free_ast_array :: proc(array: $A/[]^$T, allocator: mem.Allocator) {
	for elem, i in array {
		free_ast(elem, allocator);
	}
	delete(array, allocator);
}

free_ast_dynamic_array :: proc(array: $A/[dynamic]^$T, allocator: mem.Allocator) {
	for elem, i in array {
		free_ast(elem, allocator);
	}

	delete(array);
}

free_ast_node :: proc(node: ^ast.Node, allocator: mem.Allocator) {

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
		free_ast(n.expr, allocator);
	case Proc_Lit:
		free_ast(n.type, allocator);
		free_ast(n.body, allocator);
		free_ast(n.where_clauses, allocator);
	case Comp_Lit:
		free_ast(n.type, allocator);
		free_ast(n.elems, allocator);
	case Tag_Expr:
		free_ast(n.expr, allocator);
	case Unary_Expr:
		free_ast(n.expr, allocator);
	case Binary_Expr:
		free_ast(n.left, allocator);
		free_ast(n.right, allocator);
	case Paren_Expr:
		free_ast(n.expr, allocator);
	case Call_Expr:
		free_ast(n.expr, allocator);
		free_ast(n.args, allocator);
	case Selector_Expr:
		free_ast(n.expr, allocator);
		free_ast(n.field, allocator);
	case Implicit_Selector_Expr:
		free_ast(n.field, allocator);
	case Index_Expr:
		free_ast(n.expr, allocator);
		free_ast(n.index, allocator);
	case Deref_Expr:
		free_ast(n.expr, allocator);
	case Slice_Expr:
		free_ast(n.expr, allocator);
		free_ast(n.low, allocator);
		free_ast(n.high, allocator);
	case Field_Value:
		free_ast(n.field, allocator);
		free_ast(n.value, allocator);
	case Ternary_Expr:
		free_ast(n.cond, allocator);
		free_ast(n.x, allocator);
		free_ast(n.y, allocator);
	case Ternary_If_Expr:
		free_ast(n.x, allocator);
		free_ast(n.cond, allocator);
		free_ast(n.y, allocator);
	case Ternary_When_Expr:
		free_ast(n.x, allocator);
		free_ast(n.cond, allocator);
		free_ast(n.y, allocator);
	case Type_Assertion:
		free_ast(n.expr, allocator);
		free_ast(n.type, allocator);
	case Type_Cast:
		free_ast(n.type, allocator);
		free_ast(n.expr, allocator);
	case Auto_Cast:
		free_ast(n.expr, allocator);
	case Bad_Stmt:
	case Empty_Stmt:
	case Expr_Stmt:
		free_ast(n.expr, allocator);
	case Tag_Stmt:
		r := cast(^Expr_Stmt)node;
		free_ast(r.expr, allocator);
	case Assign_Stmt:
		free_ast(n.lhs, allocator);
		free_ast(n.rhs, allocator);
	case Block_Stmt:
		free_ast(n.label, allocator);
		free_ast(n.stmts, allocator);
	case If_Stmt:
		free_ast(n.label, allocator);
		free_ast(n.init, allocator);
		free_ast(n.cond, allocator);
		free_ast(n.body, allocator);
		free_ast(n.else_stmt, allocator);
	case When_Stmt:
		free_ast(n.cond, allocator);
		free_ast(n.body, allocator);
		free_ast(n.else_stmt, allocator);
	case Return_Stmt:
		free_ast(n.results, allocator);
	case Defer_Stmt:
		free_ast(n.stmt, allocator);
	case For_Stmt:
		free_ast(n.label, allocator);
		free_ast(n.init, allocator);
		free_ast(n.cond, allocator);
		free_ast(n.post, allocator);
		free_ast(n.body, allocator);
	case Range_Stmt:
		free_ast(n.label, allocator);
		free_ast(n.vals, allocator);
		free_ast(n.expr, allocator);
		free_ast(n.body, allocator);
	case Case_Clause:
		free_ast(n.list, allocator);
		free_ast(n.body, allocator);
	case Switch_Stmt:
		free_ast(n.label, allocator);
		free_ast(n.init, allocator);
		free_ast(n.cond, allocator);
		free_ast(n.body, allocator);
	case Type_Switch_Stmt:
		free_ast(n.label, allocator);
		free_ast(n.tag, allocator);
		free_ast(n.expr, allocator);
		free_ast(n.body, allocator);
	case Branch_Stmt:
		free_ast(n.label, allocator);
	case Using_Stmt:
		free_ast(n.list, allocator);
	case Bad_Decl:
	case Value_Decl:
		free_ast(n.attributes, allocator);
		free_ast(n.names, allocator);
		free_ast(n.type, allocator);
		free_ast(n.values, allocator);
			//free_ast(n.docs);
			//free_ast(n.comment);
	case Package_Decl:
			//free_ast(n.docs);
			//free_ast(n.comment);
	case Import_Decl:
			//free_ast(n.docs);
			//free_ast(n.comment);
	case Foreign_Block_Decl:
		free_ast(n.attributes, allocator);
		free_ast(n.foreign_library, allocator);
		free_ast(n.body, allocator);
	case Foreign_Import_Decl:
		free_ast(n.name, allocator);
		free_ast(n.attributes, allocator);
	case Proc_Group:
		free_ast(n.args, allocator);
	case Attribute:
		free_ast(n.elems, allocator);
	case Field:
		free_ast(n.names, allocator);
		free_ast(n.type, allocator);
		free_ast(n.default_value, allocator);
			//free_ast(n.docs);
			//free_ast(n.comment);
	case Field_List:
		free_ast(n.list, allocator);
	case Typeid_Type:
		free_ast(n.specialization, allocator);
	case Helper_Type:
		free_ast(n.type, allocator);
	case Distinct_Type:
		free_ast(n.type, allocator);
	case Poly_Type:
		free_ast(n.type, allocator);
		free_ast(n.specialization, allocator);
	case Proc_Type:
		free_ast(n.params, allocator);
		free_ast(n.results, allocator);
	case Pointer_Type:
		free_ast(n.elem, allocator);
	case Array_Type:
		free_ast(n.len, allocator);
		free_ast(n.elem, allocator);
		free_ast(n.tag, allocator);
	case Dynamic_Array_Type:
		free_ast(n.elem, allocator);
		free_ast(n.tag, allocator);
	case Struct_Type:
		free_ast(n.poly_params, allocator);
		free_ast(n.align, allocator);
		free_ast(n.fields, allocator);
		free_ast(n.where_clauses, allocator);
	case Union_Type:
		free_ast(n.poly_params, allocator);
		free_ast(n.align, allocator);
		free_ast(n.variants, allocator);
		free_ast(n.where_clauses, allocator);
	case Enum_Type:
		free_ast(n.base_type, allocator);
		free_ast(n.fields, allocator);
	case Bit_Set_Type:
		free_ast(n.elem, allocator);
		free_ast(n.underlying, allocator);
	case Map_Type:
		free_ast(n.key, allocator);
		free_ast(n.value, allocator);
	case:
		log.warnf("free Unhandled node kind: %T", n);
	}

	mem.free(node, allocator);
}

free_ast_file :: proc(file: ast.File, allocator := context.allocator) {

	for decl in file.decls {
		free_ast(decl, allocator);
	}

	free_ast(file.pkg_decl, allocator);

	for comment in file.comments {
		free_ast(comment, allocator);
	}

	delete(file.comments);
	delete(file.imports);
	delete(file.decls);
}

node_equal :: proc{
	node_equal_node,
	node_equal_array,
	node_equal_dynamic_array,
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
			return true;
			//return n.name == m.name;
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
		return true;
			//return node_equal(n.sp)
			//if n, ok := a.derived.(Poly_Type); ok {
			//    ret := node_equal(n.type, m.type);
			//    ret &= node_equal(n.specialization, m.specialization);
			//    return ret;
			//}
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
		return true;
			//if n, ok := a.derived.(Typeid_Type); ok {
			//    return node_equal(n.specialization, m.specialization);
			//}
	case:
		log.warn("Unhandled poly node kind: %T", m);
	}

	return false;
}
