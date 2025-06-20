package server

import "base:intrinsics"

import "core:fmt"
import "core:log"
import "core:mem"
import "core:mem/virtual"
import "core:odin/ast"
import "core:odin/parser"
import "core:odin/tokenizer"
import "core:os"
import "core:path/filepath"
import path "core:path/slashpath"
import "core:strings"

import "src:common"

ParserError :: struct {
	message: string,
	line:    int,
	column:  int,
	file:    string,
	offset:  int,
}

Package :: struct {
	name:          string, //the entire absolute path to the directory
	base:          string,
	base_original: string,
	original:      string,
}

Document :: struct {
	uri:              common.Uri,
	fullpath:         string,
	text:             []u8,
	used_text:        int, //allow for the text to be reallocated with more data than needed
	client_owned:     bool,
	diagnosed_errors: bool,
	ast:              ast.File,
	imports:          []Package,
	package_name:     string,
	allocator:        ^virtual.Arena, //because parser does not support freeing I use arena allocators for each document
	operating_on:     int, //atomic
	version:          Maybe(int),
}


DocumentStorage :: struct {
	documents:       map[string]Document,
	free_allocators: [dynamic]^virtual.Arena,
}

document_storage: DocumentStorage

document_storage_shutdown :: proc() {
	for k, v in document_storage.documents {
		virtual.arena_destroy(v.allocator)
		free(v.allocator)
		delete(k)
	}

	for alloc in document_storage.free_allocators {
		virtual.arena_destroy(alloc)
		free(alloc)
	}

	delete(document_storage.free_allocators)
	delete(document_storage.documents)
}

document_get_allocator :: proc() -> ^virtual.Arena {
	if len(document_storage.free_allocators) > 0 {
		return pop(&document_storage.free_allocators)
	} else {
		allocator := new(virtual.Arena)
		_ = virtual.arena_init_growing(allocator) 
		return allocator
	}
}

document_free_allocator :: proc(allocator: ^virtual.Arena) {
	free_all(virtual.arena_allocator(allocator))
	append(&document_storage.free_allocators, allocator)
}

document_get :: proc(uri_string: string) -> ^Document {
	uri, parsed_ok := common.parse_uri(uri_string, context.temp_allocator)

	if !parsed_ok {
		return nil
	}

	document := &document_storage.documents[uri.path]

	if document == nil {
		log.errorf("Failed to get document %v", uri.path)
		return nil
	}

	intrinsics.atomic_add(&document.operating_on, 1)

	return document
}

document_release :: proc(document: ^Document) {
	if document != nil {
		intrinsics.atomic_sub(&document.operating_on, 1)
	}
}

/*
	Client opens a document with transferred text
*/

document_open :: proc(uri_string: string, text: string, config: ^common.Config, writer: ^Writer) -> common.Error {
	uri, parsed_ok := common.parse_uri(uri_string, context.allocator)

	if !parsed_ok {
		log.error("Failed to parse uri")
		return .ParseError
	}

	if document := &document_storage.documents[uri.path]; document != nil {
		if document.client_owned {
			log.errorf("Client called open on an already open document: %v ", document.uri.path)
			return .InvalidRequest
		}

		document.uri = uri
		document.client_owned = true
		document.text = transmute([]u8)text
		document.used_text = len(document.text)
		document.allocator = document_get_allocator()

		document_setup(document)

		if err := document_refresh(document, config, writer); err != .None {
			return err
		}
	} else {
		document := Document {
			uri          = uri,
			text         = transmute([]u8)text,
			client_owned = true,
			used_text    = len(text),
			allocator    = document_get_allocator(),
		}

		document_setup(&document)

		if err := document_refresh(&document, config, writer); err != .None {
			return err
		}

		document_storage.documents[strings.clone(uri.path)] = document
	}

	delete(uri_string)

	return .None
}

document_setup :: proc(document: ^Document) {
	//Right now not all clients return the case correct windows path, and that causes issues with indexing, so we ensure that it's case correct.
	when ODIN_OS == .Windows {
		package_name := path.dir(document.uri.path, context.temp_allocator)
		forward, _ := filepath.to_slash(common.get_case_sensitive_path(package_name), context.temp_allocator)
		if forward == "" {
			document.package_name = package_name
		} else {
			document.package_name = strings.clone(forward)
		}
	} else {
		document.package_name = path.dir(document.uri.path)
	}

	when ODIN_OS == .Windows {
		correct := common.get_case_sensitive_path(document.uri.path)
		fullpath: string
		if correct == "" {
			//This is basically here to handle the tests where the physical file doesn't actual exist.
			document.fullpath, _ = filepath.to_slash(document.uri.path)
		} else {
			document.fullpath, _ = filepath.to_slash(correct)
		}
	} else {
		document.fullpath = document.uri.path
	}
}

/*
	Function that applies changes to the given document through incremental syncronization
*/
document_apply_changes :: proc(
	uri_string: string,
	changes: [dynamic]TextDocumentContentChangeEvent,
	version: Maybe(int),
	config: ^common.Config,
	writer: ^Writer,
) -> common.Error {
	uri, parsed_ok := common.parse_uri(uri_string, context.temp_allocator)

	if !parsed_ok {
		return .ParseError
	}

	document := &document_storage.documents[uri.path]

	document.version = version

	if !document.client_owned {
		log.errorf("Client called change on an document not opened: %v ", document.uri.path)
		return .InvalidRequest
	}

	for change in changes {
		//for some reason sublime doesn't seem to care even if i tell it to do incremental sync
		if range, ok := change.range.(common.Range); ok {
			absolute_range, ok := common.get_absolute_range(range, document.text[:document.used_text])

			if !ok {
				return .ParseError
			}

			//lower bound is before the change
			lower := document.text[:absolute_range.start]

			//new change between lower and upper
			middle := change.text

			//upper bound is after the change
			upper := document.text[absolute_range.end:document.used_text]

			//total new size needed
			document.used_text = len(lower) + len(change.text) + len(upper)

			//Reduce the amount of allocation by allocating more memory than needed
			if document.used_text > len(document.text) {
				new_text := make([]u8, document.used_text * 2)

				//join the 3 splices into the text
				copy(new_text, lower)
				copy(new_text[len(lower):], middle)
				copy(new_text[len(lower) + len(middle):], upper)

				delete(document.text)

				document.text = new_text
			} else {
				//order matters here, we need to make sure we swap the data already in the text before the middle
				copy(document.text, lower)
				copy(document.text[len(lower) + len(middle):], upper)
				copy(document.text[len(lower):], middle)
			}
		} else {
			document.used_text = len(change.text)

			if document.used_text > len(document.text) {
				new_text := make([]u8, document.used_text * 2)
				copy(new_text, change.text)
				delete(document.text)
				document.text = new_text
			} else {
				copy(document.text, change.text)
			}
		}
	}

	return document_refresh(document, config, writer)
}

document_close :: proc(uri_string: string) -> common.Error {
	log.infof("document_close: %v", uri_string)

	uri, parsed_ok := common.parse_uri(uri_string, context.temp_allocator)

	if !parsed_ok {
		return .ParseError
	}

	document := &document_storage.documents[uri.path]

	if document == nil || !document.client_owned {
		log.errorf("Client called close on a document that was never opened: %v ", document.uri.path)
		return .InvalidRequest
	}

	if document.uri.uri in file_resolve_cache.files {
		delete_key(&file_resolve_cache.files, document.uri.uri)
	}

	document_free_allocator(document.allocator)

	document.allocator = nil
	document.client_owned = false

	common.delete_uri(document.uri)

	delete(document.text)
	delete(document.package_name)

	document.used_text = 0

	return .None
}

document_refresh :: proc(document: ^Document, config: ^common.Config, writer: ^Writer) -> common.Error {
	errors, ok := parse_document(document, config)

	if !ok {
		return .ParseError
	}

	if strings.contains(document.uri.uri, "base/builtin/builtin.odin") ||
	   strings.contains(document.uri.uri, "base/intrinsics/intrinsics.odin") {
		return .None
	}

	if writer != nil && len(errors) > 0 && !config.disable_parser_errors {
		document.diagnosed_errors = true

		params := NotificationPublishDiagnosticsParams {
			uri         = document.uri.uri,
			diagnostics = make([]Diagnostic, len(errors), context.temp_allocator),
		}

		for error, i in errors {
			params.diagnostics[i] = Diagnostic {
				range = common.Range {
					start = common.Position{line = error.line - 1, character = 0},
					end = common.Position{line = error.line, character = 0},
				},
				severity = DiagnosticSeverity.Error,
				code = "Syntax",
				message = error.message,
			}
		}

		notifaction := Notification {
			jsonrpc = "2.0",
			method  = "textDocument/publishDiagnostics",
			params  = params,
		}

		send_notification(notifaction, writer)
	}

	if writer != nil && len(errors) == 0 {
		//send empty diagnosis to remove the clients errors
		if document.diagnosed_errors {

			notifaction := Notification {
				jsonrpc = "2.0",
				method = "textDocument/publishDiagnostics",
				params = NotificationPublishDiagnosticsParams {
					uri = document.uri.uri,
					diagnostics = make([]Diagnostic, len(errors), context.temp_allocator),
				},
			}

			document.diagnosed_errors = false

			send_notification(notifaction, writer)
		}
	}

	return .None
}

current_errors: [dynamic]ParserError

parser_error_handler :: proc(pos: tokenizer.Pos, msg: string, args: ..any) {
	error := ParserError {
		line    = pos.line,
		column  = pos.column,
		file    = pos.file,
		offset  = pos.offset,
		message = fmt.tprintf(msg, ..args),
	}
	append(&current_errors, error)
}

parse_document :: proc(document: ^Document, config: ^common.Config) -> ([]ParserError, bool) {
	p := parser.Parser {
		err   = parser_error_handler,
		warn  = common.parser_warning_handler,
		flags = {.Optional_Semicolons},
	}

	current_errors = make([dynamic]ParserError, context.temp_allocator)

	if document.uri.uri in file_resolve_cache.files {
		delete_key(&file_resolve_cache.files, document.uri.uri)
	}

	free_all(virtual.arena_allocator(document.allocator))

	context.allocator = virtual.arena_allocator(document.allocator)

	pkg := new(ast.Package)
	pkg.kind = .Normal
	pkg.fullpath = document.fullpath

	if strings.contains(document.fullpath, "base/runtime") {
		pkg.kind = .Runtime
	}

	document.ast = ast.File {
		fullpath = document.fullpath,
		src      = string(document.text[:document.used_text]),
		pkg      = pkg,
	}

	parser.parse_file(&p, &document.ast)

	parse_imports(document, config)

	return current_errors[:], true
}

parse_imports :: proc(document: ^Document, config: ^common.Config) {
	imports := make([dynamic]Package)

	for imp, index in document.ast.imports {
		if i := strings.index(imp.fullpath, "\""); i == -1 {
			continue
		}

		//collection specified
		if i := strings.index(imp.fullpath, ":"); i != -1 && i > 1 && i < len(imp.fullpath) - 1 {
			if len(imp.fullpath) < 2 {
				continue
			}

			collection := imp.fullpath[1:i]
			p := imp.fullpath[i + 1:len(imp.fullpath) - 1]

			dir, ok := config.collections[collection]

			if !ok {
				continue
			}

			import_: Package
			import_.original = imp.fullpath
			import_.name = strings.clone(path.join(elems = {dir, p}, allocator = context.temp_allocator))

			if imp.name.text != "" {
				import_.base = imp.name.text
				import_.base_original = path.base(import_.name, false)
			} else {
				import_.base = path.base(import_.name, false)
			}

			append(&imports, import_)
		} else {
			//relative
			if len(imp.fullpath) < 2 {
				continue
			}

			import_: Package
			import_.original = imp.fullpath
			import_.name = path.join(
				elems = {document.package_name, imp.fullpath[1:len(imp.fullpath) - 1]},
				allocator = context.temp_allocator,
			)
			import_.name = path.clean(import_.name)

			if imp.name.text != "" {
				import_.base = imp.name.text
				import_.base_original = path.base(import_.name, false)
			} else {
				import_.base = path.base(import_.name, false)
			}

			append(&imports, import_)
		}
	}

	for imp in imports {
		try_build_package(imp.name)
	}

	try_build_package(document.package_name)

	document.imports = imports[:]
}
