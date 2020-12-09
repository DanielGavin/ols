package index

import "core:hash"
import "core:strings"
import "core:fmt"
import "core:log"
import "core:sort"

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

    for _, symbol in index.collection.symbols {

        if !exists_in_scope(symbol.pkg, pkgs) {
            continue;
        }

        score, ok := common.fuzzy_match(fuzzy_matcher, symbol.name);

        result := FuzzyResult {
            symbol = symbol,
            score = score,
        };

        append(&symbols, result);

    }

    //strings.builder
    sort.sort(fuzzy_sort_interface(&symbols));

    //sort. ERROR CRASH

    for s in symbols {
        log.infof("score %v", s.score);
    }


    return symbols[:top], true;
}

exists_in_scope :: proc(symbol_scope: string, scope: [] string) -> bool {

    for s in scope {
        if strings.compare(symbol_scope, s) == 0 {
            return true;
        }
    }

    return false;
}