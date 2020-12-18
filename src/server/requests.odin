package server

import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"
import "core:strings"
import "core:slice"
import "core:strconv"
import "core:encoding/json"
import "core:path"
import "core:runtime"
import "core:thread"
import "core:sync"
import "intrinsics"

import "shared:common"
import "shared:index"

Header :: struct {
    content_length: int,
    content_type: string,
};

RequestType :: enum {
    Initialize,
    Initialized,
    Shutdown,
    Exit,
    DidOpen,
    DidChange,
    DidClose,
    DidSave,
    Definition,
    Completion,
    SignatureHelp,
    DocumentSymbol,
    SemanticTokensFull,
    SemanticTokensRange,
    Hover,
    CancelRequest,
};

RequestInfo :: struct {
    root: json.Value,
    params: json.Value,
    document: ^Document,
    id: RequestId,
    config: ^common.Config,
    writer: ^Writer,
    result: common.Error,
};


pool: common.Pool;


get_request_info :: proc(task: ^common.Task) -> ^RequestInfo {
    return cast(^RequestInfo)task.data;
}

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

        index := strings.last_index_byte(message, ':');

        if index == -1 {
            log.error("Failed to find semicolon");
            return header, false;
        }

        header_name := message[0:index];
        header_value := message[len(header_name) + 2 : len(message)-2];

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

    value, err = json.parse(data = data, allocator = context.allocator, parse_integers = true);

    if(err != json.Error.None) {
        log.error("Failed to parse body");
        return value, false;
    }

    return value, true;
}

request_map : map [string] RequestType =
        {"initialize" = .Initialize,
         "initialized" = .Initialized,
         "shutdown" = .Shutdown,
         "exit" = .Exit,
         "textDocument/didOpen" = .DidOpen,
         "textDocument/didChange" = .DidChange,
         "textDocument/didClose" = .DidClose,
         "textDocument/didSave" = .DidSave,
         "textDocument/definition" = .Definition,
         "textDocument/completion" = .Completion,
         "textDocument/signatureHelp" = .SignatureHelp,
         "textDocument/documentSymbol" = .DocumentSymbol,
         "textDocument/semanticTokens/full" = .SemanticTokensFull,
         "textDocument/semanticTokens/range" = .SemanticTokensRange,
         "textDocument/hover" = .Hover,
         "$/cancelRequest" = .CancelRequest };

handle_error :: proc(err: common.Error, id: RequestId, writer: ^Writer) {

    if err != .None {

        response := make_response_message_error(
            id = id,
            error = ResponseError {code = err, message = ""}
        );

        send_error(response, writer);
    }

}

handle_request :: proc(request: json.Value, config: ^common.Config, writer: ^Writer) -> bool {

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

    request_type: RequestType;
    request_type, ok = request_map[method];

    if !ok {
        response := make_response_message_error(
                id = id,
                error = ResponseError {code = .MethodNotFound, message = ""}
            );

        send_error(response, writer);
    }

    else {

        info := new(RequestInfo);

        info.root = request;
        info.params = root["params"];
        info.id = id;
        info.config = config;
        info.writer = writer;

        task_proc: common.Task_Proc;

        switch request_type {
        case .Initialize:
            task_proc = request_initialize;
        case .Initialized:
            task_proc = request_initialized;
        case .Shutdown:
            task_proc = request_shutdown;
        case .Exit:
            task_proc = notification_exit;
        case .DidOpen:
            task_proc = notification_did_open;
        case .DidChange:
            task_proc = notification_did_change;
        case .DidClose:
            task_proc = notification_did_close;
        case .DidSave:
            task_proc = notification_did_save;
        case .Definition:
            task_proc = request_definition;
        case .Completion:
            task_proc = request_completion;
        case .SignatureHelp:
            task_proc = request_signature_help;
        case .DocumentSymbol:
            task_proc = request_document_symbols;
        case .SemanticTokensFull:
            task_proc = request_semantic_token_full;
        case .SemanticTokensRange:
            task_proc = request_semantic_token_range;
        case .Hover:
            task_proc = request_hover;
        case .CancelRequest:
        }

        task := common.Task {
            data = info,
            procedure = task_proc,
        };

        #partial switch request_type {
        case .CancelRequest:
            for {
                if task, ok := common.pool_try_and_pop_task(&pool); ok {
                    common.pool_do_work(&pool, &task);
                }

                else {
                    break;
                }
            }
        case .Initialize, .Initialized:
            task_proc(&task);
        case .Completion, .Definition, .Hover:

            uri := root["params"].value.(json.Object)["textDocument"].value.(json.Object)["uri"].value.(json.String);

            document := document_get(uri);

            if document == nil {
                handle_error(.InternalError, id, writer);
                return false;
            }

            info.document = document;

            task_proc(&task);

        case .DidClose, .DidChange, .DidOpen:

            uri := root["params"].value.(json.Object)["textDocument"].value.(json.Object)["uri"].value.(json.String);

            document := document_get(uri);

            if document != nil {

                for intrinsics.atomic_load(&document.operating_on) > 1 {
                    if task, ok := common.pool_try_and_pop_task(&pool); ok {
                        common.pool_do_work(&pool, &task);
                    }
                }

            }

            task_proc(&task);

            document_release(document);
        case .Shutdown, .Exit:
            task_proc(&task);
        case .SignatureHelp, .SemanticTokensFull, .SemanticTokensRange, .DocumentSymbol:

            uri := root["params"].value.(json.Object)["textDocument"].value.(json.Object)["uri"].value.(json.String);

            document := document_get(uri);

            if document == nil {
                handle_error(.InternalError, id, writer);
                return false;
            }

            info.document = document;

            if !config.debug_single_thread {
                common.pool_add_task(&pool, task_proc, info);
            }

            else{
                task_proc(&task);
            }
        case:

            if !config.debug_single_thread {
                common.pool_add_task(&pool, task_proc, info);
            }

            else {
                task_proc(&task);
            }
        }

    }


    return true;
}

request_initialize :: proc(task: ^common.Task) {
    info := get_request_info(task);

    using info;

    defer json.destroy_value(root);
    defer free(info);

    params_object, ok := params.value.(json.Object);

    if !ok {
        handle_error(.ParseError, id, writer);
        return;
    }

    initialize_params: RequestInitializeParams;

    if unmarshal(params, initialize_params, context.temp_allocator) != .None {
        handle_error(.ParseError, id, writer);
        return;
    }

    config.workspace_folders = make([dynamic]common.WorkspaceFolder);

    for s in initialize_params.workspaceFolders {
        append(&config.workspace_folders, s);
    }

    thread_count := 2;

    enable_document_symbols: bool;
    enable_hover: bool;

    if len(config.workspace_folders) > 0 {

        //right now just look at the first workspace - TODO(daniel, add multiple workspace support)
        if uri, ok := common.parse_uri(config.workspace_folders[0].uri, context.temp_allocator); ok {

            ols_config_path := path.join(elems = {uri.path, "ols.json"}, allocator = context.temp_allocator);

            if data, ok := os.read_entire_file(ols_config_path, context.temp_allocator); ok {

                if value, err := json.parse(data = data, allocator = context.temp_allocator, parse_integers = true); err == .None {

                    ols_config: OlsConfig;

                    if unmarshal(value, ols_config, context.temp_allocator) == .None {

                        thread_count = ols_config.thread_pool_count;
                        enable_document_symbols = ols_config.enable_document_symbols;
                        enable_hover = ols_config.enable_hover;
                        config.enable_semantic_tokens = ols_config.enable_semantic_tokens;

                        for p in ols_config.collections {
                            config.collections[strings.clone(p.name)] = strings.clone(strings.to_lower(p.path, context.temp_allocator));
                        }

                    }

                }

            }

        }

    }

    common.pool_init(&pool, thread_count);
    common.pool_start(&pool);

    //ERROR can't go to defintion
    for format in initialize_params.capabilities.textDocument.hover.contentFormat {
        if format == "markdown" {
            config.hover_support_md = true;
        }
    }


    for format in initialize_params.capabilities.textDocument.completion.documentationFormat {
        if format == "markdown" {
            config.completion_support_md = true;
        }
    }


    config.signature_offset_support = initialize_params.capabilities.textDocument.signatureHelp.signatureInformation.parameterInformation.labelOffsetSupport;

    completionTriggerCharacters := [] string { "." };
    signatureTriggerCharacters := [] string { "(" };

    token_type := type_info_of(SemanticTokenTypes).variant.(runtime.Type_Info_Named).base.variant.(runtime.Type_Info_Enum);
    token_modifier := type_info_of(SemanticTokenModifiers).variant.(runtime.Type_Info_Named).base.variant.(runtime.Type_Info_Enum);

    token_types := make([] string, len(token_type.names), context.temp_allocator);
    token_modifiers := make([] string, len(token_modifier.names), context.temp_allocator);

    for name, i in token_type.names {
        token_types[i] = strings.to_lower(name, context.temp_allocator);
    }

    for name, i in token_modifier.names {
        token_modifiers[i] = strings.to_lower(name, context.temp_allocator);
    }

    response := make_response_message(
        params = ResponseInitializeParams {
            capabilities = ServerCapabilities {
                textDocumentSync = TextDocumentSyncOptions {
                    openClose = true,
                    change = 2, //incremental
                },
                definitionProvider = true,
                completionProvider = CompletionOptions {
                    resolveProvider = false,
                    triggerCharacters = completionTriggerCharacters,
                },
                signatureHelpProvider = SignatureHelpOptions {
                    triggerCharacters = signatureTriggerCharacters,
                },
                semanticTokensProvider = SemanticTokensOptions {
                    range = config.enable_semantic_tokens,
                    full = false,
                    legend = SemanticTokensLegend {
                        tokenTypes = token_types,
                        tokenModifiers = token_modifiers,
                    },
                },
                documentSymbolProvider = enable_document_symbols,
                hoverProvider = enable_hover,
            },
        },
        id = id,
    );

    send_response(response, writer);

    /*
        Temp index here, but should be some background thread that starts the indexing
    */

    index.build_static_index(context.allocator, config);

    /*
        Add the builtin and runtime package
    */

    if core, ok := config.collections["core"]; ok {
        append(&index.indexer.built_in_packages, path.join(core, "builtin"));
        append(&index.indexer.built_in_packages, path.join(core, "runtime"));
    }

    log.info("Finished indexing");
}

request_initialized :: proc(task: ^common.Task) {
    info := get_request_info(task);

    using info;

    json.destroy_value(root);
    free(info);
}

request_shutdown :: proc(task: ^common.Task) {

    info := get_request_info(task);

    using info;

    defer json.destroy_value(root);
    defer free(info);

    response := make_response_message(
        params = nil,
        id = id,
    );

    send_response(response, writer);


}

request_definition :: proc(task: ^common.Task) {

    info := get_request_info(task);

    using info;

    defer document_release(document);
    defer free(info);
    defer json.destroy_value(root);

    params_object, ok := params.value.(json.Object);

    if !ok {
        handle_error(.ParseError, id, writer);
        return;
    }

    definition_params: TextDocumentPositionParams;

    if unmarshal(params, definition_params, context.temp_allocator) != .None {
        handle_error(.ParseError, id, writer);
        return;
    }

    location, ok2 := get_definition_location(document, definition_params.position);

    if !ok2 {
        log.error("Failed to get definition location");
    }

    response := make_response_message(
        params = location,
        id = id,
    );

    send_response(response, writer);
}


request_completion :: proc(task: ^common.Task) {

    info := get_request_info(task);

    using info;

    defer document_release(document);
    defer json.destroy_value(root);
    defer free(info);

    params_object, ok := params.value.(json.Object);

    if !ok {
        handle_error(.ParseError, id, writer);
        return;
    }

    completition_params: CompletionParams;


    if unmarshal(params, completition_params, context.temp_allocator) != .None {
        log.error("Failed to unmarshal completion request");
        handle_error(.ParseError, id, writer);
        return;
    }

    list: CompletionList;
    list, ok = get_completion_list(document, completition_params.position);

    if !ok {
        handle_error(.InternalError, id, writer);
        return;
    }

    response := make_response_message(
        params = list,
        id = id,
    );

    send_response(response, writer);
}

request_signature_help :: proc(task: ^common.Task) {

    info := get_request_info(task);

    using info;

    defer document_release(document);
    defer json.destroy_value(root);
    defer free(info);

    params_object, ok := params.value.(json.Object);

    if !ok {
        handle_error(.ParseError, id, writer);
        return;
    }

    signature_params: SignatureHelpParams;

    if unmarshal(params, signature_params, context.temp_allocator) != .None {
        handle_error(.ParseError, id, writer);
        return;
    }

    help: SignatureHelp;
    help, ok = get_signature_information(document, signature_params.position);

    response := make_response_message(
        params = help,
        id = id,
    );

    send_response(response, writer);
}

notification_exit :: proc(task: ^common.Task) {
    info := get_request_info(task);
    using info;

    defer json.destroy_value(root);
    defer free(info);

    config.running = false;
}

notification_did_open :: proc(task: ^common.Task) {

    info := get_request_info(task);

    using info;

    defer json.destroy_value(root);
    defer free(info);

    params_object, ok := params.value.(json.Object);

    if !ok {
        log.error("Failed to parse open document notification");
        handle_error(.ParseError, id, writer);
        return;
    }

    open_params: DidOpenTextDocumentParams;

    if unmarshal(params, open_params, context.allocator) != .None {
        log.error("Failed to parse open document notification");
        handle_error(.ParseError, id, writer);
        return;
    }

    if n := document_open(open_params.textDocument.uri, open_params.textDocument.text, config, writer); n != .None {
        handle_error(n, id, writer);
    }
}

notification_did_change :: proc(task: ^common.Task) {

    info := get_request_info(task);

    using info;

    defer json.destroy_value(root);
    defer free(info);

    params_object, ok := params.value.(json.Object);

    if !ok {
        handle_error(.ParseError, id, writer);
        return;
    }

    change_params: DidChangeTextDocumentParams;

    if unmarshal(params, change_params, context.temp_allocator) != .None {
        handle_error(.ParseError, id, writer);
        return;
    }


    document_apply_changes(change_params.textDocument.uri, change_params.contentChanges, config, writer);
}

notification_did_close :: proc(task: ^common.Task) {

    info := get_request_info(task);

    using info;

    defer json.destroy_value(root);
    defer free(info);

    params_object, ok := params.value.(json.Object);

    if !ok {
        handle_error(.ParseError, id, writer);
        return;
    }

    close_params: DidCloseTextDocumentParams;

    if unmarshal(params, close_params, context.temp_allocator) != .None {
        handle_error(.ParseError, id, writer);
        return;
    }

    if n := document_close(close_params.textDocument.uri); n != .None {
        handle_error(n, id, writer);
        return;
    }
}

notification_did_save :: proc(task: ^common.Task) {
    info := get_request_info(task);

    using info;

    json.destroy_value(root);
    free(info);
}

request_semantic_token_full :: proc(task: ^common.Task) {

    info := get_request_info(task);

    using info;

    defer document_release(document);
    defer json.destroy_value(root);
    defer free(info);

    params_object, ok := params.value.(json.Object);

    if !ok {
        handle_error(.ParseError, id, writer);
        return;
    }

    semantic_params: SemanticTokensParams;

    if unmarshal(params, semantic_params, context.temp_allocator) != .None {
        handle_error(.ParseError, id, writer);
        return;
    }

    range := common.Range {
        start = common.Position {
            line = 0,
        },

        end = common.Position {
            line = 9000000, //should be enough
        }
    };

    symbols: SemanticTokens;

    if false && config.enable_semantic_tokens {
        symbols = get_semantic_tokens(document, range);
    }

    response := make_response_message(
        params = symbols,
        id = id,
    );

    send_response(response, writer);
}

request_semantic_token_range :: proc(task: ^common.Task) {

    info := get_request_info(task);

    using info;

    params_object, ok := params.value.(json.Object);

    defer document_release(document);
    defer json.destroy_value(root);
    defer free(info);

    if !ok {
        handle_error(.ParseError, id, writer);
        return;
    }

    semantic_params: SemanticTokensRangeParams;

    if unmarshal(params, semantic_params, context.temp_allocator) != .None {
        handle_error(.ParseError, id, writer);
        return;
    }

    symbols: SemanticTokens;

    if false && config.enable_semantic_tokens {
        symbols = get_semantic_tokens(document, semantic_params.range);
    }

    response := make_response_message(
        params = symbols,
        id = id,
    );

    send_response(response, writer);
}

request_document_symbols :: proc(task: ^common.Task) {

    info := get_request_info(task);

    using info;

    defer document_release(document);
    defer json.destroy_value(root);
    defer free(info);

    params_object, ok := params.value.(json.Object);

    if !ok {
        handle_error(.ParseError, id, writer);
        return;
    }

    symbol_params: DocumentSymbolParams;

    if unmarshal(params, symbol_params, context.temp_allocator) != .None {
        handle_error(.ParseError, id, writer);
        return;
    }

    symbols := get_document_symbols(document);

    response := make_response_message(
        params = symbols,
        id = id,
    );

    send_response(response, writer);
}

request_hover :: proc(task: ^common.Task) {

    info := get_request_info(task);

    using info;

    defer document_release(document);
    defer json.destroy_value(root);
    defer free(info);

    params_object, ok := params.value.(json.Object);

    if !ok {
        handle_error(.ParseError, id, writer);
        return;
    }

    hover_params: HoverParams;

    if unmarshal(params, hover_params, context.temp_allocator) != .None {
        handle_error(.ParseError, id, writer);
        return;
    }

    hover: Hover;
    hover, ok = get_hover_information(document, hover_params.position);

    if !ok {
        handle_error(.InternalError, id, writer);
        return;
    }

    response := make_response_message(
        params = hover,
        id = id,
    );

    send_response(response, writer);
}