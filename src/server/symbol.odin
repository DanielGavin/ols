package server

import "core:fmt"
import "core:hash"
import "core:log"
import "core:mem"
import "core:odin/ast"
import "core:odin/parser"
import "core:odin/tokenizer"
import "core:path/filepath"
import path "core:path/slashpath"
import "core:slice"
import "core:strings"

import "src:common"

SymbolAndNode :: struct {
	symbol: Symbol,
	node:   ^ast.Node,
}

UsingInfo :: struct {
	from_index: int,
	is_using:   bool,
}

SymbolStructValue :: struct {
	names:             []string,
	ranges:            []common.Range,
	types:             []^ast.Expr,
	usings:            map[int]struct{},
	from_usings:       []int,
	unexpanded_usings: []int,
	poly:              ^ast.Field_List,
	args:              []^ast.Expr, //The arguments in the call expression for poly
	docs:              []^ast.Comment_Group,
	comments:          []^ast.Comment_Group,
}

SymbolBitFieldValue :: struct {
	names:  []string,
	ranges: []common.Range,
	types:  []^ast.Expr,
}

SymbolPackageValue :: struct {
}

SymbolProcedureValue :: struct {
	return_types:      []^ast.Field,
	arg_types:         []^ast.Field,
	orig_return_types: []^ast.Field, //When generics have overloaded the types, we store the original version here.
	orig_arg_types:    []^ast.Field, //When generics have overloaded the types, we store the original version here.
	generic:           bool,
	diverging:         bool,
}

SymbolProcedureGroupValue :: struct {
	group: ^ast.Expr,
}

// currently only used for proc group references
// TODO needs a better name
SymbolAggregateValue :: struct {
	symbols: []Symbol,
}

SymbolEnumValue :: struct {
	names:  []string,
	ranges: []common.Range,
}

SymbolUnionValue :: struct {
	types: []^ast.Expr,
	poly:  ^ast.Field_List,
}

SymbolDynamicArrayValue :: struct {
	expr: ^ast.Expr,
}

SymbolMultiPointerValue :: struct {
	expr: ^ast.Expr,
}

SymbolFixedArrayValue :: struct {
	len:  ^ast.Expr,
	expr: ^ast.Expr,
}

SymbolSliceValue :: struct {
	expr: ^ast.Expr,
}

SymbolBasicValue :: struct {
	ident: ^ast.Ident,
}

SymbolBitSetValue :: struct {
	expr: ^ast.Expr,
}

SymbolUntypedValue :: struct {
	type: enum {
		Integer,
		Float,
		String,
		Bool,
	},
	tok:  tokenizer.Token,
}

SymbolMapValue :: struct {
	key:   ^ast.Expr,
	value: ^ast.Expr,
}

SymbolMatrixValue :: struct {
	x:    ^ast.Expr,
	y:    ^ast.Expr,
	expr: ^ast.Expr,
}

/*
	Generic symbol that is used by the indexer for any variable type(constants, defined global variables, etc),
*/
SymbolGenericValue :: struct {
	expr: ^ast.Expr,
}

SymbolValue :: union {
	SymbolStructValue,
	SymbolPackageValue,
	SymbolProcedureValue,
	SymbolGenericValue,
	SymbolProcedureGroupValue,
	SymbolUnionValue,
	SymbolEnumValue,
	SymbolBitSetValue,
	SymbolAggregateValue,
	SymbolDynamicArrayValue,
	SymbolFixedArrayValue,
	SymbolMultiPointerValue,
	SymbolMapValue,
	SymbolSliceValue,
	SymbolBasicValue,
	SymbolUntypedValue,
	SymbolMatrixValue,
	SymbolBitFieldValue,
}

SymbolFlag :: enum {
	Distinct,
	Deprecated,
	PrivateFile,
	PrivatePackage,
	Anonymous, //Usually applied to structs that are defined inline inside another struct
	Variable, //Symbols that are variable, this means their value decl was mutable
	Local,
	ObjC,
	ObjCIsClassMethod, // should be set true only when ObjC is enabled
	Soa,
}

SymbolFlags :: bit_set[SymbolFlag]

Symbol :: struct {
	range:     common.Range, //the range of the symbol in the file
	uri:       string, //uri of the file the symbol resides
	pkg:       string, //absolute directory path where the symbol resides
	name:      string, //name of the symbol
	doc:       string,
	comment:   string,
	signature: string, //type signature
	type:      SymbolType,
	type_pkg:  string,
	type_name: string,
	value:     SymbolValue,
	pointers:  int, //how many `^` are applied to the symbol
	flags:     SymbolFlags,
}

SymbolType :: enum {
	Function      = 3,
	Field         = 5,
	Variable      = 6,
	Package       = 9,
	Enum          = 13,
	Keyword       = 14,
	EnumMember    = 20,
	Constant      = 21,
	Struct        = 22,
	Type_Function = 23,
	Union         = 7,
	Type          = 8, //For maps, arrays, slices, dyn arrays, matrixes, etc
	Unresolved    = 1, //Use text if not being able to resolve it.
}

SymbolStructValueBuilder :: struct {
	symbol:            Symbol,
	names:             [dynamic]string,
	types:             [dynamic]^ast.Expr,
	args:              [dynamic]^ast.Expr, //The arguments in the call expression for poly
	ranges:            [dynamic]common.Range,
	docs:              [dynamic]^ast.Comment_Group,
	comments:          [dynamic]^ast.Comment_Group,
	usings:            map[int]struct{},
	from_usings:       [dynamic]int,
	unexpanded_usings: [dynamic]int,
	poly:              ^ast.Field_List,
}

symbol_struct_value_builder_make_none :: proc(allocator := context.allocator) -> SymbolStructValueBuilder {
	return SymbolStructValueBuilder {
		names = make([dynamic]string, allocator),
		types = make([dynamic]^ast.Expr, allocator),
		args = make([dynamic]^ast.Expr, allocator),
		ranges = make([dynamic]common.Range, allocator),
		docs = make([dynamic]^ast.Comment_Group, allocator),
		comments = make([dynamic]^ast.Comment_Group, allocator),
		usings = make(map[int]struct{}, allocator),
		from_usings = make([dynamic]int, allocator),
		unexpanded_usings = make([dynamic]int, allocator),
	}
}

symbol_struct_value_builder_make_symbol :: proc(
	symbol: Symbol,
	allocator := context.allocator,
) -> SymbolStructValueBuilder {
	return SymbolStructValueBuilder {
		symbol = symbol,
		names = make([dynamic]string, allocator),
		types = make([dynamic]^ast.Expr, allocator),
		args = make([dynamic]^ast.Expr, allocator),
		ranges = make([dynamic]common.Range, allocator),
		docs = make([dynamic]^ast.Comment_Group, allocator),
		comments = make([dynamic]^ast.Comment_Group, allocator),
		usings = make(map[int]struct{}, allocator),
		from_usings = make([dynamic]int, allocator),
		unexpanded_usings = make([dynamic]int, allocator),
	}
}

symbol_struct_value_builder_make_symbol_symbol_struct_value :: proc(
	symbol: Symbol,
	v: SymbolStructValue,
	allocator := context.allocator,
) -> SymbolStructValueBuilder {
	return SymbolStructValueBuilder {
		symbol = symbol,
		names = slice.to_dynamic(v.names, allocator),
		types = slice.to_dynamic(v.types, allocator),
		args = slice.to_dynamic(v.args, allocator),
		ranges = slice.to_dynamic(v.ranges, allocator),
		docs = slice.to_dynamic(v.docs, allocator),
		comments = slice.to_dynamic(v.comments, allocator),
		usings = v.usings,
		from_usings = slice.to_dynamic(v.from_usings, allocator),
		unexpanded_usings = slice.to_dynamic(v.unexpanded_usings, allocator),
	}
}

symbol_struct_value_builder_make :: proc {
	symbol_struct_value_builder_make_none,
	symbol_struct_value_builder_make_symbol,
	symbol_struct_value_builder_make_symbol_symbol_struct_value,
}

to_symbol :: proc(b: SymbolStructValueBuilder) -> Symbol {
	symbol := b.symbol
	symbol.value = to_symbol_struct_value(b)
	return symbol
}

to_symbol_struct_value :: proc(b: SymbolStructValueBuilder) -> SymbolStructValue {
	return SymbolStructValue {
		names = b.names[:],
		types = b.types[:],
		ranges = b.ranges[:],
		args = b.args[:],
		docs = b.docs[:],
		comments = b.comments[:],
		usings = b.usings,
		from_usings = b.from_usings[:],
		unexpanded_usings = b.unexpanded_usings[:],
		poly = b.poly,
	}
}

write_struct_type :: proc(
	ast_context: ^AstContext,
	b: ^SymbolStructValueBuilder,
	v: ast.Struct_Type,
	ident: ast.Ident,
	attributes: []^ast.Attribute,
	base_using_index: int,
	inlined := false,
) {
	b.poly = v.poly_params
	v := v
	construct_struct_field_docs(ast_context.file, &v)
	for field, i in v.fields.list {
		for n in field.names {
			if identifier, ok := n.derived.(^ast.Ident); ok && field.type != nil {
				if .Using in field.flags {
					append(&b.unexpanded_usings, len(b.types))
					b.usings[len(b.types)] = struct{}{}
				}

				append(&b.names, identifier.name)
				if v.poly_params != nil {
					append(&b.types, clone_type(field.type, ast_context.allocator, nil))
				} else {
					append(&b.types, field.type)
				}

				append(&b.ranges, common.get_token_range(n, ast_context.file.src))
				append(&b.docs, field.docs)
				append(&b.comments, field.comment)
				append(&b.from_usings, base_using_index)
			}
		}
	}

	if _, ok := get_attribute_objc_class_name(attributes); ok {
		b.symbol.flags |= {.ObjC}
		if get_attribute_objc_is_class_method(attributes) {
			b.symbol.flags |= {.ObjCIsClassMethod}
		}
	}

	if v.poly_params != nil {
		resolve_poly_struct(ast_context, b, v.poly_params)
	}

	expand_usings(ast_context, b)
	expand_objc(ast_context, b)
}

write_symbol_struct_value :: proc(
	ast_context: ^AstContext, b: ^SymbolStructValueBuilder, v: SymbolStructValue, base_using_index: int
) {
	base_index := len(b.names)
	for name in v.names {
		append(&b.names, name)
	}
	for type in v.types {
		append(&b.types, type)
	}
	for arg in v.args {
		append(&b.args, arg)
	}
	for range in v.ranges {
		append(&b.ranges, range)
	}
	for doc in v.docs {
		append(&b.docs, doc)
	}
	for comment in v.comments {
		append(&b.comments, comment)
	}
	for u in v.from_usings {
		if u == -1 {
			append(&b.from_usings, base_using_index)
		} else {
			append(&b.from_usings, u + base_index)
		}
	}
	for u in v.unexpanded_usings {
		append(&b.unexpanded_usings, u+base_index)
	}
	for k in v.usings {
		b.usings[k+base_index] = struct{}{}
	}
	expand_usings(ast_context, b)
}

expand_usings :: proc(ast_context: ^AstContext, b: ^SymbolStructValueBuilder) {
	base := len(b.names) - 1
	for len(b.unexpanded_usings) > 0 {
		u := pop_front(&b.unexpanded_usings)

		field_expr := b.types[u]
		pkg := get_package_from_node(field_expr.expr_base)
		set_ast_package_set_scoped(ast_context, pkg)


		if field_expr == nil {
			continue
		}

		b.usings[u] = struct{}{}
		
		if ident, ok := field_expr.derived.(^ast.Ident); ok {
			if v, ok := struct_type_from_identifier(ast_context, ident^); ok {
				write_struct_type(ast_context, b, v^, ident^, {}, u, true)
			} else {
				clear(&ast_context.recursion_map)
				if symbol, ok := resolve_type_identifier(ast_context, ident^); ok {
					if v, ok := symbol.value.(SymbolStructValue); ok {
						write_symbol_struct_value(ast_context, b, v, u)
					}
				}
			}
		} else if selector, ok := field_expr.derived.(^ast.Selector_Expr); ok {
			if s, ok := resolve_selector_expression(ast_context, selector); ok {
				if v, ok := s.value.(SymbolStructValue); ok {
					write_symbol_struct_value(ast_context, b, v, u)
				}
			}
		} else if v, ok := field_expr.derived.(^ast.Struct_Type); ok {
			write_struct_type(ast_context, b, v^, ast_context.field_name, {}, u)
		}
		delete_key(&ast_context.recursion_map, b.types[u])
	}
}

expand_objc :: proc(ast_context: ^AstContext, b: ^SymbolStructValueBuilder) {
	symbol := b.symbol
	if .ObjC in symbol.flags {
		pkg := indexer.index.collection.packages[symbol.pkg]

		if obj_struct, ok := pkg.objc_structs[symbol.name]; ok {
			_objc_function: for function, i in obj_struct.functions {
				base := new_type(ast.Ident, {}, {}, context.temp_allocator)
				base.name = obj_struct.pkg

				field := new_type(ast.Ident, {}, {}, context.temp_allocator)
				field.name = function.physical_name

				selector := new_type(ast.Selector_Expr, {}, {}, context.temp_allocator)

				selector.field = field
				selector.expr = base

				//Check if the base functions need to be overridden. Potentially look at some faster approach than a linear loop.
				for name, j in b.names {
					if name == function.logical_name {
						b.names[j] = function.logical_name
						b.types[j] = selector
						b.ranges[j] = obj_struct.ranges[i]
						continue _objc_function
					}
				}

				append(&b.names, function.logical_name)
				append(&b.types, selector)
				append(&b.ranges, obj_struct.ranges[i])
				append(&b.docs, nil)
				append(&b.comments, nil)
				append(&b.from_usings, -1)
			}
		}
	}
}

new_clone_symbol :: proc(data: Symbol, allocator := context.allocator) -> ^Symbol {
	new_symbol := new(Symbol, allocator)
	new_symbol^ = data
	new_symbol.value = data.value
	return new_symbol
}

free_symbol :: proc(symbol: Symbol, allocator: mem.Allocator) {
	if symbol.signature != "" &&
	   symbol.signature != "struct" &&
	   symbol.signature != "union" &&
	   symbol.signature != "enum" &&
	   symbol.signature != "bitset" &&
	   symbol.signature != "bit_field" {
		delete(symbol.signature, allocator)
	}

	if symbol.doc != "" {
		delete(symbol.doc, allocator)
	}

	switch v in symbol.value {
	case SymbolMatrixValue:
		free_ast(v.expr, allocator)
		free_ast(v.x, allocator)
		free_ast(v.y, allocator)
	case SymbolMultiPointerValue:
		free_ast(v.expr, allocator)
	case SymbolProcedureValue:
		free_ast(v.return_types, allocator)
		free_ast(v.arg_types, allocator)
	case SymbolStructValue:
		delete(v.names, allocator)
		delete(v.ranges, allocator)
		free_ast(v.types, allocator)
	case SymbolGenericValue:
		free_ast(v.expr, allocator)
	case SymbolProcedureGroupValue:
		free_ast(v.group, allocator)
	case SymbolEnumValue:
		delete(v.names, allocator)
		delete(v.ranges, allocator)
	case SymbolUnionValue:
		free_ast(v.types, allocator)
	case SymbolBitSetValue:
		free_ast(v.expr, allocator)
	case SymbolDynamicArrayValue:
		free_ast(v.expr, allocator)
	case SymbolFixedArrayValue:
		free_ast(v.expr, allocator)
		free_ast(v.len, allocator)
	case SymbolSliceValue:
		free_ast(v.expr, allocator)
	case SymbolBasicValue:
		free_ast(v.ident, allocator)
	case SymbolAggregateValue:
		for symbol in v.symbols {
			free_symbol(symbol, allocator)
		}
	case SymbolMapValue:
		free_ast(v.key, allocator)
		free_ast(v.value, allocator)
	case SymbolUntypedValue:
		delete(v.tok.text)
	case SymbolPackageValue:
	case SymbolBitFieldValue:
		delete(v.names, allocator)
		delete(v.ranges, allocator)
		free_ast(v.types, allocator)
	}
}

symbol_type_to_completion_kind :: proc(type: SymbolType) -> CompletionItemKind {
	switch type {
	case .Function:
		return .Function
	case .Field:
		return .Field
	case .Variable:
		return .Variable
	case .Package:
		return .Module
	case .Enum:
		return .Enum
	case .Keyword:
		return .Keyword
	case .EnumMember:
		return .EnumMember
	case .Constant:
		return .Constant
	case .Struct:
		return .Struct
	case .Type_Function:
		return .Function
	case .Union:
		return .Enum
	case .Unresolved:
		return .Text
	case .Type:
		return .Constant
	case:
		return .Text
	}
}

symbol_kind_to_type :: proc(type: SymbolType) -> SymbolKind {
	#partial switch type {
	case .Function:
		return .Function
	case .Constant:
		return .Constant
	case .Variable:
		return .Variable
	case .Union:
		return .Enum
	case .Struct:
		return .Struct
	case .Enum:
		return .Enum
	case .Keyword:
		return .Key
	case:
		return .Null
	}
}

symbol_to_expr :: proc(symbol: Symbol, file: string, allocator := context.temp_allocator) -> ^ast.Expr {

	pos := tokenizer.Pos {
		file = file,
	}

	end := tokenizer.Pos {
		file = file,
	}

	#partial switch v in symbol.value {
	case SymbolDynamicArrayValue:
		type := new_type(ast.Dynamic_Array_Type, pos, end, allocator)
		type.elem = v.expr
		return type
	case SymbolFixedArrayValue:
		type := new_type(ast.Array_Type, pos, end, allocator)
		type.elem = v.expr
		type.len = v.len
		return type
	case SymbolMapValue:
		type := new_type(ast.Map_Type, pos, end, allocator)
		type.key = v.key
		type.value = v.value
		return type
	case SymbolBasicValue:
		return v.ident
	case SymbolSliceValue:
		type := new_type(ast.Array_Type, pos, end, allocator)
		type.elem = v.expr
		return type
	case SymbolStructValue:
		type := new_type(ast.Struct_Type, pos, end, allocator)
		return type
	case SymbolUntypedValue:
		type := new_type(ast.Basic_Lit, pos, end, allocator)
		type.tok = v.tok
		return type
	case SymbolMatrixValue:
		type := new_type(ast.Matrix_Type, pos, end, allocator)
		type.row_count = v.x
		type.column_count = v.y
		type.elem = v.expr
		return type
	case SymbolProcedureValue:
		type := new_type(ast.Proc_Type, pos, end, allocator)
		type.results = new_type(ast.Field_List, pos, end, allocator)
		type.results.list = v.return_types
		type.params = new_type(ast.Field_List, pos, end, allocator)
		type.params.list = v.arg_types
		return type
	case SymbolBitFieldValue:
		type := new_type(ast.Bit_Field_Type, pos, end, allocator)
		return type
	case:
		return nil
	}

	return nil
}
