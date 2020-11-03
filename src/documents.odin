package main

import "core:strings"
import "core:fmt"
import "core:log"

Package :: struct {
    documents: [dynamic]^Document,
};

Document :: struct {
    uri: string,
    path: string,
    text: [] u8, //transmuted version of text plus potential unused space
    used_text: int, //allow for the text to be reallocated with more data than needed
    client_owned: bool,
};

DocumentStorage :: struct {
    documents: map [string] Document,
};

document_storage: DocumentStorage;


document_open :: proc(uri_string: string, text: string) -> Error {

    uri, parsed_ok := parse_uri(uri_string);

    if !parsed_ok {
        return .ParseError;
    }

    if document := &document_storage.documents[uri.path]; document != nil {

        //According to the specification you can't call open more than once without closing it.
        if document.client_owned {
            log.errorf("Client called open on an already open document: %v ", document.path);
            return .InvalidRequest;
        }

        if document.text != nil {
            delete(document.text);
        }

        document.client_owned = true;
        document.text = transmute([] u8)text;
        document.used_text = len(document.text);

        if err := document_refresh(document); err != .None {
            return err;
        }

        document_refresh(document);
    }

    else {

        document := Document {
            uri = uri.full,
            path = uri.path,
            text = transmute([] u8)text,
            client_owned = true,
            used_text = len(text),
        };

        if err := document_refresh(&document); err != .None {
            return err;
        }

        document_storage.documents[uri.path] = document;
    }



    //hmm feels like odin needs some ownership semantic
    delete(uri_string);

    return .None;
}

document_apply_changes :: proc(uri_string: string, changes: [dynamic] TextDocumentContentChangeEvent) -> Error {

    uri, parsed_ok := parse_uri(uri_string, context.temp_allocator);

    if !parsed_ok {
        return .ParseError;
    }

    document := &document_storage.documents[uri.path];

    if !document.client_owned {
        log.errorf("Client called change on an document not opened: %v ", document.path);
        return .InvalidRequest;
    }

    for change in changes {

        absolute_range, ok := get_absolute_range(change.range, document.text);

        if !ok {
            return .ParseError;
        }

        //lower bound is before the change
        lower  := document.text[:absolute_range.start];

        //new change between lower and upper
        middle := change.text;

        //upper bound is after the change
        upper := document.text[min(len(document.text), absolute_range.end+1):];

        //total new size needed
        document.used_text = len(lower) + len(change.text) + len(upper);

        if document.used_text > len(document.text) {
            new_text := make([]u8, document.used_text * 2);

            //join the 3 splices into the text
            copy(new_text, lower);
            copy(new_text[len(lower):], middle);
            copy(new_text[len(lower)+len(middle):], upper);

            delete(document.text);

            document.text = new_text;
        }

        else {
            //no need to copy the lower since it is already in the document.
            copy(document.text[len(lower):], middle);
            copy(document.text[len(lower)+len(middle):], upper);
        }


        /*
        fmt.println(string(document.text[:document.used_text]));

        fmt.println("LOWER");
        fmt.println(string(lower));

        fmt.println("CHANGE");
        fmt.println(change.text);
        fmt.println(len(change.text));

        fmt.println("UPPER");
        fmt.println(string(upper));
        */

    }





    return .None;
}

document_close :: proc(uri_string: string) -> Error {

    uri, parsed_ok := parse_uri(uri_string, context.temp_allocator);

    if !parsed_ok {
        return .ParseError;
    }

    document := &document_storage.documents[uri.path];

    if document == nil || !document.client_owned {
        log.errorf("Client called close on a document that was never opened: %v ", document.path);
        return .InvalidRequest;
    }

    document.client_owned = false;

    return .None;
}

document_refresh :: proc(document: ^Document) -> Error {
    return .None;
}

