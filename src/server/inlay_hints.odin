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
	Visitor_Data :: struct {
		hints:    [dynamic]InlayHint,
		document: ^Document,
		symbols:  map[uintptr]SymbolAndNode,
		config:   ^common.Config,
	}

	data := Visitor_Data{
		hints    = make([dynamic]InlayHint, context.temp_allocator),
		document = document,
		symbols  = symbols,
		config   = config,
	}

	visitor := ast.Visitor{
		data  = &data,
		visit = proc(visitor: ^ast.Visitor, node: ^ast.Node) -> ^ast.Visitor {
			if node == nil || visitor == nil {
				return nil
			}

			if call, ok := node.derived.(^ast.Call_Expr); ok {
				visit_call(call, (^Visitor_Data)(visitor.data))
			}

			return visitor
		},
	}

	for decl in document.ast.decls {
		ast.walk(&visitor, decl)
	}

	visit_call :: proc (
		call: ^ast.Call_Expr,
		data: ^Visitor_Data,
	) -> (ok: bool) {

		is_ellipsis := false
		has_added_default := false

		selector, is_selector_call := call.expr.derived.(^ast.Selector_Expr)
		is_selector_call &&= selector.op.kind == .Arrow_Right

		end_pos := common.token_pos_to_position(call.close, string(data.document.text))

		symbol_and_node := data.symbols[cast(uintptr)call.expr] or_return
		symbol_call := symbol_and_node.symbol.value.(SymbolProcedureValue) or_return

		positional_arg_idx := 0

		expr_name :: proc (node: ^ast.Node) -> (name: string, ok: bool) {
			#partial switch v in node.derived {
			case ^ast.Ident: return v.name, true
			case ^ast.Poly_Type: return expr_name(v.type)
			case: return
			}
		}

		for arg, arg_type_idx in symbol_call.arg_types {
			if arg_type_idx == 0 && is_selector_call {
				continue
			}

			for name, name_idx in arg.names {

				arg_call_idx := arg_type_idx + name_idx
				if is_selector_call do arg_call_idx -= 1

				label := expr_name(name) or_return

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
						return
					}

					if !data.config.enable_inlay_hints_default_params {
						return
					}

					value := node_to_string(arg.default_value)

					needs_leading_comma := arg_call_idx > 0

					if !has_added_default && needs_leading_comma {
						till_end := string(data.document.text[:call.close.offset])
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
					append(&data.hints, hint)

					has_added_default = true
				} else if data.config.enable_inlay_hints_params && is_provided_positional && !is_provided_named {
					// This parameter is provided via positional argument, show parameter hint

					// if the arg name and param name are the same, don't add it.
					call_arg_name, _ := expr_name(call_arg)
					if call_arg_name != label {
						range := common.get_token_range(call_arg, string(data.document.text))
						hint := InlayHint {
							kind     = .Parameter,
							label    = fmt.tprintf("%v = ", label),
							position = range.start,
						}
						append(&data.hints, hint)
					}
				}

				if arg.type != nil {
					_, is_current_ellipsis := arg.type.derived.(^ast.Ellipsis)
					is_ellipsis ||= is_current_ellipsis
				}
			}
		}

		return true
	}

	return data.hints[:], true
}
