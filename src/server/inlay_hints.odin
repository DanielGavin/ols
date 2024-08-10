package server

import "core:fmt"
import "core:log"
import "core:odin/ast"

import "src:common"

get_inlay_hints :: proc(
	document: ^Document,
	symbols: map[uintptr]SymbolAndNode,
	config: ^common.Config,
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
		is_selector_call := false
		is_ellipsis := false
		has_added_default := false

		call := node_call.derived.(^ast.Call_Expr)

		// TODO: support this (inlay hints in calls that use named args, e.g. `foobar(foo=bar)`
		for arg in call.args {
			if _, ok := arg.derived.(^ast.Field_Value); ok {
				continue loop
			}
		}

		if selector, ok := call.expr.derived.(^ast.Selector_Expr); ok && selector.op.kind == .Arrow_Right {
			is_selector_call = true
		}

		if symbol_and_node, ok := symbols[cast(uintptr)call.expr]; ok {
			if symbol_call, ok := symbol_and_node.symbol.value.(SymbolProcedureValue); ok {
				for arg, i in symbol_call.arg_types {
					if i == 0 && is_selector_call {
						continue
					}

					for name in arg.names {
						label := ""
						is_current_ellipsis := false

						if arg.type != nil {
							if ellipsis, ok := arg.type.derived.(^ast.Ellipsis); ok {
								is_current_ellipsis = true
							}
						}

						#partial switch v in name.derived {
						case ^ast.Ident:
							label = v.name
						case ^ast.Poly_Type:
							if ident, ok := v.type.derived.(^ast.Ident); ok {
								label = ident.name
							} else {
								continue loop
							}
						case:
							continue loop
						}

						if is_ellipsis || symbol_arg_count >= len(call.args) {
							if arg.default_value == nil {
								continue loop
							}

							if !config.enable_inlay_hints_default_params {
								continue loop
							}

							value := common.node_to_string(arg.default_value)

							call_range := common.get_token_range(call, string(document.text))

							position: common.Position
							position = call_range.end
							position.character -= 1

							needs_leading_comma := i > 0

							if !has_added_default && needs_leading_comma {
								till_end := string(document.text[:call.close.offset])
								#reverse for ch in till_end {
									switch ch {
									case ' ', '\t', '\n':
										continue
									case ',':
										needs_leading_comma = false
									}
									break
								}
							}

							hint := InlayHint {
								kind     = .Parameter,
								label    = fmt.tprintf("%s %v := %v", needs_leading_comma ? "," : "", label, value),
								position = position,
							}
							append(&hints, hint)

							has_added_default = true
						} else if config.enable_inlay_hints_params {

							// if the arg name and param name are the same, don't add it.
							same_name: bool
							#partial switch v in call.args[symbol_arg_count].derived_expr {
							case ^ast.Ident:
								same_name = label == v.name
							case ^ast.Poly_Type:
								if ident, ok := v.type.derived.(^ast.Ident); ok {
									same_name = label == ident.name
								}
							}

							if !same_name {
								range := common.get_token_range(call.args[symbol_arg_count], string(document.text))
								hint := InlayHint {
									kind     = .Parameter,
									label    = fmt.tprintf("%v = ", label),
									position = range.start,
								}
								append(&hints, hint)
							}
						}

						if is_current_ellipsis {
							is_ellipsis = true
						}

						symbol_arg_count += 1
					}
				}
			}
		}
	}

	return hints[:], true
}
