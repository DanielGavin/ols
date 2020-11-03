package main

import "core:encoding/json"

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

NotificationParams :: union {
    NotificationLoggingParams,
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

DidOpenTextDocumentParams :: struct {
    textDocument: TextDocumentItem,
};

Position :: struct {
	line: int,
	character: int,
};

Range :: struct {
	start: Position,
	end: Position,
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

DidChangeTextDocumentParams :: struct {
	textDocument: VersionedTextDocumentIdentifier,
	contentChanges: [dynamic] TextDocumentContentChangeEvent,
};

DidCloseTextDocumentParams :: struct{
    textDocument: TextDocumentItem,
};

TextDocumentItem :: struct {
	uri: string,
	text: string,
};