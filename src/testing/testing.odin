package ols_testing

import "core:fmt"
import "core:log"
import "core:mem"
import "core:mem/virtual"
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
	src.document.allocator = new(virtual.Arena, context.temp_allocator)
	src.document.package_name = "test"

	_ = virtual.arena_init_growing(src.document.allocator)

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
		context.allocator = virtual.arena_allocator(src.document.allocator)

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
	server.free_index()
	server.indexer.index = {}
	virtual.arena_destroy(src.document.allocator)
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

	completion_list, ok := server.get_completion_list(src.document, src.position, completion_context, &src.config)

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

expect_completion_docs :: proc(
	t: ^testing.T,
	src: ^Source,
	trigger_character: string,
	expect_details: []string,
	expect_excluded: []string = nil,
) {
	setup(src)
	defer teardown(src)

	get_doc :: proc(doc: server.CompletionDocumention) -> string {
		switch v in doc {
		case string:
			return v
		case server.MarkupContent:
			first_strip, _ := strings.remove(v.value, "```odin\n", 2, context.temp_allocator)
			content_without_markdown, _ := strings.remove(first_strip, "\n```", 2, context.temp_allocator)
			return content_without_markdown
		}
		return ""
	}

	completion_context := server.CompletionContext {
		triggerCharacter = trigger_character,
	}

	completion_list, ok := server.get_completion_list(src.document, src.position, completion_context, &src.config)

	if !ok {
		log.error("Failed get_completion_list")
	}

	if len(expect_details) == 0 && len(completion_list.items) > 0 {
		log.errorf("Expected empty completion label, but received %v", completion_list.items)
	}

	flags := make([]int, len(expect_details), context.temp_allocator)

	for expect_detail, i in expect_details {
		for completion, j in completion_list.items {
			if expect_detail == get_doc(completion.documentation) {
				flags[i] += 1
			}
		}
	}

	for flag, i in flags {
		if flag != 1 {
			log.errorf("Expected completion label %v, but received %v", expect_details[i], completion_list.items)
		}
	}

	for expect_exclude in expect_excluded {
		for completion in completion_list.items {
			if expect_exclude == get_doc(completion.documentation) {
				log.errorf("Expected completion label %v to not be included", expect_exclude)
			}
		}
	}
}

expect_completion_insert_text :: proc(
	t: ^testing.T,
	src: ^Source,
	trigger_character: string,
	expect_inserts: []string,
) {
	setup(src)
	defer teardown(src)

	completion_context := server.CompletionContext {
		triggerCharacter = trigger_character,
	}

	completion_list, ok := server.get_completion_list(src.document, src.position, completion_context, &src.config)

	if !ok {
		log.error("Failed get_completion_list")
	}

	if len(expect_inserts) == 0 && len(completion_list.items) > 0 {
		log.errorf("Expected empty completion inserts, but received %v", completion_list.items)
	}

	flags := make([]int, len(expect_inserts), context.temp_allocator)

	for expect_insert, i in expect_inserts {
		for completion, j in completion_list.items {
			if insert_text, ok := completion.insertText.(string); ok {
				if expect_insert == insert_text {
					flags[i] += 1
					continue
				}
			}
		}
	}

	for flag, i in flags {
		if flag != 1 {
			log.errorf("Expected completion insert %v, but received %v", expect_inserts[i], completion_list.items)
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

	first_strip, _ := strings.remove(hover.contents.value, "```odin\n", 2, context.temp_allocator)
	content_without_markdown, _ := strings.remove(first_strip, "\n```", 2, context.temp_allocator)

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

expect_type_definition_locations :: proc(t: ^testing.T, src: ^Source, expect_locations: []common.Location) {
	setup(src)
	defer teardown(src)

	locations, ok := server.get_type_definition_locations(src.document, src.position)

	if !ok {
		log.error("Failed get_definition_location")
	}

	if len(expect_locations) == 0 && len(locations) > 0 {
		log.errorf("Expected empty locations, but received %v", locations)
	}

	flags := make([]int, len(expect_locations), context.temp_allocator)

	for expect_location, i in expect_locations {
		for location, j in locations {
			if expect_location.uri != "" {
				if location.range == expect_location.range && location.uri == expect_location.uri {
					flags[i] += 1
				}
			} else if location.range == expect_location.range {
				flags[i] += 1
			}
		}
	}

	for flag, i in flags {
		if flag != 1 {
			if expect_locations[i].uri == "" {
				log.errorf("Expected location %v, but received %v", expect_locations[i].range, locations)
			} else {
				log.errorf("Expected location %v, but received %v", expect_locations[i], locations)
			}
		}
	}
}

expect_reference_locations :: proc(
	t: ^testing.T,
	src: ^Source,
	expect_locations: []common.Location,
	expect_excluded: []common.Location = nil,
) {
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

	for expect_exclude in expect_excluded {
		for location in locations {
			if expect_exclude.range == location.range {
				log.errorf("Expected location %v to not be included\n", expect_exclude)
			}
		}
	}
}

expect_prepare_rename_range :: proc(t: ^testing.T, src: ^Source, expect_range: common.Range) {
	setup(src)
	defer teardown(src)

	range, ok := server.get_prepare_rename(src.document, src.position)
	if !ok {
		log.error("Failed to find range")
	}

	if range != expect_range {
		ok = false
		log.errorf("Failed to match with range: %v", expect_range)
	}

	if !ok {
		log.error("Received: %v\n", range)
	}
}


expect_action :: proc(t: ^testing.T, src: ^Source, expect_action_names: []string) {
	setup(src)
	defer teardown(src)

	input_range := common.Range{start=src.position, end=src.position}
	actions, ok := server.get_code_actions(src.document, input_range, &src.config)
	if !ok {
		log.error("Failed to find actions")
	}

	if len(expect_action_names) == 0 && len(actions) > 0 {
		log.errorf("Expected empty actions, but received %v", actions)
	}

	flags := make([]int, len(expect_action_names), context.temp_allocator)

	for name, i in expect_action_names {
		for action, j in actions {
			if action.title == name {
				flags[i] += 1
			}
		}
	}

	for flag, i in flags {
		if flag != 1 {
			log.errorf("Expected action %v, but received %v", expect_action_names[i], actions)
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

expect_inlay_hints :: proc(t: ^testing.T, src: ^Source) {

	src_builder := strings.builder_make(context.temp_allocator)
	expected_hints := make([dynamic]server.InlayHint, context.temp_allocator)

	HINT_OPEN  :: "[["
	HINT_CLOSE :: "]]"

	{
		last, line, col: int
		saw_brackets: bool
		for i:= 0; i < len(src.main); i += 1 {
			if saw_brackets {
				if i+1 < len(src.main) && src.main[i:][:len(HINT_CLOSE)] == HINT_CLOSE {
					saw_brackets = false
					hint_str := src.main[last:i]
					last = i+len(HINT_CLOSE)
					i = last-1
					append(&expected_hints, server.InlayHint{
						position = {line, col},
						label    = hint_str,
						kind     = .Parameter,
					})
				}
			} else {
				if i+1 < len(src.main) && src.main[i:][:len(HINT_OPEN)] == HINT_OPEN {
					strings.write_string(&src_builder, src.main[last:i])
					saw_brackets = true
					last = i+len(HINT_OPEN)
					i = last-1
				} else if src.main[i] == '\n' {
					line += 1
					col = 0
				} else {
					col += 1
				}
			}
		}

		if saw_brackets {
			log.error("Unclosed inlay hint marker")
			return
		}

		strings.write_string(&src_builder, src.main[last:len(src.main)])
	}

	src.main = strings.to_string(src_builder)

	setup(src)
	defer teardown(src)

	resolve_flag: server.ResolveReferenceFlag
	symbols_and_nodes := server.resolve_entire_file(src.document, resolve_flag, )

	hints, hints_ok := server.get_inlay_hints(src.document, symbols_and_nodes, &src.config)
	if !hints_ok {
		log.error("Failed get_inlay_hints")
		return
	}

	testing.expectf(t,
		len(expected_hints) == len(hints),
		"Expected %d inlay hints, but received %d",
		len(expected_hints),
		len(hints),
	)

	lines := strings.split_lines(src.main, context.temp_allocator)

	get_source_line_with_hint :: proc(lines: []string, hint: server.InlayHint) -> string {
		line := lines[hint.position.line] if hint.position.line >= 0 && hint.position.line < len(lines) else ""
		if hint.position.character >= 0 && hint.position.character <= len(line) {
			builder := strings.builder_make(context.temp_allocator)
			strings.write_string(&builder, line[:hint.position.character])
			strings.write_string(&builder, HINT_OPEN)
			strings.write_string(&builder, hint.label)
			strings.write_string(&builder, HINT_CLOSE)
			strings.write_string(&builder, line[hint.position.character:])
			return strings.to_string(builder)
		}
		return ""
	}

	for i in 0 ..< max(len(expected_hints), len(hints)) {
		expected_text := "---"
		actual_text   := "---"

		if i < len(expected_hints) {
			expected := expected_hints[i]
			expected_line := get_source_line_with_hint(lines, expected)
			expected_text = fmt.tprintf("\"%s\" at (%d, %d): \"%s\"",
				expected.label, expected.position.line, expected.position.character, expected_line)
		}

		if i < len(hints) {
			actual := hints[i]
			actual_line := get_source_line_with_hint(lines, actual)
			actual_text = fmt.tprintf("\"%s\" at (%d, %d): \"%s\"",
				actual.label, actual.position.line, actual.position.character, actual_line)
		}

		if i >= len(expected_hints) {
			log.errorf("[%d]: Unexpected inlay hint\nExpected: %s\nActual:   %s", i, expected_text, actual_text)
		} else if i >= len(hints) {
			log.errorf("[%d]: Missing inlay hint\nExpected: %s\nActual:   %s", i, expected_text, actual_text)
		} else if expected_hints[i] != hints[i] {
			log.errorf("[%d]: Inlay hint mismatch\nExpected: %s\nActual:   %s", i, expected_text, actual_text)
		}
	}
}
