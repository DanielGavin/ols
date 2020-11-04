package main

import "core:strings"
import "core:fmt"
import "core:log"
import "core:os"

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
    symbols: DocumentSymbols,
};

DocumentStorage :: struct {
    documents: map [string] Document,
};

document_storage: DocumentStorage;

/*
    Note(Daniel, Should there be reference counting of documents or just clear everything on workspace change?
        You usually always need the documents that are loaded in core files, your own files, etc.)
 */

/*
    Server opens a new document with text from filesystem
*/
document_new :: proc(path: string, config: ^Config) -> Error {

    text, ok := os.read_entire_file(path);

    cloned_path := strings.clone(path);

    if !ok {
        return .ParseError;
    }

    document := Document {
        uri = cloned_path,
        path = cloned_path,
        text = transmute([] u8)text,
        client_owned = true,
        used_text = len(text),
    };

    if err := document_refresh(&document, config, nil); err != .None {
        return err;
    }

    document_storage.documents[path] = document;

    return .None;
}

/*
    Client opens a document with transferred text
*/

document_open :: proc(uri_string: string, text: string, config: ^Config, writer: ^Writer) -> Error {

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

        if len(document.uri) > 0 {
            delete(document.uri);
        }

        document.uri = uri.full;
        document.path = uri.path;
        document.client_owned = true;
        document.text = transmute([] u8)text;
        document.used_text = len(document.text);

        if err := document_refresh(document, config, writer); err != .None {
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

        if err := document_refresh(&document, config, writer); err != .None {
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
document_apply_changes :: proc(uri_string: string, changes: [dynamic] TextDocumentContentChangeEvent, config: ^Config, writer: ^Writer) -> Error {

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

    return document_refresh(document, config, writer);
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



document_refresh :: proc(document: ^Document, config: ^Config, writer: ^Writer) -> Error {


    document_symbols, errors, package_name, imports, ok := parse_document_symbols(document, config);

    document.symbols = document_symbols;

    if !ok {
        return .ParseError;
    }

    //right now we don't allow to writer errors out from files read from the file directory, core files, etc.
    if writer != nil && len(errors) > 0 {
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

    if writer != nil && len(errors) == 0 {

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


    /*
        go through the imports from this document and see if we need to load them into memory(not owned by client),
        and also refresh them if needed
    */
    for imp in imports {

        if err := document_load_package(imp, config); err != .None {
            return err;
        }

    }


    return .None;
}

document_load_package :: proc(package_directory: string, config: ^Config) -> Error {

    fd, err := os.open(package_directory);

    if err != 0 {
        return .ParseError;
    }

    files: []os.File_Info;
    files, err = os.read_dir(fd, 100, context.temp_allocator);

    for file in files {

        //if we have never encountered the document
        if _, ok := document_storage.documents[file.fullpath]; !ok {

            if doc_err := document_new(file.fullpath, config); doc_err != .None {
                return doc_err;
            }

        }

    }

    return .None;
}
