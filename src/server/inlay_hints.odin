package server

import "core:odin/ast"
import "core:fmt"

import "shared:common"

get_inlay_hints :: proc(
	document: ^Document,
	symbols: map[uintptr]SymbolAndNode,
) -> (
	[]InlayHint,
	bool,
) {
	hints := make([dynamic]InlayHint, context.temp_allocator)

	ast_context := make_ast_context(
		document.ast,
		document.imports,
		document.package_name,
		document.uri.uri,
		document.fullpath,
	)

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
		data  = &data,
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

		if symbol_and_node, ok := symbols[cast(uintptr)node_call]; ok {
			if symbol_call, ok := symbol_and_node.symbol.value.(SymbolProcedureValue);
			   ok {
				for arg in symbol_call.arg_types {
					for name in arg.names {
						if symbol_arg_count >= len(call.args) {
							continue loop
						}

						if ident, ok := name.derived.(^ast.Ident); ok {
							range := common.get_token_range(
								call.args[symbol_arg_count],
								string(document.text),
							)
							hint := InlayHint {
								kind     = .Parameter,
								label    = fmt.tprintf("%v = ", ident.name),
								position = range.start,
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
