package index

import "core:odin/ast"
import "core:hash"
import "core:strings"
import "core:mem"
import "core:fmt"

import "shared:common"

/*
    Note(Daniel, how concerned should we be about keeping the memory usage low for the symbol. You could hash some of strings.
        Right now I have the unique string map in order to have strings reference the same string match.)

 */

SymbolStructValue :: struct {
    names: [] string,
    types: [] ^ast.Expr,
};

SymbolValue :: union {
    SymbolStructValue,
};

Symbol :: struct {
    id: u64,
    range: common.Range,
    uri: string,
    scope: string,
    name: string,
    signature: string,
    type: SymbolType,
    value: SymbolValue,
};

SymbolType :: enum {
	Function = 3,
    Field = 5,
    Package = 9, //set by ast symbol
    Keyword = 14, //set by ast symbol
	Struct = 22,
};

SymbolCollection :: struct {
    allocator: mem.Allocator,
    symbols: map[u64] Symbol,
    unique_strings: map[u64] string, //store all our strings as unique strings and reference them to save memory.
};

get_index_unique_string :: proc(collection: ^SymbolCollection, s: string) -> string {

    id := hash.murmur64(transmute([]u8)s);

    if _, ok := collection.unique_strings[id]; !ok {
        collection.unique_strings[id] = strings.clone(s, collection.allocator);
    }

    return collection.unique_strings[id];
}

make_symbol_collection :: proc(allocator := context.allocator) -> SymbolCollection {
    return SymbolCollection {
        allocator = allocator,
        symbols = make(map[u64] Symbol, 16, allocator),
        unique_strings = make(map[u64] string, 16, allocator),
    };
}

collect_struct_fields :: proc(collection: ^SymbolCollection, fields: ^ast.Field_List, src: [] byte) -> SymbolStructValue {

    names := make([dynamic] string, 0, collection.allocator);
    types := make([dynamic] ^ast.Expr, 0, collection.allocator);

    for field in fields.list {

        for n in field.names {
            identifier := n.derived.(ast.Ident);
            append(&names, get_index_unique_string(collection, identifier.name));
            append(&types, ast.clone_expr(field.type));
        }

    }

    value := SymbolStructValue {
        names = names[:],
        types = types[:],
    };

    return value;
}

collect_symbols :: proc(collection: ^SymbolCollection, file: ast.File, uri: string) -> common.Error {

    for decl in file.decls {

        symbol: Symbol;

        if value_decl, ok := decl.derived.(ast.Value_Decl); ok {

            name := string(file.src[value_decl.names[0].pos.offset:value_decl.names[0].end.offset]);

            if len(value_decl.values) == 1 {

                token: ast.Node;
                token_type: SymbolType;

                switch v in value_decl.values[0].derived {
                case ast.Proc_Lit:
                    token = v;
                    token_type = .Function;
                case ast.Struct_Type:
                    token = v;
                    token_type = .Struct;
                    collect_struct_fields(collection, v.fields, file.src);
                case: // default
                    break;
                }

                symbol.range = common.get_token_range(token, file.src);
                symbol.name = get_index_unique_string(collection, name);
                symbol.scope = get_index_unique_string(collection, file.pkg_name);
                symbol.type = token_type;
                symbol.uri = get_index_unique_string(collection, uri);

                id := hash.murmur64(transmute([]u8)strings.concatenate({file.pkg_name, name}, context.temp_allocator));

                collection.symbols[id] = symbol;
            }

        }
    }

    return .None;
}
