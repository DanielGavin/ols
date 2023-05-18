package ols_testing

import "core:testing"
import "core:mem"
import "core:fmt"
import "core:strings"
import "core:path/filepath"
import "core:odin/parser"
import "core:odin/ast"

import "shared:server"
import "shared:common"

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
	src.main = strings.clone(src.main)
	src.document = new(server.Document, context.temp_allocator)
	src.document.uri = common.create_uri(
		"test/test.odin",
		context.temp_allocator,
	)
	src.document.client_owned = true
	src.document.text = transmute([]u8)src.main
	src.document.used_text = len(src.document.text)
	src.document.allocator = new(common.Scratch_Allocator)
	src.document.package_name = "test"

	common.scratch_allocator_init(
		src.document.allocator,
		mem.Kilobyte * 200,
		context.temp_allocator,
	)

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
		} else if src.main[current_index:current_index + 3] == "{*}" {
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

	/*
		There is a lot code here that is used in the real code, then i'd like to see.
	*/


	for src_pkg in src.packages {
		uri := common.create_uri(
			fmt.aprintf("test/%v/package.odin", src_pkg.pkg),
			context.temp_allocator,
		)

		fullpath := uri.path

		p := parser.Parser {
			err = parser.default_error_handler,
			warn = parser.default_error_handler,
			flags = {.Optional_Semicolons},
		}

		dir := filepath.base(filepath.dir(fullpath, context.temp_allocator))

		pkg := new(ast.Package)
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

		if ret := server.collect_symbols(
			&server.indexer.index.collection,
			file,
			uri.uri,
		); ret != .None {
			return
		}
	}
}

@(private)
teardown :: proc(src: ^Source) {
	server.free_index()
	server.indexer.index = {}
}

expect_signature_labels :: proc(
	t: ^testing.T,
	src: ^Source,
	expect_labels: []string,
) {
	setup(src)
	defer teardown(src)

	help, ok := server.get_signature_information(src.document, src.position)

	if !ok {
		testing.error(t, "Failed get_signature_information")
	}

	if len(expect_labels) == 0 && len(help.signatures) > 0 {
		testing.errorf(
			t,
			"Expected empty signature label, but received %v",
			help.signatures,
		)
	}

	flags := make([]int, len(expect_labels))

	for expect_label, i in expect_labels {
		for signature, j in help.signatures {
			if expect_label == signature.label {
				flags[i] += 1
			}
		}
	}

	for flag, i in flags {
		if flag != 1 {
			testing.errorf(
				t,
				"Expected signature label %v, but received %v",
				expect_labels[i],
				help.signatures,
			)
		}
	}

}

expect_signature_parameter_position :: proc(
	t: ^testing.T,
	src: ^Source,
	position: int,
) {
	setup(src)
	defer teardown(src)

	help, ok := server.get_signature_information(src.document, src.position)

	if help.activeParameter != position {
		testing.errorf(
			t,
			"expected parameter position %v, but received %v",
			position,
			help.activeParameter,
		)
	}
}

expect_completion_labels :: proc(
	t: ^testing.T,
	src: ^Source,
	trigger_character: string,
	expect_labels: []string,
) {
	setup(src)
	defer teardown(src)

	completion_context := server.CompletionContext {
		triggerCharacter = trigger_character,
	}

	completion_list, ok := server.get_completion_list(
		src.document,
		src.position,
		completion_context,
	)

	if !ok {
		testing.error(t, "Failed get_completion_list")
	}

	if len(expect_labels) == 0 && len(completion_list.items) > 0 {
		testing.errorf(
			t,
			"Expected empty completion label, but received %v",
			completion_list.items,
		)
	}

	flags := make([]int, len(expect_labels))

	for expect_label, i in expect_labels {
		for completion, j in completion_list.items {
			if expect_label == completion.label {
				flags[i] += 1
			}
		}
	}

	for flag, i in flags {
		if flag != 1 {
			testing.errorf(
				t,
				"Expected completion detail %v, but received %v",
				expect_labels[i],
				completion_list.items,
			)
		}
	}
}

expect_completion_details :: proc(
	t: ^testing.T,
	src: ^Source,
	trigger_character: string,
	expect_details: []string,
) {
	setup(src)
	defer teardown(src)

	completion_context := server.CompletionContext {
		triggerCharacter = trigger_character,
	}

	completion_list, ok := server.get_completion_list(
		src.document,
		src.position,
		completion_context,
	)

	if !ok {
		testing.error(t, "Failed get_completion_list")
	}

	if len(expect_details) == 0 && len(completion_list.items) > 0 {
		testing.errorf(
			t,
			"Expected empty completion label, but received %v",
			completion_list.items,
		)
	}

	flags := make([]int, len(expect_details))

	for expect_detail, i in expect_details {
		for completion, j in completion_list.items {
			if expect_detail == completion.detail {
				flags[i] += 1
			}
		}
	}

	for flag, i in flags {
		if flag != 1 {
			testing.errorf(
				t,
				"Expected completion label %v, but received %v",
				expect_details[i],
				completion_list.items,
			)
		}
	}
}

expect_hover :: proc(
	t: ^testing.T,
	src: ^Source,
	expect_hover_string: string,
) {
	setup(src)
	defer teardown(src)

	hover, _, ok := server.get_hover_information(src.document, src.position)

	if !ok {
		testing.error(t, "Failed get_hover_information")
	}

	if expect_hover_string == "" && hover.contents.value != "" {
		testing.errorf(
			t,
			"Expected empty hover string, but received %v",
			hover.contents.value,
		)
	}

	if !strings.contains(hover.contents.value, expect_hover_string) {
		testing.errorf(
			t,
			"Expected hover string %v, but received %v",
			expect_hover_string,
			hover.contents.value,
		)
	}
}

expect_definition_locations :: proc(
	t: ^testing.T,
	src: ^Source,
	expect_locations: []common.Location,
) {
	setup(src)
	defer teardown(src)

	locations, ok := server.get_definition_location(src.document, src.position)

	if !ok {
		testing.error(t, "Failed get_definition_location")
	}

	if len(expect_locations) == 0 && len(locations) > 0 {
		testing.errorf(
			t,
			"Expected empty locations, but received %v",
			locations,
		)
	}

	flags := make([]int, len(expect_locations))

	for expect_location, i in expect_locations {
		for location, j in locations {
			if location.range == expect_location.range {
				flags[i] += 1
			}
		}
	}

	for flag, i in flags {
		if flag != 1 {
			testing.errorf(
				t,
				"Expected location %v, but received %v",
				expect_locations[i].range,
				locations,
			)
		}
	}
}
