#+feature dynamic-literals
package server

import "core:fmt"
import "core:log"
import "core:odin/ast"
import path "core:path/slashpath"
import "core:strings"

keywords_docs: map[string]struct{} = {
	"typeid"        = {},
	"string"        = {},
	"cstring"       = {},
	"int"           = {},
	"uint"          = {},
	"u8"            = {},
	"i8"            = {},
	"u16"           = {},
	"i16"           = {},
	"u32"           = {},
	"i32"           = {},
	"u64"           = {},
	"i64"           = {},
	"u128"          = {},
	"i128"          = {},
	"f16"           = {},
	"f32"           = {},
	"f64"           = {},
	"bool"          = {},
	"rawptr"        = {},
	"any"           = {},
	"b8"            = {},
	"b16"           = {},
	"b32"           = {},
	"b64"           = {},
	"true"          = {},
	"false"         = {},
	"nil"           = {},
	"byte"          = {},
	"rune"          = {},
	"f16be"         = {},
	"f16le"         = {},
	"f32be"         = {},
	"f32le"         = {},
	"f64be"         = {},
	"f64le"         = {},
	"i16be"         = {},
	"i16le"         = {},
	"i32be"         = {},
	"i32le"         = {},
	"i64be"         = {},
	"i64le"         = {},
	"u16be"         = {},
	"u16le"         = {},
	"u32be"         = {},
	"u32le"         = {},
	"u64be"         = {},
	"u64le"         = {},
	"i128be"        = {},
	"i128le"        = {},
	"u128be"        = {},
	"u128le"        = {},
	"complex32"     = {},
	"complex64"     = {},
	"complex128"    = {},
	"quaternion64"  = {},
	"quaternion128" = {},
	"quaternion256" = {},
	"uintptr"       = {},
	// taken from https://github.com/odin-lang/Odin/wiki/Keywords-and-Operators
	"asm"           = {},
	"auto_cast"     = {},
	"bit_field"     = {},
	"bit_set"       = {},
	"break"         = {},
	"case"          = {},
	"cast"          = {},
	"context"       = {},
	"continue"      = {},
	"defer"         = {},
	"distinct"      = {},
	"do"            = {},
	"dynamic"       = {},
	"else"          = {},
	"enum"          = {},
	"fallthrough"   = {},
	"for"           = {},
	"foreign"       = {},
	"if"            = {},
	"import"        = {},
	"in"            = {},
	"map"           = {},
	"not_in"        = {},
	"or_else"       = {},
	"or_return"     = {},
	"package"       = {},
	"proc"          = {},
	"return"        = {},
	"struct"        = {},
	"switch"        = {},
	"transmute"     = {},
	"typeid"        = {},
	"union"         = {},
	"using"         = {},
	"when"          = {},
	"where"         = {},
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
			strings.write_string(sb, "enum {}")
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
		if len(v.names) == 0 {
			strings.write_string(sb, "struct {}")
			if symbol.comment != "" {
				fmt.sbprintf(sb, " %s", symbol.comment)
			}
			return
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
		if len(v.types) == 0 {
			strings.write_string(sb, " {}")
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
			strings.write_string(sb, " {}")
		}
		return
	case SymbolMapValue:
		fmt.sbprintf(sb, "%smap[", pointer_prefix)
		build_string_node(v.key, sb, false)
		strings.write_string(sb, "]")
		write_node(sb, ast_context, v.value, "", short_signature = true)
		return
	case SymbolProcedureValue:
		write_procedure_symbol_signature(sb, v, detailed_signature = true)
		return
	case SymbolAggregateValue:
		strings.write_string(sb, "proc (..)")
		return
	case SymbolStructValue:
		strings.write_string(sb, pointer_prefix)
		strings.write_string(sb, "struct")
		write_poly_list(sb, v.poly, v.poly_names)
		if len(v.types) > 0 {
			strings.write_string(sb, " {..}")
		} else {
			strings.write_string(sb, " {}")
		}
		return
	case SymbolUnionValue:
		strings.write_string(sb, pointer_prefix)
		strings.write_string(sb, "union")
		write_poly_list(sb, v.poly, v.poly_names)
		if len(v.types) > 0 {
			strings.write_string(sb, " {..}")
		} else {
			strings.write_string(sb, " {}")
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
		fmt.sbprintf(sb, "%s[dynamic]", pointer_prefix)
		write_node(sb, ast_context, v.expr, "", short_signature = true)
		return
	case SymbolSliceValue:
		fmt.sbprintf(sb, "%s[]", pointer_prefix)
		write_node(sb, ast_context, v.expr, "", short_signature = true)
		return
	case SymbolFixedArrayValue:
		fmt.sbprintf(sb, "%s[", pointer_prefix)
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
		switch v.type {
		case .Float:
			strings.write_string(sb, "float")
		case .String:
			strings.write_string(sb, "string")
		case .Bool:
			strings.write_string(sb, "bool")
		case .Integer:
			strings.write_string(sb, "int")
		}
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

write_struct_hover :: proc(sb: ^strings.Builder, ast_context: ^AstContext, v: SymbolStructValue, depth: int) {
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
		if _, ok := v.usings[i]; ok {
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
		symbol = make_symbol_procedure_from_ast(ast_context, nil, n^, name, {}, true, .None)
		ok = true
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
	if pkg != "" && pkg != "$builtin" {
		fmt.sbprintf(sb, "%v.", pkg)
	}
	strings.write_string(sb, symbol.name)
	strings.write_string(sb, ": ")
}

write_symbol_type_information :: proc(sb: ^strings.Builder, ast_context: ^AstContext, symbol: Symbol) -> bool {
	show_type_info :=
		(symbol.type == .Variable || symbol.type == .Field) && !(.Anonymous in symbol.flags) && symbol.type_name != ""

	if !show_type_info {
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
