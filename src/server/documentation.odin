package server

import "core:fmt"
import "core:log"
import path "core:path/slashpath"
import "core:strings"


get_signature :: proc(ast_context: ^AstContext, symbol: Symbol) -> string {
	is_variable := symbol.type == .Variable

	pointer_prefix := repeat("^", symbol.pointers, context.temp_allocator)


	#partial switch v in symbol.value {
	case SymbolEnumValue:
		sb := strings.builder_make(ast_context.allocator)
		if is_variable {
			append_variable_full_name(&sb, ast_context, symbol, pointer_prefix)
			strings.write_string(&sb, " :: ")
		}
		strings.write_string(&sb, "enum {\n")
		for i in 0 ..< len(v.names) {
			strings.write_string(&sb, "\t")
			strings.write_string(&sb, v.names[i])
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
		strings.write_string(&sb, "union {\n")
		for i in 0 ..< len(v.types) {
			strings.write_string(&sb, "\t")
			build_string_node(v.types[i], &sb, false)
			strings.write_string(&sb, ",\n")
		}
		strings.write_string(&sb, "}")
		return strings.to_string(sb)
	case SymbolAggregateValue:
		sb := strings.builder_make(context.temp_allocator)
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
	}

	return get_short_signature(ast_context, symbol)
}

get_short_signature :: proc(ast_context: ^AstContext, symbol: Symbol) -> string {
	is_variable := symbol.type == .Variable

	pointer_prefix := repeat("^", symbol.pointers, context.temp_allocator)
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
		sb := strings.builder_make(context.temp_allocator)
		if symbol.type_pkg != "" {
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
		fmt.sbprintf(sb, "%s%s", pointer_prefix, symbol.name)
		return
	}
	fmt.sbprintf(sb, "%s%s.%s", pointer_prefix, pkg_name, symbol.name)
	return
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
