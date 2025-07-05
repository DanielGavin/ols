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

		is_ellipsis := false
		has_added_default := false

		call := node_call.derived.(^ast.Call_Expr)

		selector, is_selector_call := call.expr.derived.(^ast.Selector_Expr)
		is_selector_call &&= selector.op.kind == .Arrow_Right

		end_pos := common.token_pos_to_position(call.close, string(document.text))

		symbol_and_node := symbols[cast(uintptr)call.expr] or_continue
		symbol_call := symbol_and_node.symbol.value.(SymbolProcedureValue) or_continue
		
		positional_arg_idx := 0

		expr_name :: proc (node: ^ast.Node) -> (name: string, ok: bool) {
			#partial switch v in node.derived {
			case ^ast.Ident:
				return v.name, true
			case ^ast.Poly_Type:
				ident := v.type.derived.(^ast.Ident) or_return
				return ident.name, true
			case:
				return
			}
		}
		
		for arg, arg_type_idx in symbol_call.arg_types {
			if arg_type_idx == 0 && is_selector_call {
				continue
			}

			for name, name_idx in arg.names {

				arg_call_idx := arg_type_idx + name_idx
				if is_selector_call do arg_call_idx -= 1

				label := expr_name(name) or_continue loop

				is_provided_named, is_provided_positional: bool
				call_arg: ^ast.Expr

				for a, a_i in call.args[positional_arg_idx:] {
					call_arg_idx := a_i + positional_arg_idx
					// provided as named
					if field_value, ok := a.derived.(^ast.Field_Value); ok {
						ident := field_value.field.derived.(^ast.Ident) or_break
						if ident.name == label {
							is_provided_named = true
							call_arg = a
						}
						break
					} // provided as positional
					else if arg_call_idx == call_arg_idx {
						is_provided_positional = true
						positional_arg_idx += 1
						call_arg = a
						break
					}
				}

				if is_ellipsis || (!is_provided_named && !is_provided_positional) {
					// This parameter is not provided, so it should use default value
					if arg.default_value == nil {
						continue loop
					}

					if !config.enable_inlay_hints_default_params {
						continue loop
					}

					value := node_to_string(arg.default_value)

					needs_leading_comma := arg_call_idx > 0

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
						label    = fmt.tprintf("%s%v = %v", needs_leading_comma ? ", " : "", label, value),
						position = end_pos,
					}
					append(&hints, hint)

					has_added_default = true
				} else if config.enable_inlay_hints_params && is_provided_positional && !is_provided_named {
					// This parameter is provided via positional argument, show parameter hint

					// if the arg name and param name are the same, don't add it.
					call_arg_name, _ := expr_name(call_arg)
					if call_arg_name != label {
						range := common.get_token_range(call_arg, string(document.text))
						hint := InlayHint {
							kind     = .Parameter,
							label    = fmt.tprintf("%v = ", label),
							position = range.start,
						}
						append(&hints, hint)
					}
				}

				if arg.type != nil {
					_, is_current_ellipsis := arg.type.derived.(^ast.Ellipsis)
					is_ellipsis ||= is_current_ellipsis
				}
			}
		}
	}

	return hints[:], true
}
