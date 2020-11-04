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
    text: [] u8,
    used_text: int, //allow for the text to be reallocated with more data than needed
    client_owned: bool,
    diagnosed_errors: bool,
};

DocumentStorage :: struct {
    documents: map [string] Document,
};

document_storage: DocumentStorage;


document_open :: proc(uri_string: string, text: string, writer: ^Writer) -> Error {

    uri, parsed_ok := parse_uri(uri_string);

    if !parsed_ok {
        return .ParseError;
    }

    if document := &document_storage.documents[uri.path]; document != nil {

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

        if err := document_refresh(document, writer); err != .None {
            return err;
        }

    }

    else {

        document := Document {
            uri = uri.full,
            path = uri.path,
            text = transmute([] u8)text,
            client_owned = true,
            used_text = len(text),
        };

        if err := document_refresh(&document, writer); err != .None {
            return err;
        }

        document_storage.documents[uri.path] = document;
    }



    //hmm feels like odin needs some ownership semantic
    delete(uri_string);

    return .None;
}

/*
    Function that applies changes to the given document through incremental syncronization
 */
document_apply_changes :: proc(uri_string: string, changes: [dynamic] TextDocumentContentChangeEvent, writer: ^Writer) -> Error {

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

        absolute_range, ok := get_absolute_range(change.range, document.text[:document.used_text]);

        if !ok {
            return .ParseError;
        }

        //lower bound is before the change
        lower := document.text[:absolute_range.start];

        //new change between lower and upper
        middle := change.text;

        //upper bound is after the change
        upper := document.text[absolute_range.end:document.used_text];

        //total new size needed
        document.used_text = len(lower) + len(change.text) + len(upper);

        //Reduce the amount of allocation by allocating more memory than needed
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
            //order matters here, we need to make sure we swap the data already in the text before the middle
            copy(document.text, lower);
            copy(document.text[len(lower)+len(middle):], upper);
            copy(document.text[len(lower):], middle);
        }

    }

    return document_refresh(document, writer);
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



document_refresh :: proc(document: ^Document, writer: ^Writer) -> Error {


    document_symbols, errors, ok := parse_document_symbols(document);

    if !ok {
        return .ParseError;
    }

    if len(errors) > 0 {
        document.diagnosed_errors = true;

        params := NotificationPublishDiagnosticsParams {
            uri = document.uri,
            diagnostics = make([] Diagnostic, len(errors), context.temp_allocator),
        };

        for error, i in errors {

            params.diagnostics[i] = Diagnostic {
                range = Range {
                    start = Position {
                        line = error.line - 1,
                        character = 0,
                    },
                    end = Position {
                        line = error.line,
                        character = 0,
                    },
                },
                severity = DiagnosticSeverity.Error,
                code = "test",
                message = error.message,
            };

        }

        notifaction := Notification {
            jsonrpc = "2.0",
            method = "textDocument/publishDiagnostics",
            params = params,
        };

        send_notification(notifaction, writer);

    }

    if len(errors) == 0 {

        //send empty diagnosis to remove the clients errors
        if document.diagnosed_errors {

            notifaction := Notification {
            jsonrpc = "2.0",
            method = "textDocument/publishDiagnostics",

            params = NotificationPublishDiagnosticsParams {
                uri = document.uri,
                diagnostics = make([] Diagnostic, len(errors), context.temp_allocator),
                },
            };

            document.diagnosed_errors = false;

            send_notification(notifaction, writer);
        }

    }

    return .None;
}

