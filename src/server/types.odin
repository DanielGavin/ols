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
};

ResponseParams :: union {
    ResponseInitializeParams,
    rawptr,
    common.Location,
    CompletionList,
};

ResponseMessage :: struct {
    jsonrpc: string,
    id: RequestId,
    result: ResponseParams,
};

ResponseMessageError :: struct {
    jsonrpc: string,
    id: RequestId,
    error: ResponseError,
};

ResponseError :: struct {
 	code: common.Error,
	message: string,
};

NotificationLoggingParams :: struct {
    type: int,
    message: string,
};

NotificationPublishDiagnosticsParams :: struct {
	uri: string,
	diagnostics: [] Diagnostic,
};

NotificationParams :: union {
    NotificationLoggingParams,
    NotificationPublishDiagnosticsParams,
};

Notification :: struct {
    jsonrpc: string,
    method: string,
    params: NotificationParams
};

ResponseInitializeParams :: struct {
    capabilities: ServerCapabilities,
};

RequestInitializeParams :: struct {
    trace: string,
    workspaceFolders: [dynamic] common.WorkspaceFolder,
    capabilities: ClientCapabilities,
};

//Can't really follow the uppercase style for enums when i need to represent it as text as well
MarkupKind :: enum {
    Plaintext,
    Markdown,
};

ServerCapabilities :: struct {
    textDocumentSync: int,
    definitionProvider: bool,
    completionProvider: CompletionOptions,
};

CompletionOptions  :: struct {
    resolveProvider: bool,
	triggerCharacters: [] string,
};

HoverClientCapabilities :: struct {
    dynamicRegistration: bool,
    contentFormat: [dynamic] MarkupKind,
};

TextDocumentClientCapabilities :: struct {
    completion: CompletionClientCapabilities,
    hover: HoverClientCapabilities,
};

CompletionClientCapabilities :: struct {

};

ClientCapabilities :: struct {
    textDocument: TextDocumentClientCapabilities,
};

TextDocumentContentChangeEvent :: struct {
	range: common.Range,
	text: string,
};

Version :: union {
    int,
    json.Null,
};

VersionedTextDocumentIdentifier :: struct  {
    uri: string,
};

TextDocumentIdentifier :: struct {
	uri: string,
};

TextDocumentItem :: struct {
	uri: string,
	text: string,
};

DiagnosticSeverity :: enum {
    Error = 1,
    Warning = 2,
	Information = 3,
	Hint = 4,
};

Diagnostic :: struct {
	range: common.Range,
	severity: DiagnosticSeverity,
	code: string,
	message: string,
};

DidOpenTextDocumentParams :: struct {
    textDocument: TextDocumentItem,
};

DidChangeTextDocumentParams :: struct {
	textDocument: VersionedTextDocumentIdentifier,
	contentChanges: [dynamic] TextDocumentContentChangeEvent,
};

DidCloseTextDocumentParams :: struct {
    textDocument: TextDocumentIdentifier,
};

TextDocumentPositionParams :: struct {
	textDocument: TextDocumentIdentifier,
	position: common.Position,
};

CompletionParams :: struct {
    textDocument: TextDocumentIdentifier,
	position: common.Position,
};

CompletionItemKind :: enum {
	Text = 1,
	Method = 2,
	Function = 3,
	Constructor = 4,
	Field = 5,
	Variable = 6,
	Class = 7,
	Interface = 8,
	Module = 9,
	Property = 10,
	Unit = 11,
	Value = 12,
	Enum = 13,
	Keyword = 14,
	Snippet = 15,
	Color = 16,
	File = 17,
	Reference = 18,
	Folder = 19,
	EnumMember = 20,
	Constant = 21,
	Struct = 22,
	Event = 23,
	Operator = 24,
	TypeParameter = 25,
};

CompletionItem :: struct {
	label: string,
	kind: CompletionItemKind,
};

CompletionList :: struct {
    isIncomplete: bool,
	items: [] CompletionItem,
};