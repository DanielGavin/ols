package server

import "core:slice"
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

	expr_name :: proc (node: ^ast.Node) -> (name: string, ok: bool) {
		#partial switch v in node.derived {
		case ^ast.Ident: return v.name, true
		case ^ast.Poly_Type: return expr_name(v.type)
		case: return
		}
	}

	visit_call :: proc (
		call: ^ast.Call_Expr,
		data: ^Visitor_Data,
	) -> (ok: bool) {

		selector, is_selector_call := call.expr.derived.(^ast.Selector_Expr)
		is_selector_call &&= selector.op.kind == .Arrow_Right

		src := string(data.document.text)
		end_pos := common.token_pos_to_position(call.close, src)

		symbol_and_node := data.symbols[uintptr(call.expr)] or_return
		proc_symbol := symbol_and_node.symbol.value.(SymbolProcedureValue) or_return

		param_idx := 1 if is_selector_call else 0
		label_idx := 0
		arg_idx   := 0

		// Positional arguments
		for ; arg_idx < len(call.args); arg_idx += 1 {
			arg := call.args[arg_idx]

			// provided as named
			if _, is_field := arg.derived.(^ast.Field_Value); is_field do break

			param := slice.get(proc_symbol.arg_types, param_idx) or_return

			// param is variadic
			if param.type != nil {
				if _, is_variadic := param.type.derived.(^ast.Ellipsis); is_variadic do break
			}

			label := slice.get(param.names, label_idx) or_return

			label_name := expr_name(label) or_return
			arg_name, arg_has_name := expr_name(arg)

			// Add param name hint (skip idents with same name as param)
			if data.config.enable_inlay_hints_params && (!arg_has_name || arg_name != label_name) {
				range := common.get_token_range(arg, string(data.document.text))
				hint_label := fmt.tprintf("%v = ", label_name)
				append(&data.hints, InlayHint{range.start, .Parameter, hint_label})
			}

			label_idx += 1
			if label_idx >= len(param.names) {
				param_idx += 1
				label_idx = 0
				if param_idx >= len(proc_symbol.arg_types) {
					return // end of parameters
				}
			}
		}

		// Variadic arguments
		variadic: {
			param := slice.get(proc_symbol.arg_types, param_idx) or_return

			// param is variadic
			if param.type == nil do break variadic
			_ = param.type.derived.(^ast.Ellipsis) or_break variadic

			label := slice.get(param.names, 0) or_return
			label_name := expr_name(label) or_return

			init_arg_idx := arg_idx
			for arg_idx < len(call.args) {

				// provided as named
				if _, is_field := call.args[arg_idx].derived.(^ast.Field_Value); is_field do break

				arg_idx += 1
			}

			// Add param name hint
			if arg_idx > init_arg_idx && data.config.enable_inlay_hints_params {
				// get range from first variadic arg
				range := common.get_token_range(call.args[init_arg_idx], string(data.document.text))
				hint_label := fmt.tprintf("%v = ", label_name)
				append(&data.hints, InlayHint{range.start, .Parameter, hint_label})
			}

			param_idx += 1
			label_idx = 0
			if param_idx >= len(proc_symbol.arg_types) {
				return // end of parameters
			}
		}

		// Named arguments
		named: if data.config.enable_inlay_hints_default_params {

			init_arg_idx := arg_idx
			added_default_hint := false

			for ; param_idx < len(proc_symbol.arg_types); param_idx, label_idx = param_idx + 1, 0 {
				param := slice.get(proc_symbol.arg_types, param_idx) or_return

				label_loop: for ; label_idx < len(param.names); label_idx += 1 {
					label := slice.get(param.names, label_idx) or_return
					label_name := expr_name(label) or_return

					if param.default_value == nil do continue

					// check if was already provided
					for arg in call.args[init_arg_idx:] {

						field_value := arg.derived.(^ast.Field_Value) or_break named
						ident := field_value.field.derived.(^ast.Ident) or_break named

						if ident.name == label_name {
							continue label_loop
						}
					}

					needs_leading_comma := added_default_hint || param_idx > 0 || label_idx > 0
					if needs_leading_comma && !added_default_hint {
						// check for existing trailing comma
						#reverse for ch in string(data.document.text[:call.close.offset]) {
							switch ch {
							case ' ', '\t', '\n': continue
							case ',': needs_leading_comma = false
							}
							break
						}
					}

					// Add default param hint
					value := node_to_string(param.default_value)
					hint_label := fmt.tprintf("%s%v = %v", needs_leading_comma ? ", " : "", label_name, value)
					append(&data.hints, InlayHint{end_pos, .Parameter, hint_label})

					added_default_hint = true
				}
			}
		}

		return true
	}

	return data.hints[:], true
}
