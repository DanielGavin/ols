package ols_testing

import "core:fmt"
import "core:log"
import "core:mem"
import "core:odin/ast"
import "core:odin/parser"
import "core:path/filepath"
import "core:strings"
import "core:testing"

import "src:common"
import "src:server"

Package :: struct {
	pkg:    string,
	source: string,
}

Source :: struct {
	main:        string,
	packages:    []Package,
	document:    ^server.Document,
	collections: map[string]string,
	config:      common.Config,
	position:    common.Position,
}

@(private)
setup :: proc(src: ^Source) {
	src.main = strings.clone(src.main, context.temp_allocator)
	src.document = new(server.Document, context.temp_allocator)
	src.document.uri = common.create_uri("test/test.odin", context.temp_allocator)
	src.document.client_owned = true
	src.document.text = transmute([]u8)src.main
	src.document.used_text = len(src.document.text)
	src.document.allocator = new(common.Scratch_Allocator, context.temp_allocator)
	src.document.package_name = "test"

	common.scratch_allocator_init(src.document.allocator, mem.Kilobyte * 2000, context.temp_allocator)

	//no unicode in tests currently
	current, last: u8
	current_line, current_character: int

	for current_index := 0; current_index < len(src.main); current_index += 1 {
		current = src.main[current_index]

		if last == '\r' {
			current_line += 1
			current_character = 0
		} else if current == '\n' {
			current_line += 1
			current_character = 0
		} else if len(src.main) > current_index + 3 && src.main[current_index:current_index + 3] == "{*}" {
			dst_slice := transmute([]u8)src.main[current_index:]
			src_slice := transmute([]u8)src.main[current_index + 3:]
			copy(dst_slice, src_slice)
			src.position.character = current_character
			src.position.line = current_line
			break
		} else {
			current_character += 1
		}

		last = current
	}

	server.setup_index()

	server.document_setup(src.document)

	server.document_refresh(src.document, &src.config, nil)

	for src_pkg in src.packages {
		context.allocator = common.scratch_allocator(src.document.allocator)

		uri := common.create_uri(fmt.aprintf("test/%v/package.odin", src_pkg.pkg), context.temp_allocator)

		fullpath := uri.path

		p := parser.Parser {
			err   = parser.default_error_handler,
			warn  = parser.default_error_handler,
			flags = {.Optional_Semicolons},
		}

		dir := filepath.base(filepath.dir(fullpath, context.temp_allocator))

		pkg := new(ast.Package, context.temp_allocator)
		pkg.kind = .Normal
		pkg.fullpath = fullpath
		pkg.name = dir

		if dir == "runtime" {
			pkg.kind = .Runtime
		}

		file := ast.File {
			fullpath = fullpath,
			src      = src_pkg.source,
			pkg      = pkg,
		}

		ok := parser.parse_file(&p, &file)


		if !ok || file.syntax_error_count > 0 {
			panic("Parser error in test package source")
		}

		if ret := server.collect_symbols(&server.indexer.index.collection, file, uri.uri); ret != .None {
			return
		}
	}
}

@(private)
teardown :: proc(src: ^Source) {
	//A lot of these deletes are managed by other systems in ols, but to simplify it, we just delete them here in tests.

	server.free_index()
	server.indexer.index = {}

	delete(src.document.package_name)

	for k, v in server.build_cache.loaded_pkgs {
		delete(k)
	}

	delete(server.build_cache.loaded_pkgs)

	common.scratch_allocator_destroy(src.document.allocator)
}

expect_signature_labels :: proc(t: ^testing.T, src: ^Source, expect_labels: []string) {
	setup(src)
	defer teardown(src)

	help, ok := server.get_signature_information(src.document, src.position)

	if !ok {
		log.error("Failed get_signature_information")
	}

	if len(expect_labels) == 0 && len(help.signatures) > 0 {
		log.errorf("Expected empty signature label, but received %v", help.signatures)
	}

	flags := make([]int, len(expect_labels), context.temp_allocator)

	for expect_label, i in expect_labels {
		for signature, j in help.signatures {
			if expect_label == signature.label {
				flags[i] += 1
			}
		}
	}

	for flag, i in flags {
		if flag != 1 {
			log.errorf("Expected signature label %v, but received %v", expect_labels[i], help.signatures)
		}
	}

}

expect_signature_parameter_position :: proc(t: ^testing.T, src: ^Source, position: int) {
	setup(src)
	defer teardown(src)

	help, ok := server.get_signature_information(src.document, src.position)

	if help.activeParameter != position {
		log.errorf("expected parameter position %v, but received %v", position, help.activeParameter)
	}
}

expect_completion_labels :: proc(t: ^testing.T, src: ^Source, trigger_character: string, expect_labels: []string) {
	setup(src)
	defer teardown(src)

	completion_context := server.CompletionContext {
		triggerCharacter = trigger_character,
	}

	completion_list, ok := server.get_completion_list(src.document, src.position, completion_context)

	if !ok {
		log.error("Failed get_completion_list")
	}

	if len(expect_labels) == 0 && len(completion_list.items) > 0 {
		log.errorf("Expected empty completion label, but received %v", completion_list.items)
	}

	flags := make([]int, len(expect_labels), context.temp_allocator)

	for expect_label, i in expect_labels {
		for completion, j in completion_list.items {
			if expect_label == completion.label {
				flags[i] += 1
			}
		}
	}

	for flag, i in flags {
		if flag != 1 {
			log.errorf("Expected completion detail %v, but received %v", expect_labels[i], completion_list.items)
		}
	}
}

expect_completion_details :: proc(t: ^testing.T, src: ^Source, trigger_character: string, expect_details: []string) {
	setup(src)
	defer teardown(src)

	completion_context := server.CompletionContext {
		triggerCharacter = trigger_character,
	}

	completion_list, ok := server.get_completion_list(src.document, src.position, completion_context)

	if !ok {
		log.error("Failed get_completion_list")
	}

	if len(expect_details) == 0 && len(completion_list.items) > 0 {
		log.errorf("Expected empty completion label, but received %v", completion_list.items)
	}

	flags := make([]int, len(expect_details), context.temp_allocator)

	for expect_detail, i in expect_details {
		for completion, j in completion_list.items {
			if expect_detail == completion.detail {
				flags[i] += 1
			}
		}
	}

	for flag, i in flags {
		if flag != 1 {
			log.errorf("Expected completion label %v, but received %v", expect_details[i], completion_list.items)
		}
	}
}

expect_hover :: proc(t: ^testing.T, src: ^Source, expect_hover_string: string) {
	setup(src)
	defer teardown(src)

	hover, valid, ok := server.get_hover_information(src.document, src.position)

	if !ok {
		log.error(t, "Failed get_hover_information")
		return
	}

	if !valid {
		log.error(t, "Failed get_hover_information")
		return
	}

	content_without_markdown := hover.contents.value[8:len(hover.contents.value) - 5]

	if content_without_markdown != expect_hover_string {
		log.errorf("Expected hover string:\n%q, but received:\n%q", expect_hover_string, content_without_markdown)
	}
}

expect_definition_locations :: proc(t: ^testing.T, src: ^Source, expect_locations: []common.Location) {
	setup(src)
	defer teardown(src)

	locations, ok := server.get_definition_location(src.document, src.position)

	if !ok {
		log.error("Failed get_definition_location")
	}

	if len(expect_locations) == 0 && len(locations) > 0 {
		log.errorf("Expected empty locations, but received %v", locations)
	}

	flags := make([]int, len(expect_locations), context.temp_allocator)

	for expect_location, i in expect_locations {
		for location, j in locations {
			if location.range == expect_location.range {
				flags[i] += 1
			}
		}
	}

	for flag, i in flags {
		if flag != 1 {
			log.errorf("Expected location %v, but received %v", expect_locations[i].range, locations)
		}
	}
}

expect_reference_locations :: proc(t: ^testing.T, src: ^Source, expect_locations: []common.Location) {
	setup(src)
	defer teardown(src)

	locations, ok := server.get_references(src.document, src.position)

	for expect_location in expect_locations {
		match := false
		for location in locations {
			if location.range == expect_location.range {
				match = true
			}
		}
		if !match {
			ok = false
			log.errorf("Failed to match with location: %v", expect_location)
		}
	}

	if !ok {
		log.error("Received:")
		for location in locations {
			log.errorf("%v \n", location)
		}
	}
}

expect_semantic_tokens :: proc(t: ^testing.T, src: ^Source, expected: []server.SemanticToken) {
	setup(src)
	defer teardown(src)


	resolve_flag: server.ResolveReferenceFlag
	symbols_and_nodes := server.resolve_entire_file(src.document, resolve_flag, context.temp_allocator)

	range := common.Range {
		end = {line = 9000000},
	} //should be enough
	tokens := server.get_semantic_tokens(src.document, range, symbols_and_nodes)

	testing.expectf(
		t,
		len(expected) == len(tokens),
		"\nExpected %d tokens, but received %d",
		len(expected),
		len(tokens),
	)

	for i in 0 ..< min(len(expected), len(tokens)) {
		e, a := expected[i], tokens[i]
		testing.expectf(
			t,
			e == a,
			"\n[%d]: Expected \n(%d, %d, %d, %v, %w)\nbut received\n(%d, %d, %d, %v, %w)",
			i,
			e.delta_line,
			e.delta_char,
			e.len,
			e.type,
			e.modifiers,
			a.delta_line,
			a.delta_char,
			a.len,
			a.type,
			a.modifiers,
		)
	}
}
