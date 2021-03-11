package server

import "shared:common"

import "core:odin/printer"

FormattingOptions :: struct {
	tabSize: uint,
	insertSpaces: bool, //tabs or spaces
	trimTrailingWhitespace: bool,
	insertFinalNewline: bool,
	trimFinalNewlines: bool,
}

DocumentFormattingParams :: struct {
	textDocument: TextDocumentIdentifier,
	options: FormattingOptions,
}

TextEdit :: struct {
	range: common.Range,
	newText: string,
}

get_complete_format :: proc(document: ^Document) -> ([] TextEdit, bool) {

	/*
	prnt := printer.make_printer(printer.default_style, context.temp_allocator);

	printer.print_file(&prnt, &document.ast);

	end_line := document.ast.decls[len(document.ast.decls)-1].end.line;

	edit := TextEdit {
		newText = printer.to_string(prnt),
		range = {
			start = {
				character = 0,
				line = 0,
			},
			end = {
				character = 1,
				line = end_line + 1,
			}
		}
	};

	edits := make([dynamic] TextEdit, context.temp_allocator);

	append(&edits, edit);

	return edits[:], true;
	*/

	return {}, false;
}