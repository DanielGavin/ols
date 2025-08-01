#+feature dynamic-literals
package server

import "core:fmt"
import "core:log"
import "core:odin/ast"
import path "core:path/slashpath"
import "core:strings"

keywords_docs: map[string]bool = {
	"typeid"        = true,
	"string"        = true,
	"cstring"       = true,
	"int"           = true,
	"uint"          = true,
	"u8"            = true,
	"i8"            = true,
	"u16"           = true,
	"i16"           = true,
	"u32"           = true,
	"i32"           = true,
	"u64"           = true,
	"i64"           = true,
	"u128"          = true,
	"i128"          = true,
	"f16"           = true,
	"f32"           = true,
	"f64"           = true,
	"bool"          = true,
	"rawptr"        = true,
	"any"           = true,
	"b8"            = true,
	"b16"           = true,
	"b32"           = true,
	"b64"           = true,
	"true"          = true,
	"false"         = true,
	"nil"           = true,
	"byte"          = true,
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
	// taken from https://github.com/odin-lang/Odin/wiki/Keywords-and-Operators
	"asm"           = true,
	"auto_cast"     = true,
	"bit_field"     = true,
	"bit_set"       = true,
	"break"         = true,
	"case"          = true,
	"cast"          = true,
	"context"       = true,
	"continue"      = true,
	"defer"         = true,
	"distinct"      = true,
	"do"            = true,
	"dynamic"       = true,
	"else"          = true,
	"enum"          = true,
	"fallthrough"   = true,
	"for"           = true,
	"foreign"       = true,
	"if"            = true,
	"import"        = true,
	"in"            = true,
	"map"           = true,
	"not_in"        = true,
	"or_else"       = true,
	"or_return"     = true,
	"package"       = true,
	"proc"          = true,
	"return"        = true,
	"struct"        = true,
	"switch"        = true,
	"transmute"     = true,
	"typeid"        = true,
	"union"         = true,
	"using"         = true,
	"when"          = true,
	"where"         = true,
}

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

construct_symbol_docs :: proc(symbol: Symbol, markdown := true, allocator := context.temp_allocator) -> string {
	sb := strings.builder_make(allocator = allocator)
	if symbol.doc != "" {
		strings.write_string(&sb, symbol.doc)
		if symbol.comment != "" {
			strings.write_string(&sb, "\n")
		}
	}

	if symbol.comment != "" {
		if markdown {
			fmt.sbprintf(&sb, "\n```odin\n%s\n```", symbol.comment)
		} else {
			fmt.sbprintf(&sb, "\n%s", symbol.comment)
		}
	}

	 return strings.to_string(sb)
}

// Returns the fully detailed signature for the symbol, including things like attributes and fields
get_signature :: proc(ast_context: ^AstContext, symbol: Symbol) -> string {
	show_type_info := symbol.type == .Variable || symbol.type == .Field

	pointer_prefix := repeat("^", symbol.pointers, ast_context.allocator)

	#partial switch v in symbol.value {
	case SymbolEnumValue:
		sb := strings.builder_make(ast_context.allocator)
		if show_type_info {
			append_type_information(&sb, ast_context, symbol, pointer_prefix)
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
		if show_type_info {
			append_type_information(&sb, ast_context, symbol, pointer_prefix)
			strings.write_string(&sb, " :: ")
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
		if show_type_info {
			append_type_information(&sb, ast_context, symbol, pointer_prefix)
			strings.write_string(&sb, " :: ")
		}
		strings.write_string(&sb, "union")
		write_poly_list(&sb, v.poly, v.poly_names)
		if len(v.types) == 0 {
			strings.write_string(&sb, " {}")
			return strings.to_string(sb)
		}
		strings.write_string(&sb, " {\n")
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
				write_procedure_symbol_signature(&sb, value, detailed_signature=false)
				strings.write_string(&sb, ",\n")
			}
		}
		strings.write_string(&sb, "}")
		return strings.to_string(sb)
	case SymbolProcedureValue:
		sb := strings.builder_make(ast_context.allocator)
		if show_type_info {
			append_type_information(&sb, ast_context, symbol, pointer_prefix)
			strings.write_string(&sb, " :: ")
		}
		write_procedure_symbol_signature(&sb, v, detailed_signature=true)
		return strings.to_string(sb)
	case SymbolBitFieldValue:
		sb := strings.builder_make(ast_context.allocator)
		if show_type_info {
			append_type_information(&sb, ast_context, symbol, pointer_prefix)
			strings.write_string(&sb, " :: ")
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
	// TODO: this is also a bit much, might need to clean it up into a function
	show_type_info := (symbol.type == .Variable || symbol.type == .Field) && !(.Anonymous in symbol.flags) && symbol.type_name != ""

	pointer_prefix := repeat("^", symbol.pointers, ast_context.allocator)
	#partial switch v in symbol.value {
	case SymbolBasicValue:
		sb := strings.builder_make(ast_context.allocator)
		if show_type_info {
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
		return strings.to_string(sb)
	case SymbolBitSetValue:
		sb := strings.builder_make(ast_context.allocator)
		fmt.sbprintf(&sb, "%sbit_set[", pointer_prefix)
		build_string_node(v.expr, &sb, false)
		strings.write_string(&sb, "]")
		return strings.to_string(sb)
	case SymbolEnumValue:
		// TODO: we need a better way to do this for enum fields
		if symbol.type == .Field && symbol.type_name == "" {
			return symbol.signature
		}
		sb := strings.builder_make(ast_context.allocator)
		if show_type_info {
			append_type_information(&sb, ast_context, symbol, pointer_prefix)
		} else {
			strings.write_string(&sb, pointer_prefix)
			strings.write_string(&sb, "enum {..}")
		}
		return strings.to_string(sb)
	case SymbolMapValue:
		sb := strings.builder_make(ast_context.allocator)
		fmt.sbprintf(&sb, "%smap[", pointer_prefix)
		build_string_node(v.key, &sb, false)
		strings.write_string(&sb, "]")
		build_string_node(v.value, &sb, false)
		return strings.to_string(sb)
	case SymbolProcedureValue:
		sb := strings.builder_make(ast_context.allocator)
		if show_type_info {
			append_type_information(&sb, ast_context, symbol, pointer_prefix)
			strings.write_string(&sb, " :: ")
		}
		write_procedure_symbol_signature(&sb, v, detailed_signature=true)
		return strings.to_string(sb)
	case SymbolAggregateValue:
		return "proc (..)"
	case SymbolStructValue:
		sb := strings.builder_make(ast_context.allocator)
		if show_type_info {
			append_type_information(&sb, ast_context, symbol, pointer_prefix)
			write_poly_list(&sb, v.poly, v.poly_names)
		} else {
			strings.write_string(&sb, pointer_prefix)
			strings.write_string(&sb, "struct")
			write_poly_list(&sb, v.poly, v.poly_names)
			strings.write_string(&sb, " {..}")
		}
		return strings.to_string(sb)
	case SymbolUnionValue:
		sb := strings.builder_make(ast_context.allocator)
		if show_type_info {
			append_type_information(&sb, ast_context, symbol, pointer_prefix)
			write_poly_list(&sb, v.poly, v.poly_names)
		} else {
			strings.write_string(&sb, pointer_prefix)
			strings.write_string(&sb, "union")
			write_poly_list(&sb, v.poly, v.poly_names)
			strings.write_string(&sb, " {..}")
		}
		return strings.to_string(sb)
	case SymbolBitFieldValue:
		sb := strings.builder_make(ast_context.allocator)
		if show_type_info {
			append_type_information(&sb, ast_context, symbol, pointer_prefix)
		} else {
			fmt.sbprintf(&sb, "%sbit_field ", pointer_prefix)
			build_string_node(v.backing_type, &sb, false)
			strings.write_string(&sb, " {..}")
		}
		return strings.to_string(sb)
		
	case SymbolMultiPointerValue:
		sb := strings.builder_make(ast_context.allocator)
		fmt.sbprintf(&sb, "%s[^]", pointer_prefix)
		build_string_node(v.expr, &sb, false)
		return strings.to_string(sb)
	case SymbolDynamicArrayValue:
		sb := strings.builder_make(ast_context.allocator)
		fmt.sbprintf(&sb, "%s[dynamic]", pointer_prefix)
		build_string_node(v.expr, &sb, false)
		return strings.to_string(sb)
	case SymbolSliceValue:
		sb := strings.builder_make(ast_context.allocator)
		fmt.sbprintf(&sb, "%s[]", pointer_prefix)
		build_string_node(v.expr, &sb, false)
		return strings.to_string(sb)
	case SymbolFixedArrayValue:
		sb := strings.builder_make(ast_context.allocator)
		fmt.sbprintf(&sb, "%s[", pointer_prefix)
		build_string_node(v.len, &sb, false)
		strings.write_string(&sb, "]")
		build_string_node(v.expr, &sb, false)
		return strings.to_string(sb)
	case SymbolMatrixValue:
		sb := strings.builder_make(ast_context.allocator)
		fmt.sbprintf(&sb, "%smatrix[", pointer_prefix)
		build_string_node(v.x, &sb, false)
		strings.write_string(&sb, ",")
		build_string_node(v.y, &sb, false)
		strings.write_string(&sb, "]")
		build_string_node(v.expr, &sb, false)
		return strings.to_string(sb)
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
	return strings.to_string(sb)
}

write_symbol_type_information :: proc(ast_context: ^AstContext, sb: ^strings.Builder, symbol: Symbol, pointer_prefix: string) {
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
}

write_proc_param_list_and_return :: proc(sb: ^strings.Builder, value: SymbolProcedureValue) {
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
	}
	write_proc_param_list_and_return(sb, value)
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
	write_poly_list(sb, v.poly, v.poly_names)
	strings.write_string(sb, " {\n")

	for i in 0 ..< len(v.names) {
		if i < len(v.from_usings) {
			if index := v.from_usings[i]; index != using_index && index != -1 {
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

append_type_information :: proc(
	sb: ^strings.Builder,
	ast_context: ^AstContext,
	symbol: Symbol,
	pointer_prefix: string,
) {
	pkg_name := get_pkg_name(ast_context, symbol.type_pkg)
	if pkg_name == "" || pkg_name == "$builtin"{
		fmt.sbprintf(sb, "%s%s", pointer_prefix, symbol.type_name)
		return
	}
	fmt.sbprintf(sb, "%s%s.%s", pointer_prefix, pkg_name, symbol.type_name)
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
	if v, ok := symbol.value.(SymbolProcedureValue); ok {
		pkg := path.base(symbol.pkg, false, context.temp_allocator)
		sb := strings.builder_make(context.temp_allocator)
		for attribute in v.attributes {
			if len(attribute.elems) == 0 {
				strings.write_string(&sb, "@()\n")
				continue
			}
			strings.write_string(&sb, "@(")
			for elem, i in attribute.elems {
				if directive, ok := elem.derived.(^ast.Field_Value); ok {
					build_string_node(directive.field, &sb, false)
					strings.write_string(&sb, "=")
					build_string_node(directive.value, &sb, false)
				} else {
					build_string_node(elem, &sb, false)
				}
				if i != len(attribute.elems) - 1 {
					strings.write_string(&sb, ", ")
				}

			}
			strings.write_string(&sb, ")\n")
		}

		if pkg != "" && pkg != "$builtin" {
			fmt.sbprintf(&sb, "%v.", pkg)
		}
		fmt.sbprintf(&sb, "%v", symbol.name)
		if symbol.signature != "" {
			fmt.sbprintf(&sb, ": %v", symbol.signature)
		}
		return strings.to_string(sb)
	}

	return concatenate_raw_string_information(
		ast_context,
		symbol.pkg,
		symbol.name,
		symbol.signature,
		symbol.type,
	)
}

concatenate_raw_string_information :: proc(
	ast_context: ^AstContext,
	pkg: string,
	name: string,
	signature: string,
	type: SymbolType,
) -> string {
	pkg := path.base(pkg, false, context.temp_allocator)

	if type == .Package {
		return fmt.tprintf("%v: package", name)
	}
	sb := strings.builder_make()
	if pkg != "" && pkg != "$builtin" {
		fmt.sbprintf(&sb, "%v.", pkg)
	}
	fmt.sbprintf(&sb, "%v", name)
	if signature != "" {
		fmt.sbprintf(&sb, ": %v", signature)
	}
	return strings.to_string(sb)
}
