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

SymbolValue :: union {
    SymbolStructValue,
    SymbolPackageValue,
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
    Package = 9, //set by ast symbol
    Keyword = 14, //set by ast symbol
	Struct = 22,
};