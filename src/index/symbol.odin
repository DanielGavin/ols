package index

import "core:odin/ast"
import "core:hash"
import "core:strings"
import "core:mem"
import "core:fmt"

import "shared:common"

Symbol :: struct {
    id: u64,
    range: common.Range,
    uri: string,
    scope: string,
    name: string,
    type: SymbolType,
};

SymbolType :: enum {
    Text = 1,
	Method = 2,
	Function = 3,
	Constructor = 4,
	Field = 5,
	Variable = 6,
	Interface = 8,
	Module = 9,
	Property = 10,
	Unit = 11,
	Value = 12,
	Enum = 13,
	Keyword = 14,
	Snippet = 15,
	Color = 16,
	File = 17,
	Reference = 18,
	Folder = 19,
	EnumMember = 20,
	Constant = 21,
	Struct = 22,
	Event = 23,
	Operator = 24,
	TypeParameter = 25,
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
                case: // default
                    break;
                }

                symbol.range = common.get_token_range(token, file.src);
                symbol.name = strings.clone(name);
                symbol.scope = strings.clone(file.pkg_name); //have this use unique strings to save space
                symbol.type = token_type;

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

    return .None;
}
