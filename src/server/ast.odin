#+feature dynamic-literals
package server

import "core:fmt"
import "core:log"
import "core:mem"
import "core:odin/ast"
import "core:odin/parser"
import path "core:path/slashpath"
import "core:strings"

keyword_map: map[string]bool = {
	"typeid"        = true,
	"int"           = true,
	"uint"          = true,
	"string"        = true,
	"cstring"       = true,
	"u64"           = true,
	"f32"           = true,
	"f64"           = true,
	"i64"           = true,
	"i128"          = true,
	"i32"           = true,
	"i16"           = true,
	"u16"           = true,
	"bool"          = true,
	"rawptr"        = true,
	"any"           = true,
	"u32"           = true,
	"u128"          = true,
	"b8"            = true,
	"b16"           = true,
	"b32"           = true,
	"b64"           = true,
	"true"          = true,
	"false"         = true,
	"nil"           = true,
	"byte"          = true,
	"u8"            = true,
	"i8"            = true,
	"rune"          = true,
	"f16be"         = true,
	"f16le"         = true,
	"f32be"         = true,
	"f32le"         = true,
	"f64be"         = true,
	"f64le"         = true,
	"i16be"         = true,
	"i16le"         = true,
	"i32be"         = true,
	"i32le"         = true,
	"i64be"         = true,
	"i64le"         = true,
	"u16be"         = true,
	"u16le"         = true,
	"u32be"         = true,
	"u32le"         = true,
	"u64be"         = true,
	"u64le"         = true,
	"i128be"        = true,
	"i128le"        = true,
	"u128be"        = true,
	"u128le"        = true,
	"complex32"     = true,
	"complex64"     = true,
	"complex128"    = true,
	"quaternion64"  = true,
	"quaternion128" = true,
	"quaternion256" = true,
	"uintptr"       = true,
}

GlobalExpr :: struct {
	name:       string,
	name_expr:  ^ast.Expr,
	expr:       ^ast.Expr,
	mutable:    bool,
	docs:       ^ast.Comment_Group,
	comment:    ^ast.Comment_Group,
	attributes: []^ast.Attribute,
	deprecated: bool,
	private:    parser.Private_Flag,
	builtin:    bool,
}

get_attribute_objc_type :: proc(attributes: []^ast.Attribute) -> ^ast.Expr {
	for attribute in attributes {
		for elem in attribute.elems {
			if assign, ok := elem.derived.(^ast.Field_Value); ok {
				if ident, ok := assign.field.derived.(^ast.Ident); ok && ident.name == "objc_type" {
					return assign.value
				}
			}
		}
	}

	return nil
}

get_attribute_objc_name :: proc(attributes: []^ast.Attribute) -> (string, bool) {
	for attribute in attributes {
		for elem in attribute.elems {
			if assign, ok := elem.derived.(^ast.Field_Value); ok {
				if ident, ok := assign.field.derived.(^ast.Ident); ok && ident.name == "objc_name" {
					if lit, ok := assign.value.derived.(^ast.Basic_Lit); ok && len(lit.tok.text) > 2 {
						return lit.tok.text[1:len(lit.tok.text) - 1], true
					}
				}

			}
		}
	}

	return "", false
}

get_attribute_objc_class_name :: proc(attributes: []^ast.Attribute) -> (string, bool) {
	for attribute in attributes {
		for elem in attribute.elems {
			if assign, ok := elem.derived.(^ast.Field_Value); ok {
				if ident, ok := assign.field.derived.(^ast.Ident); ok && ident.name == "objc_class" {
					if lit, ok := assign.value.derived.(^ast.Basic_Lit); ok && len(lit.tok.text) > 2 {
						return lit.tok.text[1:len(lit.tok.text) - 1], true
					}
				}

			}
		}
	}

	return "", false
}


get_attribute_objc_is_class_method :: proc(attributes: []^ast.Attribute) -> bool {
	for attribute in attributes {
		for elem in attribute.elems {
			if assign, ok := elem.derived.(^ast.Field_Value); ok {
				if ident, ok := assign.field.derived.(^ast.Ident); ok && ident.name == "objc_is_class_method" {
					if field_value, ok := assign.value.derived.(^ast.Ident); ok && field_value.name == "true" {
						return true
					}
				}

			}
		}
	}
	return false
}

unwrap_comp_literal :: proc(expr: ^ast.Expr) -> (^ast.Comp_Lit, int, bool) {
	n := 0
	expr := expr
	for expr != nil {
		if unary, ok := expr.derived.(^ast.Unary_Expr); ok {
			if unary.op.kind == .And {
				expr = unary.expr
				n += 1
			}
		} else {
			break
		}
	}

	if expr != nil {
		if comp_literal, ok := expr.derived.(^ast.Comp_Lit); ok {
			return comp_literal, n, ok
		}

		return {}, n, false
	}

	return {}, n, false
}

unwrap_pointer_ident :: proc(expr: ^ast.Expr) -> (ast.Ident, int, bool) {
	n := 0
	expr := expr
	for expr != nil {
		if pointer, ok := expr.derived.(^ast.Pointer_Type); ok {
			expr = pointer.elem
			n += 1
		} else {
			break
		}
	}

	// Check for parapoly specialization
	if expr != nil {
		if poly, ok := expr.derived.(^ast.Poly_Type); ok {
			expr = poly.specialization
		}
	}

	// Check for parapoly self
	if expr != nil {
		if call, ok := expr.derived.(^ast.Call_Expr); ok {
			expr = call.expr
		}
	}

	if expr != nil {
		if ident, ok := expr.derived.(^ast.Ident); ok {
			return ident^, n, ok
		}

		return {}, n, false
	}

	return {}, n, false
}

unwrap_pointer_expr :: proc(expr: ^ast.Expr) -> (^ast.Expr, int, bool) {
	n := 0
	expr := expr
	for expr != nil {
		if pointer, ok := expr.derived.(^ast.Pointer_Type); ok {
			expr = pointer.elem
			n += 1
		} else {
			break
		}
	}

	if expr == nil {
		return {}, n, false
	}

	return expr, n, true
}

array_is_soa :: proc(array: ast.Array_Type) -> bool {
	if array.tag != nil {
		if basic, ok := array.tag.derived.(^ast.Basic_Directive); ok && basic.name == "soa" {
			return true
		}
	}
	return false
}

dynamic_array_is_soa :: proc(array: ast.Dynamic_Array_Type) -> bool {
	if array.tag != nil {
		if basic, ok := array.tag.derived.(^ast.Basic_Directive); ok && basic.name == "soa" {
			return true
		}
	}
	return false
}

expr_contains_poly :: proc(expr: ^ast.Expr) -> bool {
	if expr == nil {
		return false
	}

	visit :: proc(visitor: ^ast.Visitor, node: ^ast.Node) -> ^ast.Visitor {
		if node == nil {
			return nil
		}
		if _, ok := node.derived.(^ast.Poly_Type); ok {
			b := cast(^bool)visitor.data
			b^ = true
			return nil
		}
		return visitor
	}

	found := false

	visitor := ast.Visitor {
		visit = visit,
		data  = &found,
	}

	ast.walk(&visitor, expr)

	return found
}

is_expr_basic_lit :: proc(expr: ^ast.Expr) -> bool {
	_, ok := expr.derived.(^ast.Basic_Lit)
	return ok
}

collect_value_decl :: proc(
	exprs: ^[dynamic]GlobalExpr,
	file: ast.File,
	file_tags: parser.File_Tags,
	stmt: ^ast.Node,
	skip_private: bool,
) {
	value_decl, is_value_decl := stmt.derived.(^ast.Value_Decl)

	if !is_value_decl {
		return
	}

	global_expr := GlobalExpr {
		mutable    = value_decl.is_mutable,
		docs       = value_decl.docs,
		comment    = get_file_comment(file, value_decl.pos.line),
		attributes = value_decl.attributes[:],
		private    = file_tags.private,
	}

	for attribute in value_decl.attributes {
		for elem in attribute.elems {
			ident: ^ast.Ident
			value: ast.Any_Node

			#partial switch v in elem.derived {
			case ^ast.Field_Value:
				ident = v.field.derived.(^ast.Ident) or_continue
				value = v.value.derived
			case ^ast.Ident:
				ident = v
			case:
				continue
			}

			switch ident.name {
			case "deprecated":
				global_expr.deprecated = true
			case "builtin":
				global_expr.builtin = true
			case "private":
				if val, ok := value.(^ast.Basic_Lit); ok {
					switch val.tok.text {
					case "\"file\"":
						global_expr.private = .File
					case "\"package\"":
						global_expr.private = .Package
					}
				} else {
					global_expr.private = .Package
				}
			}
		}
	}

	if file_tags.ignore {
		global_expr.private = .File
	}

	if skip_private && global_expr.private == .File {
		return
	}

	for name, i in value_decl.names {
		global_expr.name = get_ast_node_string(name, file.src)
		global_expr.name_expr = name

		if value_decl.type != nil {
			global_expr.expr = value_decl.type
			append(exprs, global_expr)
		} else if len(value_decl.values) > i {
			global_expr.expr = value_decl.values[i]
			append(exprs, global_expr)
		}
	}
}

collect_when_stmt :: proc(
	exprs: ^[dynamic]GlobalExpr,
	file: ast.File,
	file_tags: parser.File_Tags,
	when_decl: ^ast.When_Stmt,
	skip_private: bool,
) {
	if when_decl.cond == nil {
		return
	}

	if when_decl.body == nil {
		return
	}

	if resolve_when_condition(when_decl.cond) {
		if block, ok := when_decl.body.derived.(^ast.Block_Stmt); ok {
			for stmt in block.stmts {
				if when_stmt, ok := stmt.derived.(^ast.When_Stmt); ok {
					collect_when_stmt(exprs, file, file_tags, when_stmt, skip_private)
				} else if foreign_decl, ok := stmt.derived.(^ast.Foreign_Block_Decl); ok {
					if foreign_decl.body == nil {
						continue
					}

					if foreign_block, ok := foreign_decl.body.derived.(^ast.Block_Stmt); ok {
						for foreign_stmt in foreign_block.stmts {
							collect_value_decl(exprs, file, file_tags, foreign_stmt, skip_private)
						}
					}
				} else {
					collect_value_decl(exprs, file, file_tags, stmt, skip_private)
				}
			}
		}
	} else {
		else_stmt := when_decl.else_stmt

		for else_stmt != nil {
			if else_when, ok := else_stmt.derived.(^ast.When_Stmt); ok {
				if resolve_when_condition(else_when.cond) {
					if block, ok := else_when.body.derived.(^ast.Block_Stmt); ok {
						for stmt in block.stmts {
							if when_stmt, ok := stmt.derived.(^ast.When_Stmt); ok {
								collect_when_stmt(exprs, file, file_tags, when_stmt, skip_private)
							} else if foreign_decl, ok := stmt.derived.(^ast.Foreign_Block_Decl); ok {
								if foreign_decl.body != nil {
									if foreign_block, ok := foreign_decl.body.derived.(^ast.Block_Stmt); ok {
										for foreign_stmt in foreign_block.stmts {
											collect_value_decl(exprs, file, file_tags, foreign_stmt, skip_private)
										}
									}
								}
							} else {
								collect_value_decl(exprs, file, file_tags, stmt, skip_private)
							}
						}
					}
					return
				}
				else_stmt = else_when.else_stmt
			} else {
				return
			}
		}
	}


}

collect_globals :: proc(file: ast.File, skip_private := false) -> []GlobalExpr {
	exprs := make([dynamic]GlobalExpr, context.temp_allocator)
	defer shrink(&exprs)

	file_tags := parser.parse_file_tags(file, context.temp_allocator)

	for decl in file.decls {
		if value_decl, ok := decl.derived.(^ast.Value_Decl); ok {
			collect_value_decl(&exprs, file, file_tags, decl, skip_private)
		} else if when_decl, ok := decl.derived.(^ast.When_Stmt); ok {
			collect_when_stmt(&exprs, file, file_tags, when_decl, skip_private)
		} else if foreign_decl, ok := decl.derived.(^ast.Foreign_Block_Decl); ok {
			if foreign_decl.body == nil {
				continue
			}

			if block, ok := foreign_decl.body.derived.(^ast.Block_Stmt); ok {
				for stmt in block.stmts {
					collect_value_decl(&exprs, file, file_tags, stmt, skip_private)
				}
			}
		}
	}

	return exprs[:]
}

get_ast_node_string :: proc(node: ^ast.Node, src: string) -> string {
	return string(src[node.pos.offset:node.end.offset])
}

get_doc :: proc(comment: ^ast.Comment_Group, allocator: mem.Allocator) -> string {
	if comment != nil {
		tmp: string

		for doc in comment.list {
			tmp = strings.concatenate({tmp, "\n", doc.text}, context.temp_allocator)
		}

		if tmp != "" {
			no_lines, _ := strings.replace_all(tmp, "//", "", context.temp_allocator)
			no_begin_comments, _ := strings.replace_all(no_lines, "/*", "", context.temp_allocator)
			no_end_comments, _ := strings.replace_all(no_begin_comments, "*/", "", context.temp_allocator)
			return strings.clone(no_end_comments, allocator)
		}
	}

	return ""
}

get_comment :: proc(comment: ^ast.Comment_Group) -> string {
	if comment != nil && len(comment.list) > 0 {
		return comment.list[0].text
	}
	return ""
}

free_ast :: proc {
	free_ast_node,
	free_ast_array,
	free_ast_dynamic_array,
	free_ast_comment,
}

free_ast_comment :: proc(a: ^ast.Comment_Group, allocator: mem.Allocator) {
	if a == nil {
		return
	}

	if len(a.list) > 0 {
		delete(a.list, allocator)
	}

	free(a, allocator)
}

free_ast_array :: proc(array: $A/[]^$T, allocator: mem.Allocator) {
	for elem, i in array {
		free_ast(elem, allocator)
	}
	delete(array, allocator)
}

free_ast_dynamic_array :: proc(array: $A/[dynamic]^$T, allocator: mem.Allocator) {
	for elem, i in array {
		free_ast(elem, allocator)
	}

	delete(array)
}

free_ast_node :: proc(node: ^ast.Node, allocator: mem.Allocator) {
	using ast

	if node == nil {
		return
	}

	if node.derived != nil do #partial switch n in node.derived {
	case ^Bad_Expr:
	case ^Ident:
	case ^Implicit:
	case ^Undef:
	case ^Basic_Directive:
	case ^Basic_Lit:
	case ^Ellipsis:
		free_ast(n.expr, allocator)
	case ^Proc_Lit:
		free_ast(n.type, allocator)
		free_ast(n.body, allocator)
		free_ast(n.where_clauses, allocator)
	case ^Comp_Lit:
		free_ast(n.type, allocator)
		free_ast(n.elems, allocator)
	case ^Tag_Expr:
		free_ast(n.expr, allocator)
	case ^Unary_Expr:
		free_ast(n.expr, allocator)
	case ^Binary_Expr:
		free_ast(n.left, allocator)
		free_ast(n.right, allocator)
	case ^Paren_Expr:
		free_ast(n.expr, allocator)
	case ^Call_Expr:
		free_ast(n.expr, allocator)
		free_ast(n.args, allocator)
	case ^Selector_Expr:
		free_ast(n.expr, allocator)
		free_ast(n.field, allocator)
	case ^Implicit_Selector_Expr:
		free_ast(n.field, allocator)
	case ^Index_Expr:
		free_ast(n.expr, allocator)
		free_ast(n.index, allocator)
	case ^Deref_Expr:
		free_ast(n.expr, allocator)
	case ^Slice_Expr:
		free_ast(n.expr, allocator)
		free_ast(n.low, allocator)
		free_ast(n.high, allocator)
	case ^Field_Value:
		free_ast(n.field, allocator)
		free_ast(n.value, allocator)
	case ^Ternary_If_Expr:
		free_ast(n.x, allocator)
		free_ast(n.cond, allocator)
		free_ast(n.y, allocator)
	case ^Ternary_When_Expr:
		free_ast(n.x, allocator)
		free_ast(n.cond, allocator)
		free_ast(n.y, allocator)
	case ^Type_Assertion:
		free_ast(n.expr, allocator)
		free_ast(n.type, allocator)
	case ^Type_Cast:
		free_ast(n.type, allocator)
		free_ast(n.expr, allocator)
	case ^Auto_Cast:
		free_ast(n.expr, allocator)
	case ^Bad_Stmt:
	case ^Empty_Stmt:
	case ^Expr_Stmt:
		free_ast(n.expr, allocator)
	case ^Tag_Stmt:
		r := cast(^Expr_Stmt)node
		free_ast(r.expr, allocator)
	case ^Assign_Stmt:
		free_ast(n.lhs, allocator)
		free_ast(n.rhs, allocator)
	case ^Block_Stmt:
		free_ast(n.label, allocator)
		free_ast(n.stmts, allocator)
	case ^If_Stmt:
		free_ast(n.label, allocator)
		free_ast(n.init, allocator)
		free_ast(n.cond, allocator)
		free_ast(n.body, allocator)
		free_ast(n.else_stmt, allocator)
	case ^When_Stmt:
		free_ast(n.cond, allocator)
		free_ast(n.body, allocator)
		free_ast(n.else_stmt, allocator)
	case ^Return_Stmt:
		free_ast(n.results, allocator)
	case ^Defer_Stmt:
		free_ast(n.stmt, allocator)
	case ^For_Stmt:
		free_ast(n.label, allocator)
		free_ast(n.init, allocator)
		free_ast(n.cond, allocator)
		free_ast(n.post, allocator)
		free_ast(n.body, allocator)
	case ^Range_Stmt:
		free_ast(n.label, allocator)
		free_ast(n.vals, allocator)
		free_ast(n.expr, allocator)
		free_ast(n.body, allocator)
	case ^Case_Clause:
		free_ast(n.list, allocator)
		free_ast(n.body, allocator)
	case ^Switch_Stmt:
		free_ast(n.label, allocator)
		free_ast(n.init, allocator)
		free_ast(n.cond, allocator)
		free_ast(n.body, allocator)
	case ^Type_Switch_Stmt:
		free_ast(n.label, allocator)
		free_ast(n.tag, allocator)
		free_ast(n.expr, allocator)
		free_ast(n.body, allocator)
	case ^Branch_Stmt:
		free_ast(n.label, allocator)
	case ^Using_Stmt:
		free_ast(n.list, allocator)
	case ^Bad_Decl:
	case ^Value_Decl:
		free_ast(n.attributes, allocator)
		free_ast(n.names, allocator)
		free_ast(n.type, allocator)
		free_ast(n.values, allocator)
	case ^Package_Decl:
	case ^Import_Decl:
	case ^Foreign_Block_Decl:
		free_ast(n.attributes, allocator)
		free_ast(n.foreign_library, allocator)
		free_ast(n.body, allocator)
	case ^Foreign_Import_Decl:
		free_ast(n.name, allocator)
		free_ast(n.attributes, allocator)
	case ^Proc_Group:
		free_ast(n.args, allocator)
	case ^Attribute:
		free_ast(n.elems, allocator)
	case ^Field:
		free_ast(n.names, allocator)
		free_ast(n.type, allocator)
		free_ast(n.default_value, allocator)
	//free_ast(n.docs);
	//free_ast(n.comment);
	case ^Field_List:
		free_ast(n.list, allocator)
	case ^Typeid_Type:
		free_ast(n.specialization, allocator)
	case ^Helper_Type:
		free_ast(n.type, allocator)
	case ^Distinct_Type:
		free_ast(n.type, allocator)
	case ^Poly_Type:
		free_ast(n.type, allocator)
		free_ast(n.specialization, allocator)
	case ^Proc_Type:
		free_ast(n.params, allocator)
		free_ast(n.results, allocator)
	case ^Pointer_Type:
		free_ast(n.elem, allocator)
	case ^Array_Type:
		free_ast(n.len, allocator)
		free_ast(n.elem, allocator)
		free_ast(n.tag, allocator)
	case ^Dynamic_Array_Type:
		free_ast(n.elem, allocator)
		free_ast(n.tag, allocator)
	case ^Struct_Type:
		free_ast(n.poly_params, allocator)
		free_ast(n.align, allocator)
		free_ast(n.fields, allocator)
		free_ast(n.where_clauses, allocator)
	case ^Union_Type:
		free_ast(n.poly_params, allocator)
		free_ast(n.align, allocator)
		free_ast(n.variants, allocator)
		free_ast(n.where_clauses, allocator)
	case ^Enum_Type:
		free_ast(n.base_type, allocator)
		free_ast(n.fields, allocator)
	case ^Bit_Set_Type:
		free_ast(n.elem, allocator)
		free_ast(n.underlying, allocator)
	case ^Map_Type:
		free_ast(n.key, allocator)
		free_ast(n.value, allocator)
	case ^Multi_Pointer_Type:
		free_ast(n.elem, allocator)
	case ^Matrix_Type:
		free_ast(n.elem, allocator)
	case ^Relative_Type:
		free_ast(n.tag, allocator)
		free_ast(n.type, allocator)
	case ^Bit_Field_Type:
		free_ast(n.backing_type, allocator)
		for field in n.fields do free_ast(field, allocator)
	case ^Bit_Field_Field:
		free_ast(n.name, allocator)
		free_ast(n.type, allocator)
		free_ast(n.bit_size, allocator)
	case ^ast.Or_Else_Expr:
		free_ast(n.x, allocator)
		free_ast(n.y, allocator)
	case ^ast.Or_Return_Expr:
		free_ast(n.expr, allocator)
	case:
		panic(fmt.aprintf("free Unhandled node kind: %v", node.derived))
	}

	mem.free(node, allocator)
}

free_ast_file :: proc(file: ast.File, allocator := context.allocator) {
	for decl in file.decls {
		free_ast(decl, allocator)
	}

	free_ast(file.pkg_decl, allocator)

	for comment in file.comments {
		free_ast(comment, allocator)
	}

	delete(file.comments)
	delete(file.imports)
	delete(file.decls)
}

node_equal :: proc {
	node_equal_node,
	node_equal_array,
	node_equal_dynamic_array,
}

node_equal_array :: proc(a, b: $A/[]^$T) -> bool {
	ret := true

	if len(a) != len(b) {
		return false
	}

	for elem, i in a {
		ret &= node_equal(elem, b[i])
	}

	return ret
}

node_equal_dynamic_array :: proc(a, b: $A/[dynamic]^$T) -> bool {
	ret := true

	if len(a) != len(b) {
		return false
	}

	for elem, i in a {
		ret &= node_equal(elem, b[i])
	}

	return ret
}

node_equal_node :: proc(a, b: ^ast.Node) -> bool {
	using ast

	if a == nil || b == nil {
		return false
	}

	#partial switch m in b.derived {
	case ^Bad_Expr:
		if n, ok := a.derived.(^Bad_Expr); ok {
			return true
		}
	case ^Ident:
		if n, ok := a.derived.(^Ident); ok {
			return true
			//return n.name == m.name;
		}
	case ^Implicit:
		if n, ok := a.derived.(^Implicit); ok {
			return true
		}
	case ^Undef:
		if n, ok := a.derived.(^Undef); ok {
			return true
		}
	case ^Basic_Lit:
		if n, ok := a.derived.(^Basic_Lit); ok {
			return true
		}
	case ^Poly_Type:
		return true
	case ^Ellipsis:
		if n, ok := a.derived.(^Ellipsis); ok {
			return node_equal(n.expr, m.expr)
		}
	case ^Tag_Expr:
		if n, ok := a.derived.(^Tag_Expr); ok {
			return node_equal(n.expr, m.expr)
		}
	case ^Unary_Expr:
		if n, ok := a.derived.(^Unary_Expr); ok {
			return node_equal(n.expr, m.expr)
		}
	case ^Binary_Expr:
		if n, ok := a.derived.(^Binary_Expr); ok {
			ret := node_equal(n.left, m.left)
			ret &= node_equal(n.right, m.right)
			return ret
		}
	case ^Paren_Expr:
		if n, ok := a.derived.(^Paren_Expr); ok {
			return node_equal(n.expr, m.expr)
		}
	case ^Selector_Expr:
		if n, ok := a.derived.(^Selector_Expr); ok {
			ret := node_equal(n.expr, m.expr)
			ret &= node_equal(n.field, m.field)
			return ret
		}
	case ^Slice_Expr:
		if n, ok := a.derived.(^Slice_Expr); ok {
			ret := node_equal(n.expr, m.expr)
			ret &= node_equal(n.low, m.low)
			ret &= node_equal(n.high, m.high)
			return ret
		}
	case ^Distinct_Type:
		if n, ok := a.derived.(^Distinct_Type); ok {
			return node_equal(n.type, m.type)
		}
	case ^Proc_Type:
		if n, ok := a.derived.(^Proc_Type); ok {
			ret := node_equal(n.params, m.params)
			ret &= node_equal(n.results, m.results)
			return ret
		}
	case ^Pointer_Type:
		if n, ok := a.derived.(^Pointer_Type); ok {
			return node_equal(n.elem, m.elem)
		}
	case ^Array_Type:
		if n, ok := a.derived.(^Array_Type); ok {
			ret := node_equal(n.elem, m.elem)
			if n.len != nil && m.len != nil {
				ret &= node_equal(n.len, m.len)
			}
			return ret
		}
	case ^Dynamic_Array_Type:
		if n, ok := a.derived.(^Dynamic_Array_Type); ok {
			return node_equal(n.elem, m.elem)
		}
	case ^ast.Multi_Pointer_Type:
		if n, ok := a.derived.(^Multi_Pointer_Type); ok {
			return node_equal(n.elem, m.elem)
		}
	case ^Struct_Type:
		if n, ok := a.derived.(^Struct_Type); ok {
			ret := node_equal(n.poly_params, m.poly_params)
			ret &= node_equal(n.align, m.align)
			ret &= node_equal(n.fields, m.fields)
			return ret
		}
	case ^Field:
		if n, ok := a.derived.(^Field); ok {
			ret := node_equal(n.names, m.names)
			ret &= node_equal(n.type, m.type)
			ret &= node_equal(n.default_value, m.default_value)
			return ret
		}
	case ^Field_List:
		if n, ok := a.derived.(^Field_List); ok {
			return node_equal(n.list, m.list)
		}
	case ^Field_Value:
		if n, ok := a.derived.(^Field_Value); ok {
			ret := node_equal(n.field, m.field)
			ret &= node_equal(n.value, m.value)
			return ret
		}
	case ^Union_Type:
		if n, ok := a.derived.(^Union_Type); ok {
			ret := node_equal(n.poly_params, m.poly_params)
			ret &= node_equal(n.align, m.align)
			ret &= node_equal(n.variants, m.variants)
			return ret
		}
	case ^Enum_Type:
		if n, ok := a.derived.(^Enum_Type); ok {
			ret := node_equal(n.base_type, m.base_type)
			ret &= node_equal(n.fields, m.fields)
			return ret
		}
	case ^Bit_Set_Type:
		if n, ok := a.derived.(^Bit_Set_Type); ok {
			ret := node_equal(n.elem, m.elem)
			ret &= node_equal(n.underlying, m.underlying)
			return ret
		}
	case ^Map_Type:
		if n, ok := a.derived.(^Map_Type); ok {
			ret := node_equal(n.key, m.key)
			ret &= node_equal(n.value, m.value)
			return ret
		}
	case ^Call_Expr:
		if n, ok := a.derived.(^Call_Expr); ok {
			ret := node_equal(n.expr, m.expr)
			ret &= node_equal(n.args, m.args)
			return ret
		}
	case ^Bit_Field_Type:
		if n, ok := a.derived.(^Bit_Field_Type); ok {
			if len(n.fields) != len(m.fields) do return false
			ret := node_equal(n.backing_type, m.backing_type)
			for i in 0 ..< len(n.fields) {
				ret &= node_equal(n.fields[i], m.fields[i])
			}
			return ret
		}
	case ^Bit_Field_Field:
		if n, ok := a.derived.(^Bit_Field_Field); ok {
			ret := node_equal(n.name, m.name)
			ret &= node_equal(n.type, m.type)
			ret &= node_equal(n.bit_size, m.bit_size)
			return ret
		}
	case ^Typeid_Type:
		return true
	case:
	}

	return false
}

/*
	Returns the string representation of a type. This allows us to print the signature without storing it in the indexer as a string(saving memory).
*/

node_to_string :: proc(node: ^ast.Node, remove_pointers := false) -> string {
	builder := strings.builder_make(context.temp_allocator)

	build_string(node, &builder, remove_pointers)

	return strings.to_string(builder)
}

build_string :: proc {
	build_string_ast_array,
	build_string_dynamic_array,
	build_string_node,
}

build_string_dynamic_array :: proc(array: $A/[]^$T, builder: ^strings.Builder, remove_pointers: bool) {
	for elem, i in array {
		build_string(elem, builder, remove_pointers)
	}
}

build_string_ast_array :: proc(array: $A/[dynamic]^$T, builder: ^strings.Builder, remove_pointers: bool) {
	for elem, i in array {
		build_string(elem, builder, remove_pointers)
	}
}

build_string_node :: proc(node: ^ast.Node, builder: ^strings.Builder, remove_pointers: bool) {
	using ast

	if node == nil {
		return
	}

	#partial switch n in node.derived {
	case ^Bad_Expr:
	case ^Ident:
		if strings.contains(n.name, "/") {
			strings.write_string(builder, path.base(n.name, false, context.temp_allocator))
		} else {
			strings.write_string(builder, n.name)
		}
	case ^Implicit:
		strings.write_string(builder, n.tok.text)
	case ^Undef:
	case ^Basic_Lit:
		strings.write_string(builder, n.tok.text)
	case ^Basic_Directive:
		strings.write_string(builder, "#")
		strings.write_string(builder, n.name)
	case ^Implicit_Selector_Expr:
		strings.write_string(builder, ".")
		build_string(n.field, builder, remove_pointers)
	case ^Ellipsis:
		strings.write_string(builder, "..")
		build_string(n.expr, builder, remove_pointers)
	case ^Proc_Lit:
		build_string(n.type, builder, remove_pointers)
		build_string(n.body, builder, remove_pointers)
	case ^Comp_Lit:
		build_string(n.type, builder, remove_pointers)
		strings.write_string(builder, "{")
		for elem, i in n.elems {
			build_string(elem, builder, remove_pointers)
			if len(n.elems) - 1 != i {
				strings.write_string(builder, ", ")
			}
		}
		strings.write_string(builder, "}")
	case ^Tag_Expr:
		build_string(n.expr, builder, remove_pointers)
	case ^Unary_Expr:
		strings.write_string(builder, n.op.text)
		build_string(n.expr, builder, remove_pointers)
	case ^Binary_Expr:
		build_string(n.left, builder, remove_pointers)
		strings.write_string(builder, " ")
		strings.write_string(builder, n.op.text)
		strings.write_string(builder, " ")
		build_string(n.right, builder, remove_pointers)
	case ^Paren_Expr:
		strings.write_string(builder, "(")
		build_string(n.expr, builder, remove_pointers)
		strings.write_string(builder, ")")
	case ^Call_Expr:
		build_string(n.expr, builder, remove_pointers)
		strings.write_string(builder, "(")
		for arg, i in n.args {
			build_string(arg, builder, remove_pointers)
			if len(n.args) - 1 != i {
				strings.write_string(builder, ", ")
			}
		}
		strings.write_string(builder, ")")
	case ^Selector_Expr:
		build_string(n.expr, builder, remove_pointers)
		strings.write_string(builder, ".")
		build_string(n.field, builder, remove_pointers)
	case ^Index_Expr:
		build_string(n.expr, builder, remove_pointers)
		strings.write_string(builder, "[")
		build_string(n.index, builder, remove_pointers)
		strings.write_string(builder, "]")
	case ^Deref_Expr:
		build_string(n.expr, builder, remove_pointers)
	case ^Slice_Expr:
		build_string(n.expr, builder, remove_pointers)
		build_string(n.low, builder, remove_pointers)
		build_string(n.high, builder, remove_pointers)
	case ^Field_Value:
		build_string(n.field, builder, remove_pointers)
		strings.write_string(builder, ": ")
		build_string(n.value, builder, remove_pointers)
	case ^Type_Cast:
		build_string(n.type, builder, remove_pointers)
		build_string(n.expr, builder, remove_pointers)
	case ^Bad_Stmt:
	case ^Bad_Decl:
	case ^Attribute:
		build_string(n.elems, builder, remove_pointers)
	case ^Field:
		for name, i in n.names {
			build_string(name, builder, remove_pointers)
			if len(n.names) - 1 != i {
				strings.write_string(builder, ", ")
			}
		}

		if len(n.names) > 0 && n.type != nil {
			strings.write_string(builder, ": ")
			build_string(n.type, builder, remove_pointers)

			if n.default_value != nil && n.type != nil {
				strings.write_string(builder, " = ")
			}

		} else if len(n.names) > 0 && n.default_value != nil {
			strings.write_string(builder, " := ")
		} else {
			build_string(n.type, builder, remove_pointers)
		}

		build_string(n.default_value, builder, remove_pointers)
	case ^Field_List:
		for field, i in n.list {
			build_string(field, builder, remove_pointers)
			if len(n.list) - 1 != i {
				strings.write_string(builder, ",")
			}
		}
	case ^Typeid_Type:
		strings.write_string(builder, "typeid")
		build_string(n.specialization, builder, remove_pointers)
	case ^Helper_Type:
		build_string(n.type, builder, remove_pointers)
	case ^Distinct_Type:
		build_string(n.type, builder, remove_pointers)
	case ^Poly_Type:
		strings.write_string(builder, "$")

		build_string(n.type, builder, remove_pointers)

		if n.specialization != nil {
			strings.write_string(builder, "/")
			build_string(n.specialization, builder, remove_pointers)
		}
	case ^Proc_Type:
		strings.write_string(builder, "proc(")
		build_string(n.params, builder, remove_pointers)
		strings.write_string(builder, ")")
		if n.results != nil {
			strings.write_string(builder, " -> ")
			build_string(n.results, builder, remove_pointers)
		}
	case ^Pointer_Type:
		if !remove_pointers {
			strings.write_string(builder, "^")
		}
		build_string(n.elem, builder, remove_pointers)
	case ^Array_Type:
		strings.write_string(builder, "[")
		build_string(n.len, builder, remove_pointers)
		strings.write_string(builder, "]")
		build_string(n.elem, builder, remove_pointers)
	case ^Dynamic_Array_Type:
		strings.write_string(builder, "[dynamic]")
		build_string(n.elem, builder, remove_pointers)
	case ^Struct_Type:
		build_string(n.poly_params, builder, remove_pointers)
		build_string(n.align, builder, remove_pointers)
		build_string(n.fields, builder, remove_pointers)
	case ^Union_Type:
		build_string(n.poly_params, builder, remove_pointers)
		build_string(n.align, builder, remove_pointers)
		build_string(n.variants, builder, remove_pointers)
	case ^Enum_Type:
		build_string(n.base_type, builder, remove_pointers)
		build_string(n.fields, builder, remove_pointers)
	case ^Bit_Set_Type:
		strings.write_string(builder, "bit_set")
		strings.write_string(builder, "[")
		build_string(n.elem, builder, remove_pointers)
		strings.write_string(builder, "]")
		build_string(n.underlying, builder, remove_pointers)
	case ^Map_Type:
		strings.write_string(builder, "map")
		strings.write_string(builder, "[")
		build_string(n.key, builder, remove_pointers)
		strings.write_string(builder, "]")
		build_string(n.value, builder, remove_pointers)
	case ^ast.Multi_Pointer_Type:
		strings.write_string(builder, "[^]")
		build_string(n.elem, builder, remove_pointers)
	case ^ast.Bit_Field_Type:
		strings.write_string(builder, "bit_field")
		build_string(n.backing_type, builder, remove_pointers)
		for field, i in n.fields {
			build_string(field, builder, remove_pointers)
			if len(n.fields) - 1 != i {
				strings.write_string(builder, ",")
			}
		}
	case ^ast.Bit_Field_Field:
		build_string(n.name, builder, remove_pointers)
		strings.write_string(builder, ": ")
		build_string(n.type, builder, remove_pointers)
		strings.write_string(builder, " | ")
		build_string(n.bit_size, builder, remove_pointers)
	}
}

repeat :: proc(value: string, count: int, allocator := context.allocator) -> string {
	if count <= 0 {
		return ""
	}
	return strings.repeat(value, count, allocator)
}

construct_struct_field_docs :: proc(file: ast.File, v: ^ast.Struct_Type) {
	for field, i in v.fields.list {
		// There is currently a bug in the odin parser where it adds line comments for a field to the
		// docs of the following field, we address this problem here.
		// see https://github.com/odin-lang/Odin/issues/5353
		if field.comment == nil {
			// We check if the comment is at the start of the next field
			if i != len(v.fields.list) - 1 {
				next_field := v.fields.list[i + 1]
				if next_field.docs != nil && len(next_field.docs.list) > 0 {
					list := next_field.docs.list
					if list[0].pos.line == field.pos.line {
						field.comment = ast.new(ast.Comment_Group, list[0].pos, parser.end_pos(list[0]))
						field.comment.list = list[:1]
						if len(list) > 1 {
							next_field.docs = ast.new(
								ast.Comment_Group,
								list[1].pos,
								parser.end_pos(list[len(list) - 2]),
							)
							next_field.docs.list = list[1:]
						} else {
							next_field.docs = nil
						}
					}
				}
			} else {
				// We need to check the file to see if it contains a line comment as there is no next field
				field.comment = get_file_comment(file, field.pos.line)
			}
		}
	}
}

construct_bit_field_field_docs :: proc(file: ast.File, v: ^ast.Bit_Field_Type) {
	for field, i in v.fields {
		// There is currently a bug in the odin parser where it adds line comments for a field to the
		// docs of the following field, we address this problem here.
		// see https://github.com/odin-lang/Odin/issues/5353
		if field.comments == nil {
			// We check if the comment is at the start of the next field
			if i != len(v.fields) - 1 {
				next_field := v.fields[i + 1]
				if next_field.docs != nil && len(next_field.docs.list) > 0 {
					list := next_field.docs.list
					if list[0].pos.line == field.pos.line {
						field.comments = ast.new(ast.Comment_Group, list[0].pos, parser.end_pos(list[0]))
						field.comments.list = list[:1]
						if len(list) > 1 {
							next_field.docs = ast.new(
								ast.Comment_Group,
								list[1].pos,
								parser.end_pos(list[len(list) - 2]),
							)
							next_field.docs.list = list[1:]
						} else {
							next_field.docs = nil
						}
					}
				}
			} else {
				// We need to check the file to see if it contains a line comment as there is no next field
				field.comments = get_file_comment(file, field.pos.line)
			}
		}
	}
}

// Retrives the comment group from the specified line of the file
get_file_comment :: proc(file: ast.File, line: int) -> ^ast.Comment_Group {
	// TODO: linear scan might be a bit slow for files with lots of comments?
	for c in file.comments {
		if c.pos.line == line {
			for item, j in c.list {
				comment := ast.new(ast.Comment_Group, item.pos, parser.end_pos(item))
				if j == len(c.list) - 1 {
					comment.list = c.list[j:]
				} else {
					comment.list = c.list[j:j + 1]
				}
				return comment
			}
		}
	}
	return nil
}
