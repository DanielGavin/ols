package index

import "core:hash"
import "core:strings"
import "core:fmt"
import "core:log"

import "shared:common"

/*
    This is a in memory index designed for the dynamic indexing of symbols and files.
    Designed for few files and should be fast at rebuilding.

    Right now the implementation is extremely naive.
 */
MemoryIndex :: struct {
    collection: SymbolCollection,
};


make_memory_index :: proc(collection: SymbolCollection) -> MemoryIndex {

    return MemoryIndex {
        collection = collection,
    };

}

memory_index_lookup :: proc(index: ^MemoryIndex, name: string, pkg: string) -> (Symbol, bool) {
    id := get_symbol_id(strings.concatenate({pkg, name}, context.temp_allocator));
    return index.collection.symbols[id];
}

memory_index_fuzzy_search :: proc(index: ^MemoryIndex, name: string, pkgs: [] string) -> ([] FuzzyResult, bool) {

    symbols := make([dynamic] FuzzyResult, 0, context.temp_allocator);

    fuzzy_matcher := common.make_fuzzy_matcher(name);

    top := 20;
    i := 0;

    for _, symbol in index.collection.symbols {

        if i >= top {
            break;
        }

        if !exists_in_scope(symbol.pkg, pkgs) {
            continue;
        }

        if name == "" || common.fuzzy_match(fuzzy_matcher, symbol.name) > 0.5 {
            result := FuzzyResult {symbol = symbol};
            append(&symbols, result);
            i += 1;
        }


    }

    return symbols[:], true;
}

exists_in_scope :: proc(symbol_scope: string, scope: [] string) -> bool {

    for s in scope {
        if strings.compare(symbol_scope, s) == 0 {
            return true;
        }
    }

    return false;
}