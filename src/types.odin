package main

import "core:encoding/json"

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

Error :: enum {
    None = 0,

	// Defined by JSON RPC
	ParseError = -32700,
	InvalidRequest = -32600,
	MethodNotFound = -32601,
	InvalidParams = -32602,
	InternalError = -32603,
	serverErrorStart = -32099,
	serverErrorEnd = -32000,
	ServerNotInitialized = -32002,
	UnknownErrorCode = -32001,

	// Defined by the protocol.
	RequestCancelled = -32800,
	ContentModified = -32801,
};

ResponseError :: struct {
 	code: Error,
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

WorkspaceFolder :: struct {
    name: string,
    uri: string,
};

ResponseInitializeParams :: struct {
    capabilities: ServerCapabilities,
};

RequestInitializeParams :: struct {
    trace: string,
    workspaceFolders: [dynamic] WorkspaceFolder,
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
};

CompletionClientCapabilities :: struct {

};

HoverClientCapabilities :: struct {
    dynamicRegistration: bool,
    contentFormat: [dynamic] MarkupKind,
};

TextDocumentClientCapabilities :: struct {
    completion: CompletionClientCapabilities,
    hover: HoverClientCapabilities,
};

ClientCapabilities :: struct {
    textDocument: TextDocumentClientCapabilities,
};

Position :: struct {
	line: int,
	character: int,
};

Range :: struct {
	start: Position,
	end: Position,
};

Location :: struct {
	uri: string,
	range: Range,
};

TextDocumentContentChangeEvent :: struct {
	range: Range,
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
	range: Range,
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
	position: Position,
};