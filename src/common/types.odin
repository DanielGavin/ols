package common

Error :: enum 

// Defined by JSON RPC

// Defined by the protocol.

{
	None                 = 0,
	ParseError           = -32700,
	InvalidRequest       = -32600,
	MethodNotFound       = -32601,
	InvalidParams        = -32602,
	InternalError        = -32603,
	serverErrorStart     = -32099,
	serverErrorEnd       = -32000,
	ServerNotInitialized = -32002,
	UnknownErrorCode     = -32001,
	RequestCancelled     = -32800,
	ContentModified      = -32801,
}

WorkspaceFolder :: struct {
	name: string,
	uri:  string,
}
