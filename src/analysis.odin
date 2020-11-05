package main

import "core:odin/parser"
import "core:odin/ast"
import "core:odin/tokenizer"
import "core:fmt"
import "core:log"
import "core:strings"
import "core:path"


DocumentPositionContextType :: enum {
    GlobalVariable,
    DottedVariable,
    Unknown,
};

DocumentPositionContextValue :: union {
    string,
    int,
};

DocumentPositionContext :: struct {
    type: DocumentPositionContextType,
    value: DocumentPositionContextValue,
};


tokenizer_error_handler :: proc(pos: tokenizer.Pos, msg: string, args: ..any) {

}

/*
    Figure out what exactly is at the given position and whether it is in a function, struct, etc.
*/
get_document_position_context :: proc(document: ^Document, position: Position) -> (DocumentPositionContext, bool) {

    position_context: DocumentPositionContext;

    absolute_position, ok := get_absolute_position(position, document.text);

    if !ok {
        return position_context, false;
    }


    //Using the ast is not really viable since this may be broken code
    t: tokenizer.Tokenizer;

    tokenizer.init(&t, document.text, document.path, tokenizer_error_handler);

    stack := make([dynamic] tokenizer.Token, context.temp_allocator);

    current_token: tokenizer.Token;

    /*
        Idea is to push and pop into braces, brackets, etc, and use the final stack to infer context
     */

    for true {

        current_token = tokenizer.scan(&t);

        #partial switch current_token.kind {
        case .Open_Paren:

        case .EOF:
            break;

        }

        //fmt.println(current_token.text);
        //fmt.println();

        if current_token.pos.offset+len(current_token.text) >= absolute_position {
            break;
        }

    }

    #partial switch current_token.kind {
        case .Ident:
            position_context.type = .GlobalVariable;
            position_context.value = current_token.text;
        case:
            position_context.type = .Unknown;
    }

    return position_context, true;
}


get_definition_location :: proc(document: ^Document, position: Position) -> (Location, bool) {

    location: Location;

    position_context, ok := get_document_position_context(document, position);

    if !ok {
        return location, false;
    }




    return location, true;
}

