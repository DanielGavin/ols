package server

import "shared:common"
import "shared:odin/printer"
import "shared:odin/format"
import "core:path/filepath"

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

	style := format.find_config_file_or_default(filepath.dir(document.fullpath, context.temp_allocator))
	prnt := printer.make_printer(style, context.temp_allocator)

	src := printer.print(&prnt, &document.ast)

	log.error(src)

	end_line := 0
	end_charcter := 0

	last := document.text[0]
	line := 0

	for current_index := 0; current_index < len(document.text); current_index += 1 {
		current := document.text[current_index]

		if last == '\r' && current == '\n' {
			line += 1
			current_index += 1
		} else if current == '\n' {
			line += 1
		}

		last = current
	}

	edit := TextEdit {
		newText = src,
		range = {
			start = {
				character = 0,
				line = 0,
			},
			end = {
				character = 1,
				line = line+1,
			},
		},
	}

	edits := make([dynamic]TextEdit, context.temp_allocator)

	append(&edits, edit)

	return edits[:], true
}
