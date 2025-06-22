package server

import "core:encoding/json"

import "src:common"

/*
	General types
*/

//TODO(Daniel, move some of the more specific structs to their appropriate place)

RequestId :: union {
	string,
	i64,
}

ResponseParams :: union {
	ResponseInitializeParams,
	rawptr,
	common.Location,
	[]common.Location,
	CompletionList,
	SignatureHelp,
	[]DocumentSymbol,
	SemanticTokensResponseParams,
	Hover,
	[]TextEdit,
	[]InlayHint,
	[]DocumentLink,
	[]WorkspaceSymbol,
	WorkspaceEdit,
	common.Range,
}

RequestMessage :: struct {
	jsonrpc: string,
	method:  string,
	id:      RequestId,
	params:  union {
		RegistrationParams,
	},
}

ResponseMessage :: struct {
	jsonrpc: string,
	id:      RequestId,
	result:  ResponseParams,
}

ResponseMessageError :: struct {
	jsonrpc: string,
	id:      RequestId,
	error:   ResponseError,
}

ResponseError :: struct {
	code:    common.Error,
	message: string,
}

NotificationLoggingParams :: struct {
	type:    DiagnosticSeverity,
	message: string,
}

NotificationPublishDiagnosticsParams :: struct {
	uri:         string,
	diagnostics: []Diagnostic,
}

NotificationParams :: union {
	NotificationLoggingParams,
	NotificationPublishDiagnosticsParams,
}

Notification :: struct {
	jsonrpc: string,
	method:  string,
	params:  NotificationParams,
}

ResponseInitializeParams :: struct {
	capabilities: ServerCapabilities,
}

RequestInitializeParams :: struct {
	trace:                 string,
	workspaceFolders:      [dynamic]common.WorkspaceFolder,
	capabilities:          ClientCapabilities,
	rootUri:               string,
	initializationOptions: OlsConfig,
	clientInfo:            ClientInfo,
}

FileChangeType :: enum {
	Created = 1,
	Changed = 2,
	Deleted = 3,
}

FileEvent :: struct {
	uri:  string,
	type: int,
}

DidChangeWatchedFilesParams :: struct {
	changes: [dynamic]FileEvent,
}

Registration :: struct {
	id:              string,
	method:          string,
	registerOptions: union {
		DidChangeWatchedFilesRegistrationOptions,
	},
}

RegistrationParams :: struct {
	registrations: []Registration,
}

ClientInfo :: struct {
	name: string,
}

MarkupContent :: struct {
	kind:  string,
	value: string,
}

ServerCapabilities :: struct {
	textDocumentSync:           TextDocumentSyncOptions,
	definitionProvider:         bool,
	typeDefinitionProvider:     bool,
	completionProvider:         CompletionOptions,
	signatureHelpProvider:      SignatureHelpOptions,
	semanticTokensProvider:     SemanticTokensOptions,
	documentSymbolProvider:     bool,
	hoverProvider:              bool,
	documentFormattingProvider: bool,
	inlayHintProvider:          bool,
	renameProvider:             RenameOptions,
	referencesProvider:         bool,
	workspaceSymbolProvider:    bool,
	documentLinkProvider:       DocumentLinkOptions,
}

DidChangeWatchedFilesRegistrationOptions :: struct {
	watchers: []FileSystemWatcher,
}

RenameOptions :: struct {
	prepareProvider: bool,
}

CompletionOptions :: struct {
	resolveProvider:   bool,
	triggerCharacters: []string,
	completionItem:    struct {
		labelDetailsSupport: bool,
	},
}

CompletionContext :: struct {
	triggerCharacter: string,
}

SaveOptions :: struct {
	includeText: bool,
}

HoverClientCapabilities :: struct {
	dynamicRegistration: bool,
	contentFormat:       [dynamic]string,
}

DocumentSymbolClientCapabilities :: struct {
	symbolKind:                        struct {
		valueSet: [dynamic]SymbolKind,
	},
	hierarchicalDocumentSymbolSupport: bool,
}

TextDocumentClientCapabilities :: struct {
	completion:     CompletionClientCapabilities,
	hover:          HoverClientCapabilities,
	signatureHelp:  SignatureHelpClientCapabilities,
	documentSymbol: DocumentSymbolClientCapabilities,
}

StaleRequestSupport :: struct {
	cancel: bool,
}

GeneralClientCapabilities :: struct {
	staleRequestSupport: StaleRequestSupport,
}

CompletionItemCapabilities :: struct {
	snippetSupport:      bool,
	labelDetailsSupport: bool,
}

CompletionClientCapabilities :: struct {
	documentationFormat: [dynamic]string,
	completionItem:      CompletionItemCapabilities,
}

ParameterInformationCapabilities :: struct {
	labelOffsetSupport: bool,
}

ClientCapabilities :: struct {
	textDocument: TextDocumentClientCapabilities,
	general:      GeneralClientCapabilities,
	workspace:    WorkspaceCapabilities,
}

WorkspaceCapabilities :: struct {
	didChangeWatchedFiles: DidChangeWatchedFilesClientCapabilities,
}

DidChangeWatchedFilesClientCapabilities :: struct {
	dynamicRegistration: bool,
}


RangeOptional :: union {
	common.Range,
}

TextDocumentContentChangeEvent :: struct {
	range: RangeOptional,
	text:  string,
}

Version :: union {
	int,
	json.Null,
}

VersionedTextDocumentIdentifier :: struct {
	uri:     string,
	version: int,
}

TextDocumentIdentifier :: struct {
	uri: string,
}

TextDocumentItem :: struct {
	uri:  string,
	text: string,
}

TextEdit :: struct {
	range:   common.Range,
	newText: string,
}

InsertReplaceEdit :: struct {
	insert:  common.Range,
	newText: string,
	replace: common.Range,
}

DiagnosticSeverity :: enum {
	Error       = 1,
	Warning     = 2,
	Information = 3,
	Hint        = 4,
}

Diagnostic :: struct {
	range:    common.Range,
	severity: DiagnosticSeverity,
	code:     string,
	message:  string,
}

DidOpenTextDocumentParams :: struct {
	textDocument: TextDocumentItem,
}

DocumentSymbolParams :: struct {
	textDocument: TextDocumentIdentifier,
}

DidChangeTextDocumentParams :: struct {
	textDocument:   VersionedTextDocumentIdentifier,
	contentChanges: [dynamic]TextDocumentContentChangeEvent,
}

DidCloseTextDocumentParams :: struct {
	textDocument: TextDocumentIdentifier,
}

DidSaveTextDocumentParams :: struct {
	textDocument: TextDocumentIdentifier,
	text:         string,
}

TextDocumentPositionParams :: struct {
	textDocument: TextDocumentIdentifier,
	position:     common.Position,
}

SignatureHelpParams :: struct {
	textDocument: TextDocumentIdentifier,
	position:     common.Position,
}

CompletionParams :: struct {
	textDocument: TextDocumentIdentifier,
	position:     common.Position,
	context_:     CompletionContext,
}

CompletionItemKind :: enum {
	Text          = 1,
	Method        = 2,
	Function      = 3,
	Constructor   = 4,
	Field         = 5,
	Variable      = 6,
	Class         = 7,
	Interface     = 8,
	Module        = 9,
	Property      = 10,
	Unit          = 11,
	Value         = 12,
	Enum          = 13,
	Keyword       = 14,
	Snippet       = 15,
	Color         = 16,
	File          = 17,
	Reference     = 18,
	Folder        = 19,
	EnumMember    = 20,
	Constant      = 21,
	Struct        = 22,
	Event         = 23,
	Operator      = 24,
	TypeParameter = 25,
}

InsertTextFormat :: enum {
	PlainText = 1,
	Snippet   = 2,
}

InsertTextMode :: enum {
	asIs              = 1,
	adjustIndentation = 2,
}

CompletionItem :: struct {
	label:               string,
	kind:                CompletionItemKind,
	detail:              string,
	documentation:       string,
	insertTextFormat:    Maybe(InsertTextFormat),
	insertText:          Maybe(string),
	InsertTextMode:      Maybe(InsertTextMode),
	textEdit:            Maybe(TextEdit),
	additionalTextEdits: Maybe([]TextEdit),
	tags:                []CompletionItemTag,
	deprecated:          bool,
	command:             Maybe(Command),
	labelDetails:        Maybe(CompletionItemLabelDetails),
}

CompletionItemLabelDetails :: struct {
	detail:      string,
	description: string,
}

CompletionItemTag :: enum {
	Deprecated = 1,
}

CompletionList :: struct {
	isIncomplete: bool,
	items:        []CompletionItem,
}

TextDocumentSyncOptions :: struct {
	openClose: bool,
	change:    int,
	save:      SaveOptions,
}

FileSystemWatcher :: struct {
	globPattern: string,
}

OlsConfig :: struct {
	collections:                       [dynamic]OlsConfigCollection,
	thread_pool_count:                 Maybe(int),
	enable_semantic_tokens:            Maybe(bool),
	enable_document_symbols:           Maybe(bool),
	enable_format:                     Maybe(bool),
	enable_hover:                      Maybe(bool),
	enable_procedure_context:          Maybe(bool),
	enable_snippets:                   Maybe(bool),
	enable_inlay_hints:                Maybe(bool),
	enable_inlay_hints_params:         Maybe(bool),
	enable_inlay_hints_default_params: Maybe(bool),
	enable_references:                 Maybe(bool),
	enable_rename:                     Maybe(bool),
	enable_fake_methods:               Maybe(bool),
	enable_procedure_snippet:          Maybe(bool),
	enable_checker_only_saved:         Maybe(bool),
	enable_auto_import:                Maybe(bool),
	disable_parser_errors:             Maybe(bool),
	verbose:                           Maybe(bool),
	file_log:                          Maybe(bool),
	odin_command:                      string,
	checker_args:                      string,
	checker_targets:                   []string,
	profiles:                          [dynamic]common.ConfigProfile,
	profile:                           string,
}

OlsConfigCollection :: struct {
	name: string,
	path: string,
}

SymbolKind :: enum {
	File          = 1,
	Module        = 2,
	Namespace     = 3,
	Package       = 4,
	Class         = 5,
	Method        = 6,
	Property      = 7,
	Field         = 8,
	Constructor   = 9,
	Enum          = 10,
	Interface     = 11,
	Function      = 12,
	Variable      = 13,
	Constant      = 14,
	String        = 15,
	Number        = 16,
	Boolean       = 17,
	Array         = 18,
	Object        = 19,
	Key           = 20,
	Null          = 21,
	EnumMember    = 22,
	Struct        = 23,
	Event         = 24,
	Operator      = 25,
	TypeParameter = 26,
}

DocumentSymbol :: struct {
	name:           string,
	kind:           SymbolKind,
	range:          common.Range,
	selectionRange: common.Range,
	children:       []DocumentSymbol,
}

HoverParams :: struct {
	textDocument: TextDocumentIdentifier,
	position:     common.Position,
}


InlayParams :: struct {
	textDocument: TextDocumentIdentifier,
	range:        common.Range,
}

Hover :: struct {
	contents: MarkupContent,
	range:    common.Range,
}

Command :: struct {
	title:     string,
	command:   string,
	arguments: []string,
}

InlayHintKind :: enum {
	Type      = 1,
	Parameter = 2,
}

InlayHint :: struct {
	position: common.Position,
	kind:     InlayHintKind,
	label:    string,
}

DocumentLinkClientCapabilities :: struct {
	tooltipSupport: bool,
}

DocumentLinkParams :: struct {
	textDocument: TextDocumentIdentifier,
}

DocumentLink :: struct {
	range:   common.Range,
	target:  string,
	tooltip: string,
}

DocumentLinkOptions :: struct {
	resolveProvider: bool,
}

PrepareSupportDefaultBehavior :: enum {
	Identifier = 1,
}

RenameClientCapabilities :: struct {
	prepareSupport:                bool,
	prepareSupportDefaultBehavior: PrepareSupportDefaultBehavior,
	honorsChangeAnnotations:       bool,
}

RenameParams :: struct {
	newName:      string,
	textDocument: TextDocumentIdentifier,
	position:     common.Position,
}

PrepareRenameParams :: struct {
	textDocument: TextDocumentIdentifier,
	position:     common.Position,
}

ReferenceParams :: struct {
	textDocument: TextDocumentIdentifier,
	position:     common.Position,
}

OptionalVersionedTextDocumentIdentifier :: struct {
	uri:     string,
	version: Maybe(int),
}

TextDocumentEdit :: struct {
	textDocument: OptionalVersionedTextDocumentIdentifier,
	edits:        []TextEdit,
}

WorkspaceEdit :: struct {
	changes: map[string][]TextEdit,
}

WorkspaceSymbolParams :: struct {
	query: string,
}

WorkspaceSymbol :: struct {
	name:     string,
	kind:     SymbolKind,
	location: common.Location,
}

DidChangeConfigurationParams :: struct {
	settings: OlsConfig,
}
