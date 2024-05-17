package server

import "base:intrinsics"
import "base:runtime"

import "core:encoding/json"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:odin/ast"
import "core:odin/parser"
import "core:os"
import "core:path/filepath"
import path "core:path/slashpath"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"

import "src:common"

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
	document: ^Document,
	id:       RequestId,
	config:   ^common.Config,
	writer:   ^Writer,
	result:   common.Error,
}


make_response_message :: proc(
	id: RequestId,
	params: ResponseParams,
) -> ResponseMessage {
	return ResponseMessage{jsonrpc = "2.0", id = id, result = params}
}

make_response_message_error :: proc(
	id: RequestId,
	error: ResponseError,
) -> ResponseMessageError {
	return ResponseMessageError{jsonrpc = "2.0", id = id, error = error}
}

RequestThreadData :: struct {
	reader: ^Reader,
	writer: ^Writer,
	logger: ^log.Logger,
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
		context.logger = request_data.logger^

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
			append(&deletings, Request{id = id})
			json.destroy_value(root)
		} else if method in notification_map {
			append(&requests, Request{value = root, is_notification = true})
			sync.sema_post(&requests_sempahore)
		} else {
			append(&requests, Request{id = id, value = root})
			sync.sema_post(&requests_sempahore)
		}

		sync.mutex_unlock(&requests_mutex)

		free_all(context.temp_allocator)
	}
}

read_and_parse_header :: proc(reader: ^Reader) -> (Header, bool) {
	header: Header

	builder := strings.builder_make(context.temp_allocator)

	found_content_length := false

	for true {
		strings.builder_reset(&builder)

		if !read_until_delimiter(reader, '\n', &builder) {
			log.error("Failed to read with delimiter")
			return header, false
		}

		message := strings.to_string(builder)

		if len(message) < 2 || message[len(message) - 2] != '\r' {
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

		header_name := message[0:index]
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

read_and_parse_body :: proc(
	reader: ^Reader,
	header: Header,
) -> (
	json.Value,
	bool,
) {
	value: json.Value

	data := make([]u8, header.content_length, context.temp_allocator)

	if !read_sized(reader, data) {
		log.error("Failed to read body")
		return value, false
	}

	err: json.Error

	value, err = json.parse(
		data = data,
		allocator = context.allocator,
		parse_integers = true,
	)

	if (err != json.Error.None) {
		log.error("Failed to parse body")
		return value, false
	}

	return value, true
}

call_map: map[string]proc(
	_: json.Value,
	_: RequestId,
	_: ^common.Config,
	_: ^Writer,
) -> common.Error = {
	"initialize"                        = request_initialize,
	"initialized"                       = request_initialized,
	"shutdown"                          = request_shutdown,
	"exit"                              = notification_exit,
	"textDocument/didOpen"              = notification_did_open,
	"textDocument/didChange"            = notification_did_change,
	"textDocument/didClose"             = notification_did_close,
	"textDocument/didSave"              = notification_did_save,
	"textDocument/definition"           = request_definition,
	"textDocument/completion"           = request_completion,
	"textDocument/signatureHelp"        = request_signature_help,
	"textDocument/documentSymbol"       = request_document_symbols,
	"textDocument/semanticTokens/full"  = request_semantic_token_full,
	"textDocument/semanticTokens/range" = request_semantic_token_range,
	"textDocument/hover"                = request_hover,
	"textDocument/formatting"           = request_format_document,
	"textDocument/inlayHint"            = request_inlay_hint,
	"textDocument/documentLink"         = request_document_links,
	"textDocument/rename"               = request_rename,
	"textDocument/references"           = request_references,
	"window/progress"                   = request_noop,
	"workspace/symbol"                  = request_workspace_symbols,
	"workspace/didChangeConfiguration"  = notification_workspace_did_change_configuration,
}

notification_map: map[string]bool = {
	"textDocument/didOpen"   = true,
	"textDocument/didChange" = true,
	"textDocument/didClose"  = true,
	"textDocument/didSave"   = true,
	"initialized"            = true,
	"window/progress"        = true,
}

consume_requests :: proc(config: ^common.Config, writer: ^Writer) -> bool {
	temp_requests := make([dynamic]Request, 0, context.allocator)
	defer delete(temp_requests)

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
			cancel(
				requests[delete_index].value,
				requests[delete_index].id,
				writer,
				config,
			)
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
		clear_index_cache()
		json.destroy_value(request.value)
		free_all(context.temp_allocator)
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


cancel :: proc(
	value: json.Value,
	id: RequestId,
	writer: ^Writer,
	config: ^common.Config,
) {
	response := make_response_message(id = id, params = ResponseParams{})

	json.destroy_value(value)

	send_response(response, writer)
}

call :: proc(
	value: json.Value,
	id: RequestId,
	writer: ^Writer,
	config: ^common.Config,
) {
	root := value.(json.Object)
	method := root["method"].(json.String)

	diff: time.Duration
	{
		time.SCOPED_TICK_DURATION(&diff)

		if fn, ok := call_map[method]; !ok {
			response := make_response_message_error(
				id = id,
				error = ResponseError{code = .MethodNotFound, message = ""},
			)
			send_error(response, writer)
		} else {
			err := fn(root["params"], id, config, writer)
			if err != .None {
				response := make_response_message_error(
					id = id,
					error = ResponseError{code = err, message = ""},
				)
				send_error(response, writer)
			}
		}
	}

	//log.errorf("time duration %v for %v", time.duration_milliseconds(diff), method)
}

read_ols_initialize_options :: proc(
	config: ^common.Config,
	ols_config: OlsConfig,
	uri: common.Uri,
) {
	config.disable_parser_errors =
		ols_config.disable_parser_errors.(bool) or_else config.disable_parser_errors
	config.thread_count =
		ols_config.thread_pool_count.(int) or_else config.thread_count
	config.enable_document_symbols =
		ols_config.enable_document_symbols.(bool) or_else config.enable_document_symbols
	config.enable_format =
		ols_config.enable_format.(bool) or_else config.enable_format
	config.enable_hover =
		ols_config.enable_hover.(bool) or_else config.enable_hover
	config.enable_semantic_tokens =
		ols_config.enable_semantic_tokens.(bool) or_else config.enable_semantic_tokens
	config.enable_procedure_context =
		ols_config.enable_procedure_context.(bool) or_else config.enable_procedure_context
	config.enable_snippets =
		ols_config.enable_snippets.(bool) or_else config.enable_snippets
	config.enable_references =
		ols_config.enable_references.(bool) or_else config.enable_references
	config.verbose = ols_config.verbose.(bool) or_else config.verbose
	config.file_log = ols_config.file_log.(bool) or_else config.file_log
	config.enable_rename =
		ols_config.enable_references.(bool) or_else config.enable_rename

	config.enable_procedure_snippet =
		ols_config.enable_procedure_snippet.(bool) or_else config.enable_procedure_snippet

	config.enable_checker_only_saved =
		ols_config.enable_checker_only_saved.(bool) or_else config.enable_checker_only_saved

	if ols_config.odin_command != "" {
		config.odin_command = strings.clone(
			ols_config.odin_command,
			context.temp_allocator,
		)

		allocated: bool
		config.odin_command, allocated = common.resolve_home_dir(
			config.odin_command,
		)
		if !allocated {
			config.odin_command = strings.clone(
				config.odin_command,
				context.allocator,
			)
		}
	}

	if ols_config.checker_args != "" {
		config.checker_args = strings.clone(
			ols_config.checker_args,
			context.allocator,
		)
	}

	for profile in ols_config.profiles {
		if ols_config.profile == profile.name {
			config.profile.checker_path = make(
				[dynamic]string,
				len(profile.checker_path),
			)

			if filepath.is_abs(ols_config.profile) {
				for checker_path, i in profile.checker_path {
					config.profile.checker_path[i] = strings.clone(
						checker_path,
					)
				}
			} else {
				for checker_path, i in profile.checker_path {
					config.profile.checker_path[i] = path.join(
						elems = {uri.path, checker_path},
					)
				}
			}
		}
	}

	config.checker_targets = slice.clone(
		ols_config.checker_targets,
		context.allocator,
	)

	found_target := false

	for target in config.checker_targets {
		if ODIN_OS in os_enum_to_string {
			found_target = true
		}
	}


	config.enable_inlay_hints =
		ols_config.enable_inlay_hints.(bool) or_else config.enable_inlay_hints
	config.enable_fake_method =
		ols_config.enable_fake_methods.(bool) or_else config.enable_fake_method


	for it in ols_config.collections {
		if it.name in config.collections {
			delete(config.collections[it.name])
			delete_key(&config.collections, it.name)
		}

		forward_path, _ := filepath.to_slash(it.path, context.temp_allocator)

		forward_path = common.resolve_home_dir(
			forward_path,
			context.temp_allocator,
		)

		final_path := ""

		when ODIN_OS == .Windows {
			if filepath.is_abs(it.path) {
				final_path, _ = filepath.to_slash(
					common.get_case_sensitive_path(
						forward_path,
						context.temp_allocator,
					),
					context.temp_allocator,
				)
			} else {
				final_path, _ = filepath.to_slash(
					common.get_case_sensitive_path(
						path.join(
							elems = {uri.path, forward_path},
							allocator = context.temp_allocator,
						),
						context.temp_allocator,
					),
					context.temp_allocator,
				)
			}

			final_path = strings.clone(final_path, context.temp_allocator)
		} else {
			if filepath.is_abs(it.path) {
				final_path = strings.clone(
					forward_path,
					context.temp_allocator,
				)
			} else {
				final_path = path.join(
					{uri.path, forward_path},
					context.temp_allocator,
				)
			}
		}

		if abs_final_path, ok := filepath.abs(final_path); ok {
			slashed_path, _ := filepath.to_slash(
				abs_final_path,
				context.temp_allocator,
			)

			config.collections[strings.clone(it.name)] =  strings.clone(slashed_path)
		} else {
			log.errorf(
				"Failed to find absolute address of collection: %v",
				final_path,
			)
			config.collections[strings.clone(it.name)] = strings.clone(
				final_path,
			)
		}
	}

	// Ideally we'd disallow specifying the builtin `base`, `core` and `vendor` completely
	// because using `odin root` is always correct, but I suspect a lot of people have this in
	// their config and it would break.

	odin_core_env: string
	odin_bin := "odin" if config.odin_command == "" else config.odin_command

	root_buf: [1024]byte
	root_slice := root_buf[:]
	root_command := strings.concatenate(
		{odin_bin, " root"},
		context.temp_allocator,
	)
	code, ok, out := common.run_executable(root_command, &root_slice)
	if ok && !strings.contains(string(out), "Usage") {
		odin_core_env = string(out)
	} else {
		log.warnf("failed executing %q with code %v", root_command, code)

		// User is probably on an older Odin version, let's try our best.

		odin_core_env = os.get_env("ODIN_ROOT", context.temp_allocator)
		if odin_core_env == "" {
			if filepath.is_abs(odin_bin) {
				odin_core_env = filepath.dir(odin_bin, context.temp_allocator)
			} else if exe_path, ok := common.lookup_in_path(odin_bin); ok {
				odin_core_env = filepath.dir(exe_path, context.temp_allocator)
			}
		}

		if abs_core_env, ok := filepath.abs(
			odin_core_env,
			context.temp_allocator,
		); ok {
			odin_core_env = abs_core_env
		}
	}

	log.infof("resolved odin root to: %q", odin_core_env)

	if "core" not_in config.collections && odin_core_env != "" {
		forward_path, _ := filepath.to_slash(
			odin_core_env,
			context.temp_allocator,
		)
		config.collections[strings.clone("core")] = path.join(
			elems = {forward_path, "core"},
			allocator = context.allocator,
		)
	}

	if "vendor" not_in config.collections && odin_core_env != "" {
		forward_path, _ := filepath.to_slash(
			odin_core_env,
			context.temp_allocator,
		)
		config.collections[strings.clone("vendor")] = path.join(
			elems = {forward_path, "vendor"},
			allocator = context.allocator,
		)
	}

	if "base" not_in config.collections && odin_core_env != "" {
		forward_path, _ := filepath.to_slash(
			odin_core_env,
			context.temp_allocator,
		)
		config.collections[strings.clone("base")] = path.join(
			elems = {forward_path, "base"},
			allocator = context.allocator,
		)
	}

	if "shared" not_in config.collections && odin_core_env != "" {
		forward_path, _ := filepath.to_slash(
			odin_core_env,
			context.temp_allocator,
		)
		config.collections[strings.clone("shared")] = path.join(
			elems = {forward_path, "shared"},
			allocator = context.allocator,
		)
	}

	log.info(config.collections)
}

request_initialize :: proc(
	params: json.Value,
	id: RequestId,
	config: ^common.Config,
	writer: ^Writer,
) -> common.Error {
	params_object, ok := params.(json.Object)

	if !ok {
		return .ParseError
	}

	initialize_params: RequestInitializeParams

	if unmarshal(params, initialize_params, context.temp_allocator) != nil {
		return .ParseError
	}

	config.client_name = strings.clone(initialize_params.clientInfo.name)
	config.workspace_folders = make([dynamic]common.WorkspaceFolder)

	for s in initialize_params.workspaceFolders {
		workspace: common.WorkspaceFolder
		workspace.uri = strings.clone(s.uri)
		append(&config.workspace_folders, workspace)
	}

	config.enable_hover = true
	config.enable_format = true

	config.disable_parser_errors = false
	config.thread_count = 2
	config.enable_document_symbols = true
	config.enable_format = true
	config.enable_hover = true
	config.enable_semantic_tokens = false
	config.enable_procedure_context = false
	config.enable_snippets = false
	config.enable_references = false
	config.verbose = false
	config.file_log = false
	config.enable_rename = false
	config.odin_command = ""
	config.checker_args = ""
	config.enable_inlay_hints = false
	config.enable_fake_method = false
	config.enable_procedure_snippet = true
	config.enable_checker_only_saved = false

	read_ols_config :: proc(
		file: string,
		config: ^common.Config,
		uri: common.Uri,
	) {
		if data, ok := os.read_entire_file(file, context.temp_allocator); ok {
			if value, err := json.parse(
				data = data,
				allocator = context.temp_allocator,
				parse_integers = true,
			); err == .None {
				ols_config: OlsConfig

				if unmarshal(value, ols_config, context.temp_allocator) ==
				   nil {
					read_ols_initialize_options(config, ols_config, uri)
				} else {
					log.warnf("Failed to unmarshal %v", file)
				}
			} else {
				log.warnf("Failed to parse json %v", file)
			}
		} else {
			log.warnf("Failed to read/find %v", file)
		}
	}

	project_uri := ""

	if len(config.workspace_folders) > 0 {
		project_uri = config.workspace_folders[0].uri
	} else if initialize_params.rootUri != "" {
		project_uri = initialize_params.rootUri
	}

	if uri, ok := common.parse_uri(project_uri, context.temp_allocator); ok {
		global_ols_config_path := path.join(
			elems =  {
				filepath.dir(os.args[0], context.temp_allocator),
				"ols.json",
			},
			allocator = context.temp_allocator,
		)

		read_ols_config(global_ols_config_path, config, uri)

		ols_config_path := path.join(
			elems = {uri.path, "ols.json"},
			allocator = context.temp_allocator,
		)

		read_ols_config(ols_config_path, config, uri)

		read_ols_initialize_options(
			config,
			initialize_params.initializationOptions,
			uri,
		)
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

	config.enable_label_details =
		initialize_params.capabilities.textDocument.completion.completionItem.labelDetailsSupport

	config.enable_snippets &=
		initialize_params.capabilities.textDocument.completion.completionItem.snippetSupport

	config.signature_offset_support =
		initialize_params.capabilities.textDocument.signatureHelp.signatureInformation.parameterInformation.labelOffsetSupport

	completionTriggerCharacters := []string{".", ">", "#", "\"", "/", ":"}
	signatureTriggerCharacters := []string{"(", ","}
	signatureRetriggerCharacters := []string{","}

	response := make_response_message(
		params = ResponseInitializeParams {
			capabilities = ServerCapabilities {
				textDocumentSync = TextDocumentSyncOptions {
					openClose = true,
					change = 2,
					save = {includeText = true},
				},
				renameProvider = config.enable_rename,
				workspaceSymbolProvider = true,
				referencesProvider = config.enable_references,
				definitionProvider = true,
				completionProvider = CompletionOptions {
					resolveProvider = false,
					triggerCharacters = completionTriggerCharacters,
					completionItem = {labelDetailsSupport = true},
				},
				signatureHelpProvider = SignatureHelpOptions {
					triggerCharacters = signatureTriggerCharacters,
					retriggerCharacters = signatureRetriggerCharacters,
				},
				semanticTokensProvider = SemanticTokensOptions {
					range = config.enable_semantic_tokens,
					full = config.enable_semantic_tokens,
					legend = SemanticTokensLegend {
						tokenTypes = semantic_token_type_names,
						tokenModifiers = semantic_token_modifier_names,
					},
				},
				inlayHintProvider = config.enable_inlay_hints,
				documentSymbolProvider = config.enable_document_symbols,
				hoverProvider = config.enable_hover,
				documentFormattingProvider = config.enable_format,
				documentLinkProvider = {resolveProvider = false},
			},
		},
		id = id,
	)

	send_response(response, writer)

	/*
		Add runtime package
	*/

	if core, ok := config.collections["base"]; ok {
		append(&indexer.builtin_packages, path.join({core, "runtime"}))
	}

	file_resolve_cache.files = make(map[string]FileResolve, 200)

	setup_index()

	for pkg in indexer.builtin_packages {
		try_build_package(pkg)
	}

	return .None
}

request_initialized :: proc(
	params: json.Value,
	id: RequestId,
	config: ^common.Config,
	writer: ^Writer,
) -> common.Error {
	return .None
}

request_shutdown :: proc(
	params: json.Value,
	id: RequestId,
	config: ^common.Config,
	writer: ^Writer,
) -> common.Error {
	response := make_response_message(params = nil, id = id)

	send_response(response, writer)

	return .None
}

request_definition :: proc(
	params: json.Value,
	id: RequestId,
	config: ^common.Config,
	writer: ^Writer,
) -> common.Error {
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

	locations, ok2 := get_definition_location(
		document,
		definition_params.position,
	)

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

request_completion :: proc(
	params: json.Value,
	id: RequestId,
	config: ^common.Config,
	writer: ^Writer,
) -> common.Error {
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
	list, ok = get_completion_list(
		document,
		completition_params.position,
		completition_params.context_,
	)

	if !ok {
		return .InternalError
	}

	response := make_response_message(params = list, id = id)

	send_response(response, writer)

	return .None
}

request_signature_help :: proc(
	params: json.Value,
	id: RequestId,
	config: ^common.Config,
	writer: ^Writer,
) -> common.Error {
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

request_format_document :: proc(
	params: json.Value,
	id: RequestId,
	config: ^common.Config,
	writer: ^Writer,
) -> common.Error {
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

notification_exit :: proc(
	params: json.Value,
	id: RequestId,
	config: ^common.Config,
	writer: ^Writer,
) -> common.Error {
	config.running = false
	return .None
}

notification_did_open :: proc(
	params: json.Value,
	id: RequestId,
	config: ^common.Config,
	writer: ^Writer,
) -> common.Error {
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

	if n := document_open(
		open_params.textDocument.uri,
		open_params.textDocument.text,
		config,
		writer,
	); n != .None {
		return .InternalError
	}

	return .None
}

notification_did_change :: proc(
	params: json.Value,
	id: RequestId,
	config: ^common.Config,
	writer: ^Writer,
) -> common.Error {
	params_object, ok := params.(json.Object)

	if !ok {
		return .ParseError
	}

	change_params: DidChangeTextDocumentParams

	if unmarshal(params, change_params, context.temp_allocator) != nil {
		return .ParseError
	}

	document_apply_changes(
		change_params.textDocument.uri,
		change_params.contentChanges,
		change_params.textDocument.version,
		config,
		writer,
	)

	return .None
}

notification_did_close :: proc(
	params: json.Value,
	id: RequestId,
	config: ^common.Config,
	writer: ^Writer,
) -> common.Error {
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

notification_did_save :: proc(
	params: json.Value,
	id: RequestId,
	config: ^common.Config,
	writer: ^Writer,
) -> common.Error {
	params_object, ok := params.(json.Object)

	if !ok {
		return .ParseError
	}

	save_params: DidSaveTextDocumentParams

	if unmarshal(params, save_params, context.temp_allocator) != nil {
		return .ParseError
	}

	uri: common.Uri

	if uri, ok = common.parse_uri(
		save_params.textDocument.uri,
		context.temp_allocator,
	); !ok {
		return .ParseError
	}

	fullpath := uri.path

	p := parser.Parser {
		err   = log_error_handler,
		warn  = log_warning_handler,
		flags = {.Optional_Semicolons},
	}

	when ODIN_OS == .Windows {
		correct := common.get_case_sensitive_path(
			fullpath,
			context.temp_allocator,
		)
		fullpath, _ = filepath.to_slash(correct, context.temp_allocator)
	}

	dir := filepath.base(filepath.dir(fullpath, context.temp_allocator))

	pkg := new(ast.Package)
	pkg.kind = .Normal
	pkg.fullpath = fullpath
	pkg.name = dir

	if dir == "runtime" {
		pkg.kind = .Runtime
	}

	file := ast.File {
		fullpath = fullpath,
		src      = save_params.text,
		pkg      = pkg,
	}

	ok = parser.parse_file(&p, &file)

	if !ok {
		if !strings.contains(fullpath, "builtin.odin") &&
		   !strings.contains(fullpath, "intrinsics.odin") {
			log.errorf("error in parse file for indexing %v", fullpath)
		}
	}

	corrected_uri := common.create_uri(fullpath, context.temp_allocator)

	for k, &v in indexer.index.collection.packages {
		for k2, v2 in v.symbols {
			if corrected_uri.uri == v2.uri {
				free_symbol(v2, indexer.index.collection.allocator)
				delete_key(&v.symbols, k2)
			}
		}

		for method, &symbols in v.methods {
			for i := 0; i < len(symbols); i += 1 {
				#no_bounds_check symbol := symbols[i]
				if corrected_uri.uri == symbol.uri {
					unordered_remove(&symbols, i)
					i -= 1
				}
			}
		}
	}

	if ret := collect_symbols(
		&indexer.index.collection,
		file,
		corrected_uri.uri,
	); ret != .None {
		log.errorf("failed to collect symbols on save %v", ret)
	}

	check(config.profile.checker_path[:], corrected_uri, writer, config)

	return .None
}

request_semantic_token_full :: proc(
	params: json.Value,
	id: RequestId,
	config: ^common.Config,
	writer: ^Writer,
) -> common.Error {
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
		start = common.Position{line = 0},
		end = common.Position{line = 9000000}, //should be enough
	}

	symbols: SemanticTokens

	if config.enable_semantic_tokens {
		resolve_entire_file_cached(document)

		if file, ok := file_resolve_cache.files[document.uri.uri]; ok {
			symbols = get_semantic_tokens(document, range, file.symbols)
		}
	}

	response := make_response_message(params = symbols, id = id)

	send_response(response, writer)

	return .None
}

request_semantic_token_range :: proc(
	params: json.Value,
	id: RequestId,
	config: ^common.Config,
	writer: ^Writer,
) -> common.Error {
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
		resolve_entire_file_cached(document)

		if file, ok := file_resolve_cache.files[document.uri.uri]; ok {
			symbols = get_semantic_tokens(
				document,
				semantic_params.range,
				file.symbols,
			)
		}
	}

	response := make_response_message(params = symbols, id = id)

	send_response(response, writer)

	return .None
}

request_document_symbols :: proc(
	params: json.Value,
	id: RequestId,
	config: ^common.Config,
	writer: ^Writer,
) -> common.Error {
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

request_hover :: proc(
	params: json.Value,
	id: RequestId,
	config: ^common.Config,
	writer: ^Writer,
) -> common.Error {
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
	} else {
		response := make_response_message(params = nil, id = id)
		send_response(response, writer)
	}

	return .None
}

request_inlay_hint :: proc(
	params: json.Value,
	id: RequestId,
	config: ^common.Config,
	writer: ^Writer,
) -> common.Error {
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

	if file, ok := file_resolve_cache.files[document.uri.uri]; ok {
		hints, ok = get_inlay_hints(document, file.symbols)
	}

	if !ok {
		return .InternalError
	}

	response := make_response_message(params = hints, id = id)

	send_response(response, writer)

	return .None
}

request_document_links :: proc(
	params: json.Value,
	id: RequestId,
	config: ^common.Config,
	writer: ^Writer,
) -> common.Error {
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

request_rename :: proc(
	params: json.Value,
	id: RequestId,
	config: ^common.Config,
	writer: ^Writer,
) -> common.Error {
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
	workspace_edit, ok = get_rename(
		document,
		rename_param.newName,
		rename_param.position,
	)

	if !ok {
		return .InternalError
	}

	response := make_response_message(params = workspace_edit, id = id)

	send_response(response, writer)

	return .None
}

request_references :: proc(
	params: json.Value,
	id: RequestId,
	config: ^common.Config,
	writer: ^Writer,
) -> common.Error {
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

notification_workspace_did_change_configuration :: proc(
	params: json.Value,
	id: RequestId,
	config: ^common.Config,
	writer: ^Writer,
) -> common.Error {
	params_object, ok := params.(json.Object)

	if !ok {
		return .ParseError
	}

	workspace_config_params: DidChangeConfigurationParams

	if unmarshal(params, workspace_config_params, context.temp_allocator) !=
	   nil {
		return .ParseError
	}

	ols_config := workspace_config_params.settings

	if uri, ok := common.parse_uri(
		config.workspace_folders[0].uri,
		context.temp_allocator,
	); ok {
		read_ols_initialize_options(config, ols_config, uri)
	}

	return .None
}

request_workspace_symbols :: proc(
	params: json.Value,
	id: RequestId,
	config: ^common.Config,
	writer: ^Writer,
) -> common.Error {
	params_object, ok := params.(json.Object)

	if !ok {
		return .ParseError
	}

	workspace_symbol_params: WorkspaceSymbolParams

	if unmarshal(params, workspace_symbol_params, context.temp_allocator) !=
	   nil {
		return .ParseError
	}

	symbols: []WorkspaceSymbol
	symbols, ok = get_workspace_symbols(workspace_symbol_params.query)

	if !ok {
		return .InternalError
	}

	response := make_response_message(params = symbols, id = id)

	send_response(response, writer)

	return .None
}

request_noop :: proc(
	params: json.Value,
	id: RequestId,
	config: ^common.Config,
	writer: ^Writer,
) -> common.Error {
	return .None
}
