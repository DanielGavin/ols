package server

import "src:common"

import "core:time"

//Used in semantic tokens and inlay hints to handle the entire file being resolved.

FileResolve :: struct {
	symbols: map[uintptr]SymbolAndNode,
}


FileResolveCache :: struct {
	files: map[string]FileResolve,
}

file_resolve_cache: FileResolveCache

resolve_entire_file_cached :: proc(document: ^Document) -> map[uintptr]SymbolAndNode {
	if document.uri.uri not_in file_resolve_cache.files {
		file_resolve_cache.files[document.uri.uri] = FileResolve {
			symbols = resolve_entire_file(document, .None, common.scratch_allocator(document.allocator)),
		}
	}

	return file_resolve_cache.files[document.uri.uri].symbols
}

BuildCache :: struct {
	loaded_pkgs: map[string]PackageCacheInfo,
}

PackageCacheInfo :: struct {
	timestamp: time.Time,
}

build_cache: BuildCache
