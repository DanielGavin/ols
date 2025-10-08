package server

import "core:fmt"
import "core:hash"
import "core:log"
import "core:mem"
import "core:odin/ast"
import "core:path/filepath"
import path "core:path/slashpath"
import "core:strconv"
import "core:strings"

import "src:common"

SymbolCollection :: struct {
	allocator:      mem.Allocator,
	config:         ^common.Config,
	packages:       map[string]SymbolPackage,
	unique_strings: map[string]string, //store all our strings as unique strings and reference them to save memory.
}

ObjcFunction :: struct {
	physical_name: string,
	logical_name:  string,
}

ObjcStruct :: struct {
	functions: [dynamic]ObjcFunction,
	pkg:       string,
	ranges:    [dynamic]common.Range,
}

Method :: struct {
	pkg:  string,
	name: string,
}

SymbolPackage :: struct {
	symbols:      map[string]Symbol,
	objc_structs: map[string]ObjcStruct, //mapping from struct name to function
	methods:      map[Method][dynamic]Symbol,
	imports:      [dynamic]string, //Used for references to figure whether the package is even able to reference the symbol
}

get_index_unique_string :: proc {
	get_index_unique_string_collection,
	get_index_unique_string_collection_raw,
}

get_index_unique_string_collection :: proc(collection: ^SymbolCollection, s: string) -> string {
	return get_index_unique_string_collection_raw(&collection.unique_strings, collection.allocator, s)
}

get_index_unique_string_collection_raw :: proc(
	unique_strings: ^map[string]string,
	allocator: mem.Allocator,
	s: string,
) -> string {
	if _, ok := unique_strings[s]; !ok {
		str := strings.clone(s, allocator)
		unique_strings[str] = str
	}

	return unique_strings[s]
}

make_symbol_collection :: proc(allocator := context.allocator, config: ^common.Config) -> SymbolCollection {
	return SymbolCollection {
		allocator = allocator,
		config = config,
		packages = make(map[string]SymbolPackage, 16, allocator),
		unique_strings = make(map[string]string, 16, allocator),
	}
}

delete_symbol_collection :: proc(collection: SymbolCollection) {
	free_all(collection.allocator)
}

collect_procedure_fields :: proc(
	collection: ^SymbolCollection,
	proc_type: ^ast.Proc_Type,
	arg_list: ^ast.Field_List,
	return_list: ^ast.Field_List,
	package_map: map[string]string,
	attributes: []^ast.Attribute,
	inlining: ast.Proc_Inlining,
	where_clauses: []^ast.Expr,
) -> (value: SymbolProcedureValue) {

	returns := return_list.list if return_list != nil else {}
	args := arg_list.list if arg_list != nil else {}

	for ret in returns {
		collection_clone_node_strings(collection, ret)
		replace_package_alias(ret, package_map, collection)
	}

	for arg in args {
		collection_clone_node_strings(collection, arg)
		replace_package_alias(arg, package_map, collection)
	}

	for attr in attributes {
		collection_clone_node_strings(collection, attr)
	}

	for clause in where_clauses {
		collection_clone_node_strings(collection, clause)
	}

	return {
		return_types       = returns,
		orig_return_types  = returns,
		arg_types          = args,
		orig_arg_types     = args,
		generic            = is_procedure_generic(proc_type),
		diverging          = proc_type.diverging,
		calling_convention = clone_calling_convention(
			proc_type.calling_convention,
			collection.allocator,
			&collection.unique_strings,
		),
		tags               = proc_type.tags,
		attributes         = attributes,
		inlining           = inlining,
		where_clauses      = where_clauses,
	}
}

collect_struct_fields :: proc(
	collection: ^SymbolCollection,
	struct_type: ^ast.Struct_Type,
	package_map: map[string]string,
	file: ast.File,
) -> SymbolStructValue {
	b := symbol_struct_value_builder_make(collection.allocator)
	construct_struct_field_docs(file, struct_type, collection.allocator)

	for field in struct_type.fields.list {
		for n in field.names {
			ident := n.derived.(^ast.Ident) or_continue

			append(&b.names, get_index_unique_string(collection, ident.name))

			collection_clone_node_strings(collection, field.type)
			replace_package_alias(field.type, package_map, collection)
			append(&b.types, field.type)

			if .Using in field.flags {
				append(&b.unexpanded_usings, len(b.names) - 1)
				b.usings[len(b.names) - 1] = struct{}{}
			}

			append(&b.ranges, common.get_token_range(n, file.src))

			collection_clone_node_strings(collection, field.docs)
			append(&b.docs, field.docs)

			collection_clone_node_strings(collection, field.comment)
			append(&b.comments, field.comment)
			append(&b.from_usings, -1)
		}
	}

	collection_clone_node_strings(collection, struct_type.align)
	collection_clone_node_strings(collection, struct_type.max_field_align)
	collection_clone_node_strings(collection, struct_type.min_field_align)
	collection_clone_node_strings(collection, struct_type.poly_params)

	b.align           = struct_type.align
	b.max_field_align = struct_type.max_field_align
	b.min_field_align = struct_type.min_field_align
	b.poly            = struct_type.poly_params

	if struct_type.is_no_copy   do b.tags |= {.Is_No_Copy}
	if struct_type.is_packed    do b.tags |= {.Is_Packed}
	if struct_type.is_raw_union do b.tags |= {.Is_Raw_Union}

	for clause in struct_type.where_clauses {
		collection_clone_node_strings(collection, clause)
		append(&b.where_clauses, clause)
	}
	value := to_symbol_struct_value(b)

	return value
}

collect_bit_field_fields :: proc(
	collection: ^SymbolCollection,
	bit_field_type: ^ast.Bit_Field_Type,
	package_map: map[string]string,
	file: ast.File,
) -> SymbolBitFieldValue {
	context.allocator = collection.allocator

	construct_bit_field_field_docs(file, bit_field_type, collection.allocator)

	names := make([]string, len(bit_field_type.fields))
	ranges := make([]common.Range, len(bit_field_type.fields))
	types := make([]^ast.Expr, len(bit_field_type.fields))
	docs := make([]^ast.Comment_Group, len(bit_field_type.fields))
	comments := make([]^ast.Comment_Group, len(bit_field_type.fields))
	bit_sizes := make([]^ast.Expr, len(bit_field_type.fields))

	#no_bounds_check for field, i in bit_field_type.fields {
		collection_clone_node_strings(collection, field.type)
		replace_package_alias(field.type, package_map, collection)

		collection_clone_node_strings(collection, field.docs)
		collection_clone_node_strings(collection, field.comments)
		collection_clone_node_strings(collection, field.bit_size)

		types[i] = field.type
		docs[i] = field.docs
		comments[i] = field.comments
		bit_sizes[i] = field.bit_size

		ident := field.name.derived.(^ast.Ident) or_continue
		names[i] = get_index_unique_string(collection, ident.name)
		ranges[i] = common.get_token_range(ident, file.src)
	}

	collection_clone_node_strings(collection, bit_field_type.backing_type)

	return {
		backing_type = bit_field_type.backing_type,
		names        = names[:],
		types        = types[:],
		ranges       = ranges[:],
		docs         = docs[:],
		comments     = comments[:],
		bit_sizes    = bit_sizes[:],
	}
}

collect_enum_fields :: proc(
	collection: ^SymbolCollection,
	enum_type: ast.Enum_Type,
	package_map: map[string]string,
	file: ast.File,
) -> SymbolEnumValue {
	context.allocator = collection.allocator

	names := make([]string, len(enum_type.fields))
	ranges := make([]common.Range, len(enum_type.fields))
	values := make([]^ast.Expr, len(enum_type.fields))

	#no_bounds_check for n, i in enum_type.fields {
		name, range, field_value := get_enum_field_name_range_value(n, file.src)
		collection_clone_node_strings(collection, field_value)

		names[i] = strings.clone(name)
		ranges[i] = range
		values[i] = field_value
	}

	docs, comments := get_field_docs_and_comments(file, enum_type.fields, collection.allocator)

	for doc in docs {
		collection_clone_node_strings(collection, doc)
	}
	for comment in comments {
		collection_clone_node_strings(collection, comment)
	}

	collection_clone_node_strings(collection, enum_type.base_type)

	return {
		names     = names[:],
		ranges    = ranges[:],
		values    = values[:],
		base_type = enum_type.base_type,
		comments  = comments[:],
		docs      = docs[:],
	}
}

collect_union_fields :: proc(
	collection: ^SymbolCollection,
	union_type: ast.Union_Type,
	package_map: map[string]string,
	file: ast.File,
) -> SymbolUnionValue {
	context.allocator = collection.allocator

	types := union_type.variants

	for type in types {
		collection_clone_node_strings(collection, type)
		replace_package_alias(type, package_map, collection)
	}

	docs, comments := get_field_docs_and_comments(file, union_type.variants, collection.allocator)

	for doc in docs {
		collection_clone_node_strings(collection, doc)
	}
	for comment in comments {
		collection_clone_node_strings(collection, comment)
	}

	collection_clone_node_strings(collection, union_type.poly_params)
	collection_clone_node_strings(collection, union_type.align)

	for clause in union_type.where_clauses {
		collection_clone_node_strings(collection, clause)
	}

	return {
		types         = types[:],
		poly          = union_type.poly_params,
		comments      = comments[:],
		docs          = docs[:],
		kind          = union_type.kind,
		align         = union_type.align,
		where_clauses = union_type.where_clauses,
	}
}

collect_bitset_field :: proc(
	collection: ^SymbolCollection,
	bitset_type: ast.Bit_Set_Type,
	package_map: map[string]string,
) -> SymbolBitSetValue {
	collection_clone_node_strings(collection, bitset_type.elem)
	replace_package_alias(bitset_type.elem, package_map, collection)

	return SymbolBitSetValue{expr = bitset_type.elem}
}

collect_slice :: proc(
	collection: ^SymbolCollection,
	array: ast.Array_Type,
	package_map: map[string]string,
) -> SymbolSliceValue {
	collection_clone_node_strings(collection, array.elem)
	replace_package_alias(array.elem, package_map, collection)

	return SymbolSliceValue{expr = array.elem}
}

collect_array :: proc(
	collection: ^SymbolCollection,
	array: ast.Array_Type,
	package_map: map[string]string,
) -> SymbolFixedArrayValue {
	collection_clone_node_strings(collection, array.elem)
	collection_clone_node_strings(collection, array.len)

	replace_package_alias(array.elem, package_map, collection)
	replace_package_alias(array.len, package_map, collection)

	return SymbolFixedArrayValue{expr = array.elem, len = array.len}
}

collect_map :: proc(collection: ^SymbolCollection, m: ast.Map_Type, package_map: map[string]string) -> SymbolMapValue {
	collection_clone_node_strings(collection, m.key)
	collection_clone_node_strings(collection, m.value)

	replace_package_alias(m.key, package_map, collection)
	replace_package_alias(m.value, package_map, collection)

	return SymbolMapValue{key = m.key, value = m.value}
}

collect_dynamic_array :: proc(
	collection: ^SymbolCollection,
	array: ast.Dynamic_Array_Type,
	package_map: map[string]string,
) -> SymbolDynamicArrayValue {
	collection_clone_node_strings(collection, array.elem)
	replace_package_alias(array.elem, package_map, collection)

	return SymbolDynamicArrayValue{expr = array.elem}
}

collect_matrix :: proc(
	collection: ^SymbolCollection,
	mat: ast.Matrix_Type,
	package_map: map[string]string,
) -> SymbolMatrixValue {
	collection_clone_node_strings(collection, mat.elem)
	collection_clone_node_strings(collection, mat.column_count)
	collection_clone_node_strings(collection, mat.row_count)

	replace_package_alias(mat.elem, package_map, collection)
	replace_package_alias(mat.row_count, package_map, collection)
	replace_package_alias(mat.column_count, package_map, collection)

	return SymbolMatrixValue{expr = mat.elem, x = mat.row_count, y = mat.column_count}
}

collect_multi_pointer :: proc(
	collection: ^SymbolCollection,
	array: ast.Multi_Pointer_Type,
	package_map: map[string]string,
) -> SymbolMultiPointerValue {
	collection_clone_node_strings(collection, array.elem)
	replace_package_alias(array.elem, package_map, collection)

	return SymbolMultiPointerValue{expr = array.elem}
}


collect_generic :: proc(
	collection: ^SymbolCollection,
	expr: ^ast.Expr,
	package_map: map[string]string,
	uri: string,
) -> SymbolGenericValue {
	//Bit hacky right now, but it's hopefully a temporary solution.
	//In the c package code it uses a documentation package(builtin).
	if selector, ok := expr.derived.(^ast.Selector_Expr); ok {
		if ident, ok := selector.expr.derived.(^ast.Ident); ok {
			if ident.name == "builtin" && strings.contains(uri, "/core/c/c.odin") {
				collection_clone_node_strings(collection, selector.field)
				replace_package_alias(selector.field, package_map, collection)
				value := SymbolGenericValue {
					expr = selector.field,
				}
				return value
			}
		}
	}

	collection_clone_node_strings(collection, expr)
	replace_package_alias(expr, package_map, collection)

	value := SymbolGenericValue {
		expr = expr,
	}

	return value
}

add_comp_lit_fields :: proc(
	collection: ^SymbolCollection,
	generic: ^SymbolGenericValue,
	comp_lit_type: ^ast.Comp_Lit,
	package_map: map[string]string,
	file: ast.File,
) {
	names := make([dynamic]string, 0, len(comp_lit_type.elems), collection.allocator)
	ranges := make([dynamic]common.Range, 0, len(comp_lit_type.elems), collection.allocator)
	for elem in comp_lit_type.elems {
		if field_value, ok := elem.derived.(^ast.Field_Value); ok {
			if ident, ok := field_value.field.derived.(^ast.Ident); ok {
				name := get_index_unique_string(collection, ident.name)
				append(&names, name)
				append(&ranges, common.get_token_range(field_value, file.src))
			}
		}
	}
	generic.field_names = names[:]
	generic.ranges = ranges[:]
}

collect_method :: proc(collection: ^SymbolCollection, symbol: Symbol) {
	pkg := &collection.packages[symbol.pkg]

	if value, ok := symbol.value.(SymbolProcedureValue); ok {
		if len(value.arg_types) == 0 {
			return
		}

		expr, _, ok := unwrap_pointer_ident(value.arg_types[0].type)

		if !ok {
			return
		}

		method: Method

		#partial switch v in expr.derived {
		case ^ast.Selector_Expr:
			if ident, ok := v.expr.derived.(^ast.Ident); ok {
				method.pkg = get_index_unique_string(collection, ident.name)
				method.name = get_index_unique_string(collection, v.field.name)
			} else {
				return
			}
		case ^ast.Ident:
			method.pkg = symbol.pkg
			method.name = get_index_unique_string(collection, v.name)
		case:
			return
		}

		symbols := &pkg.methods[method]

		if symbols == nil {
			pkg.methods[method] = make([dynamic]Symbol, collection.allocator)
			symbols = &pkg.methods[method]
		}

		append(symbols, symbol)
	}
}

collect_objc :: proc(collection: ^SymbolCollection, attributes: []^ast.Attribute, symbol: Symbol) {
	pkg := &collection.packages[symbol.pkg]

	if value, ok := symbol.value.(SymbolProcedureValue); ok {
		objc_name, found_objc_name := get_attribute_objc_name(attributes)

		if objc_type := get_attribute_objc_type(attributes); objc_type != nil && found_objc_name {

			if struct_ident, ok := objc_type.derived.(^ast.Ident); ok {
				struct_name := get_index_unique_string_collection(collection, struct_ident.name)

				objc_struct := &pkg.objc_structs[struct_name]

				if objc_struct == nil {
					pkg.objc_structs[struct_name] = {}
					objc_struct = &pkg.objc_structs[struct_name]
					objc_struct.functions = make([dynamic]ObjcFunction, 0, 10, collection.allocator)
					objc_struct.ranges = make([dynamic]common.Range, 0, 10, collection.allocator)
					objc_struct.pkg = symbol.pkg
				}

				append(&objc_struct.ranges, symbol.range)

				append(
					&objc_struct.functions,
					ObjcFunction {
						logical_name = get_index_unique_string_collection(collection, objc_name),
						physical_name = symbol.name,
					},
				)
			}
		}
	}
}

collect_imports :: proc(collection: ^SymbolCollection, file: ast.File, directory: string) {
	_pkg := get_index_unique_string(collection, directory)

	if _pkg, ok := collection.packages[_pkg]; ok {

	}

}


collect_symbols :: proc(collection: ^SymbolCollection, file: ast.File, uri: string) -> common.Error {
	forward, _ := filepath.to_slash(file.fullpath, context.temp_allocator)
	directory := path.dir(forward, context.temp_allocator)
	package_map := get_package_mapping(file, collection.config, directory)
	exprs := collect_globals(file)

	for expr in exprs {
		symbol: Symbol

		token: ast.Node
		token_type: SymbolType

		name := expr.name

		col_expr := expr.expr

		if helper, ok := col_expr.derived.(^ast.Helper_Type); ok {
			if helper.type != nil {
				col_expr = helper.type
			}
		}
		is_distinct := false

		if dist, ok := col_expr.derived.(^ast.Distinct_Type); ok {
			if dist.type != nil {
				col_expr = dist.type
				is_distinct = true
			}
		}

		#partial switch v in col_expr.derived {
		case ^ast.Matrix_Type:
			token = v^
			token_type = .Type
			symbol.value = collect_matrix(collection, v^, package_map)
		case ^ast.Proc_Lit:
			token = v^
			token_type = .Function

			if v.type != nil {
				symbol.value = collect_procedure_fields(
					collection,
					v.type,
					v.type.params,
					v.type.results,
					package_map,
					expr.attributes,
					v.inlining,
					v.where_clauses,
				)
			}

			if _, is_objc := get_attribute_objc_name(expr.attributes); is_objc {
				symbol.flags |= {.ObjC}
				if get_attribute_objc_is_class_method(expr.attributes) {
					symbol.flags |= {.ObjCIsClassMethod}
				}
			}
		case ^ast.Proc_Type:
			token = v^
			token_type = .Type_Function
			symbol.value = collect_procedure_fields(
				collection,
				cast(^ast.Proc_Type)col_expr,
				v.params,
				v.results,
				package_map,
				expr.attributes,
				.None,
				nil,
			)
		case ^ast.Proc_Group:
			token = v^
			token_type = .Function
			collection_clone_node_strings(collection, col_expr)
			symbol.value = SymbolProcedureGroupValue {
				group = col_expr,
			}
		case ^ast.Struct_Type:
			token = v^
			token_type = .Struct
			symbol.value = collect_struct_fields(collection, v, package_map, file)
			symbol.signature = "struct"

			if _, is_objc := get_attribute_objc_class_name(expr.attributes); is_objc {
				symbol.flags |= {.ObjC}
				if get_attribute_objc_is_class_method(expr.attributes) {
					symbol.flags |= {.ObjCIsClassMethod}
				}
			}
		case ^ast.Enum_Type:
			token = v^
			token_type = .Enum
			symbol.value = collect_enum_fields(collection, v^, package_map, file)
			symbol.signature = "enum"
		case ^ast.Union_Type:
			token = v^
			token_type = .Union
			symbol.value = collect_union_fields(collection, v^, package_map, file)
			symbol.signature = "union"
		case ^ast.Bit_Set_Type:
			token = v^
			token_type = .Enum
			symbol.value = collect_bitset_field(collection, v^, package_map)
			symbol.signature = "bitset"
		case ^ast.Bit_Field_Type:
			token = v^
			token_type = .Struct
			symbol.value = collect_bit_field_fields(collection, v, package_map, file)
			symbol.signature = "bit_field"
		case ^ast.Map_Type:
			token = v^
			token_type = .Type
			symbol.value = collect_map(collection, v^, package_map)
		case ^ast.Array_Type:
			token = v^
			token_type = .Type
			if v.len == nil {
				symbol.value = collect_slice(collection, v^, package_map)
			} else {
				symbol.value = collect_array(collection, v^, package_map)
			}
		case ^ast.Dynamic_Array_Type:
			token = v^
			token_type = .Type
			symbol.value = collect_dynamic_array(collection, v^, package_map)
		case ^ast.Multi_Pointer_Type:
			token = v^
			token_type = .Type
			symbol.value = collect_multi_pointer(collection, v^, package_map)
		case ^ast.Typeid_Type:
			if v.specialization == nil {
				continue
			}

			ident := new_type(ast.Ident, v.pos, v.end, context.temp_allocator)
			ident.name = "typeid"

			symbol.value = collect_generic(collection, ident, package_map, uri)
		case ^ast.Basic_Lit:
			token = v^
			symbol.value = collect_generic(collection, col_expr, package_map, uri)
			token_type = .Unresolved
		case ^ast.Ident:
			token = v^
			symbol.value = collect_generic(collection, col_expr, package_map, uri)

			if .Mutable in expr.flags {
				token_type = .Variable
			} else {
				token_type = .Unresolved
			}
		case ^ast.Comp_Lit:
			generic := collect_generic(collection, col_expr, package_map, uri)

			if .Mutable in expr.flags {
				token_type = .Variable
			} else {
				token_type = .Unresolved
			}

			token = expr.expr

			add_comp_lit_fields(collection, &generic, v, package_map, file)
			symbol.value = generic
		case:
			// default
			symbol.value = collect_generic(collection, col_expr, package_map, uri)

			if .Mutable in expr.flags {
				token_type = .Variable
			} else {
				token_type = .Unresolved
			}

			token = expr.expr
		}


		symbol.range = common.get_token_range(expr.name_expr, file.src)
		symbol.name = get_index_unique_string(collection, name)
		symbol.type = token_type
		symbol.doc = get_doc(expr.name_expr, expr.docs, collection.allocator)
		symbol.uri = get_index_unique_string(collection, uri)
		collection_clone_node_strings(collection, expr.type_expr)
		symbol.type_expr = expr.type_expr

		collection_clone_node_strings(collection, expr.value_expr)
		symbol.value_expr = expr.value_expr
		comment, _ := get_file_comment(file, symbol.range.start.line + 1)
		symbol.comment = strings.clone(get_comment(comment), collection.allocator)

		if expr.builtin || strings.contains(uri, "builtin.odin") {
			symbol.pkg = "$builtin"
		} else if strings.contains(uri, "intrinsics.odin") {
			path := filepath.join(
				elems = {common.config.collections["base"], "/intrinsics"},
				allocator = context.temp_allocator,
			)

			path, _ = filepath.to_slash(path, context.temp_allocator)

			symbol.pkg = get_index_unique_string(collection, path)
		} else {
			symbol.pkg = get_index_unique_string(collection, directory)
		}

		if is_distinct {
			symbol.flags |= {.Distinct}
		}

		if expr.deprecated {
			symbol.flags |= {.Deprecated}
		}

		if expr.private == .File {
			symbol.flags |= {.PrivateFile}
		}

		if expr.private == .Package {
			symbol.flags |= {.PrivatePackage}
		}

		if .Variable in expr.flags {
			symbol.flags |= {.Variable}
		}

		if .Mutable in expr.flags {
			symbol.flags |= {.Mutable}
		}

		pkg: ^SymbolPackage
		ok: bool

		if pkg, ok = &collection.packages[symbol.pkg]; !ok {
			collection.packages[symbol.pkg] = {}
			pkg = &collection.packages[symbol.pkg]
			pkg.symbols = make(map[string]Symbol, 100, collection.allocator)
			pkg.methods = make(map[Method][dynamic]Symbol, 100, collection.allocator)
			pkg.objc_structs = make(map[string]ObjcStruct, 5, collection.allocator)
		}

		if .ObjC in symbol.flags {
			collect_objc(collection, expr.attributes, symbol)
		}

		if symbol.type == .Function && common.config.enable_fake_method {
			collect_method(collection, symbol)
		}

		if v, ok := pkg.symbols[symbol.name]; !ok || v.name == "" {
			pkg.symbols[symbol.name] = symbol
		} else {
			free_symbol(symbol, collection.allocator)
		}
	}

	collect_imports(collection, file, directory)


	return .None
}

Reference :: struct {
	identifiers: [dynamic]common.Location,
	selectors:   map[string][dynamic]common.Range,
}

/*
	Gets the map from import alias to absolute package directory
*/
get_package_mapping :: proc(file: ast.File, config: ^common.Config, directory: string) -> map[string]string {
	package_map := make(map[string]string, 0, context.temp_allocator)

	for imp, index in file.imports {
		//collection specified
		if len(imp.fullpath) < 2 {
			continue
		}

		if i := strings.index(imp.fullpath, ":"); i != -1 && i != len(imp.fullpath) - 1 {
			collection := imp.fullpath[1:i]
			p := imp.fullpath[i + 1:len(imp.fullpath) - 1]

			dir, ok := config.collections[collection]

			if !ok {
				continue
			}

			name: string

			full := path.join(elems = {dir, p}, allocator = context.temp_allocator)

			if imp.name.text != "" {
				name = imp.name.text
			} else {
				name = path.base(full, false, context.temp_allocator)
			}

			package_map[name] = full
		} else {
			name: string

			full := path.join(
				elems = {directory, imp.fullpath[1:len(imp.fullpath) - 1]},
				allocator = context.temp_allocator,
			)
			full = path.clean(full, context.temp_allocator)

			if imp.name.text != "" {
				name = imp.name.text
			} else {
				name = path.base(full, false, context.temp_allocator)
			}

			package_map[name] = full
		}
	}

	return package_map
}

/*
	We can't have the alias names for packages with selector expression since that is specific to every files import, instead just replace it with the absolute
	package name(absolute directory path)
*/

replace_package_alias :: proc {
	replace_package_alias_node,
	replace_package_alias_expr,
	replace_package_alias_array,
	replace_package_alias_dynamic_array,
}

replace_package_alias_array :: proc(array: $A/[]^$T, package_map: map[string]string, collection: ^SymbolCollection) {
	for elem, i in array {
		replace_package_alias(elem, package_map, collection)
	}
}

replace_package_alias_dynamic_array :: proc(
	array: $A/[dynamic]^$T,
	package_map: map[string]string,
	collection: ^SymbolCollection,
) {
	for elem, i in array {
		replace_package_alias(elem, package_map, collection)
	}
}

replace_package_alias_expr :: proc(node: ^ast.Expr, package_map: map[string]string, collection: ^SymbolCollection) {
	replace_package_alias_node(node, package_map, collection)
}

replace_package_alias_node :: proc(node: ^ast.Node, package_map: map[string]string, collection: ^SymbolCollection) {
	using ast

	if node == nil {
		return
	}

	#partial switch n in node.derived {
	case ^Bad_Expr:
	case ^Ident:
	case ^Implicit:
	case ^Undef:
	case ^Basic_Lit:
	case ^Basic_Directive:
	case ^Ellipsis:
		replace_package_alias(n.expr, package_map, collection)
	case ^Tag_Expr:
		replace_package_alias(n.expr, package_map, collection)
	case ^Unary_Expr:
		replace_package_alias(n.expr, package_map, collection)
	case ^Binary_Expr:
		replace_package_alias(n.left, package_map, collection)
		replace_package_alias(n.right, package_map, collection)
	case ^Paren_Expr:
		replace_package_alias(n.expr, package_map, collection)
	case ^Selector_Expr:
		if _, ok := n.expr.derived.(^Ident); ok {
			ident := n.expr.derived.(^Ident)

			if package_name, ok := package_map[ident.name]; ok {
				ident.name = get_index_unique_string(collection, package_name)
			}
		} else {
			replace_package_alias(n.expr, package_map, collection)
			replace_package_alias(n.field, package_map, collection)
		}
	case ^Implicit_Selector_Expr:
		replace_package_alias(n.field, package_map, collection)
	case ^Slice_Expr:
		replace_package_alias(n.expr, package_map, collection)
		replace_package_alias(n.low, package_map, collection)
		replace_package_alias(n.high, package_map, collection)
	case ^Attribute:
		replace_package_alias(n.elems, package_map, collection)
	case ^Distinct_Type:
		replace_package_alias(n.type, package_map, collection)
	case ^Proc_Type:
		replace_package_alias(n.params, package_map, collection)
		replace_package_alias(n.results, package_map, collection)
	case ^Pointer_Type:
		replace_package_alias(n.elem, package_map, collection)
	case ^Array_Type:
		replace_package_alias(n.len, package_map, collection)
		replace_package_alias(n.elem, package_map, collection)
	case ^Dynamic_Array_Type:
		replace_package_alias(n.elem, package_map, collection)
	case ^Struct_Type:
		replace_package_alias(n.poly_params, package_map, collection)
		replace_package_alias(n.align, package_map, collection)
		replace_package_alias(n.fields, package_map, collection)
	case ^Field:
		replace_package_alias(n.names, package_map, collection)
		replace_package_alias(n.type, package_map, collection)
		replace_package_alias(n.default_value, package_map, collection)
	case ^Field_List:
		replace_package_alias(n.list, package_map, collection)
	case ^Field_Value:
		replace_package_alias(n.field, package_map, collection)
		replace_package_alias(n.value, package_map, collection)
	case ^Union_Type:
		replace_package_alias(n.poly_params, package_map, collection)
		replace_package_alias(n.align, package_map, collection)
		replace_package_alias(n.variants, package_map, collection)
	case ^Enum_Type:
		replace_package_alias(n.base_type, package_map, collection)
		replace_package_alias(n.fields, package_map, collection)
	case ^Bit_Set_Type:
		replace_package_alias(n.elem, package_map, collection)
		replace_package_alias(n.underlying, package_map, collection)
	case ^Map_Type:
		replace_package_alias(n.key, package_map, collection)
		replace_package_alias(n.value, package_map, collection)
	case ^Call_Expr:
		replace_package_alias(n.expr, package_map, collection)
		replace_package_alias(n.args, package_map, collection)
	case ^Typeid_Type:
		replace_package_alias(n.specialization, package_map, collection)
	case ^Poly_Type:
		replace_package_alias(n.type, package_map, collection)
		replace_package_alias(n.specialization, package_map, collection)
	case ^Proc_Group:
		replace_package_alias(n.args, package_map, collection)
	case ^Comp_Lit:
		replace_package_alias(n.type, package_map, collection)
		replace_package_alias(n.elems, package_map, collection)
	case ^Helper_Type:
		replace_package_alias(n.type, package_map, collection)
	case ^Proc_Lit:
	case ^Multi_Pointer_Type:
		replace_package_alias(n.elem, package_map, collection)
	case ^Bit_Field_Type:
		replace_package_alias(n.backing_type, package_map, collection)
		replace_package_alias(n.fields, package_map, collection)
	case ^Bit_Field_Field:
		replace_package_alias(n.name, package_map, collection)
		replace_package_alias(n.type, package_map, collection)
		replace_package_alias(n.bit_size, package_map, collection)
	case:
	}
}
