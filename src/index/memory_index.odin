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
}

make_memory_index :: proc(collection: SymbolCollection) -> MemoryIndex {
	return MemoryIndex {
		collection = collection,
	}
}

memory_index_lookup :: proc(index: ^MemoryIndex, name: string, pkg: string) -> (Symbol, bool) {
	if pkg, ok := &index.collection.packages[pkg]; ok {
		return pkg[name]
	} 

	return {}, false
}

memory_index_fuzzy_search :: proc(index: ^MemoryIndex, name: string, pkgs: []string) -> ([]FuzzyResult, bool) {
	symbols := make([dynamic]FuzzyResult, 0, context.temp_allocator)

	fuzzy_matcher := common.make_fuzzy_matcher(name)

	top := 20

	for pkg in pkgs {
		if pkg, ok := index.collection.packages[pkg]; ok {
			for _, symbol in pkg {
				if score, ok := common.fuzzy_match(fuzzy_matcher, symbol.name); ok == 1 {
					result := FuzzyResult {
						symbol = symbol,
						score = score,
					}
		
					append(&symbols, result)
				}
			}
		} 
	}

	sort.sort(fuzzy_sort_interface(&symbols))

	if name == "" {
		return symbols[:], true
	} else {
		return symbols[:min(top, len(symbols))], true
	}
}

