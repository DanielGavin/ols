package index

import "core:odin/ast"
import "core:hash"
import "core:strings"
import "core:mem"
import "core:fmt"
import "core:path/filepath"
import "core:path"

import "shared:common"

/*
    Note(Daniel, how concerned should we be about keeping the memory usage low for the symbol. You could hash some of strings.
        Right now I have the unique string map in order to have strings reference the same string match.)

 */


SymbolFile :: struct {
    imports: [] string,
};


SymbolStructValue :: struct {
    names: [] string,
    types: [] ^ast.Expr,
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
    scope: string,
    name: string,
    signature: string,
    type: SymbolType,
    value: SymbolValue,
    file: ^SymbolFile,
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

free_symbol :: proc(symbol: Symbol) {

    #partial switch v in symbol.value {
    case SymbolProcedureValue:
        common.free_ast(v.return_types);
        common.free_ast(v.arg_types);
    case SymbolStructValue:
        common.free_ast(v.types);
    case SymbolGenericValue:
        common.free_ast(v.expr);
    }

}