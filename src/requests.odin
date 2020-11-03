package main 

import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"
import "core:strings"
import "core:slice"
import "core:strconv"
import "core:encoding/json"


Header :: struct {
    content_length: int,
    content_type: string,
};

make_response_message :: proc(id: RequestId, params: ResponseParams) -> ResponseMessage {

    return ResponseMessage {
        jsonrpc = "2.0",
        id = id,
        result = params,
    };

}

make_response_message_error :: proc(id: RequestId, error: ResponseError) -> ResponseMessageError {

    return ResponseMessageError {
        jsonrpc = "2.0",
        id = id,
        error = error,
    };

}

read_and_parse_header :: proc(reader: ^Reader) -> (Header, bool) {

    header: Header;

    builder := strings.make_builder(context.temp_allocator);

    found_content_length := false;

    for true {

        strings.reset_builder(&builder);

        if !read_until_delimiter(reader, '\n', &builder) {
            log.error("Failed to read with delimiter");
            return header, false;
        }

        message := strings.to_string(builder);

        if len(message) == 0 || message[len(message)-2] != '\r' {
            log.error("No carriage return");
            return header, false;
        }

        if len(message)==2 {
            break;
        }

        index := strings.last_index_byte (message, ':');

        if index == -1 {
            log.error("Failed to find semicolon");
            return header, false;
        }

        header_name := message[0 : index];
        header_value := message[len(header_name) + 2 : len(message)-1];

        if strings.compare(header_name, "Content-Length") == 0 {

            if len(header_value) == 0 {
                log.error("Header value has no length");
                return header, false;
            }

            value, ok := strconv.parse_int(header_value);

            if !ok {
                log.error("Failed to parse content length value");
                return header, false;
            }

            header.content_length = value;

            found_content_length = true;

        }

        else if strings.compare(header_name, "Content-Type") == 0 {
            if len(header_value) == 0 {
                log.error("Header value has no length");
                return header, false;
            }
        }
        
    }

    return header, found_content_length;
}

read_and_parse_body :: proc(reader: ^Reader, header: Header) -> (json.Value, bool) {

    value: json.Value;

    data := make([]u8, header.content_length, context.temp_allocator);

    if !read_sized(reader, data) {
        log.error("Failed to read body");
        return value, false;
    }

    err: json.Error;

    value, err = json.parse(data = data, allocator = context.temp_allocator, parse_integers = true);

    if(err != json.Error.None) {
        log.error("Failed to parse body");
        return value, false;
    }

    return value, true;
} 


handle_request :: proc(request: json.Value, config: ^Config, writer: ^Writer) -> bool {
    log.info("Handling request");
    
    root, ok := request.value.(json.Object);

    if !ok  {
        log.error("No root object");
        return false;
    }

    id: RequestId;
    id_value: json.Value;
    id_value, ok = root["id"];

    if ok  {
        #partial
        switch v in id_value.value {
        case json.String:
            id = v;
        case json.Integer:
            id = v;
        case:
            id = 0; 
        }
    }

    method := root["method"].value.(json.String);

    call_map : map [string] proc(json.Value, RequestId, ^Config, ^Writer) -> Error = 
        {"initialize" = request_initialize,
         "initialized" = request_initialized,
         "shutdown" = request_shutdown,
         "exit" = notification_exit,
         "textDocument/didOpen" = notification_did_open,
         "textDocument/didChange" = notification_did_change,
         "textDocument/didClose" = notification_did_close};

    fn: proc(json.Value, RequestId, ^Config, ^Writer) -> Error;
    fn, ok = call_map[method];


    if !ok {
        response := make_response_message_error(
                id = id,
                error = ResponseError {code = .MethodNotFound, message = ""}
            );

        send_error(response, writer);
    }

    else {
        err := fn(root["params"], id, config, writer);

        if err != .None {

            response := make_response_message_error(
                id = id,
                error = ResponseError {code = err, message = ""}
            );

            send_error(response, writer);
        }
    }

    return true;
}

request_initialize :: proc(params: json.Value, id: RequestId, config: ^Config, writer: ^Writer) -> Error {  

    params_object, ok := params.value.(json.Object);

    if !ok {
        return .ParseError;
    }

    initialize_params: RequestInitializeParams;

    if unmarshal(params, initialize_params, context.temp_allocator) != .None {
        return  .ParseError;
    }

    config.workspace_folders = make([dynamic]WorkspaceFolder);

    for s in initialize_params.workspaceFolders {
        append_elem(&config.workspace_folders, s);
    }

    for format in initialize_params.capabilities.textDocument.hover.contentFormat {
        if format == .Markdown {
            config.hover_support_md = true;
        }
    }
    
    response := make_response_message(   
        params = ResponseInitializeParams {
            capabilities = ServerCapabilities {
                textDocumentSync = 2, //incremental
            },
        },
        id = id,
    );

    send_response(response, writer);

    return .None;
}

request_initialized :: proc(params: json.Value, id: RequestId, config: ^Config, writer: ^Writer) -> Error {
    return .None;
}

request_shutdown :: proc(params: json.Value, id: RequestId, config: ^Config, writer: ^Writer) -> Error {

    response := make_response_message(   
        params = nil,
        id = id,
    );

    send_response(response, writer);

    return .None;
}

notification_exit :: proc(params: json.Value, id: RequestId, config: ^Config, writer: ^Writer) -> Error {
    running = false;
    return .None;
}

notification_did_open :: proc(params: json.Value, id: RequestId, config: ^Config, writer: ^Writer) -> Error {

    params_object, ok := params.value.(json.Object);

    if !ok {
        return .ParseError;
    }

    open_params: DidOpenTextDocumentParams;

    if unmarshal(params, open_params, context.allocator) != .None {
        return .ParseError;
    }
   
    return document_open(open_params.textDocument.uri, open_params.textDocument.text);
}

notification_did_change :: proc(params: json.Value, id: RequestId, config: ^Config, writer: ^Writer) -> Error {

    params_object, ok := params.value.(json.Object);

    if !ok {
        return .ParseError;
    }

    change_params: DidChangeTextDocumentParams;

    if unmarshal(params, change_params, context.temp_allocator) != .None {
        return .ParseError;
    }

    fmt.println(change_params);

    return .None;
}

notification_did_close :: proc(params: json.Value, id: RequestId, config: ^Config, writer: ^Writer) -> Error {

    params_object, ok := params.value.(json.Object);

    if !ok {
        return .ParseError;
    }

    close_params: DidCloseTextDocumentParams;

    if unmarshal(params, close_params, context.temp_allocator) != .None {
        return .ParseError;
    }

    return document_close(close_params.textDocument.uri, close_params.textDocument.text);
}

