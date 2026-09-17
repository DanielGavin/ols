package ols_testing

import "core:mem/virtual"
import "core:testing"

import "src:common"
import "src:server"

expect_invalid_file_skips_unused_import_resolution :: proc(t: ^testing.T, src: ^Source) {
	setup(src)
	defer teardown(src)

	testing.expectf(t, src.document.ast.syntax_error_count > 0, "Expected a syntax error")
	_ = server.find_unused_imports(src.document)
	_, cached := src.document.symbols.?
	testing.expectf(t, !cached, "Invalid files must not cache partial symbols")
}

expect_index_updates_preserve_and_invalidate_resolution_caches :: proc(t: ^testing.T, src: ^Source) {
	setup(src)
	defer teardown(src)

	indexed_uri := common.create_uri("test/builtin/builtin.odin", context.temp_allocator)
	valid_source := `package test
Last_Good :: 1
`
	malformed_source := `package test
Partial :: 2
Broken :: \
`
	replacement_source := `package test
Replacement :: 3
`

	testing.expectf(
		t,
		server.index_file(indexed_uri, valid_source) == .None,
		"Expected initial index update to succeed",
	)
	expect_index_symbol(t, "$builtin", "Last_Good", true)

	cache_arena := new(virtual.Arena, context.temp_allocator)
	_ = virtual.arena_init_growing(cache_arena)
	defer virtual.arena_destroy(cache_arena)

	previous_documents := server.document_storage.documents
	server.document_storage.documents = make(map[string]server.Document, context.temp_allocator)
	defer {
		delete(server.document_storage.documents)
		server.document_storage.documents = previous_documents
	}
	server.document_storage.documents["cache"] = server.Document {
		symbol_cache_arena = cache_arena,
	}
	cache_document := &server.document_storage.documents["cache"]
	cache_document_symbols(t, cache_document)

	testing.expectf(
		t,
		server.index_file(indexed_uri, malformed_source) == .None,
		"Expected malformed index update to keep the last good index",
	)
	expect_index_symbol(t, "$builtin", "Last_Good", true)
	expect_index_symbol(t, "$builtin", "Partial", false)
	_, cached := cache_document.symbols.?
	testing.expectf(t, cached, "Malformed index updates must retain valid resolution caches")

	testing.expectf(
		t,
		server.index_file(indexed_uri, replacement_source) == .None,
		"Expected replacement index update to succeed",
	)
	expect_index_symbol(t, "$builtin", "Last_Good", false)
	expect_index_symbol(t, "$builtin", "Replacement", true)
	_, cached = cache_document.symbols.?
	testing.expectf(t, !cached, "Valid index replacements must invalidate resolution caches")

	cache_document_symbols(t, cache_document)
	testing.expectf(t, server.remove_index_file(indexed_uri) == .None, "Expected index removal to succeed")
	expect_index_symbol(t, "$builtin", "Replacement", false)
	_, cached = cache_document.symbols.?
	testing.expectf(t, !cached, "Index removal must invalidate resolution caches")
}

@(private)
cache_document_symbols :: proc(t: ^testing.T, document: ^server.Document) {
	allocator, ok := server.document_allocator(document^)
	testing.expectf(t, ok, "Expected a symbol cache allocator")
	if !ok {
		return
	}
	document.symbols = make(server.SymbolAndNodeMap, 1, allocator)
}

@(private)
expect_index_symbol :: proc(t: ^testing.T, package_name, name: string, expected: bool) {
	pkg := &server.indexer.index.collection.packages[package_name]
	_, found := pkg.symbols[name]
	testing.expectf(t, found == expected, "Expected indexed symbol %q presence to be %v", name, expected)
}
