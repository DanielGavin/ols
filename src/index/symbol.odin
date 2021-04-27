package index

import "core:odin/ast"
import "core:hash"
import "core:strings"
import "core:mem"
import "core:path/filepath"
import "core:path"
import "core:slice"

import "shared:common"

SymbolStructValue :: struct {
	names:   []string,
	types:   []^ast.Expr,
	usings:  map[string]bool,
	generic: bool,
}

SymbolPackageValue :: struct {}

SymbolProcedureValue :: struct {
	return_types: []^ast.Field,
	arg_types:    []^ast.Field,
	generic:      bool,
}

SymbolProcedureGroupValue :: struct {
	group: ^ast.Expr,
}

//runtime temp symbol value
SymbolAggregateValue :: struct {
	symbols: []Symbol,
}

SymbolEnumValue :: struct {
	names: []string,
}

SymbolUnionValue :: struct {
	names: []string,
	types: []^ast.Expr,
}

SymbolDynamicArrayValue :: struct {
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
	type: enum {Integer, Float, String, Bool},
}

SymbolMapValue :: struct {
	key:   ^ast.Expr,
	value: ^ast.Expr,
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
	SymbolMapValue,
	SymbolSliceValue,
	SymbolBasicValue,
	SymbolUntypedValue,
}

Symbol :: struct {
	range:       common.Range,
	uri:         string,
	pkg:         string,
	name:        string,
	doc:         string,
	signature:   string,
	returns:     string,
	type:        SymbolType,
	value:       SymbolValue,
	pointers:    int,
	is_distinct: bool,
}

SymbolType :: enum {
	Function   = 3,
	Field      = 5,
	Variable   = 6,
	Package    = 9,
	Enum       = 13,
	Keyword    = 14,
	EnumMember = 20,
	Struct     = 22,
	Unresolved = 9999,
}

free_symbol :: proc(symbol: Symbol, allocator: mem.Allocator) {

	if symbol.signature != "" && symbol.signature != "struct" &&
	   symbol.signature != "union" && symbol.signature != "enum" &&
	   symbol.signature != "bitset" {
		delete(symbol.signature, allocator);
	}

	if symbol.returns != "" {
		delete(symbol.returns, allocator);
	}

	if symbol.doc != "" {
		delete(symbol.doc, allocator);
	}

	#partial switch v in symbol.value {
	case SymbolProcedureValue:
		common.free_ast(v.return_types, allocator);
		common.free_ast(v.arg_types, allocator);
	case SymbolStructValue:
		delete(v.names, allocator);
		common.free_ast(v.types, allocator);
	case SymbolGenericValue:
		common.free_ast(v.expr, allocator);
	case SymbolProcedureGroupValue:
		common.free_ast(v.group, allocator);
	case SymbolEnumValue:
		delete(v.names, allocator);
	case SymbolUnionValue:
		delete(v.names, allocator);
		common.free_ast(v.types, allocator);
	case SymbolBitSetValue:
		common.free_ast(v.expr, allocator);
	case SymbolDynamicArrayValue:
		common.free_ast(v.expr, allocator);
	case SymbolFixedArrayValue:
		common.free_ast(v.expr, allocator);
	case SymbolSliceValue:
		common.free_ast(v.expr, allocator);
	case SymbolBasicValue:
		common.free_ast(v.ident, allocator);
	}
}

get_symbol_id :: proc(str: string) -> uint {
	ret := common.sha1_hash(transmute([]byte)str);
	r   := cast(^uint)slice.first_ptr(ret[:]);
	return r^;
}
