package server

import "core:path/filepath"
import "src:common"
import "src:odin/format"
import "src:odin/printer"

import "core:log"

FormattingOptions :: struct {
	tabSize:                uint,
	insertSpaces:           bool, //tabs or spaces
	trimTrailingWhitespace: bool,
	insertFinalNewline:     bool,
	trimFinalNewlines:      bool,
}

DocumentFormattingParams :: struct {
	textDocument: TextDocumentIdentifier,
	options:      FormattingOptions,
}

get_complete_format :: proc(document: ^Document, config: ^common.Config) -> ([]TextEdit, bool) {
	if document.ast.syntax_error_count > 0 {
		return {}, true
	}

	if len(document.text) == 0 {
		return {}, true
	}

	if config.enable_import_fixer {
		fix_imports(document)
	}

	style := format.find_config_file_or_default(filepath.dir(document.fullpath, context.temp_allocator))
	prnt := printer.make_printer(style, context.temp_allocator)

	src := printer.print(&prnt, &document.ast)

	if prnt.errored_out {
		return {}, true
	}

	edit := TextEdit {
		newText = src,
		range   = common.get_document_range(document.text[0:document.used_text]),
	}

	edits := make([dynamic]TextEdit, context.temp_allocator)

	append(&edits, edit)

	return edits[:], true
}
