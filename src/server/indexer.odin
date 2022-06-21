package server

import "core:odin/ast"
import "core:fmt"
import "core:strings"
import "core:log"
import "core:sort"


Indexer :: struct {
	builtin_packages:  [dynamic]string,
	index:             MemoryIndex,
}

indexer: Indexer

FuzzyResult :: struct {
	symbol: Symbol,
	score:  f32,
}

lookup :: proc(name: string, pkg: string, loc := #caller_location) -> (Symbol, bool) {
	if symbol, ok := memory_index_lookup(&indexer.index, name, pkg); ok {
		log.infof("lookup name: %v pkg: %v, symbol %v location %v", name, pkg, symbol, loc)
		return symbol, true
	}

	log.infof("lookup failed name: %v pkg: %v location %v", name, pkg, loc)
	return {}, false
}

fuzzy_search :: proc(name: string, pkgs: []string) -> ([]FuzzyResult, bool) {
	results, ok := memory_index_fuzzy_search(&indexer.index, name, pkgs)
	result := make([dynamic]FuzzyResult, context.temp_allocator)

	if !ok {
		return {}, false
	}

	for r in results {
		append(&result, r)
	}

	sort.sort(fuzzy_sort_interface(&result))

	return result[:], true
}

fuzzy_sort_interface :: proc(s: ^[dynamic]FuzzyResult) -> sort.Interface {
	return sort.Interface {
		collection = rawptr(s),
		len = proc(it: sort.Interface) -> int {
			s := (^[dynamic]FuzzyResult)(it.collection)
			return len(s^)
		},
		less = proc(it: sort.Interface, i, j: int) -> bool {
			s := (^[dynamic]FuzzyResult)(it.collection)
			return s[i].score > s[j].score
		},
		swap = proc(it: sort.Interface, i, j: int) {
			s := (^[dynamic]FuzzyResult)(it.collection)
			s[i], s[j] = s[j], s[i]
		},
	}
}
