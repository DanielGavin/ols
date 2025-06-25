package server

import "core:fmt"
import "core:log"
import "core:odin/ast"
import "core:slice"
import "core:strings"


Indexer :: struct {
	builtin_packages: [dynamic]string,
	runtime_package:  string,
	index:            MemoryIndex,
}

@(thread_local)
indexer: Indexer

FuzzyResult :: struct {
	symbol: Symbol,
	score:  f32,
}

clear_index_cache :: proc() {
	memory_index_clear_cache(&indexer.index)
}

lookup :: proc(name: string, pkg: string, loc := #caller_location) -> (Symbol, bool) {
	if name == "" {
		return {}, false
	}

	if symbol, ok := memory_index_lookup(&indexer.index, name, pkg); ok {
		return symbol, true
	}

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

	slice.sort_by(result[:], proc(i, j: FuzzyResult) -> bool {
		return j.score < i.score
	})

	return result[:], true
}
