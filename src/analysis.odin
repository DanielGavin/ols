package main

import "core:odin/parser"
import "core:odin/ast"
import "core:odin/tokenizer"
import "core:fmt"
import "core:log"

ParserError :: struct {
    message: string,
    line: int,
    column: int,
    file: string,
    offset: int,
};

StructSymbol :: struct {

};

ProcedureSymbol :: struct {

};

Symbol :: union {
    StructSymbol,
    ProcedureSymbol,
};

DocumentSymbols :: struct {
    globals: map [string] Symbol,
};

DocumentPositionContext :: struct {
    symbol: Symbol,
};

current_errors: [dynamic] ParserError;

parser_error_handler :: proc(pos: tokenizer.Pos, msg: string, args: ..any) {
    error := ParserError { line = pos.line, column = pos.column, file = pos.file,
                           offset = pos.offset, message = fmt.tprintf(msg, ..args) };
    append(&current_errors, error);
}

parser_warning_handler :: proc(pos: tokenizer.Pos, msg: string, args: ..any) {

}


/*
    Parses and walks through the ast saving all the global symbols for the document. Local symbols are not saved
    because they are determined by the position.

    Document is responsible in freeing the DocumentSymbols
*/

parse_document_symbols :: proc(document: ^Document) -> (DocumentSymbols, [dynamic] ParserError, bool) {

    p := parser.Parser {
		err  = parser_error_handler,
		warn = parser_warning_handler,
	};

    current_errors = make([dynamic] ParserError, context.temp_allocator);


    ast := ast.File {
        fullpath = document.path,
        src = document.text[:document.used_text],
    };

    parser.parse_file(&p, &ast);

    return DocumentSymbols {}, current_errors, true;
}



/*
    Figure out what exactly is at the given position and whether it is in a function, struct, etc.
*/
get_document_position_context :: proc(document: ^Document, position: Position) -> DocumentPositionContext {

    position_context: DocumentPositionContext;

    return position_context;
}



