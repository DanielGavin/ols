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
}

get_index_unique_string :: proc {
	get_index_unique_string_collection,
	get_index_unique_string_collection_raw,
}

get_index_unique_string_collection :: proc(
	collection: ^SymbolCollection,
	s: string,
) -> string {
	return get_index_unique_string_collection_raw(
		&collection.unique_strings,
		collection.allocator,
		s,
	)
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

make_symbol_collection :: proc(
	allocator := context.allocator,
	config: ^common.Config,
) -> SymbolCollection {
	return(
		SymbolCollection {
			allocator = allocator,
			config = config,
			packages = make(map[string]SymbolPackage, 16, allocator),
			unique_strings = make(map[string]string, 16, allocator),
		} \
	)
}

delete_symbol_collection :: proc(collection: SymbolCollection) {
	for k, v in collection.packages {
		for k2, v2 in v.symbols {
			free_symbol(v2, collection.allocator)
		}
	}

	for k, v in collection.unique_strings {
		delete(v, collection.allocator)
	}

	for k, v in collection.packages {
		delete(v.symbols)
	}

	delete(collection.packages)
	delete(collection.unique_strings)
}

collect_procedure_fields :: proc(
	collection: ^SymbolCollection,
	proc_type: ^ast.Proc_Type,
	arg_list: ^ast.Field_List,
	return_list: ^ast.Field_List,
	package_map: map[string]string,
	attributes: []^ast.Attribute,
) -> SymbolProcedureValue {
	returns := make([dynamic]^ast.Field, 0, collection.allocator)
	args := make([dynamic]^ast.Field, 0, collection.allocator)

	if return_list != nil {
		for ret in return_list.list {
			cloned := cast(^ast.Field)clone_type(
				ret,
				collection.allocator,
				&collection.unique_strings,
			)
			replace_package_alias(cloned, package_map, collection)
			append(&returns, cloned)
		}
	}

	if arg_list != nil {
		for arg in arg_list.list {
			cloned := cast(^ast.Field)clone_type(
				arg,
				collection.allocator,
				&collection.unique_strings,
			)
			replace_package_alias(cloned, package_map, collection)
			append(&args, cloned)
		}
	}

	value := SymbolProcedureValue {
		return_types = returns[:],
		arg_types    = args[:],
		generic      = is_procedure_generic(proc_type),
	}

	return value
}

collect_struct_fields :: proc(
	collection: ^SymbolCollection,
	struct_type: ast.Struct_Type,
	package_map: map[string]string,
	file: ast.File,
) -> SymbolStructValue {
	names := make([dynamic]string, 0, collection.allocator)
	types := make([dynamic]^ast.Expr, 0, collection.allocator)
	usings := make(map[int]bool, 0, collection.allocator)
	ranges := make([dynamic]common.Range, 0, collection.allocator)

	for field in struct_type.fields.list {
		for n in field.names {
			ident := n.derived.(^ast.Ident)
			append(&names, get_index_unique_string(collection, ident.name))

			cloned := clone_type(
				field.type,
				collection.allocator,
				&collection.unique_strings,
			)
			replace_package_alias(cloned, package_map, collection)
			append(&types, cloned)

			if .Using in field.flags {
				usings[len(names) - 1] = true
			}

			append(&ranges, common.get_token_range(n, file.src))
		}
	}

	value := SymbolStructValue {
		names  = names[:],
		types  = types[:],
		ranges = ranges[:],
		usings = usings,
		poly   = cast(^ast.Field_List)clone_type(struct_type.poly_params, collection.allocator, &collection.unique_strings),
	}

	return value
}

collect_enum_fields :: proc(
	collection: ^SymbolCollection,
	fields: []^ast.Expr,
	package_map: map[string]string,
	file: ast.File,
) -> SymbolEnumValue {
	names := make([dynamic]string, 0, collection.allocator)
	ranges := make([dynamic]common.Range, 0, collection.allocator)

	//ERROR no hover on n in the for, but elsewhere is fine
	for n in fields {
		append(&ranges, common.get_token_range(n, file.src))
		if ident, ok := n.derived.(^ast.Ident); ok {
			append(&names, get_index_unique_string(collection, ident.name))
		} else if field, ok := n.derived.(^ast.Field_Value); ok {
			if ident, ok := field.field.derived.(^ast.Ident); ok {
				append(&names, get_index_unique_string(collection, ident.name))
			} else if binary, ok := field.field.derived.(^ast.Binary_Expr);
			   ok {
				append(
					&names,
					get_index_unique_string(
						collection,
						binary.left.derived.(^ast.Ident).name,
					),
				)
			}
		}
	}

	value := SymbolEnumValue {
		names  = names[:],
		ranges = ranges[:],
	}

	return value
}

collect_union_fields :: proc(
	collection: ^SymbolCollection,
	union_type: ast.Union_Type,
	package_map: map[string]string,
) -> SymbolUnionValue {
	types := make([dynamic]^ast.Expr, 0, collection.allocator)

	for variant in union_type.variants {
		cloned := clone_type(
			variant,
			collection.allocator,
			&collection.unique_strings,
		)
		replace_package_alias(cloned, package_map, collection)
		append(&types, cloned)
	}

	value := SymbolUnionValue {
		types = types[:],
		poly  = cast(^ast.Field_List)clone_type(union_type.poly_params, collection.allocator, &collection.unique_strings),
	}

	return value
}

collect_bitset_field :: proc(
	collection: ^SymbolCollection,
	bitset_type: ast.Bit_Set_Type,
	package_map: map[string]string,
) -> SymbolBitSetValue {
	cloned := clone_type(
		bitset_type.elem,
		collection.allocator,
		&collection.unique_strings,
	)
	replace_package_alias(cloned, package_map, collection)

	return SymbolBitSetValue{expr = cloned}
}

collect_slice :: proc(
	collection: ^SymbolCollection,
	array: ast.Array_Type,
	package_map: map[string]string,
) -> SymbolFixedArrayValue {
	elem := clone_type(
		array.elem,
		collection.allocator,
		&collection.unique_strings,
	)
	len := clone_type(
		array.len,
		collection.allocator,
		&collection.unique_strings,
	)

	replace_package_alias(elem, package_map, collection)
	replace_package_alias(len, package_map, collection)

	return SymbolFixedArrayValue{expr = elem, len = len}
}

collect_array :: proc(
	collection: ^SymbolCollection,
	array: ast.Array_Type,
	package_map: map[string]string,
) -> SymbolSliceValue {
	elem := clone_type(
		array.elem,
		collection.allocator,
		&collection.unique_strings,
	)

	replace_package_alias(elem, package_map, collection)

	return SymbolSliceValue{expr = elem}
}

collect_map :: proc(
	collection: ^SymbolCollection,
	m: ast.Map_Type,
	package_map: map[string]string,
) -> SymbolMapValue {
	key := clone_type(m.key, collection.allocator, &collection.unique_strings)
	value := clone_type(
		m.value,
		collection.allocator,
		&collection.unique_strings,
	)

	replace_package_alias(key, package_map, collection)
	replace_package_alias(value, package_map, collection)

	return SymbolMapValue{key = key, value = value}
}

collect_dynamic_array :: proc(
	collection: ^SymbolCollection,
	array: ast.Dynamic_Array_Type,
	package_map: map[string]string,
) -> SymbolDynamicArrayValue {
	elem := clone_type(
		array.elem,
		collection.allocator,
		&collection.unique_strings,
	)

	replace_package_alias(elem, package_map, collection)

	return SymbolDynamicArrayValue{expr = elem}
}

collect_matrix :: proc(
	collection: ^SymbolCollection,
	mat: ast.Matrix_Type,
	package_map: map[string]string,
) -> SymbolMatrixValue {
	elem := clone_type(
		mat.elem,
		collection.allocator,
		&collection.unique_strings,
	)

	y := clone_type(
		mat.column_count,
		collection.allocator,
		&collection.unique_strings,
	)

	x := clone_type(
		mat.row_count,
		collection.allocator,
		&collection.unique_strings,
	)

	replace_package_alias(elem, package_map, collection)
	replace_package_alias(x, package_map, collection)
	replace_package_alias(y, package_map, collection)

	return SymbolMatrixValue{expr = elem, x = x, y = y}
}

collect_multi_pointer :: proc(
	collection: ^SymbolCollection,
	array: ast.Multi_Pointer_Type,
	package_map: map[string]string,
) -> SymbolMultiPointer {
	elem := clone_type(
		array.elem,
		collection.allocator,
		&collection.unique_strings,
	)

	replace_package_alias(elem, package_map, collection)

	return SymbolMultiPointer{expr = elem}
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
			if ident.name == "builtin" &&
			   strings.contains(uri, "Odin/core/c/c.odin") {
				cloned := clone_type(
					selector.field,
					collection.allocator,
					&collection.unique_strings,
				)
				replace_package_alias(cloned, package_map, collection)
				value := SymbolGenericValue {
					expr = cloned,
				}
				return value
			}
		}
	}

	cloned := clone_type(
		expr,
		collection.allocator,
		&collection.unique_strings,
	)
	replace_package_alias(cloned, package_map, collection)

	value := SymbolGenericValue {
		expr = cloned,
	}

	return value
}

collect_method :: proc(collection: ^SymbolCollection, symbol: Symbol) {
	pkg := &collection.packages[symbol.pkg]

	if value, ok := symbol.value.(SymbolProcedureValue); ok {
		if len(value.arg_types) == 0 {
			return
		}

		expr, _, ok := common.unwrap_pointer_ident(value.arg_types[0].type)

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

collect_objc :: proc(
	collection: ^SymbolCollection,
	attributes: []^ast.Attribute,
	symbol: Symbol,
) {
	pkg := &collection.packages[symbol.pkg]

	if value, ok := symbol.value.(SymbolProcedureValue); ok {
		objc_name, found_objc_name := common.get_attribute_objc_name(
			attributes,
		)

		if objc_type := common.get_attribute_objc_type(attributes);
		   objc_type != nil && found_objc_name {

			if struct_ident, ok := objc_type.derived.(^ast.Ident); ok {
				struct_name := get_index_unique_string_collection(
					collection,
					struct_ident.name,
				)

				objc_struct := &pkg.objc_structs[struct_name]

				if objc_struct == nil {
					pkg.objc_structs[struct_name] = {}
					objc_struct = &pkg.objc_structs[struct_name]
					objc_struct.functions = make(
						[dynamic]ObjcFunction,
						0,
						10,
						collection.allocator,
					)
					objc_struct.ranges = make(
						[dynamic]common.Range,
						0,
						10,
						collection.allocator,
					)
					objc_struct.pkg = symbol.pkg
				}

				append(&objc_struct.ranges, symbol.range)

				append(
					&objc_struct.functions,
					ObjcFunction {
						logical_name = get_index_unique_string_collection(
							collection,
							objc_name,
						),
						physical_name = symbol.name,
					},
				)
			}
		}
	}
}

collect_symbols :: proc(
	collection: ^SymbolCollection,
	file: ast.File,
	uri: string,
) -> common.Error {
	forward, _ := filepath.to_slash(file.fullpath, context.temp_allocator)
	directory := path.dir(forward, context.temp_allocator)
	package_map := get_package_mapping(file, collection.config, directory)

	exprs := common.collect_globals(file, true)

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

		if dist, ok := col_expr.derived.(^ast.Distinct_Type); ok {
			if dist.type != nil {
				col_expr = dist.type
			}
		}

		#partial switch v in col_expr.derived {
		case ^ast.Matrix_Type:
			token = v^
			token_type = .Variable
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
				)
			}

			if _, is_objc := common.get_attribute_objc_name(expr.attributes);
			   is_objc {
				symbol.flags |= {.ObjC}
				if common.get_attribute_objc_is_class_method(expr.attributes) {
					symbol.flags |= {.ObjCIsClassMethod}
				}
			}
		case ^ast.Proc_Type:
			token = v^
			token_type = .Function
			symbol.value = collect_procedure_fields(
				collection,
				cast(^ast.Proc_Type)col_expr,
				v.params,
				v.results,
				package_map,
				expr.attributes,
			)
		case ^ast.Proc_Group:
			token = v^
			token_type = .Function
			symbol.value = SymbolProcedureGroupValue {
				group = clone_type(
					col_expr,
					collection.allocator,
					&collection.unique_strings,
				),
			}
		case ^ast.Struct_Type:
			token = v^
			token_type = .Struct
			symbol.value = collect_struct_fields(
				collection,
				v^,
				package_map,
				file,
			)
			symbol.signature = "struct"

			if _, is_objc := common.get_attribute_objc_class_name(
				expr.attributes,
			); is_objc {
				symbol.flags |= {.ObjC}
				if common.get_attribute_objc_is_class_method(expr.attributes) {
					symbol.flags |= {.ObjCIsClassMethod}
				}
			}
		case ^ast.Enum_Type:
			token = v^
			token_type = .Enum
			symbol.value = collect_enum_fields(
				collection,
				v.fields,
				package_map,
				file,
			)
			symbol.signature = "enum"
		case ^ast.Union_Type:
			token = v^
			token_type = .Union
			symbol.value = collect_union_fields(collection, v^, package_map)
			symbol.signature = "union"
		case ^ast.Bit_Set_Type:
			token = v^
			token_type = .Enum
			symbol.value = collect_bitset_field(collection, v^, package_map)
			symbol.signature = "bitset"
		case ^ast.Map_Type:
			token = v^
			token_type = .Variable
			symbol.value = collect_map(collection, v^, package_map)
		case ^ast.Array_Type:
			token = v^
			token_type = .Variable
			if v.len == nil {
				symbol.value = collect_slice(collection, v^, package_map)
			} else {
				symbol.value = collect_array(collection, v^, package_map)
			}
		case ^ast.Dynamic_Array_Type:
			token = v^
			token_type = .Variable
			symbol.value = collect_dynamic_array(collection, v^, package_map)
		case ^ast.Multi_Pointer_Type:
			token = v^
			token_type = .Variable
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
			symbol.value = collect_generic(
				collection,
				col_expr,
				package_map,
				uri,
			)
		case ^ast.Ident:
			token = v^
			symbol.value = collect_generic(
				collection,
				col_expr,
				package_map,
				uri,
			)

			if expr.mutable {
				token_type = .Variable
			} else {
				token_type = .Unresolved
			}
		case:
			// default
			symbol.value = collect_generic(
				collection,
				col_expr,
				package_map,
				uri,
			)

			if expr.mutable {
				token_type = .Variable
			} else {
				token_type = .Unresolved
			}

			token = expr.expr
		}


		symbol.range = common.get_token_range(expr.name_expr, file.src)
		symbol.name = get_index_unique_string(collection, name)
		symbol.type = token_type
		symbol.doc = common.get_doc(expr.docs, collection.allocator)

		if expr.builtin || strings.contains(uri, "builtin.odin") {
			symbol.pkg = "$builtin"
		} else if strings.contains(uri, "intrinsics.odin") {
			path := filepath.join(
				elems = {common.config.collections["core"], "/intrinsics"},
				allocator = context.temp_allocator,
			)

			path, _ = filepath.to_slash(path, context.temp_allocator)

			symbol.pkg = get_index_unique_string(collection, path)
		} else {
			symbol.pkg = get_index_unique_string(collection, directory)
		}

		if expr.deprecated {
			symbol.flags |= {.Deprecated}
		}

		if expr.file_private {
			symbol.flags |= {.PrivateFile}
		}

		if expr.package_private {
			symbol.flags |= {.PrivatePackage}
		}

		symbol.uri = get_index_unique_string(collection, uri)

		pkg: ^SymbolPackage
		ok: bool

		if pkg, ok = &collection.packages[symbol.pkg]; !ok {
			collection.packages[symbol.pkg] = {}
			pkg = &collection.packages[symbol.pkg]
			pkg.symbols = make(map[string]Symbol, 100, collection.allocator)
			pkg.methods = make(
				map[Method][dynamic]Symbol,
				100,
				collection.allocator,
			)
			pkg.objc_structs = make(
				map[string]ObjcStruct,
				5,
				collection.allocator,
			)
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

	return .None
}

Reference :: struct {
	identifiers: [dynamic]common.Location,
	selectors:   map[string][dynamic]common.Range,
}

/*
	Gets the map from import alias to absolute package directory
*/
get_package_mapping :: proc(
	file: ast.File,
	config: ^common.Config,
	directory: string,
) -> map[string]string {
	package_map := make(map[string]string, 0, context.temp_allocator)

	for imp, index in file.imports {
		//collection specified
		if len(imp.fullpath) < 2 {
			continue
		}
		if i := strings.index(imp.fullpath, ":"); i != -1 {
			collection := imp.fullpath[1:i]
			p := imp.fullpath[i + 1:len(imp.fullpath) - 1]

			dir, ok := config.collections[collection]

			if !ok {
				continue
			}

			name: string

			full := path.join(
				elems = {dir, p},
				allocator = context.temp_allocator,
			)

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

replace_package_alias_array :: proc(
	array: $A/[]^$T,
	package_map: map[string]string,
	collection: ^SymbolCollection,
) {
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

replace_package_alias_expr :: proc(
	node: ^ast.Expr,
	package_map: map[string]string,
	collection: ^SymbolCollection,
) {
	replace_package_alias_node(node, package_map, collection)
}

replace_package_alias_node :: proc(
	node: ^ast.Node,
	package_map: map[string]string,
	collection: ^SymbolCollection,
) {
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
	case:
	}
}
