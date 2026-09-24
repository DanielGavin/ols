package tests

import "core:encoding/json"
import "core:fmt"
import "core:path/filepath"
import "core:strings"
import "core:testing"

import "src:common"
import "src:server"

@(private = "file")
setup_diagnostics :: proc() {
	for diagnostic_type in server.DiagnosticType {
		server.diagnostics[diagnostic_type] = make(map[string][dynamic]server.Diagnostic)
	}
}

@(private = "file")
teardown_diagnostics :: proc() {
	for diagnostic_type in server.DiagnosticType {
		server.clear_diagnostics(diagnostic_type)
		for uri, &arr in server.diagnostics[diagnostic_type] {
			delete(arr)
			delete(uri)
		}
		delete(server.diagnostics[diagnostic_type])
	}
}

@(private = "file")
TestWriterCapture :: struct {
	data: [dynamic]u8,
}

@(private = "file")
test_writer_capture :: proc(ctx: rawptr, data: []byte) -> (int, int) {
	capture := cast(^TestWriterCapture)ctx
	append(&capture.data, ..data)
	return len(data), 0
}

@(test)
unused_imports_on_change_preserves_previous_behavior :: proc(t: ^testing.T) {

	config := common.Config {
		enable_diagnostics              = true,
		enable_parser_errors            = true,
		enable_unused_imports_reporting = true,
		enable_unused_imports_on_change = true,
		collections                     = make(map[string]string),
	}
	defer delete(config.collections)

	previous_diagnostics := common.config.enable_diagnostics
	common.config.enable_diagnostics = true
	defer common.config.enable_diagnostics = previous_diagnostics

	setup_diagnostics()
	defer teardown_diagnostics()

	server.document_storage.documents = make(map[string]server.Document)
	defer server.document_storage_shutdown()

	builtin_path := server.get_builtin_path()
	defer delete(builtin_path)

	server.setup_index(builtin_path)
	defer server.free_index()

	fullpath, path_error := filepath.abs(".", context.temp_allocator)
	if path_error != nil {
		testing.expectf(t, false, "failed to create test path: %v", path_error)
		return
	}

	test_path, join_error := filepath.join({fullpath, "ols-unused-import-test", "main.odin"}, context.temp_allocator)
	if join_error != nil {
		testing.expectf(t, false, "failed to join test path: %v", join_error)
		return
	}

	uri := common.create_uri(test_path, context.temp_allocator)
	when ODIN_OS == .Windows {
		// create_uri omits the third slash in tests, but document_open expects a client URI.
		uri.uri = strings.concatenate({"file:///", strings.trim_prefix(uri.uri, "file://")}, context.temp_allocator)
	}
	initial_text := strings.clone(`package test

import "./fmt"

main :: proc() {
	_ = fmt.println
}
`)
	if err := server.document_open(uri.uri, initial_text, &config, nil); err != .None {
		testing.expectf(t, false, "failed to open document: %v", err)
		return
	}
	defer server.document_close(uri.uri)

	changed_text := `package test

import "./fmt"

main :: proc() {
	// fmt is intentionally unused after this edit.
}
`
	params_text := strings.join(
		{
			`{"textDocument":{"uri":"`,
			uri.uri,
			`","version":2},"contentChanges":[{"text":`,
			fmt.tprintf("%q", changed_text),
			`}]}`,
		},
		"",
		context.temp_allocator,
	)
	params, parse_error := json.parse_string(params_text, parse_integers = true, allocator=context.temp_allocator)
	if parse_error != .None {
		testing.expectf(t, false, "failed to parse didChange params: %v: %s", parse_error, params_text)
		return
	}

	if err := server.notification_did_change(params, i64(0), &config, nil); err != .None {
		testing.expectf(t, false, "didChange failed: %v", err)
		return
	}

	document := server.document_get(uri.uri)
	defer server.document_release(document)
	unused_imports := server.find_unused_imports(document)

	diagnostics := server.get_merged_diagnostics()
	// Windows test URIs are canonicalized when the document is opened.
	diagnostic_uri := document.uri.uri
	unused := diagnostics[diagnostic_uri]
	if len(unused) != 1 {
		testing.expectf(
			t,
			false,
			"expected one unused-import diagnostic after didChange, got %d; parsed imports: %d, direct unused imports: %d, diagnostics enabled: %v",
			len(unused),
			len(document.imports),
			len(unused_imports),
			common.config.enable_diagnostics,
		)
		return
	}
	if unused[0].code != "Unused" {
		testing.expectf(t, false, "expected unused-import diagnostic, got %q", unused[0].code)
	}

	// A rejected edit must not analyze or publish diagnostics from the old document state.
	server.remove_diagnostics(.Unused, diagnostic_uri)
	invalid_params_text := strings.join(
		{
			`{"textDocument":{"uri":"`,
			uri.uri,
			`","version":3},"contentChanges":[{"range":`,
			`{"start":{"line":999,"character":0},`,
			`"end":{"line":999,"character":1}},`,
			`"text":""}]}`,
		},
		"",
		context.temp_allocator,
	)
	invalid_params, invalid_parse_error := json.parse_string(invalid_params_text, parse_integers = true, allocator=context.temp_allocator)
	if invalid_parse_error != .None {
		testing.expectf(
			t,
			false,
			"failed to parse invalid didChange params: %v: %s",
			invalid_parse_error,
			invalid_params_text,
		)
		return
	}

	capture: TestWriterCapture
	defer delete(capture.data)
	writer := server.make_writer(test_writer_capture, cast(rawptr)&capture)
	change_error := server.notification_did_change(invalid_params, i64(0), &config, &writer)
	testing.expect_value(t, change_error, common.Error.ParseError)

	diagnostics = server.get_merged_diagnostics()
	if got := len(diagnostics[diagnostic_uri]); got != 0 {
		testing.expectf(t, false, "expected no diagnostics after rejected didChange, got %d", got)
	}
	if got := len(capture.data); got != 0 {
		testing.expectf(t, false, "expected rejected didChange to publish nothing, got %d bytes", got)
	}
}
