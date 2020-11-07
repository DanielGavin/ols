package server

import "core:odin/parser"
import "core:odin/ast"
import "core:odin/tokenizer"
import "core:fmt"
import "core:log"
import "core:strings"
import "core:path"

import "shared:common"
import "shared:index"



DocumentPositionContextDottedValue :: struct {
    prefix: string,
    postfix: string,
};

DocumentPositionContextGlobalValue :: struct {

};

DocumentPositionContextUnknownValue :: struct {

}

DocumentPositionContextValue :: union {
    DocumentPositionContextDottedValue,
    DocumentPositionContextGlobalValue,
    DocumentPositionContextUnknownValue
};

DocumentPositionContext :: struct {
    value: DocumentPositionContextValue,
};


tokenizer_error_handler :: proc(pos: tokenizer.Pos, msg: string, args: ..any) {

}


/*
    Figure out what exactly is at the given position and whether it is in a function, struct, etc.
*/
get_document_position_context :: proc(document: ^Document, position: common.Position) -> (DocumentPositionContext, bool) {

    position_context: DocumentPositionContext;

    absolute_position, ok := common.get_absolute_position(position, document.text);

    if !ok {
        return position_context, false;
    }


    //Using the ast is not really viable since the code may be broken code
    t: tokenizer.Tokenizer;

    tokenizer.init(&t, document.text, document.uri.path, tokenizer_error_handler);

    stack := make([dynamic] tokenizer.Token, context.temp_allocator);

    current_token: tokenizer.Token;
    last_token: tokenizer.Token;

    struct_or_package_dotted: bool;
    struct_or_package: tokenizer.Token;

    /*
        Idea is to push and pop into braces, brackets, etc, and use the final stack to infer context
     */

    for true {

        current_token = tokenizer.scan(&t);

        #partial switch current_token.kind {
        case .Period:
            if last_token.kind == .Ident {
                struct_or_package_dotted = true;
                struct_or_package = last_token;
            }
        case .Ident:
        case .EOF:
            break;
        case:
            struct_or_package_dotted = false;

        }

        if current_token.pos.offset+len(current_token.text) >= absolute_position {
            break;
        }

        last_token = current_token;
    }

    #partial switch current_token.kind {
        case .Ident:
            if struct_or_package_dotted {
                position_context.value = DocumentPositionContextDottedValue {
                    prefix = struct_or_package.text,
                    postfix = current_token.text,
                };
            }
            else {

            }
        case:
            position_context.value = DocumentPositionContextUnknownValue {

            };
    }

    //fmt.println(position_context);

    return position_context, true;
}


get_definition_location :: proc(document: ^Document, position: common.Position) -> (common.Location, bool) {


    location: common.Location;



    position_context, ok := get_document_position_context(document, position);

    if !ok {
        return location, false;
    }

    symbol: index.Symbol;

    #partial switch v in position_context.value {
    case DocumentPositionContextDottedValue:
        symbol, ok = index.lookup(strings.concatenate({v.prefix, v.postfix}, context.temp_allocator));
    case:
        return location, false;
    }

    //fmt.println(indexer.symbol_table);

    if !ok {
        return location, false;
    }

    location.range = symbol.range;
    location.uri = symbol.uri;


    return location, true;
}

