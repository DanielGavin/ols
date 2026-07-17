package server

import "core:strings"

import "src:common"

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

should_skip_private_symbol :: proc(symbol: Symbol, current_pkg, current_file_uri: string) -> bool {
	if .PrivateFile not_in symbol.flags && .PrivatePackage not_in symbol.flags {
		return false
	}

	if current_file_uri == "" {
		return false
	}

	if .PrivateFile in symbol.flags && symbol.uri != current_file_uri {
		return true
	}

	if .PrivatePackage in symbol.flags && current_pkg != symbol.pkg {
		return true
	}
	return false
}

is_builtin_pkg :: proc(pkg: string) -> bool {
	return strings.equal_fold(pkg, "$builtin") || strings.has_suffix(pkg, "/builtin")
}

lookup_builtin_symbol :: proc(name: string, current_pkg: string, current_file_uri: string) -> (Symbol, bool) {
	if symbol, ok := lookup_symbol(name, "$builtin", current_pkg, current_file_uri); ok {
		return symbol, true
	}

	for built in indexer.builtin_packages {
		if symbol, ok := lookup_symbol(name, built, current_pkg, current_file_uri); ok {
			return symbol, true
		}
	}

	return {}, false
}

lookup :: proc(name: string, pkg: string, current_file: string, loc := #caller_location) -> (Symbol, bool) {
	if name == "" {
		return {}, false
	}

	current_pkg := get_package_from_filepath(current_file)
	current_file_uri := common.create_uri(current_file, context.temp_allocator).uri

	if is_builtin_pkg(pkg) {
		return lookup_builtin_symbol(name, current_pkg, current_file_uri)
	}

	return lookup_symbol(name, pkg, current_pkg, current_file_uri)
}

@(private = "file")
lookup_symbol :: proc(name: string, pkg: string, current_pkg: string, current_file_uri: string) -> (Symbol, bool) {
	if symbol, ok := memory_index_lookup(&indexer.index, name, pkg); ok {
		if should_skip_private_symbol(symbol, current_pkg, current_file_uri) {
			return {}, false
		}
		return symbol, true
	}

	return {}, false
}

fuzzy_search :: proc(
	name: string,
	pkgs: []string,
	current_file: string,
	resolve_fields := false,
	limit := 0,
) -> (
	[]FuzzyResult,
	bool,
) {
	results, ok := memory_index_fuzzy_search(&indexer.index, name, pkgs, current_file, resolve_fields, limit = limit)
	if !ok {
		return {}, false
	}
	return results[:], true
}
