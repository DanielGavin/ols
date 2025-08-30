package server

import "core:fmt"
import "core:log"
import "core:odin/ast"
import "core:path/filepath"
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

should_skip_private_symbol :: proc(symbol: Symbol, current_file: string) -> bool {
	if .PrivateFile not_in symbol.flags && .PrivatePackage not_in symbol.flags {
		return false
	}

	if current_file == "" {
		return false
	}

	symbol_file := strings.trim_prefix(symbol.uri, "file://")
	current_file := strings.trim_prefix(current_file, "file://")
	if .PrivateFile in symbol.flags && symbol_file != current_file {
		return true
	}

	current_pkg := filepath.dir(current_file, context.temp_allocator)
	if .PrivatePackage in symbol.flags && current_pkg != symbol.pkg {
		return true
	}
	return false
}

lookup :: proc(name: string, pkg: string, current_file: string, loc := #caller_location) -> (Symbol, bool) {
	if name == "" {
		return {}, false
	}

	if symbol, ok := memory_index_lookup(&indexer.index, name, pkg); ok {
		if should_skip_private_symbol(symbol, current_file) {
			return {}, false
		}
		return symbol, true
	}

	return {}, false
}

fuzzy_search :: proc(name: string, pkgs: []string, current_file: string, resolve_fields := false) -> ([]FuzzyResult, bool) {
	results, ok := memory_index_fuzzy_search(&indexer.index, name, pkgs, current_file, resolve_fields)
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
