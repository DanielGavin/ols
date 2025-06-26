package server

import "core:fmt"
import "core:odin/ast"
import path "core:path/slashpath"
import "core:strings"


get_signature :: proc(ast_context: ^AstContext, symbol: Symbol) -> string {
	if .Distinct in symbol.flags {
		return symbol.name
	}

	is_variable := symbol.type == .Variable
	is_field := symbol.type == .Field

	pointer_prefix := repeat("^", symbol.pointers, context.temp_allocator)


	#partial switch v in symbol.value {
	case SymbolEnumValue:
		builder := strings.builder_make(ast_context.allocator)
		if is_variable {
			append_variable_full_name(&builder, ast_context, symbol, pointer_prefix)
		}
		strings.write_string(&builder, "enum {\n")
		for i in 0 ..< len(v.names) {
			strings.write_string(&builder, "\t")
			strings.write_string(&builder, v.names[i])
			strings.write_string(&builder, ",\n")
		}
		strings.write_string(&builder, "}")
		return strings.to_string(builder)
	case SymbolStructValue:
		builder := strings.builder_make(ast_context.allocator)
		if is_variable {
			append_variable_full_name(&builder, ast_context, symbol, pointer_prefix)
		} else if is_field {
			pkg_name := get_pkg_name(ast_context, symbol.type_pkg)
			if pkg_name == "" {
				fmt.sbprintf(&builder, "%s%s", pointer_prefix, symbol.type_name)
			} else {
				fmt.sbprintf(&builder, "%s%s.%s", pointer_prefix, pkg_name, symbol.type_name)
			}
			if symbol.comment != "" {
				fmt.sbprintf(&builder, " %s", symbol.comment)
			}
			return strings.to_string(builder)
		} else if symbol.type_name != "" {
			if symbol.type_pkg == "" {
				fmt.sbprintf(&builder, "%s%s :: ", pointer_prefix, symbol.type_name)
			} else {
				pkg_name := get_pkg_name(ast_context, symbol.type_pkg)
				fmt.sbprintf(&builder, "%s%s.%s :: ", pointer_prefix, pkg_name, symbol.type_name)
			}
		}
		if len(v.names) == 0 {
			strings.write_string(&builder, "struct {}")
			return strings.to_string(builder)
		}
		write_struct_hover(ast_context, &builder, v)
		return strings.to_string(builder)
	case SymbolUnionValue:
		builder := strings.builder_make(ast_context.allocator)
		if is_variable {
			append_variable_full_name(&builder, ast_context, symbol, pointer_prefix)
		}
		strings.write_string(&builder, "union {\n")
		for i in 0 ..< len(v.types) {
			strings.write_string(&builder, "\t")
			build_string_node(v.types[i], &builder, false)
			strings.write_string(&builder, ",\n")
		}
		strings.write_string(&builder, "}")
		return strings.to_string(builder)
	case SymbolAggregateValue:
		builder := strings.builder_make(context.temp_allocator)
		strings.write_string(&builder, "proc {\n")
		for symbol in v.symbols {
			if value, ok := symbol.value.(SymbolProcedureValue); ok {
				fmt.sbprintf(&builder, "\t%s :: ", symbol.name)
				write_procedure_symbol_signature(&builder, value)
				strings.write_string(&builder, ",\n")
			}
		}
		strings.write_string(&builder, "}")
		return strings.to_string(builder)
	}

	return get_short_signature(ast_context, symbol)
}

get_short_signature :: proc(ast_context: ^AstContext, symbol: Symbol) -> string {
	if .Distinct in symbol.flags {
		return symbol.name
	}

	is_variable := symbol.type == .Variable
	is_field := symbol.type == .Field

	pointer_prefix := repeat("^", symbol.pointers, context.temp_allocator)


	#partial switch v in symbol.value {
	case SymbolBasicValue:
		return strings.concatenate({pointer_prefix, node_to_string(v.ident)}, ast_context.allocator)
	case SymbolBitSetValue:
		return strings.concatenate(
			a = {pointer_prefix, "bit_set[", node_to_string(v.expr), "]"},
			allocator = ast_context.allocator,
		)
	case SymbolEnumValue:
		builder := strings.builder_make(ast_context.allocator)
		if is_variable {
			append_variable_full_name(&builder, ast_context, symbol, pointer_prefix)
		}
		strings.write_string(&builder, "enum")
		return strings.to_string(builder)
	case SymbolMapValue:
		return strings.concatenate(
			a = {pointer_prefix, "map[", node_to_string(v.key), "]", node_to_string(v.value)},
			allocator = ast_context.allocator,
		)
	case SymbolProcedureValue:
		builder := strings.builder_make(context.temp_allocator)
		write_procedure_symbol_signature(&builder, v)
		return strings.to_string(builder)
	case SymbolAggregateValue:
		return "proc"
	case SymbolStructValue:
		builder := strings.builder_make(ast_context.allocator)
		if is_variable {
			append_variable_full_name(&builder, ast_context, symbol, pointer_prefix)
		}
		strings.write_string(&builder, "struct")
		return strings.to_string(builder)
	case SymbolUnionValue:
		builder := strings.builder_make(ast_context.allocator)
		if is_variable {
			append_variable_full_name(&builder, ast_context, symbol, pointer_prefix)
		}
		strings.write_string(&builder, "union")
		return strings.to_string(builder)
	case SymbolBitFieldValue:
		if is_variable {
			return strings.concatenate({pointer_prefix, symbol.name}, ast_context.allocator)
		} else {
			return "bit_field"
		}
	case SymbolMultiPointerValue:
		return strings.concatenate(
			a = {pointer_prefix, "[^]", node_to_string(v.expr)},
			allocator = ast_context.allocator,
		)
	case SymbolDynamicArrayValue:
		return strings.concatenate(
			a = {pointer_prefix, "[dynamic]", node_to_string(v.expr)},
			allocator = ast_context.allocator,
		)
	case SymbolSliceValue:
		return strings.concatenate(
			a = {pointer_prefix, "[]", node_to_string(v.expr)},
			allocator = ast_context.allocator,
		)
	case SymbolFixedArrayValue:
		return strings.concatenate(
			a = {pointer_prefix, "[", node_to_string(v.len), "]", node_to_string(v.expr)},
			allocator = ast_context.allocator,
		)
	case SymbolMatrixValue:
		return strings.concatenate(
			a = {
				pointer_prefix,
				"matrix",
				"[",
				node_to_string(v.x),
				",",
				node_to_string(v.y),
				"]",
				node_to_string(v.expr),
			},
			allocator = ast_context.allocator,
		)
	case SymbolPackageValue:
		return "package"
	case SymbolUntypedValue:
		switch v.type {
		case .Float:
			return "float"
		case .String:
			return "string"
		case .Bool:
			return "bool"
		case .Integer:
			return "int"
		}
	}

	return ""
}

write_procedure_symbol_signature :: proc(sb: ^strings.Builder, value: SymbolProcedureValue) {
	strings.write_string(sb, "proc")
	strings.write_string(sb, "(")
	for arg, i in value.orig_arg_types {
		strings.write_string(sb, node_to_string(arg))
		if i != len(value.orig_arg_types) - 1 {
			strings.write_string(sb, ", ")
		}
	}
	strings.write_string(sb, ")")

	if len(value.orig_return_types) != 0 {
		strings.write_string(sb, " -> ")

		if len(value.orig_return_types) > 1 {
			strings.write_string(sb, "(")
		}

		for arg, i in value.orig_return_types {
			strings.write_string(sb, node_to_string(arg))
			if i != len(value.orig_return_types) - 1 {
				strings.write_string(sb, ", ")
			}
		}

		if len(value.orig_return_types) > 1 {
			strings.write_string(sb, ")")
		}
	} else if value.diverging {
		strings.write_string(sb, " -> !")
	}
}

write_struct_hover :: proc(ast_context: ^AstContext, sb: ^strings.Builder, v: SymbolStructValue) {
	using_prefix := "using "
	longestNameLen := 0
	for name, i in v.names {
		l := len(name)
		if _, ok := v.usings[i]; ok {
			l += len(using_prefix)
		}
		if l > longestNameLen {
			longestNameLen = len(name)
		}
	}

	using_index := -1

	strings.write_string(sb, "struct {\n")
	for i in 0 ..< len(v.names) {
		if i < len(v.from_usings) {
			if index := v.from_usings[i]; index != using_index {
				fmt.sbprintf(sb, "\n\t// from `using %s: ", v.names[index])
				build_string_node(v.types[index], sb, false)
				strings.write_string(sb, "`\n")
				using_index = index
			}
		}
		if i < len(v.docs) && v.docs[i] != nil {
			for c in v.docs[i].list {
				fmt.sbprintf(sb, "\t%s\n", c.text)
			}
		}

		strings.write_string(sb, "\t")

		name_len := len(v.names[i])
		if _, ok := v.usings[i]; ok {
			strings.write_string(sb, using_prefix)
			name_len += len(using_prefix)
		}
		strings.write_string(sb, v.names[i])
		fmt.sbprintf(sb, ":%*s", longestNameLen - name_len + 1, "")
		build_string_node(v.types[i], sb, false)
		strings.write_string(sb, ",")

		if i < len(v.comments) && v.comments[i] != nil {
			for c in v.comments[i].list {
				fmt.sbprintf(sb, " %s\n", c.text)
			}
		} else {
			strings.write_string(sb, "\n")
		}
	}
	strings.write_string(sb, "}")
}

append_variable_full_name :: proc(
	sb: ^strings.Builder,
	ast_context: ^AstContext,
	symbol: Symbol,
	pointer_prefix: string,
) {
	pkg_name := get_symbol_pkg_name(ast_context, symbol)
	if pkg_name == "" {
		fmt.sbprintf(sb, "%s%s :: ", pointer_prefix, symbol.name)
		return
	}
	fmt.sbprintf(sb, "%s%s.%s :: ", pointer_prefix, pkg_name, symbol.name)
	return
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
