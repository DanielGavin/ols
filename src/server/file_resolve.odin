package server

import "core:fmt"
import "core:log"
import "core:mem"
import "core:odin/ast"
import "core:odin/parser"
import "core:odin/tokenizer"
import "core:path/filepath"
import path "core:path/slashpath"
import "core:reflect"
import "core:slice"
import "core:sort"
import "core:strconv"
import "core:strings"
import "core:unicode/utf8"

import "src:common"

ResolveReferenceFlag :: enum {
	None,
	Variable,
	Constant,
	StructElement,
	EnumElement,
}

resolve_entire_file :: proc(
	document: ^Document,
	flag := ResolveReferenceFlag.None,
	allocator := context.allocator,
) -> map[uintptr]SymbolAndNode {
	ast_context := make_ast_context(
		document.ast,
		document.imports,
		document.package_name,
		document.uri.uri,
		document.fullpath,
		allocator,
	)

	get_globals(document.ast, &ast_context)


	ast_context.current_package = ast_context.document_package

	symbols := make(map[uintptr]SymbolAndNode, 10000, allocator)

	for decl in document.ast.decls {
		if _, is_value := decl.derived.(^ast.Value_Decl); !is_value {
			continue
		}

		resolve_decl(&ast_context, document, decl, &symbols, allocator)
		clear(&ast_context.locals)
	}

	return symbols
}

FileResolveData :: struct {
	ast_context: ^AstContext,
	symbols:     ^map[uintptr]SymbolAndNode,
	id_counter:  int,
	document:    ^Document,
}


@(private = "file")
resolve_decl :: proc(
	ast_context: ^AstContext,
	document: ^Document,
	decl: ^ast.Node,
	symbols: ^map[uintptr]SymbolAndNode,
	allocator := context.allocator,
) {
	data := FileResolveData {
		ast_context = ast_context,
		symbols     = symbols,
		document    = document,
	}

}

@(private = "file")
resolve_node :: proc(
	ast_context: ^AstContext,
	document: ^Document,
	node: ^ast.Node,
	symbols: ^map[uintptr]SymbolAndNode,
	data: FileResolveData,
	allocator := context.allocator,
) {


}

@(private = "file")
resolve_nodes :: proc(
	ast_context: ^AstContext,
	document: ^Document,
	array: []$T/^ast.Node,
	symbols: ^map[uintptr]SymbolAndNode,
	data: FileResolveData,
	allocator := context.allocator,
) {
	for elem in array {
		resolve_node(elem)
	}
}
