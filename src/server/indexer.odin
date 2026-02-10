package server

import "core:log"
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

should_skip_private_symbol :: proc(symbol: Symbol, current_pkg, current_file: string) -> bool {
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

	if .PrivatePackage in symbol.flags && current_pkg != symbol.pkg {
		return true
	}
	return false
}

is_builtin_pkg :: proc(pkg: string) -> bool {
	return strings.equal_fold(pkg, "$builtin") || strings.has_suffix(pkg, "/builtin")
}

lookup_builtin_symbol :: proc(name: string, current_file: string) -> (Symbol, bool) {
	if symbol, ok := lookup_symbol(name, "$builtin", current_file); ok {
		return symbol, true
	}

	for built in indexer.builtin_packages {
		if symbol, ok := lookup_symbol(name, built, current_file); ok {
			return symbol, true
		}
	}

	return {}, false
}

lookup :: proc(name: string, pkg: string, current_file: string, loc := #caller_location) -> (Symbol, bool) {
	if name == "" {
		return {}, false
	}

	if is_builtin_pkg(pkg) {
		return lookup_builtin_symbol(name, current_file)
	}

	return lookup_symbol(name, pkg, current_file)
}

@(private = "file")
lookup_symbol ::proc(name: string, pkg: string, current_file: string) -> (Symbol, bool) {
	if symbol, ok := memory_index_lookup(&indexer.index, name, pkg); ok {
		current_pkg := get_package_from_filepath(current_file)
		if should_skip_private_symbol(symbol, current_pkg, current_file) {
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
