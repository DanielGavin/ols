package server

import "core:encoding/json"

import "shared:common"

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
	CompletionList,
	SignatureHelp,
	[]DocumentSymbol,
	SemanticTokens,
	Hover,
	[]TextEdit,
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
	type:    int,
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
	trace:            string,
	workspaceFolders: [dynamic]common.WorkspaceFolder,
	capabilities:     ClientCapabilities,
}

MarkupContent :: struct {
	kind:  string,
	value: string,
}

ServerCapabilities :: struct {
	textDocumentSync:           TextDocumentSyncOptions,
	definitionProvider:         bool,
	completionProvider:         CompletionOptions,
	signatureHelpProvider:      SignatureHelpOptions,
	semanticTokensProvider:     SemanticTokensOptions,
	documentSymbolProvider:     bool,
	hoverProvider:              bool,
	documentFormattingProvider: bool,
}

CompletionOptions :: struct {
	resolveProvider:   bool,
	triggerCharacters: []string,
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

CompletionClientCapabilities :: struct {
	documentationFormat: [dynamic]string,
}

ParameterInformationCapabilities :: struct {
	labelOffsetSupport: bool,
}

SignatureInformationCapabilities :: struct {
	parameterInformation: ParameterInformationCapabilities,
}

SignatureHelpClientCapabilities :: struct {
	dynamicRegistration:  bool,
	signatureInformation: SignatureInformationCapabilities,
	contextSupport:       bool,
}

SignatureHelpOptions :: struct {
	triggerCharacters:   []string,
	retriggerCharacters: []string,
}

ClientCapabilities :: struct {
	textDocument: TextDocumentClientCapabilities,
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
	uri: string,
}

TextDocumentIdentifier :: struct {
	uri: string,
}

TextDocumentItem :: struct {
	uri:  string,
	text: string,
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
	context_: 	  CompletionContext,
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

CompletionItem :: struct {
	label:         string,
	kind:          CompletionItemKind,
	detail:        string,
	documentation: string,
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

SignatureHelp :: struct {
	signatures:      []SignatureInformation,
	activeSignature: int,
	activeParameter: int,
}

SignatureInformation :: struct {
	label:         string,
	documentation: string,
	parameters:    []ParameterInformation,
}

ParameterInformation :: struct {
	label: [2]int,
}

OlsConfig :: struct {
	collections:             [dynamic]OlsConfigCollection,
	thread_pool_count:       int,
	enable_semantic_tokens:  bool,
	enable_document_symbols: bool,
	enable_hover:            bool,
	enable_format:           bool,
	verbose:                 bool,
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

Hover :: struct {
	contents: MarkupContent,
	range:    common.Range,
}
