package server

import "core:log"
import "core:odin/ast"
import "core:odin/tokenizer"
import "core:strings"

import "src:common"

SignatureInformationCapabilities :: struct {
	parameterInformation: ParameterInformationCapabilities,
}

SignatureHelpClientCapabilities :: struct {
	dynamicRegistration:  bool,
	signatureInformation: SignatureInformationCapabilities,
	contextSupport:       bool,
}

SignatureHelpOptions :: struct {
	triggerCharacters:   []string,
	retriggerCharacters: []string,
}

SignatureHelp :: struct {
	signatures:      []SignatureInformation,
	activeSignature: int,
	activeParameter: int,
}

SignatureInformation :: struct {
	label:         string,
	documentation: string,
	parameters:    []ParameterInformation,
}

ParameterInformation :: struct {
	label: string,
}

seperate_proc_field_arguments :: proc(procedure: ^Symbol) {
	if value, ok := &procedure.value.(SymbolProcedureValue); ok {
		types := make([dynamic]^ast.Field, context.temp_allocator)

		for arg, i in value.orig_arg_types {
			if len(arg.names) == 1 {
				append(&types, arg)
				continue
			}

			for name in arg.names {
				field: ^ast.Field = new_type(ast.Field, arg.pos, arg.end, context.temp_allocator)
				field.names = make([]^ast.Expr, 1, context.temp_allocator)
				field.names[0] = name
				field.type = arg.type
				append(&types, field)
			}
		}

		value.orig_arg_types = types[:]
	}
}


get_signature_information :: proc(
	document: ^Document,
	position: common.Position,
	config: ^common.Config,
) -> (
	SignatureHelp,
	bool,
) {
	signature_help: SignatureHelp

	ast_context := make_ast_context(
		document.ast,
		document.imports,
		document.package_name,
		document.uri.uri,
		document.fullpath,
	)

	position_context, ok := get_document_position_context(document, position, .SignatureHelp)
	if !ok {
		log.warn("Failed to get position context")
		return signature_help, true
	}
	ast_context.position_hint = position_context.hint

	//TODO(should probably not be an ast.Expr, but ast.Call_Expr)
	if position_context.call == nil && !config.enable_comp_lit_signature_help {
		return signature_help, true
	}

	get_globals(document.ast, &ast_context)

	if position_context.function != nil {
		get_locals(document.ast, position_context.function, &ast_context, &position_context)
	}
	signature_information := make([dynamic]SignatureInformation, context.temp_allocator)

	if position_context.call != nil {
		signature_help.activeParameter = add_proc_signature(&ast_context, &position_context, &signature_information)
	}

	if config.enable_comp_lit_signature_help {
		if symbol, ok := resolve_comp_literal(&ast_context, &position_context); ok {
			build_documentation(&ast_context, &symbol, short_signature = false)
			append(
				&signature_information,
				SignatureInformation {
					label = get_signature(symbol),
					documentation = construct_symbol_docs(symbol),
				},
			)
		}
	}

	signature_help.signatures = signature_information[:]

	return signature_help, true
}

@(private = "file")
get_signature :: proc(symbol: Symbol) -> string {
	sb := strings.builder_make()
	write_symbol_name(&sb, symbol)
	strings.write_string(&sb, " :: ")
	strings.write_string(&sb, symbol.signature)
	return strings.to_string(sb)
}

@(private = "file")
add_proc_signature :: proc(
	ast_context: ^AstContext,
	position_context: ^DocumentPositionContext,
	signature_information: ^[dynamic]SignatureInformation,
) -> (
	active_parameter: int,
) {
	for comma, i in position_context.call_commas {
		if position_context.position > comma {
			active_parameter = i + 1
		} else if position_context.position == comma {
			active_parameter = i
		}
	}

	if position_context.arrow {
		active_parameter = 1
	}

	call, ok := resolve_type_expression(ast_context, position_context.call)
	if !ok {
		return active_parameter
	}

	seperate_proc_field_arguments(&call)

	if value, ok := call.value.(SymbolProcedureValue); ok {
		parameters := make([]ParameterInformation, len(value.orig_arg_types), context.temp_allocator)

		for arg, i in value.orig_arg_types {
			if arg.type != nil {
				if _, is_ellipsis := arg.type.derived.(^ast.Ellipsis); is_ellipsis {
					active_parameter = min(i, active_parameter)
				}
			}

			parameters[i].label = node_to_string(arg)
		}

		sb := strings.builder_make(context.temp_allocator)
		write_procedure_symbol_signature(&sb, value, detailed_signature = false)
		call.signature = strings.to_string(sb)

		info := SignatureInformation {
			label         = get_signature(call),
			documentation = construct_symbol_docs(call),
			parameters    = parameters,
		}
		append(signature_information, info)
	} else if value, ok := call.value.(SymbolAggregateValue); ok {
		//function overloaded procedures
		for symbol in value.symbols {
			symbol := symbol

			if value, ok := symbol.value.(SymbolProcedureValue); ok {
				parameters := make([]ParameterInformation, len(value.orig_arg_types), context.temp_allocator)

				for arg, i in value.orig_arg_types {
					if arg.type != nil {
						if _, is_ellipsis := arg.type.derived.(^ast.Ellipsis); is_ellipsis {
							active_parameter = min(i, active_parameter)
						}
					}

					parameters[i].label = node_to_string(arg)
				}

				sb := strings.builder_make(context.temp_allocator)
				write_procedure_symbol_signature(&sb, value, detailed_signature = false)
				symbol.signature = strings.to_string(sb)

				info := SignatureInformation {
					label         = get_signature(symbol),
					documentation = construct_symbol_docs(symbol),
					parameters    = parameters,
				}

				append(signature_information, info)
			}
		}
	}
	return active_parameter
}
