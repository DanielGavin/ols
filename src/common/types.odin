package common

import "core:odin/ast"
import "core:odin/tokenizer"

Error :: enum {
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

Package :: struct {
	name: string, //the entire absolute path to the directory
	base: string,
}

Document :: struct {
	uri:              Uri,
	text:             []u8,
	used_text:        int, //allow for the text to be reallocated with more data than needed
	client_owned:     bool,
	diagnosed_errors: bool,
	ast:              ast.File,
	imports:          []Package,
	package_name:     string,
	allocator:        ^Scratch_Allocator, //because parser does not support freeing I use arena allocators for each document
	operating_on:     int, //atomic
	version:          Maybe(int),
}

parser_warning_handler :: proc(pos: tokenizer.Pos, msg: string, args: ..any) {
}