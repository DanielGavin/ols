package server

import "core:log"
import "core:mem"
import "core:odin/ast"

import "base:runtime"

find_unused_imports :: proc(document: ^Document, allocator := context.temp_allocator) -> []Package {
	arena: runtime.Arena

	_ = runtime.arena_init(&arena, mem.Megabyte * 40, runtime.default_allocator())

	defer runtime.arena_destroy(&arena)

	context.allocator = runtime.arena_allocator(&arena)

	symbols_and_nodes := resolve_entire_file(document)

	pkgs := make(map[string]struct{}, context.temp_allocator)

	for _, v in symbols_and_nodes {
		pkgs[v.symbol.pkg] = {}
	}

	unused := make([dynamic]Package, allocator)

	for imp in document.imports {
		if imp.base != "_" && imp.name not_in pkgs {
			append(&unused, imp)
		}
	}

	return unused[:]
}
