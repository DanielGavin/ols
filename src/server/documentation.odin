#+feature dynamic-literals
package server

import "core:fmt"
import "core:odin/ast"
import path "core:path/slashpath"
import "core:strings"

DOC_SECTION_DELIMITER :: "\n---\n"                                   // The string separating each section of documentation
DOC_FMT_ODIN          :: "```odin\n%v\n```"                          // The format for wrapping odin code in a markdown codeblock
DOC_FMT_MARKDOWN      :: DOC_FMT_ODIN + DOC_SECTION_DELIMITER + "%v" // The format for presenting documentation on hover

// Adds signature and docs information to the provided symbol
// This should only be used for a symbol created with the temp allocator
build_documentation :: proc(ast_context: ^AstContext, symbol: ^Symbol, short_signature := true) {
	if short_signature {
		symbol.signature = get_short_signature(ast_context, symbol^)
	} else {
		symbol.signature = get_signature(ast_context, symbol^)
	}

	if symbol.doc == "" && symbol.comment == "" {
		return
	}
}

construct_symbol_docs :: proc(symbol: Symbol, allocator := context.temp_allocator) -> string {
	sb := strings.builder_make(allocator = allocator)
	if symbol.doc != "" {
		strings.write_string(&sb, symbol.doc)
	}

	if symbol.comment != "" {
		if symbol.doc != "" {
			strings.write_string(&sb, DOC_SECTION_DELIMITER)
		}
		strings.write_string(&sb, symbol.comment)
	}

	return strings.to_string(sb)
}

// Returns the fully detailed signature for the symbol, including things like attributes and fields
get_signature :: proc(ast_context: ^AstContext, symbol: Symbol, depth := 0) -> string {
	sb := strings.builder_make(ast_context.allocator)
	write_signature(&sb, ast_context, symbol, depth)
	return strings.to_string(sb)
}

write_signature :: proc(sb: ^strings.Builder, ast_context: ^AstContext, symbol: Symbol, depth := 0) {
	pointer_prefix := repeat("^", symbol.pointers, ast_context.allocator)

	#partial switch v in symbol.value {
	case SymbolEnumValue:
		if .Distinct in symbol.flags {
			strings.write_string(sb, "distinct ")
		}
		if len(v.names) == 0 {
			write_indent(sb, depth)
			strings.write_string(sb, "enum{}")
			if symbol.comment != "" {
				fmt.sbprintf(sb, " %s", symbol.comment)
			}
			return
		}

		longestNameLen := 0
		for name in v.names {
			if len(name) > longestNameLen {
				longestNameLen = len(name)
			}
		}
		strings.write_string(sb, "enum ")
		if v.base_type != nil {
			build_string_node(v.base_type, sb, false)
			strings.write_string(sb, " ")
		}
		strings.write_string(sb, "{\n")
		for i in 0 ..< len(v.names) {
			write_docs(sb, v.docs, i, depth + 1)
			write_indent(sb, depth + 1)
			strings.write_string(sb, v.names[i])
			if i < len(v.values) && v.values[i] != nil {
				fmt.sbprintf(sb, "%*s= ", longestNameLen - len(v.names[i]) + 1, "")
				build_string_node(v.values[i], sb, false)
			}
			strings.write_string(sb, ",")
			write_comments(sb, v.comments, i)
			strings.write_string(sb, "\n")
		}
		write_indent(sb, depth)
		strings.write_string(sb, "}")
		return
	case SymbolStructValue:
		if .Distinct in symbol.flags {
			strings.write_string(sb, "distinct ")
		}
		write_struct_hover(sb, ast_context, v, depth)
		return
	case SymbolUnionValue:
		if .Distinct in symbol.flags {
			strings.write_string(sb, "distinct ")
		}
		strings.write_string(sb, "union")
		write_poly_list(sb, v.poly, v.poly_names)
		if v.kind != .Normal {
			write_union_kind(sb, v.kind)
		}
		if v.align != nil {
			strings.write_string(sb, " #align")
			build_string_node(v.align, sb, false)
		}
		write_where_clauses(sb, v.where_clauses)
		if len(v.types) == 0 {
			strings.write_string(sb, "{}")
			return
		}
		strings.write_string(sb, " {\n")
		for i in 0 ..< len(v.types) {
			write_docs(sb, v.docs, i, depth + 1)
			write_indent(sb, depth + 1)
			build_string_node(v.types[i], sb, false)
			strings.write_string(sb, ",")
			write_comments(sb, v.comments, i)
			strings.write_string(sb, "\n")
		}
		write_indent(sb, depth)
		strings.write_string(sb, "}")
		return
	case SymbolAggregateValue:
		strings.write_string(sb, "proc {\n")
		for symbol in v.symbols {
			if value, ok := symbol.value.(SymbolProcedureValue); ok {
				write_indent(sb, depth + 1)
				fmt.sbprintf(sb, "%s :: ", symbol.name)
				write_procedure_symbol_signature(sb, value, detailed_signature = false)
				strings.write_string(sb, ",\n")
			}
		}
		write_indent(sb, depth)
		strings.write_string(sb, "}")
		return
	case SymbolProcedureValue:
		if symbol.type == .Type_Function && depth == 0 {
			strings.write_string(sb, "#type ")
		}
		write_procedure_symbol_signature(sb, v, detailed_signature = true)
		return
	case SymbolBitFieldValue:
		if .Distinct in symbol.flags {
			strings.write_string(sb, "distinct ")
		}
		strings.write_string(sb, "bit_field ")
		build_string_node(v.backing_type, sb, false)
		if len(v.names) == 0 {
			strings.write_string(sb, " {}")
			return
		}
		strings.write_string(sb, " {\n")
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
			write_docs(sb, v.docs, i, depth + 1)
			write_indent(sb, depth + 1)
			fmt.sbprintf(sb, "%s:%*s", v.names[i], longest_name_len - len(name) + 1, "")
			fmt.sbprintf(sb, "%s%*s| ", type_names[i], longest_type_len - len(type_names[i]) + 1, "")
			build_string_node(v.bit_sizes[i], sb, false)
			strings.write_string(sb, ",")
			write_comments(sb, v.comments, i)
			strings.write_string(sb, "\n")
		}
		write_indent(sb, depth)
		strings.write_string(sb, "}")
		return
	}

	write_short_signature(sb, ast_context, symbol)
}

get_short_signature :: proc(ast_context: ^AstContext, symbol: Symbol) -> string {
	sb := strings.builder_make(ast_context.allocator)
	write_short_signature(&sb, ast_context, symbol)
	return strings.to_string(sb)
}

write_short_signature :: proc(sb: ^strings.Builder, ast_context: ^AstContext, symbol: Symbol) {
	pointer_prefix := repeat("^", symbol.pointers, ast_context.allocator)
	if .Distinct in symbol.flags {
		strings.write_string(sb, "distinct ")
	}
	#partial switch v in symbol.value {
	case SymbolBasicValue:
		strings.write_string(sb, pointer_prefix)
		build_string_node(v.ident, sb, false)
		return
	case SymbolPolyTypeValue:
		fmt.sbprintf(sb, "%s$", pointer_prefix)
		build_string_node(v.ident, sb, false)
		return
	case SymbolBitSetValue:
		fmt.sbprintf(sb, "%sbit_set[", pointer_prefix)
		build_string_node(v.expr, sb, false)
		strings.write_string(sb, "]")
		return
	case SymbolEnumValue:
		// TODO: we need a better way to do this for enum fields
		if symbol.type == .Field && symbol.type_name == "" {
			strings.write_string(sb, symbol.signature)
			return
		}
		strings.write_string(sb, pointer_prefix)
		strings.write_string(sb, "enum")
		if len(v.names) > 0 {
			strings.write_string(sb, " {..}")
		} else {
			strings.write_string(sb, "{}")
		}
		return
	case SymbolMapValue:
		fmt.sbprintf(sb, "%smap[", pointer_prefix)
		build_string_node(v.key, sb, false)
		strings.write_string(sb, "]")
		write_node(sb, ast_context, v.value, "", short_signature = true)
		return
	case SymbolProcedureValue:
		if symbol.type == .Type_Function {
			strings.write_string(sb, "#type ")
		}
		write_procedure_symbol_signature(sb, v, detailed_signature = true)
		return
	case SymbolAggregateValue, SymbolProcedureGroupValue:
		strings.write_string(sb, "proc (..)")
		return
	case SymbolStructValue:
		strings.write_string(sb, pointer_prefix)
		strings.write_string(sb, "struct")
		write_poly_list(sb, v.poly, v.poly_names)
		if len(v.types) > 0 {
			strings.write_string(sb, " {..}")
		} else {
			strings.write_string(sb, "{}")
		}
		return
	case SymbolUnionValue:
		strings.write_string(sb, pointer_prefix)
		strings.write_string(sb, "union")
		write_poly_list(sb, v.poly, v.poly_names)
		if len(v.types) > 0 {
			strings.write_string(sb, " {..}")
		} else {
			strings.write_string(sb, "{}")
		}
		return
	case SymbolBitFieldValue:
		fmt.sbprintf(sb, "%sbit_field ", pointer_prefix)
		build_string_node(v.backing_type, sb, false)
		if len(v.types) > 0 {
			strings.write_string(sb, " {..}")
		} else {
			strings.write_string(sb, " {}")
		}
		return
	case SymbolMultiPointerValue:
		fmt.sbprintf(sb, "%s[^]", pointer_prefix)
		write_node(sb, ast_context, v.expr, "", short_signature = true)
		return
	case SymbolDynamicArrayValue:
		if .SoaPointer in symbol.flags {
			strings.write_string(sb, "#soa")
		}
		strings.write_string(sb, pointer_prefix)
		if .Soa in symbol.flags {
			strings.write_string(sb, "#soa")
		}
		strings.write_string(sb, "[dynamic]")
		write_node(sb, ast_context, v.expr, "", short_signature = true)
		return
	case SymbolSliceValue:
		if .SoaPointer in symbol.flags {
			strings.write_string(sb, "#soa")
		}
		strings.write_string(sb, pointer_prefix)
		if .Soa in symbol.flags {
			strings.write_string(sb, "#soa")
		}
		strings.write_string(sb, "[]")
		write_node(sb, ast_context, v.expr, "", short_signature = true)
		return
	case SymbolFixedArrayValue:
		if .SoaPointer in symbol.flags {
			strings.write_string(sb, "#soa")
		}
		strings.write_string(sb, pointer_prefix)
		if .Simd in symbol.flags {
			strings.write_string(sb, "#simd")
		}
		if .Soa in symbol.flags {
			strings.write_string(sb, "#soa")
		}
		strings.write_string(sb, "[")
		build_string_node(v.len, sb, false)
		strings.write_string(sb, "]")
		write_node(sb, ast_context, v.expr, "", short_signature = true)
		return
	case SymbolMatrixValue:
		fmt.sbprintf(sb, "%smatrix[", pointer_prefix)
		build_string_node(v.x, sb, false)
		strings.write_string(sb, ",")
		build_string_node(v.y, sb, false)
		strings.write_string(sb, "]")
		build_string_node(v.expr, sb, false)
		return
	case SymbolPackageValue:
		strings.write_string(sb, "package")
		return
	case SymbolUntypedValue:
		if .Mutable in symbol.flags || symbol.type == .Field {
			switch v.type {
			case .Float:
				strings.write_string(sb, "f64")
			case .String:
				strings.write_string(sb, "string")
			case .Bool:
				strings.write_string(sb, "bool")
			case .Integer:
				strings.write_string(sb, "int")
			case .Complex:
				strings.write_string(sb, "complex128")
			case .Quaternion:
				strings.write_string(sb, "quaternion256")
			}
			return
		}
		strings.write_string(sb, v.tok.text)
		return
	case SymbolGenericValue:
		build_string_node(v.expr, sb, false)
		return
	}

	return
}

write_indent :: proc(sb: ^strings.Builder, level: int) {
	for _ in 0 ..< level {
		strings.write_string(sb, "\t")
	}
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

get_bit_field_field_signature :: proc(
	value: SymbolBitFieldValue,
	index: int,
	allocator := context.temp_allocator,
) -> string {
	sb := strings.builder_make(allocator)
	build_string_node(value.types[index], &sb, false)
	strings.write_string(&sb, " | ")
	build_string_node(value.bit_sizes[index], &sb, false)
	return strings.to_string(sb)
}


write_proc_param_list_and_return :: proc(sb: ^strings.Builder, value: SymbolProcedureValue) {
	strings.write_string(sb, "(")
	for arg, i in value.orig_arg_types {
		if .Any_Int in arg.flags {
			strings.write_string(sb, "#any_int ")
		}
		if .By_Ptr in arg.flags {
			strings.write_string(sb, "#by_ptr ")
		}
		if .C_Vararg in arg.flags {
			strings.write_string(sb, "#c_vararg ")
		}
		if .No_Alias in arg.flags {
			strings.write_string(sb, "#no_alias ")
		}
		build_string_node(arg, sb, false)
		if i != len(value.orig_arg_types) - 1 {
			strings.write_string(sb, ", ")
		}
	}
	strings.write_string(sb, ")")

	if len(value.orig_return_types) != 0 {
		strings.write_string(sb, " -> ")

		add_parens := false
		if len(value.orig_return_types) > 1 {
			add_parens = true
		} else if field, ok := value.orig_return_types[0].derived.(^ast.Field); ok && len(field.names) > 0 {
			add_parens = true
		}

		if add_parens {
			strings.write_string(sb, "(")
		}

		for arg, i in value.orig_return_types {
			build_string_node(arg, sb, false)
			if i != len(value.orig_return_types) - 1 {
				strings.write_string(sb, ", ")
			}
		}

		if add_parens {
			strings.write_string(sb, ")")
		}
	} else if value.diverging {
		strings.write_string(sb, " -> !")
	}

}

write_procedure_symbol_signature :: proc(sb: ^strings.Builder, value: SymbolProcedureValue, detailed_signature: bool) {
	if detailed_signature {
		if value.inlining == .Inline {
			strings.write_string(sb, "#force_inline ")
		} else if value.inlining == .No_Inline {
			strings.write_string(sb, "#force_no_inline ")
		}
	}
	strings.write_string(sb, "proc")
	if s, ok := value.calling_convention.(string); ok && detailed_signature {
		fmt.sbprintf(sb, " %s ", s)
	} else if len(value.attributes) > 0 {
		for attr in value.attributes {
			for elem in attr.elems {
				if ident, value, ok := unwrap_attr_elem(elem); ok {
					if ident.name == "default_calling_convention" {
						strings.write_string(sb, " ")
						build_string_node(value, sb, false)
						strings.write_string(sb, " ")
					}
				}
			}
		}
	}
	write_proc_param_list_and_return(sb, value)
	write_where_clauses(sb, value.where_clauses)
	if detailed_signature {
		for tag in value.tags {
			s := ""
			switch tag {
			case .Optional_Ok:
				s = "#optional_ok"
			case .Optional_Allocator_Error:
				s = "#optional_allocator_error"
			case .Bounds_Check:
				s = "#bounds_check"
			case .No_Bounds_Check:
				s = "#no_bounds_check"
			}

			fmt.sbprintf(sb, " %s", s)
		}
	}
}

write_where_clauses :: proc(sb: ^strings.Builder, where_clauses: []^ast.Expr) {
	if len(where_clauses) > 0 {
		strings.write_string(sb, " where ")
		for clause, i in where_clauses {
			build_string_node(clause, sb, false)
			if i != len(where_clauses) - 1 {
				strings.write_string(sb, ", ")
			}
		}
	}
}

write_struct_hover :: proc(sb: ^strings.Builder, ast_context: ^AstContext, v: SymbolStructValue, depth: int) {
	strings.write_string(sb, "struct")
	write_poly_list(sb, v.poly, v.poly_names)

	wrote_tag := false
	if v.max_field_align != nil {
		strings.write_string(sb, " #max_field_align")
		build_string_node(v.max_field_align, sb, false)
		wrote_tag = true
	}

	if v.min_field_align != nil {
		strings.write_string(sb, " #min_field_align")
		build_string_node(v.min_field_align, sb, false)
		wrote_tag = true
	}

	if v.align != nil {
		strings.write_string(sb, " #align")
		build_string_node(v.align, sb, false)
		wrote_tag = true
	}

	for tag in v.tags {
		switch tag {
		case .Is_Raw_Union:
			wrote_tag = true
			strings.write_string(sb, " #raw_union")
		case .Is_Packed:
			wrote_tag = true
			strings.write_string(sb, " #packed")
		case .Is_No_Copy:
			wrote_tag = true
			strings.write_string(sb, " #no_copy")
		case .Is_All_Or_None:
			wrote_tag = true
			strings.write_string(sb, " #all_or_none")
		}
	}

	if len(v.where_clauses) > 0 {
		write_where_clauses(sb, v.where_clauses)
		wrote_tag = true
	}

	if len(v.names) == 0 {
		if wrote_tag {
			strings.write_string(sb, " ")
		}
		strings.write_string(sb, "{}")
		return
	}

	using_prefix := "using "
	longestNameLen := 0
	for name, i in v.names {
		l := len(name)
		if symbol_struct_value_has_using(v, i) {
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
	strings.write_string(sb, " {\n")

	for i in 0 ..< len(v.names) {
		if i < len(v.from_usings) {
			if index := v.from_usings[i]; index != using_index && index != -1 {
				strings.write_string(sb, "\n")
				write_indent(sb, depth + 1)
				fmt.sbprintf(sb, "// from `using %s: ", v.names[index])
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
		write_docs(sb, v.docs, i, depth + 1)
		write_indent(sb, depth + 1)

		name_len := len(v.names[i])
		if symbol_struct_value_has_using(v, i) {
			strings.write_string(sb, using_prefix)
			name_len += len(using_prefix)
		}
		fmt.sbprintf(sb, "%s:%*s", v.names[i], longestNameLen - name_len + 1, "")
		write_node(sb, ast_context, v.types[i], v.names[i], depth + 1)
		if bit_size, ok := v.bit_sizes[i]; ok {
			fmt.sbprintf(sb, "%*s| ", longest_type_len - len(type_names[i]) + 1, "")
			build_string_node(bit_size, sb, false)
		}
		strings.write_string(sb, ",")
		write_comments(sb, v.comments, i)
		strings.write_string(sb, "\n")
	}
	write_indent(sb, depth)
	strings.write_string(sb, "}")
}

write_poly_list :: proc(sb: ^strings.Builder, poly: ^ast.Field_List, poly_names: []string) {
	if poly != nil {
		poly_name_index := 0
		strings.write_string(sb, "(")
		for field, i in poly.list {
			write_type := true
			for name, j in field.names {
				if poly_name_index < len(poly_names) {
					poly_name := poly_names[poly_name_index]
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
			if i != len(poly.list) - 1 {
				strings.write_string(sb, ", ")
			}
		}
		strings.write_string(sb, ")")
	}
}

write_union_kind :: proc(sb: ^strings.Builder, kind: ast.Union_Type_Kind) {
	#partial switch kind {
	case .maybe:
		strings.write_string(sb, " #maybe")
	case .no_nil:
		strings.write_string(sb, " #no_nil")
	case .shared_nil:
		strings.write_string(sb, " #shared_nil")
	}
}

write_node :: proc(
	sb: ^strings.Builder,
	ast_context: ^AstContext,
	node: ^ast.Node,
	name: string,
	depth := 0,
	short_signature := false,
) {
	if node == nil {
		return
	}

	symbol: Symbol
	ok: bool
	#partial switch n in node.derived {
	case ^ast.Struct_Type:
		symbol = make_symbol_struct_from_ast(ast_context, n, name, {}, true)
		ok = true
	case ^ast.Union_Type:
		symbol = make_symbol_union_from_ast(ast_context, n^, name, true)
		ok = true
	case ^ast.Enum_Type:
		symbol = make_symbol_enum_from_ast(ast_context, n^, name, true)
		ok = true
	case ^ast.Bit_Field_Type:
		symbol = make_symbol_bit_field_from_ast(ast_context, n, name, true)
		ok = true
	case ^ast.Proc_Type:
		symbol = make_symbol_procedure_from_ast(ast_context, nil, n^, name, {}, true, .None, nil)
		ok = true
	case ^ast.Comp_Lit:
		same_line := true
		start_line := -1
		for elem in n.elems {
			if start_line == -1 {
				start_line = elem.pos.line
			} else if start_line != elem.pos.line {
				same_line = false
				break
			}
		}
		if same_line {
			build_string(n, sb, false)
		} else {
			build_string(n.type, sb, false)
			if len(n.elems) == 0 {
				strings.write_string(sb, "{}")
				return
			}
			if n.type != nil {
				strings.write_string(sb, " {\n")
			} else {
				strings.write_string(sb, "{\n")
			}

			for elem, i in n.elems {
				write_indent(sb, depth)
				if field, ok := elem.derived.(^ast.Field_Value); ok {
					build_string(field.field, sb, false)
					strings.write_string(sb, " = ")
					write_node(sb, ast_context, field.value, "", depth+1, false)
				} else {
					build_string(elem, sb, false)
				}
				strings.write_string(sb, ",\n")
			}
			write_indent(sb, depth-1)
			strings.write_string(sb, "}")
		}
		return
	}
	if ok {
		if short_signature {
			write_short_signature(sb, ast_context, symbol)
		} else {
			write_signature(sb, ast_context, symbol, depth)
		}
		return
	}

	build_string_node(node, sb, false)
}


write_docs :: proc(sb: ^strings.Builder, docs: []^ast.Comment_Group, index: int, depth := 0) {
	if index < len(docs) && docs[index] != nil {
		for c in docs[index].list {
			fmt.sbprintf(sb, "%.*s%s\n", depth, "\t", c.text)
		}
	}
}

write_comments :: proc(sb: ^strings.Builder, comments: []^ast.Comment_Group, index: int) {
	if index < len(comments) && comments[index] != nil {
		for c in comments[index].list {
			fmt.sbprintf(sb, " %s", c.text)
		}
	}
}

construct_symbol_information :: proc(ast_context: ^AstContext, symbol: Symbol) -> string {
	if symbol.name in keywords_docs {
		return symbol.name
	}
	sb := strings.builder_make(ast_context.allocator)
	write_symbol_attributes(&sb, symbol)
	write_symbol_name(&sb, symbol)

	if symbol.type == .Package {
		return strings.to_string(sb)
	}

	if symbol.type != .Field && .Mutable not_in symbol.flags {
		if symbol.value_expr != nil {
			if symbol.type_expr != nil {
				strings.write_string(&sb, " : ")
				build_string_node(symbol.type_expr, &sb, false)
				strings.write_string(&sb, " : ")
				write_node(&sb, ast_context, symbol.value_expr, "", 1, false)
				return strings.to_string(sb)
			} else if .Variable in symbol.flags {
				strings.write_string(&sb, " :: ")
				write_node(&sb, ast_context, symbol.value_expr, "", 1, false)
				return strings.to_string(sb)
			}
		}
		strings.write_string(&sb, " :: ")
	} else {
		strings.write_string(&sb, ": ")
	}


	if write_symbol_type_information(&sb, ast_context, symbol) {
		return strings.to_string(sb)
	}
	strings.write_string(&sb, symbol.signature)

	return strings.to_string(sb)
}

write_symbol_attributes :: proc(sb: ^strings.Builder, symbol: Symbol) {
	// Currently only attributes for procedures are supported
	if v, ok := symbol.value.(SymbolProcedureValue); ok {
		pkg := path.base(symbol.pkg, false, context.temp_allocator)
		for attribute in v.attributes {
			if len(attribute.elems) == 0 {
				strings.write_string(sb, "@()\n")
				continue
			}
			if len(attribute.elems) == 1 {
				if ident, _, ok := unwrap_attr_elem(attribute.elems[0]); ok {
					if ident.name == "default_calling_convention" {
						continue
					}
				}
			}
			strings.write_string(sb, "@(")
			for elem, i in attribute.elems {
				if ident, value, ok := unwrap_attr_elem(elem); ok {
					if ident.name == "default_calling_convention" {
						continue
					}

					if value != nil {
						build_string_node(ident, sb, false)
						strings.write_string(sb, "=")
						build_string_node(value, sb, false)
					}
				}
				if directive, ok := elem.derived.(^ast.Field_Value); ok {
				} else {
					build_string_node(elem, sb, false)
				}
				if i != len(attribute.elems) - 1 {
					strings.write_string(sb, ", ")
				}

			}
			strings.write_string(sb, ")\n")
		}
	}
}

write_symbol_name :: proc(sb: ^strings.Builder, symbol: Symbol) {
	pkg := path.base(symbol.pkg, false, context.temp_allocator)

	if symbol.type == .Package {
		fmt.sbprintf(sb, "%v: package", symbol.name)
		return
	}
	if symbol.parent_name != "" {
		fmt.sbprintf(sb, "%v.", symbol.parent_name)
	} else if pkg != "" && pkg != "$builtin" {
		fmt.sbprintf(sb, "%v.", pkg)
	}
	strings.write_string(sb, symbol.name)
}

write_symbol_type_information :: proc(sb: ^strings.Builder, ast_context: ^AstContext, symbol: Symbol) -> bool {
	if symbol.type_name == "" {
		return false
	}

	if symbol.type != .Variable && symbol.type != .Field {
		return false
	}

	if .Anonymous in symbol.flags {
		return false
	}

	#partial switch v in symbol.value {
	case SymbolUntypedValue,
	     SymbolBitSetValue,
	     SymbolMapValue,
	     SymbolSliceValue,
	     SymbolDynamicArrayValue,
	     SymbolFixedArrayValue,
	     SymbolMatrixValue,
	     SymbolMultiPointerValue:
		return false
	}

	pointer_prefix := repeat("^", symbol.pointers, ast_context.allocator)

	append_type_pkg := false
	pkg_name := get_pkg_name(ast_context, symbol.type_pkg)
	if pkg_name != "" && pkg_name != "$builtin" {
		if _, ok := keywords_docs[symbol.type_name]; !ok {
			append_type_pkg = true
		}
	}
	if append_type_pkg {
		fmt.sbprintf(sb, "%s%s.%s", pointer_prefix, pkg_name, symbol.type_name)
	} else {
		fmt.sbprintf(sb, "%s%s", pointer_prefix, symbol.type_name)
	}

	#partial switch v in symbol.value {
	case SymbolUnionValue:
		write_poly_list(sb, v.poly, v.poly_names)
	case SymbolStructValue:
		write_poly_list(sb, v.poly, v.poly_names)
	}
	return true
}

// Docs taken from https://pkg.odin-lang.org/base/builtin
keywords_docs: map[string]string = {
	"typeid"        = "```odin\ntypeid :: typeid\n```\n`typeid` is a unique identifier for an Odin type at runtime. It can be mapped to relevant type information through `type_info_of`.",
	"string"        = "```odin\nstring :: string\n```\n`string` is the set of all strings of 8-bit bytes, conventionally but not necessarily representing UTF-8 encoding text. A `string` may be empty but not `nil`. Elements of `string` type are immutable and indexable.",
	"string16"      = "",
	"cstring"       = "```odin\ncstring :: cstring\n```\n`cstring` is the set of all strings of 8-bit bytes terminated with a NUL (0) byte, conventionally but not necessarily representing UTF-8 encoding text. A `cstring` may be empty or `nil`. Elements of `cstring` type are immutable but not indexable.",
	"cstring16"     = "",
	"int"           = "```odin\nint :: int\n```\n`int` is a signed integer type that is at least 32 bits in size. It is a distinct type, however, and not an alias for say, `i32`.",
	"uint"          = "```odin\nuint :: uint\n```\n`uint` is an unsigned integer type that is at least 32 bits in size. It is a distinct type, however, and not an alias for say, `u32`.",
	"u8"            = "```odin\nu8 :: u8\n```\n`u8` is the set of all unsigned 8-bit integers. Range 0 through 255.",
	"i8"            = "```odin\ni8 :: i8\n```\n`i8` is the set of all signed 8-bit integers. Range -128 through 127.",
	"u16"           = "```odin\nu16 :: u16\n```\n`u16` is the set of all unsigned 16-bit integers with native endianness. Range 0 through 65535.",
	"i16"           = "```odin\ni16 :: i16\n```\n`i16` is the set of all signed 16-bit integers with native endianness. Range -32768 through 32767.",
	"u32"           = "```odin\nu32 :: u32\n```\n`u32` is the set of all unsigned 32-bit integers with native endianness. Range 0 through 4294967295.",
	"i32"           = "```odin\ni32 :: i32\n```\n`i32` is the set of all signed 32-bit integers with native endianness. Range -2147483648 through 2147483647.",
	"u64"           = "```odin\nu64 :: u64\n```\n`u64` is the set of all unsigned 64-bit integers with native endianness. Range 0 through 18446744073709551615.",
	"i64"           = "```odin\ni64 :: i64\n```\n`i64` is the set of all signed 64-bit integers with native endianness. Range -9223372036854775808 through 9223372036854775807.",
	"u128"          = "```odin\nu128 :: u128\n```\n`u128` is the set of all unsigned 128-bit integers with native endianness. Range 0 through 340282366920938463463374607431768211455.",
	"i128"          = "```odin\ni128 :: i128\n```\n`i128` is the set of all signed 128-bit integers with native endianness. Range -170141183460469231731687303715884105728 through 170141183460469231731687303715884105727.",
	"f16"           = "```odin\nf16 :: f16\n```\n`f16` is the set of all IEEE-754 16-bit floating-point numbers with native endianness.",
	"f32"           = "```odin\nf32 :: f32\n```\n`f32` is the set of all IEEE-754 32-bit floating-point numbers with native endianness.",
	"f64"           = "```odin\nf64 :: f64\n```\n`f64` is the set of all IEEE-754 64-bit floating-point numbers with native endianness.",
	"bool"          = "```odin\nbool :: bool\n```\n`bool` is the set of boolean values, `false` and `true`. This is distinct to `b8`. `bool` has a size of 1 byte (8 bits).",
	"any"           = "```odin\nany :: any\n```\n`any` is reference any data type at runtime. Internally it contains a pointer to the underlying data and its relevant `typeid`. This is a very useful construct in order to have a runtime type safe printing procedure.\n\nNote: The `any` value is only valid for as long as the underlying data is still valid. Passing a literal to an `any` will allocate the literal in the current stack frame.\n\nNote: It is highly recommend that you do not use this unless you know what you are doing. Its primary use is for printing procedures.",
	"b8"            = "```odin\nb8 :: b8\n```\n`b8` is the set of boolean values, `false` and `true`. This is distinct to `bool`. `b8` has a size of 1 byte (8 bits).",
	"b16"           = "```odin\nb16 :: b16\n```\n`b16` is the set of boolean values, `false` and `true`. `b16` has a size of 2 bytes (16 bits).",
	"b32"           = "```odin\nb32 :: b32\n```\n`b32` is the set of boolean values, `false` and `true`. `b32` has a size of 4 bytes (32 bits).",
	"b64"           = "```odin\nb64 :: b64\n```\n`b64` is the set of boolean values, `false` and `true`. `b64` has a size of 8 bytes (64 bits).",
	"true"          = "```odin\ntrue :: 0 == 0 // untyped boolean\n```",
	"false"         = "```odin\nfalse :: 0 != 0 // untyped boolean\n```",
	"nil"           = "```odin\nnil :: ... // untyped nil \n```\n`nil` is a predeclared identifier representing the zero value for a pointer, multi-pointer, enum, bit_set, slice, dynamic array, map, procedure, any, typeid, cstring, union, #soa array, #soa pointer, #relative type.",
	"byte"          = "```odin\nbyte :: u8\n```\n`byte` is an alias for `u8` and is equivalent to `u8` in all ways. It is used as a convention to distinguish values from 8-bit unsigned integer values.",
	"rune"          = "```odin\nrune :: rune\n```\n`rune` is the set of all Unicode code points. It is internally the same as i32 but distinct.",
	"f16be"         = "```odin\nf16be :: f16be\n```\n`f16be` is the set of all IEEE-754 16-bit floating-point numbers with big endianness.",
	"f16le"         = "```odin\nf16le :: f16le\n```\n`f16le` is the set of all IEEE-754 16-bit floating-point numbers with little endianness.",
	"f32be"         = "```odin\nf32be :: f32be\n```\n`f32be` is the set of all IEEE-754 32-bit floating-point numbers with big endianness.",
	"f32le"         = "```odin\nf32le :: f32le\n```\n`f32le` is the set of all IEEE-754 32-bit floating-point numbers with little endianness.",
	"f64be"         = "```odin\nf64be :: f64be\n```\n`f64be` is the set of all IEEE-754 64-bit floating-point numbers with big endianness.",
	"f64le"         = "```odin\nf64le :: f64le\n```\n`f64le` is the set of all IEEE-754 64-bit floating-point numbers with little endianness.",
	"i16be"         = "```odin\ni16be :: i16be\n```\n`i16be` is the set of all signed 16-bit integers with big endianness. Range -32768 through 32767.",
	"i16le"         = "```odin\ni16le :: i16le\n```\n`i16le` is the set of all signed 16-bit integers with little endianness. Range -32768 through 32767.",
	"i32be"         = "```odin\ni32be :: i32be\n```\n`i32be` is the set of all signed 32-bit integers with big endianness. Range -2147483648 through 2147483647.",
	"i32le"         = "```odin\ni32le :: i32le\n```\n`i32le` is the set of all signed 32-bit integers with little endianness. Range -2147483648 through 2147483647.",
	"i64be"         = "```odin\ni64be :: i64be\n```\n`i64be` is the set of all signed 64-bit integers with big endianness. Range -9223372036854775808 through 9223372036854775807.",
	"i64le"         = "```odin\ni64le :: i64le\n```\n`i64le` is the set of all signed 64-bit integers with little endianness. Range -9223372036854775808 through 9223372036854775807.",
	"u16be"         = "```odin\nu16be :: u16be\n```\n`u16be` is the set of all unsigned 16-bit integers with big endianness. Range 0 through 65535.",
	"u16le"         = "```odin\nu16le :: u16le\n```\n`u16le` is the set of all unsigned 16-bit integers with little endianness. Range 0 through 65535.",
	"u32be"         = "```odin\nu32be :: u32be\n```\n`u32be` is the set of all unsigned 32-bit integers with big endianness. Range 0 through 4294967295.",
	"u32le"         = "```odin\nu32le :: u32le\n```\n`u32le` is the set of all unsigned 32-bit integers with little endianness. Range 0 through 4294967295.",
	"u64be"         = "```odin\nu64be :: u64be\n```\n`u64be` is the set of all unsigned 64-bit integers with big endianness. Range 0 through 18446744073709551615.",
	"u64le"         = "```odin\nu64le :: u64le\n```\n`u64le` is the set of all unsigned 64-bit integers with little endianness. Range 0 through 18446744073709551615.",
	"i128be"        = "```odin\ni128be :: i128be\n```\n`i128be` is the set of all signed 128-bit integers with big endianness. Range -170141183460469231731687303715884105728 through 170141183460469231731687303715884105727.",
	"i128le"        = "```odin\ni128le :: i128le\n```\n`i128le` is the set of all signed 128-bit integers with little endianness. Range -170141183460469231731687303715884105728 through 170141183460469231731687303715884105727.",
	"u128be"        = "```odin\nu128be :: u128be\n```\n`u128be` is the set of all unsigned 128-bit integers with big endianness. Range 0 through 340282366920938463463374607431768211455.",
	"u128le"        = "```odin\nu128le :: u128le\n```\n`u128le` is the set of all unsigned 128-bit integers with little endianness. Range 0 through 340282366920938463463374607431768211455.",
	"complex32"     = "```odin\ncomplex32 :: complex32\n```\n`complex32` is the set of all complex numbers with `f16` real and imaginary parts.",
	"complex64"     = "```odin\ncomplex64 :: complex64\n```\n`complex64` is the set of all complex numbers with `f32` real and imaginary parts.",
	"complex128"    = "```odin\ncomplex128 :: complex128\n```\n`complex128` is the set of all complex numbers with `f64` real and imaginary parts.",
	"quaternion64"  = "```odin\nquaternion64 :: quaternion64\n```\n`quaternion64` is the set of all complex numbers with `f16` real and imaginary (i, j, & k) parts.",
	"quaternion128" = "```odin\nquaternion128 :: quaternion128\n```\n`quaternion128` is the set of all complex numbers with `f32` real and imaginary (i, j, & k) parts.",
	"quaternion256" = "```odin\nquaternion256 :: quaternion256\n```\n`quaternion256` is the set of all complex numbers with `f64` real and imaginary (i, j, & k) parts.",
	"uintptr"       = "```odin\nuintptr :: uintptr\n```\n`uintptr` is an unsigned integer type that is large enough to hold the bit pattern of any pointer.",
	"rawptr"        = "```odin\nrawptr :: rawptr\n```\n`rawptr` is a pointer to an arbitrary type. It is equivalent to void * in C.",
	// taken from https://github.com/odin-lang/Odin/wiki/Keywords-and-Operators
	"asm"           = "",
	"auto_cast"     = "```odin\nauto_cast v```\nAutomatically casts an expression `v` to the destination’s type if possible.",
	"bit_field"     = "",
	"bit_set"       = "",
	"break"         = "",
	"case"          = "",
	"cast"          = "```odin\ncast(T)v\n```\nConverts the value `v` to the type `T`.",
	"const"         = "",
	"context"       = "```odin\nruntime.context: Context\n```\nThe context variable is local to each scope. It is copy-on-write and is implicitly passed by pointer to any procedure call in that scope (if the procedure has the Odin calling convention).",
	"continue"      = "",
	"defer"         = "",
	"distinct"      = "```odin\ndistinct T\n```\nCreate a new type with the same underlying semantics as `T`",
	"do"            = "",
	"dynamic"       = "",
	"else"          = "",
	"enum"          = "",
	"fallthrough"   = "",
	"for"           = "",
	"foreign"       = "",
	"if"            = "",
	"import"        = "",
	"in"            = "",
	"inline"        = "",
	"map"           = "",
	"not_in"        = "",
	"or_break"      = "",
	"or_continue"   = "",
	"or_else"       = "",
	"or_return"     = "",
	"opaque"        = "",
	"package"       = "",
	"proc"          = "",
	"return"        = "",
	"struct"        = "",
	"switch"        = "",
	"transmute"     = "```odin\ntransmute(T)v\n```\nBitwise cast between 2 types of the same size.",
	"typeid"        = "",
	"union"         = "",
	"using"         = "",
	"when"          = "",
	"where"         = "",
}

directive_docs : map[string]string = {
	// Record memory layout
	"packed" = "```odin\n#packed\n```\n\nThis tag can be applied to a struct. Removes padding between fields that’s normally inserted to ensure all fields meet their type’s alignment requirements. Fields remain in source order.\n\nThis is useful where the structure is unlikely to be correctly aligned (the insertion rules for padding assume it is), or if the space-savings are more important or useful than the access speed of the fields.\n\nAccessing a field in a packed struct may require copying the field out of the struct into a temporary location, or using a machine instruction that doesn’t assume the pointer address is correctly aligned, in order to be performant or avoid crashing on some systems. (See `intrinsics.unaligned_load`.)",
	"raw_union" = "```odin\n#raw_union\n```\n\nThis tag can be applied to a `struct`. Struct’s fields will share the same memory space which serves the same functionality as `union`s in C language. Useful when writing bindings especially.",
	"align" = "```odin\n#align\n```\n\nThis tag can be applied to a `struct` or `union`. When `#align` is passed an integer `N` (as in `#align N`), it specifies that the `struct` will be aligned to `N` bytes. The `struct`’s fields will remain in source-order.",
	"no_nil" = "```odin\n#align\n```\n\nThis tag can be applied to a union to not allow `nil` values.",
	// Control statements
	"partial" = "```odin\n#partial\n```\n\nBy default all `case`s of an `enum` or `union` have to be covered in a `switch` statement. The reason for this requirement is because it makes accidental bugs less likely. However, the `#partial` tag allows you to not have to write out cases that you don’t need to handle.\n\nThe `#partial` directive can also be used to initialize an enumerated array.",
	// Procedure parameters
	"no_alias" = "```odin\n#no_alias\n```\n\nThis tag can be applied to a procedure parameter that is a pointer. This is a hint to the compiler that this parameter will not alias other parameters. This is equivalent to C’s `__restrict`.",
	"any_int" = "```odin\n#any_int\n```\n\n`#any_int` enables implicit casts to a procedure’s integer type at the call site. A parameter with `#any_int` must be an integer.",
	"caller_location" = "```odin\n#caller_location\n```\n\n`#caller_location` sets a parameter’s default value to the location of the code calling the procedure. The location value has the type `runtime.Source_Code_Location`. `#caller_location` may only be used as a default value for procedure parameters.",
	"caller_expression" = "```odin\n#caller_expression\n// or\n#caller_expression(<count>)\n```\n\n`#caller_expression` gives a procedure the entire call expression or the expression used to create a parameter. `#caller_expression` may only be used as a default value for procedure parameters.",
	"c_vararg" = "```odin\n#c_vararg\n```\n\nUsed to interface with vararg functions in foreign procedures.",
	"by_ptr" = "```odin\n#by_ptr\n```\n\nUsed to interface with const reference parameters in foreign procedures. The parameter is passed by pointer internally.",
	"optional_ok" = "```odin\n#optional_ok\n```\n\nAllows skipping the last return parameter, which needs to be a `bool`.",
	"optional_allocator_error" = "```odin\n#optional_allocator_error\n```\n\nAllows skipping the last return parameter, which needs to be a runtime.Allocator_Error",
	// Expressions
	"type" = "```odin\n#type\n```\n\nThis tag doesn’t serve a functional purpose in the compiler, this is for telling someone reading the code that the expression is a type. The main case is for showing that a procedure signature without a body is a type and not just missing its body.",
	"sparse" = "```odin\n#sparse\n```\n\nThis directive may be used to create a sparse enumerated array. This is necessary when the enumerated values are not contiguous.",
	"force_inline" = "```odin\n#force_inline\n```\n\nSpecify whether a procedure literal or call will be forced to inline (`#force_inline`) or forced to never inline `#force_no_inline`. This is not an suggestion to the compiler. If the compiler cannot inline the procedure, it will (currently) silently ignore the directive.\n\nThis is enabled all optization levels except `-o:none` which has all inlining disabled.",
	"force_no_inline" = "```odin\n#force_no_inline\n```\n\nSpecify whether a procedure literal or call will be forced to inline (`#force_inline`) or forced to never inline `#force_no_inline`. This is not an suggestion to the compiler. If the compiler cannot inline the procedure, it will (currently) silently ignore the directive.\n\nThis is enabled all optization levels except `-o:none` which has all inlining disabled.",
	// Statements
	"bounds_check" = "```odin\n#bounds_check\n```\n\nThe `#bounds_check` and `#no_bounds_check` flags control Odin’s built-in bounds checking of arrays and slices. Any statement, block, or function with one of these flags will have their bounds checking turned on or off, depending on the flag provided.\n\nBy default, the Odin compiler has bounds checking enabled program-wide where applicable, and it may be turned off by passing the -no-bounds-check build flag.",
	"no_bounds_check" = "```odin\n#no_bounds_check\n```\n\nThe `#bounds_check` and `#no_bounds_check` flags control Odin’s built-in bounds checking of arrays and slices. Any statement, block, or function with one of these flags will have their bounds checking turned on or off, depending on the flag provided.\n\nBy default, the Odin compiler has bounds checking enabled program-wide where applicable, and it may be turned off by passing the -no-bounds-check build flag.",
	"type_assert" = "```odin\n#type_assert\n```\n\n`#no_type_assert` will bypass the underlying call to `runtime.type_assertion_check` when placed at the head of a statement or block which would normally do a type assert, such as the resolution of a `union` or an `any` into its true type. `#type_assert` will re-enable type assertions, if they were turned off in an outer scope.\n\nBy default, the Odin compiler has type assertions enabled program-wide where applicable, and they may be turned off by passing the `-no-type-assert` build flag. Note that `-disable-assert` does not also turn off type assertions; `-no-type-assert` must be passed explicitly.",
	"no_type_assert" = "```odin\n#no_type_assert\n```\n\n`#no_type_assert` will bypass the underlying call to `runtime.type_assertion_check` when placed at the head of a statement or block which would normally do a type assert, such as the resolution of a `union` or an `any` into its true type. `#type_assert` will re-enable type assertions, if they were turned off in an outer scope.\n\nBy default, the Odin compiler has type assertions enabled program-wide where applicable, and they may be turned off by passing the `-no-type-assert` build flag. Note that `-disable-assert` does not also turn off type assertions; `-no-type-assert` must be passed explicitly.",
	// Built-in
	"assert" = "```odin\n#assert\n```\n\nUnlike `assert`, `#assert` runs at compile-time. `#assert` breaks compilation if the given bool expression is false, and thus #assert is useful for catching bugs before they ever even reach run-time. It also has no run-time cost.",
	"panic" = "```odin\n#panic(<string>)\n```\n\nPanic runs at compile-time. It is functionally equivalent to an `#assert` with a `false` condition, but `#panic` has an error message string parameter.",
	"config" = "```odin\n#config(<identifier>, default)\n```\n\nChecks if an identifier is defined through the command line, or gives a default value instead.\n\nValues can be set with the `-define:NAME=VALUE` command line flag.",
	"defined" = "```odin\n#defined\n```\n\nChecks if an identifier is defined. This may only be used within a procedure’s body.",
	"file" = "```odin\n#file\n```\n\nReturn the current file path.",
	"directory" = "```odin\n#directory\n```\n\nReturn the current directory.",
	"line" = "```odin\n#line\n```\n\nReturn the current line number.",
	"procedure" = "```odin\n#procedure\n```\n\nReturn the current procedure name.",
	"exists" = "```odin\n#exists(<string-path>)\n```\n\nReturns `true` or `false` if the file at the given path exists. If the path is relative, it is accessed relative to the Odin source file that references it.",
	"branch_location" = "```odin\n#branch_location\n```\n\nWhen used within a `defer` statement, this directive returns a `runtime.Source_Code_Location` of the point at which the control flow triggered execution of the `defer`. This may be a `return` statement or the end of a scope.",
	"location" = "```odin\n#location()\n// or\n#location(<entity>)\n```\n\nReturns a `runtime.Source_Code_Location`. Can be called with no parameters for current location, or with a parameter for the location of the variable/proc declaration.",
	"load" = "```odin\n#load(<string-path>)\n//or\n#load(<string-path>, <type>)\n```\n\nReturns a `[]u8` of the file contents at compile time. This means that the loaded data is baked into your program. Optionally, you can provide a type name as second argument; interpreting the data as being of that type.\n\n`#load` also works with `or_else` to provide default content when the file wasn’t found",
	"hash" = "```odin\n#hash(<string-text>, <string-hash>)\n```\n\nReturns a constant integer of the hash of a string literal at compile time.\n\nAvailable hashes:\n\n- adler32\n- crc32\n- crc64\n- fnv32\n- fnv64\n- fnv32a\n- fnv64a\n- murmur32\n- murmur64",
	"load_hash" = "```odin\n#load_hash(<string-path>, <string-hash>)\n```\n\nReturns a constant integer of the hash of a file’s contents at compile time..\n\nAvailable hashes:\n\n- adler32\n- crc32\n- crc64\n- fnv32\n- fnv64\n- fnv32a\n- fnv64a\n- murmur32\n- murmur64",
	"load_directory" = "```odin\n#load_directory(<string-path>)\n```\n\nLoads all files within a directory, at compile time. All the data of those files will be baked into your program. Returns `[]runtime.Load_Directory_File`.",
}
