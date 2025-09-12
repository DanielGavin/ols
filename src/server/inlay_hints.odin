package server

import "core:strings"
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

			if call, is_call := node.derived.(^ast.Call_Expr); is_call {
				data := (^Visitor_Data)(visitor.data)
				visit_call(call, data)
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

		src := string(data.document.text)
		end_pos := common.token_pos_to_position(call.close, src)

		selector, is_selector_call := call.expr.derived.(^ast.Selector_Expr)
		is_selector_call &&= selector.op.kind == .Arrow_Right

		symbol_and_node := data.symbols[uintptr(call.expr)] or_return // could not resolve symbol
		proc_symbol := symbol_and_node.symbol.value.(SymbolProcedureValue) or_return // not a procedure call, e.g. type cast

		param_idx := 1 if is_selector_call else 0
		label_idx := 0
		arg_idx   := 0

		if param_idx >= len(proc_symbol.arg_types) do return true // no parameters

		// Positional arguments
		positional: for ; arg_idx < len(call.args); arg_idx += 1 {
			arg := call.args[arg_idx]

			// for multi-return function call arguments
			multi_return: {
				arg_call := arg.derived.(^ast.Call_Expr) or_break multi_return
				arg_symbol_and_node := data.symbols[uintptr(arg_call.expr)] or_break multi_return
				arg_proc_symbol := arg_symbol_and_node.symbol.value.(SymbolProcedureValue) or_break multi_return

				if len(arg_proc_symbol.return_types) <= 1 do break multi_return

				hint_text_sb := strings.builder_make(context.temp_allocator)

				// Collect parameter names for this multi-return call
				for i in 0..<len(arg_proc_symbol.return_types) {
					param := proc_symbol.arg_types[param_idx]
					label := param.names[label_idx]

					label_name, label_has_name := expr_name(label)
					if data.config.enable_inlay_hints_params && label_has_name {
						if i > 0 do strings.write_string(&hint_text_sb, ", ")
						strings.write_string(&hint_text_sb, label_name)
					}

					// advance to next param
					label_idx += 1
					if label_idx >= len(param.names) {
						param_idx += 1
						label_idx = 0
						if param_idx >= len(proc_symbol.arg_types) {
							return true // end of parameters
						}
					}
				}

				// Add combined param name hint
				if data.config.enable_inlay_hints_params && strings.builder_len(hint_text_sb) > 0 {
					range := common.get_token_range(arg, src)
					strings.write_string(&hint_text_sb, " = ")
					hint_text := strings.to_string(hint_text_sb)
					append(&data.hints, InlayHint{range.start, .Parameter, hint_text})
				}

				continue positional
			}

			// provided as named
			if _, is_field := arg.derived.(^ast.Field_Value); is_field do break

			param := proc_symbol.arg_types[param_idx]

			// param is variadic
			if param.type != nil {
				if _, is_variadic := param.type.derived.(^ast.Ellipsis); is_variadic do break
			}

			// Add param name hint for single-value arg
			if data.config.enable_inlay_hints_params {
				label := param.names[label_idx]
				label_name, label_has_name := expr_name(label)
				arg_name, arg_has_name := expr_name(arg)

				// Add param name hint (skip idents with same name as param)
				if label_has_name && (!arg_has_name || arg_name != label_name) {
					range := common.get_token_range(arg, src)
					hint_text := fmt.tprintf("%v = ", label_name)
					append(&data.hints, InlayHint{range.start, .Parameter, hint_text})
				}
			}

			// advance to next param
			label_idx += 1
			if label_idx >= len(param.names) {
				param_idx += 1
				label_idx = 0
				if param_idx >= len(proc_symbol.arg_types) {
					return true // end of parameters
				}
			}
		}

		// Variadic arguments
		variadic: {
			param := proc_symbol.arg_types[param_idx]

			// param is variadic
			if param.type == nil do break variadic
			_ = param.type.derived.(^ast.Ellipsis) or_break variadic

			// skip all provided args
			init_arg_idx := arg_idx
			for ; arg_idx < len(call.args); arg_idx += 1 {
				// provided as named
				if _, is_field := call.args[arg_idx].derived.(^ast.Field_Value); is_field do break
			}

			// Add param name hint
			if arg_idx > init_arg_idx && data.config.enable_inlay_hints_params {
				if label_name, label_has_name := expr_name(param.names[0]); label_has_name {
					range := common.get_token_range(call.args[init_arg_idx], src)
					hint_text := fmt.tprintf("%v = ", label_name)
					append(&data.hints, InlayHint{range.start, .Parameter, hint_text})
				}
			}

			// advance to next param
			param_idx += 1
			label_idx = 0
			if param_idx >= len(proc_symbol.arg_types) {
				return true // end of parameters
			}
		}

		// Named arguments
		named: if data.config.enable_inlay_hints_default_params {

			init_arg_idx := arg_idx
			added_default_hint := false

			for ; param_idx < len(proc_symbol.arg_types); param_idx, label_idx = param_idx+1, 0 {
				param := proc_symbol.arg_types[param_idx]

				label_loop: for ; label_idx < len(param.names); label_idx += 1 {
					label := param.names[label_idx]
					label_name := expr_name(label) or_continue

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
					hint_text := fmt.tprintf("%s%v = %v", needs_leading_comma ? ", " : "", label_name, value)
					append(&data.hints, InlayHint{end_pos, .Parameter, hint_text})

					added_default_hint = true
				}
			}
		}

		return true
	}

	return data.hints[:], true
}
