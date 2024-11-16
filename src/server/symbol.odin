package server

import "core:fmt"
import "core:hash"
import "core:log"
import "core:mem"
import "core:odin/ast"
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

SymbolStructValue :: struct {
	names:  []string,
	ranges: []common.Range,
	types:  []^ast.Expr,
	usings: map[int]bool,
	poly:   ^ast.Field_List,
	args:   []^ast.Expr, //The arguments in the call expression for poly
}

SymbolBitFieldValue :: struct {
	names:  []string,
	ranges: []common.Range,
	types:  []^ast.Expr,
}

SymbolPackageValue :: struct {}

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

// TODO rename to SymbolMultiPointerValue
SymbolMultiPointer :: struct {
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
	SymbolMultiPointer,
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
	signature: string, //type signature
	type:      SymbolType,
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
		common.free_ast(v.expr, allocator)
		common.free_ast(v.x, allocator)
		common.free_ast(v.y, allocator)
	case SymbolMultiPointer:
		common.free_ast(v.expr, allocator)
	case SymbolProcedureValue:
		common.free_ast(v.return_types, allocator)
		common.free_ast(v.arg_types, allocator)
	case SymbolStructValue:
		delete(v.names, allocator)
		delete(v.ranges, allocator)
		common.free_ast(v.types, allocator)
	case SymbolGenericValue:
		common.free_ast(v.expr, allocator)
	case SymbolProcedureGroupValue:
		common.free_ast(v.group, allocator)
	case SymbolEnumValue:
		delete(v.names, allocator)
		delete(v.ranges, allocator)
	case SymbolUnionValue:
		common.free_ast(v.types, allocator)
	case SymbolBitSetValue:
		common.free_ast(v.expr, allocator)
	case SymbolDynamicArrayValue:
		common.free_ast(v.expr, allocator)
	case SymbolFixedArrayValue:
		common.free_ast(v.expr, allocator)
		common.free_ast(v.len, allocator)
	case SymbolSliceValue:
		common.free_ast(v.expr, allocator)
	case SymbolBasicValue:
		common.free_ast(v.ident, allocator)
	case SymbolAggregateValue:
		for symbol in v.symbols {
			free_symbol(symbol, allocator)
		}
	case SymbolMapValue:
		common.free_ast(v.key, allocator)
		common.free_ast(v.value, allocator)
	case SymbolUntypedValue:
		delete(v.tok.text)
	case SymbolPackageValue:
	case SymbolBitFieldValue:
		delete(v.names, allocator)
		delete(v.ranges, allocator)
		common.free_ast(v.types, allocator)
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
