package index

import "core:odin/ast"
import "core:hash"
import "core:strings"
import "core:mem"

import "shared:common"

Symbol :: struct {
    id: u64,
    range: common.Range,
    uri: string,
};

SymbolCollection :: struct {
    allocator: mem.Allocator,
    symbols: map[u64] Symbol,
    unique_strings: map[u64] string,
};

make_symbol_collection :: proc(allocator := context.allocator) -> SymbolCollection {
    return SymbolCollection {
        allocator = allocator,
        symbols = make(map[u64] Symbol, 16, allocator),
        unique_strings = make(map[u64] string, 16, allocator),
    };
}

collect_symbols :: proc(collection: ^SymbolCollection, file: ast.File, uri: string) -> common.Error {

    for decl in file.decls {

        if value_decl, ok := decl.derived.(ast.Value_Decl); ok {

            name := string(file.src[value_decl.names[0].pos.offset:value_decl.names[0].end.offset]);

            if len(value_decl.values) == 1 {

                if proc_lit, ok := value_decl.values[0].derived.(ast.Proc_Lit); ok {

                    symbol: Symbol;

                    symbol.range = common.get_token_range(proc_lit, file.src);

                    uri_id := hash.murmur64(transmute([]u8)uri);

                    if _, ok := collection.unique_strings[uri_id]; !ok {
                        collection.unique_strings[uri_id] = strings.clone(uri);
                    }

                    symbol.uri = collection.unique_strings[uri_id];

                    id := hash.murmur64(transmute([]u8)strings.concatenate({file.pkg_name, name}, context.temp_allocator));

                    collection.symbols[id] = symbol;

                }

            }

        }
    }

    return .None;
}
