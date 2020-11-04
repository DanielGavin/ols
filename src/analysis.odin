package main

import "core:odin/parser"
import "core:odin/ast"
import "core:odin/tokenizer"
import "core:fmt"
import "core:log"
import "core:strings"
import "core:path"

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

PackageSymbol :: struct {

};

Symbol :: union {
    StructSymbol,
    ProcedureSymbol,
    PackageSymbol
};

DocumentSymbols :: struct {
    file: ast.File,
    globals: map [string] Symbol,
    imports: [] string,
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

    Document is responsible in freeing the DocumentSymbols with free_document_symbols

    Returns DocumentSymbols, Errors, file package name, imports processed with correct path directory
*/

parse_document_symbols :: proc(document: ^Document, config: ^Config) -> (DocumentSymbols, [dynamic] ParserError, string, []string, bool) {

    symbols: DocumentSymbols;

    p := parser.Parser {
		err  = parser_error_handler,
		warn = parser_warning_handler,
	};

    current_errors = make([dynamic] ParserError, context.temp_allocator);

    symbols.file = ast.File {
        fullpath = document.path,
        src = document.text[:document.used_text],
    };

    parser.parse_file(&p, &symbols.file);

    symbols.imports = make([]string, len(symbols.file.imports));

    for imp, index in symbols.file.imports {

        //collection specified
        if i := strings.index(imp.fullpath, ":"); i != -1 {

            collection := imp.fullpath[1:i];
            p := imp.fullpath[i+1:len(imp.fullpath)-1];

            dir, ok := config.collections[collection];

            if !ok {
                continue;
            }

            symbols.imports[index] = path.join(allocator = context.temp_allocator, elems = {dir, p});

        }

        //relative
        else {

        }
    }



    return symbols, current_errors, symbols.file.pkg_name, symbols.imports, true;
}

free_document_symbols :: proc(symbols: DocumentSymbols) {

}


/*
    Figure out what exactly is at the given position and whether it is in a function, struct, etc.
*/
get_document_position_context :: proc(document: ^Document, position: Position) -> DocumentPositionContext {

    position_context: DocumentPositionContext;

    return position_context;
}



