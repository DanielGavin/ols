package server

import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"
import "core:strings"
import "core:slice"
import "core:strconv"
import "core:encoding/json"
import path "core:path/slashpath"
import "core:runtime"
import "core:thread"
import "core:sync"
import "core:path/filepath"
import "core:intrinsics"
import "core:odin/ast"
import "core:odin/parser"
import "core:time"

import "shared:common"

Header :: struct {
	content_length: int,
	content_type:   string,
}

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
	FormatDocument,
	Hover,
	CancelRequest,
	InlayHint,
}

RequestInfo :: struct {
	root:     json.Value,
	params:   json.Value,
	document: ^common.Document,
	id:       RequestId,
	config:   ^common.Config,
	writer:   ^Writer,
	result:   common.Error,
}


make_response_message :: proc (id: RequestId, params: ResponseParams) -> ResponseMessage {

	return ResponseMessage {
		jsonrpc = "2.0",
		id = id,
		result = params,
	}
}

make_response_message_error :: proc (id: RequestId, error: ResponseError) -> ResponseMessageError {

	return ResponseMessageError {
		jsonrpc = "2.0",
		id = id,
		error = error,
	}
}

RequestThreadData :: struct {
	reader: ^Reader,
	writer: ^Writer,
}

Request :: struct {
	id:              RequestId,
	value:           json.Value,
	is_notification: bool,
}


requests_sempahore: sync.Sema
requests_mutex: sync.Mutex

requests: [dynamic]Request
deletings: [dynamic]Request

thread_request_main :: proc(data: rawptr) {
	request_data := cast(^RequestThreadData)data

	for common.config.running {
		header, success := read_and_parse_header(request_data.reader)

		if (!success) {
			log.error("Failed to read and parse header")
			return
		}

		value: json.Value
		value, success = read_and_parse_body(request_data.reader, header)

		if (!success) {
			log.error("Failed to read and parse body")
			return
		}

		root, ok := value.(json.Object)

		if !ok {
			log.error("No root object")
			return
		}

		id: RequestId
		id_value: json.Value
		id_value, ok = root["id"]

		if ok {
			#partial switch v in id_value {
			case json.String:
				id = v
			case json.Integer:
				id = v
			case:
				id = 0
			}
		}

		sync.mutex_lock(&requests_mutex)

		method := root["method"].(json.String)

		if method == "$/cancelRequest" {
			append(&deletings, Request { id = id })
			json.destroy_value(root)
		} else if method in notification_map {
			append(&requests, Request { value = root, is_notification = true})
			sync.sema_post(&requests_sempahore)
		} else {
			append(&requests, Request { id = id, value = root})
			sync.sema_post(&requests_sempahore)
		}

		sync.mutex_unlock(&requests_mutex)

		free_all(context.temp_allocator)
	}
}

read_and_parse_header :: proc (reader: ^Reader) -> (Header, bool) {
	header: Header

	builder := strings.make_builder(context.temp_allocator)
	
	found_content_length := false

	for true {

		strings.reset_builder(&builder)

		if !read_until_delimiter(reader, '\n', &builder) {
			log.error("Failed to read with delimiter")
			return header, false
		}

		message := strings.to_string(builder)

		if len(message) == 0 || message[len(message) - 2] != '\r' {
			log.error("No carriage return")
			return header, false
		}

		if len(message) == 2 {
			break
		}

		index := strings.last_index_byte(message, ':')

		if index == -1 {
			log.error("Failed to find semicolon")
			return header, false
		}

		header_name  := message[0:index]
		header_value := message[len(header_name) + 2:len(message) - 2]

		if strings.compare(header_name, "Content-Length") == 0 {
			if len(header_value) == 0 {
				log.error("Header value has no length")
				return header, false
			}

			value, ok := strconv.parse_int(header_value)

			if !ok {
				log.error("Failed to parse content length value")
				return header, false
			}

			header.content_length = value

			found_content_length = true
		} else if strings.compare(header_name, "Content-Type") == 0 {
			if len(header_value) == 0 {
				log.error("Header value has no length")
				return header, false
			}
		}
	}

	return header, found_content_length
}

read_and_parse_body :: proc (reader: ^Reader, header: Header) -> (json.Value, bool) {
	value: json.Value

	data := make([]u8, header.content_length, context.temp_allocator)

	if !read_sized(reader, data) {
		log.error("Failed to read body")
		return value, false
	}

	err: json.Error

	value, err = json.parse(data = data, allocator = context.allocator, parse_integers = true)

	if (err != json.Error.None) {
		log.error("Failed to parse body")
		return value, false
	}

	return value, true
}

call_map : map [string] proc(json.Value, RequestId, ^common.Config, ^Writer) -> common.Error =
{
	"initialize" = request_initialize,
	"initialized" = request_initialized,
	"shutdown" = request_shutdown,
	"exit" = notification_exit,
	"textDocument/didOpen" = notification_did_open,
	"textDocument/didChange" = notification_did_change,
	"textDocument/didClose" = notification_did_close,
	"textDocument/didSave" = notification_did_save,
	"textDocument/definition" = request_definition,
	"textDocument/completion" = request_completion,
	"textDocument/signatureHelp" = request_signature_help,
	"textDocument/documentSymbol" = request_document_symbols,
	"textDocument/semanticTokens/full" = request_semantic_token_full,
	"textDocument/semanticTokens/range" = request_semantic_token_range,
	"textDocument/hover" = request_hover,
	"textDocument/formatting" = request_format_document,
	"odin/inlayHints" = request_inlay_hint,
	"textDocument/documentLink" = request_document_links,
	"textDocument/rename" = request_rename,
	"textDocument/references" = request_references,
}

notification_map: map [string] bool = {
	"textDocument/didOpen" = true,
	"textDocument/didChange" = true,
	"textDocument/didClose" = true,
	"textDocument/didSave" = true,
	"initialized" = true,
}

consume_requests :: proc (config: ^common.Config, writer: ^Writer) -> bool {
	temp_requests := make([dynamic]Request, 0, context.temp_allocator)

	sync.mutex_lock(&requests_mutex)

	for d in deletings {
		delete_index := -1
		for request, i in requests {			
			if request.id == d.id {
				delete_index := i
				break
			}
		}		
		if delete_index != -1 {
			cancel(requests[delete_index].value, requests[delete_index].id, writer, config)
			ordered_remove(&requests, delete_index)
		}
	}

	for request in requests {
		append(&temp_requests, request)
	}

	sync.mutex_unlock(&requests_mutex)

	request_index := 0

	for ; request_index < len(temp_requests); request_index += 1 {
		request := temp_requests[request_index]
		call(request.value, request.id, writer, config)
		json.destroy_value(request.value)
	}
	
	sync.mutex_lock(&requests_mutex)
	
	for i := 0; i < request_index; i += 1 {
		pop_front(&requests)
	}

	sync.mutex_unlock(&requests_mutex)

	if request_index != len(temp_requests) {
		sync.sema_post(&requests_sempahore)
	}

	if common.config.running {
		sync.sema_wait(&requests_sempahore)
	}

	return true
}


cancel :: proc(value: json.Value, id: RequestId, writer: ^Writer, config: ^common.Config) {
	response := make_response_message(
		id = id,
		params = ResponseParams {},
	)

	json.destroy_value(value)

	send_response(response, writer)
}

call :: proc(value: json.Value, id: RequestId, writer: ^Writer, config: ^common.Config) {
	root := value.(json.Object)
	method := root["method"].(json.String)

	diff: time.Duration
	{
		time.SCOPED_TICK_DURATION(&diff)
		
		if fn, ok := call_map[method]; !ok {
			response := make_response_message_error(id = id, error = ResponseError {code = .MethodNotFound, message = ""})
			send_error(response, writer)
		} else {
			err := fn(root["params"], id, config, writer)
			if err != .None {
				response := make_response_message_error(
					id = id,
					error = ResponseError {code = err, message = ""},
				)
				send_error(response, writer)
			}
		}
	}

	log.infof("time duration %v for %v", time.duration_milliseconds(diff), method)
}

request_initialize :: proc (params: json.Value, id: RequestId, config: ^common.Config, writer: ^Writer) -> common.Error {
	params_object, ok := params.(json.Object)
	
    if !ok {
        return .ParseError
    }

	initialize_params: RequestInitializeParams

	if unmarshal(params, initialize_params, context.temp_allocator) != nil {
		return .ParseError
	}

	config.workspace_folders = make([dynamic]common.WorkspaceFolder)

	for s in initialize_params.workspaceFolders {
		append(&config.workspace_folders, s)
	}

	read_ols_config :: proc(file: string, config: ^common.Config, uri: common.Uri) {
		if data, ok := os.read_entire_file(file, context.temp_allocator); ok {

			if value, err := json.parse(data = data, allocator = context.temp_allocator, parse_integers = true); err == .None {
				ols_config := OlsConfig {
					formatter = {
						characters = 90,
						tabs = true,
					},
				}

				if unmarshal(value, ols_config, context.temp_allocator) == nil {

					config.thread_count = ols_config.thread_pool_count
					config.enable_document_symbols = ols_config.enable_document_symbols
					config.enable_hover = ols_config.enable_hover
					config.enable_format = true // ols_config.enable_format;
					config.enable_semantic_tokens = ols_config.enable_semantic_tokens
					config.enable_procedure_context = ols_config.enable_procedure_context
					config.enable_snippets = ols_config.enable_snippets
					config.verbose = ols_config.verbose
					config.file_log = ols_config.file_log
					config.formatter = ols_config.formatter
					config.odin_command = strings.clone(ols_config.odin_command, context.allocator)
					config.checker_args = ols_config.checker_args
					config.enable_inlay_hints = ols_config.enable_inlay_hints
					
					for p in ols_config.collections {

						forward_path, _ := filepath.to_slash(p.path, context.temp_allocator)

						if filepath.is_abs(p.path) {
							config.collections[strings.clone(p.name)] = strings.clone(forward_path)
						} else {
							config.collections[strings.clone(p.name)] = path.join(elems = {uri.path, forward_path}, allocator = context.allocator)
						}
					}

					if ok := "" in config.collections; !ok {
						config.collections[""] = strings.clone(uri.path)
					}
				} else {
					log.errorf("Failed to unmarshal %v", file)
				}
			} else {
				log.errorf("Failed to parse json %v", file)
			}
		} else {
			log.errorf("Failed to read/find %v", file)
		}
	}

	project_uri := ""

	if len(config.workspace_folders) > 0 {
		project_uri = config.workspace_folders[0].uri
	} else if initialize_params.rootUri != "" {
		project_uri = initialize_params.rootUri
	}

	if uri, ok := common.parse_uri(project_uri, context.temp_allocator); ok {
		ols_config_path := path.join(elems = {uri.path, "ols.json"}, allocator = context.temp_allocator)
		read_ols_config(ols_config_path, config, uri)
	}

	odin_core_env := os.get_env("ODIN_ROOT", context.temp_allocator)

	if "core" not_in config.collections && odin_core_env != "" {
		forward_path, _ := filepath.to_slash(odin_core_env, context.temp_allocator)
		config.collections["core"] = path.join(elems = {forward_path, "core"}, allocator = context.allocator)
	}

	if "vendor" not_in config.collections && odin_core_env != "" {
		forward_path, _ := filepath.to_slash(odin_core_env, context.temp_allocator)
		config.collections["vendor"] = path.join(elems = {forward_path, "vendor"}, allocator = context.allocator)
	}

	when ODIN_OS == .Windows {
		for k, v in config.collections {
			forward, _ := filepath.to_slash(common.get_case_sensitive_path(v), context.temp_allocator)
			config.collections[k] = strings.clone(forward, context.allocator)
		}
	}

	for format in initialize_params.capabilities.textDocument.hover.contentFormat {
		if format == "markdown" {
			config.hover_support_md = true
		}
	}

	for format in initialize_params.capabilities.textDocument.completion.documentationFormat {
		if format == "markdown" {
			config.completion_support_md = true
		}
	}

	config.enable_snippets &= initialize_params.capabilities.textDocument.completion.completionItem.snippetSupport
	config.signature_offset_support = initialize_params.capabilities.textDocument.signatureHelp.signatureInformation.parameterInformation.labelOffsetSupport

	completionTriggerCharacters  := []string {".", ">", "#", "\"", "/", ":"}
	signatureTriggerCharacters   := []string {"(", ","}
	signatureRetriggerCharacters := []string {","}

	token_type     := type_info_of(SemanticTokenTypes).variant.(runtime.Type_Info_Named).base.variant.(runtime.Type_Info_Enum)
	token_modifier := type_info_of(SemanticTokenModifiers).variant.(runtime.Type_Info_Named).base.variant.(runtime.Type_Info_Enum)

	token_types     := make([]string, len(token_type.names), context.temp_allocator)
	token_modifiers := make([]string, len(token_modifier.names), context.temp_allocator)

	for name, i in token_type.names {
		if name == "EnumMember" { 
			token_types[i] = "enumMember"
		}
		else {
			token_types[i] = strings.to_lower(name, context.temp_allocator)
		}
	}

	for name, i in token_modifier.names {
		token_modifiers[i] = strings.to_lower(name, context.temp_allocator)
	}

	response := make_response_message(
	params = ResponseInitializeParams {
		capabilities = ServerCapabilities {
			textDocumentSync = TextDocumentSyncOptions {
				openClose = true,
				change = 2, //incremental
				save = {
					includeText = true,
				},
			},
			renameProvider = config.enable_rename,
			referencesProvider = config.enable_references,
			definitionProvider = true,
			completionProvider = CompletionOptions {
				resolveProvider = false,
				triggerCharacters = completionTriggerCharacters,
			},
			signatureHelpProvider = SignatureHelpOptions {
				triggerCharacters = signatureTriggerCharacters,
				retriggerCharacters = signatureRetriggerCharacters,
			},
			semanticTokensProvider = SemanticTokensOptions {
				range = config.enable_semantic_tokens,
				full = config.enable_semantic_tokens,
				legend = SemanticTokensLegend {
					tokenTypes = token_types,
					tokenModifiers = token_modifiers,
				},
			},
			inlayHintsProvider = config.enable_inlay_hints,
			documentSymbolProvider = config.enable_document_symbols,
			hoverProvider = config.enable_hover,
			documentFormattingProvider = config.enable_format,
			documentLinkProvider = {
				resolveProvider = false,
			},
		},
	}, id = id)

	send_response(response, writer)

	/*
		Temp index here, but should be some background thread that starts the indexing
	*/

	indexer.dynamic_index = make_memory_index(make_symbol_collection(context.allocator, config))
	indexer.dynamic_uri_owned = make(map[string]bool, 200, context.allocator)

	build_static_index(context.allocator, config)

	/*
		Add runtime package
	*/

	if core, ok := config.collections["core"]; ok {
		append(&indexer.builtin_packages, path.join(core, "runtime"))
	}

	log.info("Finished indexing")

	return .None
}

request_initialized :: proc(params: json.Value, id: RequestId, config: ^common.Config, writer: ^Writer) -> common.Error {
    return .None
}

request_shutdown :: proc (params: json.Value, id: RequestId, config: ^common.Config, writer: ^Writer) -> common.Error {
	response := make_response_message(params = nil, id = id)

	send_response(response, writer)

	return .None
}

request_definition :: proc (params: json.Value, id: RequestId, config: ^common.Config, writer: ^Writer) -> common.Error {
	params_object, ok := params.(json.Object)

	if !ok {
		return .ParseError
	}

	definition_params: TextDocumentPositionParams

	if unmarshal(params, definition_params, context.temp_allocator) != nil {
		return .ParseError
	}
	
	document := document_get(definition_params.textDocument.uri)

    if document == nil {
        return .InternalError
    }

	locations, ok2 := get_definition_location(document, definition_params.position)

	if !ok2 {
		log.warn("Failed to get definition location")
	}

	if len(locations) == 1 {
		response := make_response_message(params = locations[0], id = id)
		send_response(response, writer)
	} else {
		response := make_response_message(params = locations, id = id)
		send_response(response, writer)
	}

	return .None
}

request_completion :: proc (params: json.Value, id: RequestId, config: ^common.Config, writer: ^Writer) -> common.Error {
	params_object, ok := params.(json.Object)

	if !ok {
		return .ParseError
	}

	completition_params: CompletionParams

	if unmarshal(params, completition_params, context.temp_allocator) != nil {
		log.error("Failed to unmarshal completion request")
		return .ParseError
	}

	document := document_get(completition_params.textDocument.uri)

    if document == nil {
        return .InternalError
    }

	list: CompletionList
	list, ok = get_completion_list(document, completition_params.position, completition_params.context_)

	if !ok {
		return .InternalError
	}

	response := make_response_message(params = list, id = id)

	send_response(response, writer)

	return .None
}

request_signature_help :: proc (params: json.Value, id: RequestId, config: ^common.Config, writer: ^Writer) -> common.Error {
	params_object, ok := params.(json.Object)

	if !ok {
		return .ParseError
	}

	signature_params: SignatureHelpParams

	if unmarshal(params, signature_params, context.temp_allocator) != nil {
		return .ParseError
	}

	document := document_get(signature_params.textDocument.uri)

    if document == nil {
        return .InternalError
    }

	help: SignatureHelp
	help, ok = get_signature_information(document, signature_params.position)

	if !ok {
		return .InternalError
	}

	if len(help.signatures) == 0 {
		response := make_response_message(params = nil, id = id)
		send_response(response, writer)
	} else {
		response := make_response_message(params = help, id = id)
		send_response(response, writer)
	}


	return .None
}

request_format_document :: proc (params: json.Value, id: RequestId, config: ^common.Config, writer: ^Writer) -> common.Error {
	params_object, ok := params.(json.Object)

	if !ok {
		return .ParseError
	}

	format_params: DocumentFormattingParams

	if unmarshal(params, format_params, context.temp_allocator) != nil {
		return .ParseError
	}

	document := document_get(format_params.textDocument.uri)
	
    if document == nil {
        return .InternalError
    }

	edit: []TextEdit
	edit, ok = get_complete_format(document, config)

	if !ok {
		return .InternalError
	}

	response := make_response_message(params = edit, id = id)

	send_response(response, writer)

	return .None
}

notification_exit :: proc (params: json.Value, id: RequestId, config: ^common.Config, writer: ^Writer) -> common.Error {
	config.running = false
	return .None
}

notification_did_open :: proc (params: json.Value, id: RequestId, config: ^common.Config, writer: ^Writer) -> common.Error {
	params_object, ok := params.(json.Object)

	if !ok {
		log.error("Failed to parse open document notification")
		return .ParseError
	}

	open_params: DidOpenTextDocumentParams

	if unmarshal(params, open_params, context.allocator) != nil {
		log.error("Failed to parse open document notification")
		return .ParseError
	}

	if n := document_open(open_params.textDocument.uri, open_params.textDocument.text, config, writer); n != .None {
		return .InternalError
	}

	return .None
}

notification_did_change :: proc (params: json.Value, id: RequestId, config: ^common.Config, writer: ^Writer) -> common.Error {
	params_object, ok := params.(json.Object)

	if !ok {
		return .ParseError
	}

	change_params: DidChangeTextDocumentParams

	if unmarshal(params, change_params, context.temp_allocator) != nil {
		return .ParseError
	}

	document_apply_changes(change_params.textDocument.uri, change_params.contentChanges, change_params.textDocument.version, config, writer)

	return .None
}

notification_did_close :: proc(params: json.Value, id: RequestId, config: ^common.Config, writer: ^Writer) -> common.Error {
	params_object, ok := params.(json.Object)

	if !ok {
		return .ParseError
	}

	close_params: DidCloseTextDocumentParams

	if unmarshal(params, close_params, context.temp_allocator) != nil {
		return .ParseError
	}

	if n := document_close(close_params.textDocument.uri); n != nil {
		return .InternalError
	}

	return .None
}

notification_did_save :: proc (params: json.Value, id: RequestId, config: ^common.Config, writer: ^Writer) -> common.Error {
	params_object, ok := params.(json.Object)

	if !ok {
		return .ParseError
	}

	save_params: DidSaveTextDocumentParams

	if unmarshal(params, save_params, context.temp_allocator) != nil {
		return .ParseError
	}

	uri: common.Uri

	if uri, ok = common.parse_uri(save_params.textDocument.uri, context.temp_allocator); !ok {
		return .ParseError
	}

	fullpath := uri.path

	p := parser.Parser {
		err = log_error_handler,
		warn = log_warning_handler,
		flags = {.Optional_Semicolons},
	}

	when ODIN_OS == .Windows {
		correct := common.get_case_sensitive_path(fullpath, context.temp_allocator)	
		fullpath, _ = filepath.to_slash(correct, context.temp_allocator)
	} 	

	dir := filepath.base(filepath.dir(fullpath, context.temp_allocator))

	pkg := new(ast.Package)
	pkg.kind     = .Normal
	pkg.fullpath = fullpath
	pkg.name     = dir

	if dir == "runtime" {
		pkg.kind = .Runtime
	}

	file := ast.File {
		fullpath = fullpath,
		src = save_params.text,
		pkg = pkg,
	}

	ok = parser.parse_file(&p, &file)

	if !ok {
		log.errorf("error in parse file for indexing %v", fullpath)
	}

	for k, v in &indexer.dynamic_index.collection.packages {
		for k2, v2 in &v {
			if v2.uri == uri.uri {
				free_symbol(v2, context.allocator)
				v[k2] = {}
			} 
		}
	}

	if ret := collect_symbols(&indexer.dynamic_index.collection, file, uri.uri); ret != .None {
		log.errorf("failed to collect symbols on save %v", ret)
	}

	indexer.dynamic_uri_owned[uri.uri] = true

	check(uri, writer, config)

	return .None
}

request_semantic_token_full :: proc (params: json.Value, id: RequestId, config: ^common.Config, writer: ^Writer) -> common.Error {
	params_object, ok := params.(json.Object)

	if !ok {
		return .ParseError
	}

	semantic_params: SemanticTokensParams

	if unmarshal(params, semantic_params, context.temp_allocator) != nil {
		return .ParseError
	}

	document := document_get(semantic_params.textDocument.uri)

    if document == nil {
        return .InternalError
    }

	range := common.Range {
		start = common.Position {
			line = 0,
		},
		end = common.Position {
			line = 9000000, //should be enough
		},
	}

	symbols: SemanticTokens

	if config.enable_semantic_tokens {
		resolve_entire_file_cached(document)

		if cache_symbols, ok := file_resolve_cache.files[document.uri.uri]; ok {
			symbols = get_semantic_tokens(document, range, cache_symbols)
		}
	}

	response := make_response_message(params = symbols, id = id)

	send_response(response, writer)

	return .None
}

request_semantic_token_range :: proc (params: json.Value, id: RequestId, config: ^common.Config, writer: ^Writer) -> common.Error {
	params_object, ok := params.(json.Object)

	if !ok {
		return .None
	}

	semantic_params: SemanticTokensRangeParams

	if unmarshal(params, semantic_params, context.temp_allocator) != nil {
		return .None
	}

	document := document_get(semantic_params.textDocument.uri)

    if document == nil {
        return .InternalError
    }

	symbols: SemanticTokens

	if config.enable_semantic_tokens {
		if cache_symbols, ok := file_resolve_cache.files[document.uri.uri]; ok {
			symbols = get_semantic_tokens(document, semantic_params.range, cache_symbols)
		}
	}

	response := make_response_message(params = symbols, id = id)

	send_response(response, writer)

	return .None
}

request_document_symbols :: proc (params: json.Value, id: RequestId, config: ^common.Config, writer: ^Writer) -> common.Error {
	params_object, ok := params.(json.Object)

	if !ok {
		return .ParseError
	}

	symbol_params: DocumentSymbolParams

	if unmarshal(params, symbol_params, context.temp_allocator) != nil {
		return .ParseError
	}

	document := document_get(symbol_params.textDocument.uri)

    if document == nil {
        return .InternalError
    }

	symbols := get_document_symbols(document)

	response := make_response_message(params = symbols, id = id)

	send_response(response, writer)

	return .None
}

request_hover :: proc (params: json.Value, id: RequestId, config: ^common.Config, writer: ^Writer) -> common.Error {
	params_object, ok := params.(json.Object)

	if !ok {
		return .ParseError
	}

	hover_params: HoverParams

	if unmarshal(params, hover_params, context.temp_allocator) != nil {
		return .ParseError
	}

	document := document_get(hover_params.textDocument.uri)

    if document == nil {
        return .InternalError
    }

	hover: Hover
	valid: bool
	hover, valid, ok = get_hover_information(document, hover_params.position)

	if !ok {
		return .InternalError
	}

	if valid {
		response := make_response_message(params = hover, id = id)
		send_response(response, writer)
	} 
	else {
		response := make_response_message(params = nil, id = id)
		send_response(response, writer)
	}

	return .None
}

request_inlay_hint :: proc (params: json.Value, id: RequestId, config: ^common.Config, writer: ^Writer) -> common.Error {
	params_object, ok := params.(json.Object)

	if !ok {
		return .ParseError
	}

	inlay_params: InlayParams

	if unmarshal(params, inlay_params, context.temp_allocator) != nil {
		return .ParseError
	}

	document := document_get(inlay_params.textDocument.uri)

    if document == nil {
        return .InternalError
    }

	hints: []InlayHint

	resolve_entire_file_cached(document)

	if cache_symbols, ok := file_resolve_cache.files[document.uri.uri]; ok {
		hints, ok = get_inlay_hints(document, cache_symbols)
	}

	if !ok {
		return .InternalError
	}

	response := make_response_message(params = hints, id = id)

	send_response(response, writer)

	return .None
}

request_document_links :: proc (params: json.Value, id: RequestId, config: ^common.Config, writer: ^Writer) -> common.Error {
	params_object, ok := params.(json.Object)

	if !ok {
		return .ParseError
	}

	link_params: DocumentLinkParams

	if unmarshal(params, link_params, context.temp_allocator) != nil {
		return .ParseError
	}

	document := document_get(link_params.textDocument.uri)

    if document == nil {
        return .InternalError
    }

	links: []DocumentLink

	links, ok = get_document_links(document)

	if !ok {
		return .InternalError
	}

	response := make_response_message(params = links, id = id)

	send_response(response, writer)

	return .None
}

request_rename :: proc (params: json.Value, id: RequestId, config: ^common.Config, writer: ^Writer) -> common.Error {
	params_object, ok := params.(json.Object)

	if !ok {
		return .ParseError
	}

	rename_param: RenameParams

	if unmarshal(params, rename_param, context.temp_allocator) != nil {
		return .ParseError
	}

	document := document_get(rename_param.textDocument.uri)

    if document == nil {
        return .InternalError
    }

	workspace_edit: WorkspaceEdit

	workspace_edit, ok = get_rename(document, rename_param.newName, rename_param.position)

	if !ok {
		return .InternalError
	}

	response := make_response_message(params = workspace_edit, id = id)

	send_response(response, writer)

	return .None
}

request_references :: proc (params: json.Value, id: RequestId, config: ^common.Config, writer: ^Writer) -> common.Error {
	params_object, ok := params.(json.Object)

	if !ok {
		return .ParseError
	}

	reference_param: ReferenceParams

	if unmarshal(params, reference_param, context.temp_allocator) != nil {
		return .ParseError
	}

	document := document_get(reference_param.textDocument.uri)

    if document == nil {
        return .InternalError
    }

	locations: []common.Location

	locations, ok = get_references(document, reference_param.position)

	if !ok {
		return .InternalError
	}

	response := make_response_message(params = locations, id = id)

	send_response(response, writer)

	return .None
}
