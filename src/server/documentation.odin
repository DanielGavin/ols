package server

import "core:fmt"
import "core:log"
import "core:odin/ast"
import path "core:path/slashpath"
import "core:strings"


get_signature :: proc(ast_context: ^AstContext, symbol: Symbol) -> string {
	is_variable := symbol.type == .Variable

	pointer_prefix := repeat("^", symbol.pointers, ast_context.allocator)

	#partial switch v in symbol.value {
	case SymbolEnumValue:
		sb := strings.builder_make(ast_context.allocator)
		if is_variable {
			append_variable_full_name(&sb, ast_context, symbol, pointer_prefix)
			strings.write_string(&sb, " :: ")
		}
		if len(v.names) == 0 {
			strings.write_string(&sb, "enum {}")
			if symbol.comment != "" {
				fmt.sbprintf(&sb, " %s", symbol.comment)
			}
			return strings.to_string(sb)
		}

		longestNameLen := 0
		for name in v.names {
			if len(name) > longestNameLen {
				longestNameLen = len(name)
			}
		}
		strings.write_string(&sb, "enum ")
		if v.base_type != nil {
			build_string_node(v.base_type, &sb, false)
			strings.write_string(&sb, " ")
		}
		strings.write_string(&sb, "{\n")
		for i in 0 ..< len(v.names) {
			strings.write_string(&sb, "\t")
			strings.write_string(&sb, v.names[i])
			if i < len(v.values) && v.values[i] != nil {
				fmt.sbprintf(&sb, "%*s= ", longestNameLen - len(v.names[i]) + 1, "")
				build_string_node(v.values[i], &sb, false)
			}
			strings.write_string(&sb, ",\n")
		}
		strings.write_string(&sb, "}")
		return strings.to_string(sb)
	case SymbolStructValue:
		sb := strings.builder_make(ast_context.allocator)
		if is_variable {
			append_variable_full_name(&sb, ast_context, symbol, pointer_prefix)
			strings.write_string(&sb, " :: ")
		} else if symbol.type_name != "" {
			if symbol.type_pkg == "" {
				fmt.sbprintf(&sb, "%s%s :: ", pointer_prefix, symbol.type_name)
			} else {
				pkg_name := get_pkg_name(ast_context, symbol.type_pkg)
				fmt.sbprintf(&sb, "%s%s.%s :: ", pointer_prefix, pkg_name, symbol.type_name)
			}
		}
		if len(v.names) == 0 {
			strings.write_string(&sb, "struct {}")
			if symbol.comment != "" {
				fmt.sbprintf(&sb, " %s", symbol.comment)
			}
			return strings.to_string(sb)
		}
		write_struct_hover(ast_context, &sb, v)
		return strings.to_string(sb)
	case SymbolUnionValue:
		sb := strings.builder_make(ast_context.allocator)
		if is_variable {
			append_variable_full_name(&sb, ast_context, symbol, pointer_prefix)
			strings.write_string(&sb, " :: ")
		}
		if len(v.types) == 0 {
			strings.write_string(&sb, "union {}")
			return strings.to_string(sb)
		}
		strings.write_string(&sb, "union {\n")
		for i in 0 ..< len(v.types) {
			strings.write_string(&sb, "\t")
			build_string_node(v.types[i], &sb, false)
			strings.write_string(&sb, ",\n")
		}
		strings.write_string(&sb, "}")
		return strings.to_string(sb)
	case SymbolAggregateValue:
		sb := strings.builder_make(ast_context.allocator)
		strings.write_string(&sb, "proc {\n")
		for symbol in v.symbols {
			if value, ok := symbol.value.(SymbolProcedureValue); ok {
				fmt.sbprintf(&sb, "\t%s :: ", symbol.name)
				write_procedure_symbol_signature(&sb, value)
				strings.write_string(&sb, ",\n")
			}
		}
		strings.write_string(&sb, "}")
		return strings.to_string(sb)
	case SymbolBitFieldValue:
		sb := strings.builder_make(ast_context.allocator)
		if is_variable {
			append_variable_full_name(&sb, ast_context, symbol, pointer_prefix)
			strings.write_string(&sb, " :: ")
		} else if symbol.type_name != "" {
			if symbol.type_pkg == "" {
				fmt.sbprintf(&sb, "%s%s :: ", pointer_prefix, symbol.type_name)
			} else {
				pkg_name := get_pkg_name(ast_context, symbol.type_pkg)
				fmt.sbprintf(&sb, "%s%s.%s :: ", pointer_prefix, pkg_name, symbol.type_name)
			}
		}
		strings.write_string(&sb, "bit_field ")
		build_string_node(v.backing_type, &sb, false)
		if len(v.names) == 0 {
			strings.write_string(&sb, " {}")
			return strings.to_string(sb)
		}
		strings.write_string(&sb, " {\n")
		longest_name_len := 0
		for name in v.names {
			if len(name) > longest_name_len {
				longest_name_len = len(name)
			}
		}
		longest_type_len := 0
		type_names := make([dynamic]string, 0, len(v.types), ast_context.allocator)
		for t in v.types {
			type_name := node_to_string(t)
			append(&type_names, type_name)
			if len(type_name) > longest_type_len {
				longest_type_len = len(type_name)
			}
		}

		for name, i in v.names {
		    append_docs(&sb, v.docs, i)
			fmt.sbprintf(&sb, "\t%s:%*s", v.names[i], longest_name_len - len(name) + 1, "")
			fmt.sbprintf(&sb, "%s%*s| ", type_names[i], longest_type_len - len(type_names[i]) + 1, "")
			build_string_node(v.bit_sizes[i], &sb, false)
			strings.write_string(&sb, ",")
			append_comments(&sb, v.comments, i)
			strings.write_string(&sb, "\n")
		}
		strings.write_string(&sb, "}")
		return strings.to_string(sb)
	}

	return get_short_signature(ast_context, symbol)
}

get_short_signature :: proc(ast_context: ^AstContext, symbol: Symbol) -> string {
	is_variable := symbol.type == .Variable

	pointer_prefix := repeat("^", symbol.pointers, ast_context.allocator)
	#partial switch v in symbol.value {
	case SymbolBasicValue:
		sb := strings.builder_make(ast_context.allocator)
		if symbol.type_name != "" {
			write_symbol_type_information(ast_context, &sb, symbol, pointer_prefix)
		} else if .Distinct in symbol.flags {
			if symbol.type == .Keyword {
				strings.write_string(&sb, "distinct ")
				build_string_node(v.ident, &sb, false)
			} else {
				fmt.sbprintf(&sb, "%s%s", pointer_prefix, symbol.name)
			}
		} else {
			strings.write_string(&sb, pointer_prefix)
			build_string_node(v.ident, &sb, false)
		}
		if symbol.type == .Field && symbol.comment != "" {
			fmt.sbprintf(&sb, " %s", symbol.comment)
		}
		return strings.to_string(sb)
	case SymbolBitSetValue:
		return strings.concatenate(
			a = {pointer_prefix, "bit_set[", node_to_string(v.expr), "]"},
			allocator = ast_context.allocator,
		)
	case SymbolEnumValue:
		sb := strings.builder_make(ast_context.allocator)
		if is_variable {
			append_variable_full_name(&sb, ast_context, symbol, pointer_prefix)
		} else {
			strings.write_string(&sb, "enum")
		}
		return strings.to_string(sb)
	case SymbolMapValue:
		return strings.concatenate(
			a = {pointer_prefix, "map[", node_to_string(v.key), "]", node_to_string(v.value)},
			allocator = ast_context.allocator,
		)
	case SymbolProcedureValue:
		sb := strings.builder_make(ast_context.allocator)
		if symbol.type_pkg != "" && symbol.type_name != "" {
			pkg_name := get_pkg_name(ast_context, symbol.type_pkg)
			fmt.sbprintf(&sb, "%s%s.%s :: ", pointer_prefix, pkg_name, symbol.type_name)
		}
		write_procedure_symbol_signature(&sb, v)
		return strings.to_string(sb)
	case SymbolAggregateValue:
		return "proc"
	case SymbolStructValue:
		sb := strings.builder_make(ast_context.allocator)
		if is_variable {
			append_variable_full_name(&sb, ast_context, symbol, pointer_prefix)
		} else if symbol.type_name != "" {
			write_symbol_type_information(ast_context, &sb, symbol, pointer_prefix)
		} else {
			strings.write_string(&sb, "struct")
		}
		if symbol.comment != "" {
			fmt.sbprintf(&sb, " %s", symbol.comment)
		}
		return strings.to_string(sb)
	case SymbolUnionValue:
		sb := strings.builder_make(ast_context.allocator)
		if is_variable {
			append_variable_full_name(&sb, ast_context, symbol, pointer_prefix)
		} else {
			strings.write_string(&sb, "union")
		}
		return strings.to_string(sb)
	case SymbolBitFieldValue:
		sb := strings.builder_make(ast_context.allocator)
		if is_variable {
			append_variable_full_name(&sb, ast_context, symbol, pointer_prefix)
		} else if symbol.type_name != "" {
			write_symbol_type_information(ast_context, &sb, symbol, pointer_prefix)
		} else {
			strings.write_string(&sb, "bit_field ")
			build_string_node(v.backing_type, &sb, false)
		}
		if symbol.comment != "" {
			fmt.sbprintf(&sb, " %s", symbol.comment)
		}
		return strings.to_string(sb)
		
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

get_enum_field_signature :: proc(value: SymbolEnumValue, index: int, allocator := context.temp_allocator) -> string {
	sb := strings.builder_make(allocator)
	fmt.sbprintf(&sb, ".%s", value.names[index])
	if index < len(value.values) && value.values[index] != nil {
		strings.write_string(&sb, " = ")
		build_string_node(value.values[index], &sb, false)
	}
	return strings.to_string(sb)
}

get_bit_field_field_signature :: proc(value: SymbolBitFieldValue, index: int, allocator := context.temp_allocator) -> string {
	sb := strings.builder_make(allocator)
	build_string_node(value.types[index], &sb, false)
	strings.write_string(&sb, " | ")
	build_string_node(value.bit_sizes[index], &sb, false)
	append_comments(&sb, value.comments, index)
	return strings.to_string(sb)
}

write_symbol_type_information :: proc(ast_context: ^AstContext, sb: ^strings.Builder, symbol: Symbol, pointer_prefix: string) {
	append_type_pkg := false
	pkg_name := get_pkg_name(ast_context, symbol.type_pkg)
	if pkg_name != "" {
		if _, ok := keyword_map[symbol.type_name]; !ok {
			append_type_pkg = true
		}
	}
	if append_type_pkg {
		fmt.sbprintf(sb, "%s%s.%s", pointer_prefix, pkg_name, symbol.type_name)
	} else {
		fmt.sbprintf(sb, "%s%s", pointer_prefix, symbol.type_name)
	}
}

write_procedure_symbol_signature :: proc(sb: ^strings.Builder, value: SymbolProcedureValue) {
	strings.write_string(sb, "proc")
	strings.write_string(sb, "(")
	for arg, i in value.orig_arg_types {
		build_string_node(arg, sb, false)
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
			build_string_node(arg, sb, false)
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
			longestNameLen = l
		}
	}

	longest_type_len := 0
	type_names := make([dynamic]string, 0, len(v.types), ast_context.allocator)
	for t in v.types {
		type_name := node_to_string(t)
		append(&type_names, type_name)
		if len(type_name) > longest_type_len {
			longest_type_len = len(type_name)
		}
	}

	using_index := -1

	strings.write_string(sb, "struct")
	poly_name_index := 0
	if v.poly != nil {
		strings.write_string(sb, "(")
		for field, i in v.poly.list {
			write_type := true
			for name, j in field.names {
				if poly_name_index < len(v.poly_names) {
					poly_name := v.poly_names[poly_name_index]
					if !strings.starts_with(poly_name, "$") {
						write_type = false
					}
					strings.write_string(sb, poly_name)
				} else {
					build_string_node(name, sb, false)
				}
				if j != len(field.names) - 1 {
					strings.write_string(sb, ", ")
				}
				poly_name_index += 1
			}
			if write_type {
				strings.write_string(sb, ": ")
				build_string_node(field.type, sb, false)
			}
			if i != len(v.poly.list) - 1 {
				strings.write_string(sb, ", ")
			}
		}
		strings.write_string(sb, ")")
	}
	strings.write_string(sb, " {\n")

	for i in 0 ..< len(v.names) {
		if i < len(v.from_usings) {
			if index := v.from_usings[i]; index != using_index {
				fmt.sbprintf(sb, "\n\t// from `using %s: ", v.names[index])
				build_string_node(v.types[index], sb, false)
				if backing_type, ok := v.backing_types[index]; ok {
					strings.write_string(sb, " (bit_field ")
					build_string_node(backing_type, sb, false)
					strings.write_string(sb, ")")
				}
				strings.write_string(sb, "`\n")
				using_index = index
			}
		}
		append_docs(sb, v.docs, i)
		strings.write_string(sb, "\t")

		name_len := len(v.names[i])
		if _, ok := v.usings[i]; ok {
			strings.write_string(sb, using_prefix)
			name_len += len(using_prefix)
		}
		fmt.sbprintf(sb, "%s:%*s%s", v.names[i], longestNameLen - name_len + 1, "", type_names[i])
		if bit_size, ok := v.bit_sizes[i]; ok {
			fmt.sbprintf(sb, "%*s| ", longest_type_len - len(type_names[i]) + 1, "")
			build_string_node(bit_size, sb, false)
		}
		strings.write_string(sb, ",")
		append_comments(sb, v.comments, i)
		strings.write_string(sb, "\n")
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
		fmt.sbprintf(sb, "%s%s", pointer_prefix, symbol.name)
		return
	}
	fmt.sbprintf(sb, "%s%s.%s", pointer_prefix, pkg_name, symbol.name)
	return
}

append_docs :: proc(sb: ^strings.Builder, docs: []^ast.Comment_Group, index: int) {
	if index < len(docs) && docs[index] != nil {
		for c in docs[index].list {
			fmt.sbprintf(sb, "\t%s\n", c.text)
		}
	}
}

append_comments :: proc(sb: ^strings.Builder, comments: []^ast.Comment_Group, index: int) {
	if index < len(comments) && comments[index] != nil {
		for c in comments[index].list {
			fmt.sbprintf(sb, " %s", c.text)
		}
	}
}

concatenate_symbol_information :: proc {
	concatenate_raw_symbol_information,
	concatenate_raw_string_information,
}

concatenate_raw_symbol_information :: proc(ast_context: ^AstContext, symbol: Symbol) -> string {
	return concatenate_raw_string_information(
		ast_context,
		symbol.pkg,
		symbol.name,
		symbol.signature,
		symbol.type,
		symbol.comment,
	)
}

concatenate_raw_string_information :: proc(
	ast_context: ^AstContext,
	pkg: string,
	name: string,
	signature: string,
	type: SymbolType,
	comment: string,
) -> string {
	pkg := path.base(pkg, false, context.temp_allocator)

	if type == .Package {
		return fmt.tprintf("%v: package", name)
	//} else if type == .Keyword {
	//	return name
	} else {
		sb := strings.builder_make()
		if type == .Function && comment != "" {
			fmt.sbprintf(&sb, "%s\n", comment)
		}
		fmt.sbprintf(&sb, "%v.%v", pkg, name)
		if signature != "" {
			fmt.sbprintf(&sb, ": %v", signature)
		}
		return strings.to_string(sb)
	}
}
