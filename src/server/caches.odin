package server

import "shared:index"
import "shared:analysis"
import "shared:common"

//Used in semantic tokens and inlay hints to handle the entire file being resolved.
FileResolveCache :: struct {
	files: map[string]map[uintptr]index.Symbol,
}

file_resolve_cache: FileResolveCache

resolve_entire_file :: proc(document: ^common.Document) {
	file_resolve_cache.files[document.uri.uri] = analysis.resolve_entire_file(
		document,
		common.scratch_allocator(document.allocator),
	)
}
