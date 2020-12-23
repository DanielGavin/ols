package index

import "core:odin/ast"
import "core:hash"
import "core:strings"
import "core:mem"
import "core:fmt"
import "core:path/filepath"
import "core:path"
import "core:slice"

import "shared:common"

/*
    Note(Daniel, how concerned should we be about keeping the memory usage low for the symbol. You could hash some of strings.
        Right now I have the unique string map in order to have strings reference the same string match.)

 */

SymbolStructValue :: struct {
    names: [] string,
    types: [] ^ast.Expr,
    usings: [] bool, //not memory efficient
};


SymbolPackageValue :: struct {

};

SymbolProcedureValue :: struct {
    return_types: [] ^ast.Field,
    arg_types: [] ^ast.Field,
    generic: bool,
};

SymbolProcedureGroupValue :: struct {
    group: ^ast.Expr,
};

SymbolEnumValue :: struct {
    names: [] string,
};

SymbolUnionValue :: struct {
    names: [] string,
};

/*
    Generic symbol that is used by the indexer for any variable type(constants, defined global variables, etc),
*/
SymbolGenericValue :: struct {
    expr: ^ast.Expr,
};

SymbolValue :: union {
    SymbolStructValue,
    SymbolPackageValue,
    SymbolProcedureValue,
    SymbolGenericValue,
    SymbolProcedureGroupValue,
    SymbolUnionValue,
    SymbolEnumValue,
};

Symbol :: struct {
    range: common.Range,
    uri: string,
    pkg: string,
    name: string,
    doc: string,
    signature: string,
    returns: string,
    type: SymbolType,
    value: SymbolValue,
};

SymbolType :: enum {
	Function = 3,
    Field = 5,
    Variable = 6,
    Package = 9, //set by ast symbol
    Enum = 13,
    Keyword = 14, //set by ast symbol
    EnumMember = 20,
	Struct = 22,
};

free_symbol :: proc(symbol: Symbol, allocator: mem.Allocator) {

    if symbol.signature != "" && symbol.signature != "struct" && symbol.signature != "union" && symbol.signature != "enum" {
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
    }

}

get_symbol_id :: proc(str: string) -> uint {
    ret := common.sha1_hash(transmute([]byte)str);
    r := cast(^uint)slice.first_ptr(ret[:]);
    return r^;
}