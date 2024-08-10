package server

import "core:odin/ast"


import "src:common"


CodeLensClientCapabilities :: struct {
	dynamicRegistration: bool,
}

CodeLensOptions :: struct {
	resolveProvider: bool,
}

CodeLens :: struct {
	range:   common.Range,
	command: Command,
	data:    string,
}

get_code_lenses :: proc(document: ^Document, position: common.Position) -> ([]CodeLens, bool) {
	ast_context := make_ast_context(
		document.ast,
		document.imports,
		document.package_name,
		document.uri.uri,
		document.fullpath,
	)

	get_globals(document.ast, &ast_context)

	symbols := make([dynamic]CodeLens, context.temp_allocator)

	if len(document.ast.decls) == 0 {
		return {}, true
	}

	for name, global in ast_context.globals {


		if proc_lit, ok := global.expr.derived.(^ast.Proc_Lit); ok {


		}


	}


	return {}, false

}
