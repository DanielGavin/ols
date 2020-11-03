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
    text: string,
    client_owned: bool,
    lines: [dynamic] int, 
};

DocumentStorage :: struct {
    documents: map [string] Document,
};

document_storage: DocumentStorage;


document_open :: proc(uri_string: string, text: string) -> Error {

    uri, parsed_ok := parse_uri(uri_string, context.temp_allocator);

    if !parsed_ok {
        return .ParseError;
    }

    if document := &document_storage.documents[uri.path]; document != nil {
        
        //According to the specification you can't call open more than once without closing it.
        if document.client_owned {
            log.errorf("Client called open on an already open document: %v ", document.path);
            return .InvalidRequest;
        }

        if document.text != "" {
            delete(document.text);
        }

        document.client_owned = true;
        document.text = text;

        if err := document_refresh(document); err != .None {
            return err;
        }

        document_refresh(document);
    }

    else {

        document := Document {
            uri = uri.full,
            path = uri.path,
            text = text,
            client_owned = true,
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

 
 



    return .None;
}

document_close :: proc(uri_string: string, text: string) -> Error {

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

    if document.text != "" {
        delete(document.text);
    }

    document.text = text;

    if err := document_refresh(document); err != .None {
            return err;
    }
    
    return .None;
}

document_refresh :: proc(document: ^Document) -> Error {
    return .None;
}

