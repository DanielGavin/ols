package server 

import "core:odin/ast"
import "core:fmt"

import "shared:common"
import "shared:analysis"
import "shared:index"

//document
get_inlay_hints :: proc(document: ^common.Document, symbols: map[uintptr]index.Symbol) -> ([]InlayHint, bool) {
	using analysis

	hints := make([dynamic]InlayHint, context.temp_allocator)

	ast_context := make_ast_context(document.ast, document.imports, document.package_name, document.uri.uri)

	Visit_Data :: struct {
		calls: [dynamic]^ast.Node,
	}

	data := Visit_Data {
		calls = make([dynamic]^ast.Node, context.temp_allocator),
	}

	visit :: proc(visitor: ^ast.Visitor, node: ^ast.Node) -> ^ast.Visitor {
		if node == nil || visitor == nil {
			return nil
		}

		data := cast(^Visit_Data)visitor.data

		if call, ok := node.derived.(^ast.Call_Expr); ok {
			append(&data.calls, node)
		}

		return visitor
	}

	visitor := ast.Visitor {
		data = &data,
		visit = visit,
	}

	for decl in document.ast.decls {
		ast.walk(&visitor, decl)
	}

	loop: for node_call in &data.calls {
		symbol_arg_count := 0

		call := node_call.derived.(^ast.Call_Expr)

		for arg in call.args {
			if _, ok := arg.derived.(^ast.Field); ok {
				continue loop
			}
		}

		if symbol, ok := symbols[cast(uintptr)node_call]; ok {
			if symbol_call, ok := symbol.value.(index.SymbolProcedureValue); ok {
				for arg in symbol_call.arg_types {
					for name in arg.names {
						if symbol_arg_count >= len(call.args) {
							continue loop
						}

						if ident, ok := name.derived.(^ast.Ident); ok {
							hint := InlayHint {
								kind = "parameter",
								label = fmt.tprintf("%v = ", ident.name),
								range = common.get_token_range(call.args[symbol_arg_count], string(document.text)),
							}
							append(&hints, hint)
						} 
						symbol_arg_count += 1
					}
				}
			}
		}
	}

	return hints[:], true
}