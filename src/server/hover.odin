#+feature dynamic-literals
package server

import "core:fmt"
import "core:log"
import "core:odin/ast"
import "core:strings"

import "src:common"
import "src:spall"

Type_Layout :: struct {
	size:      int,
	alignment: int,
}

get_basic_type_layout :: proc(name: string) -> (Type_Layout, bool) {
	switch name {
	case "u8":
		return {size_of(u8), align_of(u8)}, true
	case "i8":
		return {size_of(i8), align_of(i8)}, true
	case "byte":
		return {size_of(byte), align_of(byte)}, true
	case "i16", "u16":
		return {size_of(u16), align_of(u16)}, true
	case "i32", "u32":
		return {size_of(u32), align_of(u32)}, true
	case "int":
		return {size_of(int), align_of(int)}, true
	case "uint":
		return {size_of(uint), align_of(uint)}, true
	case "uintptr":
		return {size_of(uintptr), align_of(uintptr)}, true
	case "rawptr":
		return {size_of(rawptr), align_of(rawptr)}, true
	case "rune":
		return {size_of(rune), align_of(rune)}, true
	case "i64", "u64":
		return {size_of(u64), align_of(u64)}, true
	case "i128", "u128":
		return {size_of(u128), align_of(u128)}, true
	case "bool":
		return {size_of(bool), align_of(bool)}, true
	case "string":
		return {size_of(string), align_of(string)}, true
	case "f16":
		return {size_of(f16), align_of(f16)}, true
	case "f32":
		return {size_of(f32), align_of(f32)}, true
	case "f64":
		return {size_of(f64), align_of(f64)}, true
	case "complex32":
		return {size_of(complex32), align_of(complex32)}, true
	case "complex64":
		return {size_of(complex64), align_of(complex64)}, true
	case "complex128":
		return {size_of(complex128), align_of(complex128)}, true
	case "quaternion64":
		return {size_of(quaternion64), align_of(quaternion64)}, true
	case "quaternion128":
		return {size_of(quaternion128), align_of(quaternion128)}, true
	case "quaternion256":
		return {size_of(quaternion256), align_of(quaternion256)}, true
	}

	return {}, false
}


layout_profile_matches_server_target :: proc(config: ^common.Config) -> bool {
	if config == nil {
		return true
	}

	arch_matches := config.profile.arch == "" || config.profile.arch == ODIN_ARCH_STRING
	os_matches := config.profile.os == "" || config.profile.os == ODIN_OS_STRING

	return arch_matches && os_matches
}


get_fixed_array_length :: proc(ast_context: ^AstContext, expr: ^ast.Expr) -> (int, bool) {
	length, known := resolve_integer_constant(ast_context, expr)
	return length, known && length >= 0
}

get_enum_value_range :: proc(ast_context: ^AstContext, value: SymbolEnumValue) -> (int, int, bool) {
	if len(value.names) == 0 || len(value.values) != len(value.names) {
		return 0, 0, false
	}

	local_values := make(map[string]int, context.temp_allocator)
	current := -1
	lower, upper := max(int), min(int)

	for name, i in value.names {
		if value.values[i] == nil {
			if current == max(int) {
				return 0, 0, false
			}

			current += 1
		} else {
			current_known: bool
			current, current_known = resolve_integer_constant(ast_context, value.values[i], local_values)
			if !current_known {
				return 0, 0, false
			}
		}

		local_values[name] = current
		lower = min(lower, current)
		upper = max(upper, current)
	}

	return lower, upper, true
}

get_bit_set_value_range :: proc(ast_context: ^AstContext, expr: ^ast.Expr) -> (int, int, bool) {
	if expr == nil {
		return 0, 0, false
	}

	if binary, ok := expr.derived.(^ast.Binary_Expr);
	   ok && (binary.op.kind == .Range_Half || binary.op.kind == .Range_Full) {
		lower, lower_known := resolve_integer_constant(ast_context, binary.left)
		upper, upper_known := resolve_integer_constant(ast_context, binary.right)

		if !lower_known || !upper_known {
			return 0, 0, false
		}

		if binary.op.kind == .Range_Half {
			if upper == min(int) {
				return 0, 0, false
			}

			upper -= 1
		}

		return lower, upper, lower <= upper
	}

	if symbol, ok := resolve_type_expression(ast_context, expr); ok {
		if enum_value, is_enum := symbol.value.(SymbolEnumValue); is_enum {
			return get_enum_value_range(ast_context, enum_value)
		}
	}

	return 0, 0, false
}

get_implicit_bit_set_layout :: proc(lower, upper: int) -> (Type_Layout, bool) {
	bit_count := i128(upper) - i128(lower) + 1
	switch {
	case bit_count <= 0:
		return {}, false
	case bit_count <= 8:
		return {size_of(bit_set[0 ..< 8]), align_of(bit_set[0 ..< 8])}, true
	case bit_count <= 16:
		return {size_of(bit_set[0 ..< 16]), align_of(bit_set[0 ..< 16])}, true
	case bit_count <= 32:
		return {size_of(bit_set[0 ..< 32]), align_of(bit_set[0 ..< 32])}, true
	case bit_count <= 64:
		return {size_of(bit_set[0 ..< 64]), align_of(bit_set[0 ..< 64])}, true
	case bit_count <= 128:
		return {size_of(bit_set[0 ..< 128]), align_of(bit_set[0 ..< 128])}, true
	}

	return {}, false
}

get_layout_alignment :: proc(ast_context: ^AstContext, expr: ^ast.Expr) -> (int, bool) {
	alignment, ok := resolve_integer_constant(ast_context, expr)

	return alignment, ok && alignment > 0 && alignment & (alignment - 1) == 0
}

get_struct_layout :: proc(ast_context: ^AstContext, value: SymbolStructValue) -> (Type_Layout, bool) {
	custom_alignment := 0
	min_field_alignment := 1
	max_field_alignment := 0

	is_packed := .Is_Packed in value.tags
	is_raw_union := .Is_Raw_Union in value.tags

	if is_packed && (value.align != nil || value.min_field_align != nil || value.max_field_align != nil) {
		return {}, false
	}

	if value.align != nil {
		if alignment, ok := get_layout_alignment(ast_context, value.align); ok {
			custom_alignment = alignment
		} else {
			return {}, false
		}
	}

	if value.min_field_align != nil {
		if alignment, ok := get_layout_alignment(ast_context, value.min_field_align); ok {
			min_field_alignment = alignment
		} else {
			return {}, false
		}
	}

	if value.max_field_align != nil {
		if alignment, ok := get_layout_alignment(ast_context, value.max_field_align); ok {
			max_field_alignment = alignment
		} else {
			return {}, false
		}
	}

	if max_field_alignment > 0 && min_field_alignment > max_field_alignment ||
	   custom_alignment > 0 && custom_alignment < min_field_alignment ||
	   max_field_alignment > 0 && custom_alignment > max_field_alignment {
		return {}, false
	}

	layout := Type_Layout{}
	natural_alignment := 1

	if len(value.from_usings) != len(value.types) {
		return {}, false
	}

	for field_type, i in value.types {
		if value.from_usings[i] != -1 {
			continue
		}

		field_layout, ok := get_expr_layout(ast_context, field_type)
		if !ok {
			return {}, false
		}

		natural_alignment = max(natural_alignment, field_layout.alignment)

		if is_raw_union {
			layout.size = max(layout.size, field_layout.size)
		} else if is_packed {
			layout.size += field_layout.size
		} else {
			field_alignment := max(field_layout.alignment, min_field_alignment)
			if max_field_alignment > 0 {
				field_alignment = min(field_alignment, max_field_alignment)
			}

			padding := (field_alignment - (layout.size % field_alignment)) % field_alignment
			layout.size += padding + field_layout.size
		}
	}

	if custom_alignment > 0 {
		layout.alignment = custom_alignment
	} else if is_packed {
		layout.alignment = 1
	} else {
		layout.alignment = max(natural_alignment, min_field_alignment)
		if max_field_alignment > 0 {
			layout.alignment = min(layout.alignment, max_field_alignment)
		}
	}

	final_padding := (layout.alignment - (layout.size % layout.alignment)) % layout.alignment
	layout.size += final_padding

	return layout, true
}

get_expr_layout :: proc(ast_context: ^AstContext, expr: ^ast.Expr) -> (Type_Layout, bool) {
	if expr == nil {
		return {}, false
	}

	// Pointer storage is independent of the pointee's layout. Resolve pointers
	// here so recursive structures do not recursively traverse their pointees.
	if _, ok := expr.derived.(^ast.Pointer_Type); ok {
		return {size_of(rawptr), align_of(rawptr)}, true
	}
	if _, ok := expr.derived.(^ast.Multi_Pointer_Type); ok {
		return {size_of(rawptr), align_of(rawptr)}, true
	}

	if distinct_type, ok := expr.derived.(^ast.Distinct_Type); ok {
		return get_expr_layout(ast_context, distinct_type.type)
	}

	if ident, ok := expr.derived.(^ast.Ident); ok {
		if layout, known := get_basic_type_layout(ident.name); known {
			return layout, true
		}
	}

	if _, ok := expr.derived.(^ast.Proc_Type); ok {
		return {size_of(^rawptr), align_of(^rawptr)}, true
	}

	if symbol, ok := resolve_type_expression(ast_context, expr); ok {
		// Pointer aliases resolve to their pointee's symbol with the pointer depth
		// stored separately on the symbol.
		if symbol.pointers > 0 {
			return {size_of(rawptr), align_of(rawptr)}, true
		}

		#partial switch value in symbol.value {
		case SymbolBasicValue:
			return get_basic_type_layout(value.ident.name)
		case SymbolStructValue:
			return get_struct_layout(ast_context, value)
		case SymbolProcedureValue:
			return {size_of(^rawptr), align_of(^rawptr)}, true
		case SymbolEnumValue:
			if value.base_type == nil {
				return get_basic_type_layout("int")
			}

			return get_expr_layout(ast_context, value.base_type)
		case SymbolFixedArrayValue:
			if .Simd in symbol.flags || .Soa in symbol.flags {
				return {}, false
			}

			length, length_known := get_fixed_array_length(ast_context, value.len)
			element, element_known := get_expr_layout(ast_context, value.expr)
			if !length_known || !element_known || element.size > 0 && length > max(int) / element.size {
				return {}, false
			}

			return {size = length * element.size, alignment = element.alignment}, true
		case SymbolSliceValue:
			return {size_of([]u8), align_of([]u8)}, true
		case SymbolDynamicArrayValue:
			if .Soa in symbol.flags {
				return {}, false
			}

			if value.cap == nil {
				return {size_of([dynamic]u8), align_of([dynamic]u8)}, true
			}

			capacity, capacity_known := get_fixed_array_length(ast_context, value.cap)
			element, element_known := get_expr_layout(ast_context, value.expr)
			if !capacity_known || !element_known || element.size > 0 && capacity > max(int) / element.size {
				return {}, false
			}

			elements_size := capacity * element.size
			int_size := size_of(int)
			length_padding := (int_size - (elements_size % int_size)) % int_size
			if elements_size > max(int) - length_padding - int_size {
				return {}, false
			}

			size := elements_size + length_padding + int_size
			alignment := max(int_size, element.alignment)
			final_padding := (alignment - (size % alignment)) % alignment
			if size > max(int) - final_padding {
				return {}, false
			}

			return {size = size + final_padding, alignment = alignment}, true
		case SymbolMapValue:
			return {size_of(map[u8]u8), align_of(map[u8]u8)}, true
		case SymbolMatrixValue:
			row_count, rows_known := get_fixed_array_length(ast_context, value.x)
			column_count, columns_known := get_fixed_array_length(ast_context, value.y)
			element, element_known := get_expr_layout(ast_context, value.expr)

			if !rows_known ||
			   !columns_known ||
			   !element_known ||
			   column_count > 0 && row_count > max(int) / column_count {
				return {}, false
			}

			element_count := row_count * column_count
			if element.size > 0 && element_count > max(int) / element.size {
				return {}, false
			}

			return {size = element_count * element.size, alignment = element.alignment}, true
		case SymbolBitSetValue:
			if value.underlying != nil {
				return get_expr_layout(ast_context, value.underlying)
			}

			lower, upper, range_known := get_bit_set_value_range(ast_context, value.expr)
			if !range_known {
				return {}, false
			}

			return get_implicit_bit_set_layout(lower, upper)
		case SymbolUnionValue:
			return {}, false
		}
	}

	return {}, false
}


write_hover_content :: proc(ast_context: ^AstContext, symbol: Symbol, config: ^common.Config) -> MarkupContent {
	cat := construct_symbol_information(ast_context, symbol)
	doc := construct_symbol_docs(symbol)

	struct_info := ""
	if config != nil && config.enable_hover_struct_size_info && layout_profile_matches_server_target(config) {
		if symbol.type == .Struct {
			if value, is_struct := symbol.value.(SymbolStructValue); is_struct {
				if layout, known := get_struct_layout(ast_context, value); known {
					struct_info = fmt.aprintf("Size: %v bytes, Alignment: %v bytes", layout.size, layout.alignment)
				}
			}
		}
	}

	content := build_markup_content(cat, doc)
	if struct_info != "" {
		content.value = fmt.tprintf("%v\n%v", content.value, struct_info)
	}

	return content
}

get_hover_information :: proc(
	document: ^Document,
	position: common.Position,
	config: ^common.Config,
) -> (
	Hover,
	bool,
	bool,
) {
	spall.trace(#procedure, document.fullpath)
	hover := Hover {
		contents = {kind = "plaintext"},
	}

	ast_context := make_ast_context(
		document.ast,
		document.imports,
		document.package_name,
		document.uri.uri,
		document.fullpath,
	)

	position_context, ok := get_document_position_context(document, position, .Hover)
	if !ok {
		log.warn("Failed to get position context")
		return hover, false, false
	}

	ast_context.position_hint = position_context.hint

	get_globals(document.ast, &ast_context)
	get_locals(&ast_context, &position_context)

	if position_context.import_stmt != nil &&
	   position_in_node(position_context.import_stmt, position_context.position) {
		for imp in document.imports {
			if imp.original != position_context.import_stmt.fullpath {
				continue
			}

			symbol := Symbol {
				name  = imp.base,
				type  = .Package,
				pkg   = imp.name,
				value = SymbolPackageValue{},
			}
			try_build_package(symbol.pkg)
			if symbol, ok = resolve_symbol_return(&ast_context, symbol); ok {
				hover.range = common.get_token_range(document.ast.pkg_decl, ast_context.file.src)
				hover.contents = write_hover_content(&ast_context, symbol, config)
				return hover, true, true
			}
		}

		return {}, false, true
	}

	if document.ast.pkg_decl != nil && position_in_node(document.ast.pkg_decl, position_context.position) {
		symbol := Symbol {
			name  = document.ast.pkg_name,
			type  = .Package,
			pkg   = ast_context.document_package,
			value = SymbolPackageValue{},
		}
		try_build_package(symbol.pkg)
		if symbol, ok = resolve_symbol_return(&ast_context, symbol); ok {
			hover.range = common.get_token_range(document.ast.pkg_decl, ast_context.file.src)
			hover.contents = write_hover_content(&ast_context, symbol, config)
			return hover, true, true
		}

	}

	if position_context.type_cast != nil &&
	   !position_in_node(position_context.type_cast.type, position_context.position) &&
	   !position_in_node(position_context.type_cast.expr, position_context.position) { 	// check that we're actually on the 'cast' word
		if str, ok := keywords_docs[position_context.type_cast.tok.text]; ok {
			hover.contents.kind = "markdown"
			hover.contents.value = str
			hover.range = common.get_token_range(position_context.type_cast, ast_context.file.src)
			return hover, true, true
		}
	}

	if position_context.directive != nil && position_in_node(position_context.directive, position_context.position) {
		if str, ok := directive_docs[position_context.directive.name]; ok {
			hover.contents.kind = "markdown"
			hover.contents.value = str
			hover.range = common.get_token_range(position_context.directive, ast_context.file.src)
			return hover, true, true
		}
	}

	if position_context.identifier != nil {
		if ident, ok := position_context.identifier.derived.(^ast.Ident); ok {
			if str, ok := keywords_docs[ident.name]; ok {
				hover.contents.kind = "markdown"
				hover.contents.value = str
				hover.range = common.get_token_range(position_context.identifier^, ast_context.file.src)
				return hover, true, true
			}
		}
	}

	if position_context.implicit_context != nil {
		if str, ok := keywords_docs[position_context.implicit_context.tok.text]; ok {
			hover.contents.kind = "markdown"
			hover.contents.value = str
			hover.range = common.get_token_range(position_context.implicit_context^, ast_context.file.src)
			return hover, true, true
		}
	}

	if position_context.value_decl != nil && len(position_context.value_decl.names) != 0 {
		if position_context.enum_type != nil {
			if enum_symbol, ok := resolve_type_expression(&ast_context, position_context.value_decl.names[0]); ok {
				if v, ok := enum_symbol.value.(SymbolEnumValue); ok {
					for field in position_context.enum_type.fields {
						if ident, ok := field.derived.(^ast.Ident); ok {
							if position_in_node(ident, position_context.position) {
								for name, i in v.names {
									if name == ident.name {
										construct_enum_field_symbol(&enum_symbol, v, i)
										hover.contents = write_hover_content(&ast_context, enum_symbol, config)
										hover.range = enum_symbol.range
										return hover, true, true
									}
								}
							}
						} else if value, ok := field.derived.(^ast.Field_Value); ok {
							if position_in_node(value.field, position_context.position) {
								if ident, ok := value.field.derived.(^ast.Ident); ok {
									for name, i in v.names {
										if name == ident.name {
											construct_enum_field_symbol(&enum_symbol, v, i)
											hover.range = enum_symbol.range
											hover.contents = write_hover_content(&ast_context, enum_symbol, config)
										}
									}
								}
								return hover, true, true
							}
						}
					}
				}
			}
		}

		if position_context.struct_type != nil {
			index := 0
			for field, field_index in position_context.struct_type.fields.list {
				for name, name_index in field.names {
					defer index += 1
					if position_in_node(name, position_context.position) {
						if identifier, ok := name.derived.(^ast.Ident); ok && field.type != nil {
							if symbol, ok := resolve_type_expression(&ast_context, field.type); ok {
								if struct_symbol, ok := resolve_type_expression(
									&ast_context,
									&position_context.struct_type.node,
								); ok {
									if value_decl_symbol, ok := resolve_type_expression(
										&ast_context,
										position_context.value_decl.names[0],
									); ok {
										name := get_field_parent_name(value_decl_symbol, struct_symbol)
										if value, ok := struct_symbol.value.(SymbolStructValue); ok {
											construct_struct_field_symbol(&symbol, name, value, index)
											build_documentation(&ast_context, &symbol, true)
											hover.range = symbol.range
											hover.contents = write_hover_content(&ast_context, symbol, config)
											return hover, true, true
										}
									}
								}
							}
						}
					}
				}
			}
		}

		if position_context.bit_field_type != nil {
			for field, i in position_context.bit_field_type.fields {
				if position_in_node(field.name, position_context.position) {
					if identifier, ok := field.name.derived.(^ast.Ident); ok && field.type != nil {
						if symbol, ok := resolve_type_expression(&ast_context, field.type); ok {
							if bit_field_symbol, ok := resolve_type_expression(
								&ast_context,
								&position_context.bit_field_type.node,
							); ok {
								if value_decl_symbol, ok := resolve_type_expression(
									&ast_context,
									position_context.value_decl.names[0],
								); ok {
									name := get_field_parent_name(value_decl_symbol, bit_field_symbol)
									if value, ok := bit_field_symbol.value.(SymbolBitFieldValue); ok {
										construct_bit_field_field_symbol(&symbol, name, value, i)
										hover.range = symbol.range
										hover.contents = write_hover_content(&ast_context, symbol, config)
										return hover, true, true
									}
								}
							}
						}
					}
				}
			}
		}
	}

	if position_context.field_value != nil &&
	   position_in_node(position_context.field_value.field, position_context.position) {
		hover.range = common.get_token_range(position_context.field_value.field^, document.ast.src)
		if position_context.comp_lit != nil {
			if comp_symbol, ok := resolve_comp_literal(&ast_context, &position_context); ok {
				if field, ok := position_context.field_value.field.derived.(^ast.Ident); ok {
					if position_in_node(field, position_context.position) {
						if v, ok := comp_symbol.value.(SymbolStructValue); ok {
							for name, i in v.names {
								if name == field.name {
									if symbol, ok := resolve_type_expression(&ast_context, v.types[i]); ok {
										construct_struct_field_symbol(&symbol, comp_symbol.name, v, i)
										build_documentation(&ast_context, &symbol, true)
										hover.contents = write_hover_content(&ast_context, symbol, config)
										return hover, true, true
									}
								}
							}
						}
					} else if v, ok := comp_symbol.value.(SymbolBitFieldValue); ok {
						for name, i in v.names {
							if name == field.name {
								if symbol, ok := resolve_type_expression(&ast_context, v.types[i]); ok {
									construct_bit_field_field_symbol(&symbol, comp_symbol.name, v, i)
									hover.contents = write_hover_content(&ast_context, symbol, config)
									return hover, true, true
								}
							}
						}
					}
				}
			}
		}

		if position_context.call != nil {
			if symbol, ok := resolve_type_location_proc_param_name(&ast_context, &position_context); ok {
				build_documentation(&ast_context, &symbol, false)
				hover.contents = write_hover_content(&ast_context, symbol, config)
				return hover, true, true
			}
		}
	}

	if position_context.selector != nil &&
	   position_context.identifier != nil &&
	   position_context.field == position_context.identifier {
		hover.range = common.get_token_range(position_context.identifier^, ast_context.file.src)

		reset_ast_context(&ast_context)

		ast_context.current_package = ast_context.document_package

		//if the base selector is the client wants to go to.
		if base, ok := position_context.selector.derived.(^ast.Ident); ok && position_context.identifier != nil {
			ident := position_context.identifier.derived.(^ast.Ident)^

			if position_in_node(base, position_context.position) {
				if resolved, ok := resolve_type_identifier(&ast_context, ident); ok {
					build_documentation(&ast_context, &resolved, false)
					resolved.name = ident.name

					if resolved.type == .Variable {
						resolved.pkg = ast_context.document_package
					}

					hover.contents = write_hover_content(&ast_context, resolved, config)
					return hover, true, true
				}
			}
		}

		selector: Symbol

		selector, ok = resolve_type_expression(&ast_context, position_context.selector)

		if !ok {
			return hover, false, true
		}

		field: string

		if position_context.field != nil {
			#partial switch v in position_context.field.derived {
			case ^ast.Ident:
				field = v.name
			}
		}

		if v, is_proc := selector.value.(SymbolProcedureValue); is_proc {
			if len(v.return_types) == 0 || v.return_types[0].type == nil {
				return {}, false, false
			}

			set_ast_package_set_scoped(&ast_context, selector.pkg)

			if selector, ok = resolve_type_expression(&ast_context, v.return_types[0].type); !ok {
				return {}, false, true
			}
		}

		ast_context.current_package = selector.pkg

		// TODO: Use resolve_selector_expression for this?
		#partial switch v in selector.value {
		case SymbolStructValue:
			for name, i in v.names {
				if name == field {
					if symbol, ok := resolve_type_expression(&ast_context, v.types[i]); ok {
						construct_struct_field_symbol(&symbol, selector.name, v, i)
						build_documentation(&ast_context, &symbol, true)
						hover.contents = write_hover_content(&ast_context, symbol, config)
						return hover, true, true
					}
				}
			}
		case SymbolBitFieldValue:
			for name, i in v.names {
				if name == field {
					if symbol, ok := resolve_type_expression(&ast_context, v.types[i]); ok {
						construct_bit_field_field_symbol(&symbol, selector.name, v, i)
						hover.contents = write_hover_content(&ast_context, symbol, config)
						return hover, true, true
					}
				}
			}
		case SymbolPackageValue:
			if position_context.field != nil {
				if ident, ok := position_context.field.derived.(^ast.Ident); ok {
					// check to see if we are in a position call context
					if position_context.call != nil && ast_context.call == nil {
						if call, ok := position_context.call.derived.(^ast.Call_Expr); ok {
							if !position_in_exprs(call.args, position_context.position) {
								ast_context.call = call
							}
						}
					}

					if resolved, ok := resolve_symbol_return(
						&ast_context,
						lookup(ident.name, selector.pkg, ast_context.fullpath),
					); ok {
						build_documentation(&ast_context, &resolved, false)
						resolved.name = ident.name

						if resolved.type == .Variable {
							resolved.pkg = ast_context.document_package
						}


						hover.contents = write_hover_content(&ast_context, resolved, config)
						return hover, true, true
					}
				}
			}
		case SymbolEnumValue:
			for name, i in v.names {
				if name == field {
					symbol := Symbol {
						name      = selector.name,
						pkg       = selector.pkg,
						signature = get_enum_field_signature(v, i),
						type      = .Field,
					}
					hover.contents = write_hover_content(&ast_context, symbol, config)
					return hover, true, true
				}
			}
		case SymbolSliceValue:
			return get_soa_field_hover(&ast_context, selector, v.expr, nil, field, config)
		case SymbolDynamicArrayValue:
			if field == "allocator" {
				if symbol, ok := resolve_container_allocator(&ast_context, "Raw_Dynamic_Array"); ok {
					hover.contents = write_hover_content(&ast_context, symbol, config)
					return hover, true, true
				}
			}
			return get_soa_field_hover(&ast_context, selector, v.expr, nil, field, config)
		case SymbolFixedArrayValue:
			return get_soa_field_hover(&ast_context, selector, v.expr, v.len, field, config)
		case SymbolMapValue:
			if field == "allocator" {
				if symbol, ok := resolve_container_allocator(&ast_context, "Raw_Map"); ok {
					hover.contents = write_hover_content(&ast_context, symbol, config)
					return hover, true, true
				}
			}
		case SymbolBasicValue:
			if selector.name == "any" {
				name := field == "id" ? "typeid" : "rawptr"
				symbol := Symbol {
					name      = name,
					pkg       = selector.pkg,
					signature = name,
					type      = .Field,
				}
				hover.contents = write_hover_content(&ast_context, symbol, config)
				return hover, true, true
			}
		}
	} else if position_context.implicit_selector_expr != nil {
		implicit_selector := position_context.implicit_selector_expr
		if symbol, ok := resolve_implicit_selector(&ast_context, &position_context); ok {
			#partial switch v in symbol.value {
			case SymbolEnumValue:
				for name, i in v.names {
					if strings.compare(name, implicit_selector.field.name) == 0 {
						construct_enum_field_symbol(&symbol, v, i)
						hover.contents = write_hover_content(&ast_context, symbol, config)
						return hover, true, true
					}
				}
			case SymbolUnionValue:
				for type in v.types {
					enum_symbol := resolve_type_expression(&ast_context, type) or_continue
					v := enum_symbol.value.(SymbolEnumValue) or_continue
					for name, i in v.names {
						if strings.compare(name, implicit_selector.field.name) == 0 {
							construct_enum_field_symbol(&enum_symbol, v, i)
							hover.contents = write_hover_content(&ast_context, enum_symbol, config)
							return hover, true, true
						}
					}
				}
			case SymbolBitSetValue:
				if enum_symbol, ok := resolve_type_expression(&ast_context, v.expr); ok {
					if v, ok := enum_symbol.value.(SymbolEnumValue); ok {
						for name, i in v.names {
							if strings.compare(name, implicit_selector.field.name) == 0 {
								construct_enum_field_symbol(&enum_symbol, v, i)
								hover.contents = write_hover_content(&ast_context, enum_symbol, config)
								return hover, true, true
							}
						}
					}
				}

				if hover, ok := get_hover_enum_field(&ast_context, symbol, implicit_selector.field.name, config); ok {
					hover.range = common.get_token_range(implicit_selector, document.ast.src)
					return hover, true, true
				}
			}
			return {}, false, true
		}} else if position_context.identifier != nil {
		reset_ast_context(&ast_context)

		ast_context.current_package = ast_context.document_package

		ident := position_context.identifier.derived.(^ast.Ident)^

		if position_context.value_decl != nil {
			ident.pos = position_context.value_decl.end
			ident.end = position_context.value_decl.end
		}

		hover.range = common.get_token_range(position_context.identifier^, document.ast.src)

		if position_context.call != nil {
			if call, ok := position_context.call.derived.(^ast.Call_Expr); ok {
				if !position_in_exprs(call.args, position_context.position) {
					ast_context.call = call
				}
			}
		}

		if resolved, ok := resolve_type_identifier(&ast_context, ident); ok {
			if position_context.enum_type != nil {
				if hover, ok := get_hover_enum_field(&ast_context, resolved, ident.name, config); ok {
					return hover, true, true
				}
			}
			construct_ident_symbol_info(&resolved, ident.name, ast_context.document_package)

			build_documentation(&ast_context, &resolved, false)
			hover.contents = write_hover_content(&ast_context, resolved, config)
			return hover, true, true
		}
	}

	return hover, false, true
}

get_hover_enum_field :: proc(
	ast_context: ^AstContext,
	symbol: Symbol,
	field_name: string,
	config: ^common.Config,
) -> (
	Hover,
	bool,
) {
	symbol := symbol
	hover: Hover
	#partial switch v in symbol.value {
	case SymbolEnumValue:
		for name, i in v.names {
			if strings.compare(name, field_name) == 0 {
				construct_enum_field_symbol(&symbol, v, i)
				hover.contents = write_hover_content(ast_context, symbol, config)
				return hover, true
			}
		}
	case SymbolUnionValue:
		for type in v.types {
			enum_symbol := resolve_type_expression(ast_context, type) or_continue
			v := enum_symbol.value.(SymbolEnumValue) or_continue
			for name, i in v.names {
				if strings.compare(name, field_name) == 0 {
					construct_enum_field_symbol(&enum_symbol, v, i)
					hover.contents = write_hover_content(ast_context, enum_symbol, config)
					return hover, true
				}
			}
		}
	case SymbolBitSetValue:
		if enum_symbol, ok := resolve_type_expression(ast_context, v.expr); ok {
			if v, ok := enum_symbol.value.(SymbolEnumValue); ok {
				for name, i in v.names {
					if strings.compare(name, field_name) == 0 {
						construct_enum_field_symbol(&enum_symbol, v, i)
						hover.contents = write_hover_content(ast_context, enum_symbol, config)
						return hover, true
					}
				}
			}
		}
	}

	return {}, false
}

@(private = "file")
get_soa_field_hover :: proc(
	ast_context: ^AstContext,
	selector: Symbol,
	expr: ^ast.Expr,
	size: ^ast.Expr,
	field: string,
	config: ^common.Config,
) -> (
	Hover,
	bool,
	bool,
) {
	if .SoaPointer not_in selector.flags && .Soa not_in selector.flags {
		return {}, false, true
	}
	if symbol, ok := resolve_soa_selector_field(ast_context, selector, expr, size, field); ok {
		if selector.name != "" {
			symbol.parent_name = selector.name
		}
		symbol.name = field
		build_documentation(ast_context, &symbol, false)
		hover: Hover
		hover.contents = write_hover_content(ast_context, symbol, config)
		return hover, true, true
	}
	return {}, false, true
}

@(private = "file")
get_field_parent_name :: proc(value_decl_symbol, symbol: Symbol) -> string {
	if value_decl_symbol.range != symbol.range {
		return symbol.name
	}
	return value_decl_symbol.name
}
