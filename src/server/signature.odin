package server

import "core:fmt"
import "core:log"
import "core:mem"
import "core:odin/ast"
import "core:odin/parser"
import "core:odin/tokenizer"
import "core:path/filepath"
import path "core:path/slashpath"
import "core:slice"
import "core:sort"
import "core:strconv"
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

/*
	Lazily build the signature and returns from ast.Nodes
*/
build_procedure_symbol_signature :: proc(symbol: ^Symbol, short_signature := true) {
	if value, ok := symbol.value.(SymbolProcedureValue); ok {
		builder := strings.builder_make(context.temp_allocator)
		write_procedure_symbol_signature(&builder, &value)
		symbol.signature = strings.to_string(builder)
	} else if value, ok := symbol.value.(SymbolAggregateValue); ok {
		if short_signature {
			symbol.signature = "proc"
			return
		}

		builder := strings.builder_make(context.temp_allocator)
		strings.write_string(&builder, "proc {\n")
		for symbol in value.symbols {
			if value, ok := symbol.value.(SymbolProcedureValue); ok {
				fmt.sbprintf(&builder, "\t%s :: ", symbol.name)
				write_procedure_symbol_signature(&builder, &value)
				strings.write_string(&builder, ",\n")
			}
		}
		strings.write_string(&builder, "}")
		symbol.signature = strings.to_string(builder)
	}
}

write_procedure_symbol_signature :: proc(sb: ^strings.Builder, value: ^SymbolProcedureValue) {
	strings.write_string(sb, "proc")
	strings.write_string(sb, "(")
	for arg, i in value.orig_arg_types {
		strings.write_string(sb, node_to_string(arg))
		if i != len(value.orig_arg_types) - 1 {
			strings.write_string(sb, ", ")
		}
	}
	strings.write_string(sb, ")")

	if len(value.orig_return_types) != 0 {
		strings.write_string(sb, " -> ")

		if len(value.orig_return_types) > 1 {
			strings.write_string(sb, "(")
		}

		for arg, i in value.orig_return_types {
			strings.write_string(sb, node_to_string(arg))
			if i != len(value.orig_return_types) - 1 {
				strings.write_string(sb, ", ")
			}
		}

		if len(value.orig_return_types) > 1 {
			strings.write_string(sb, ")")
		}
	} else if value.diverging {
		strings.write_string(sb, " -> !")
	}
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

get_signature_information :: proc(document: ^Document, position: common.Position) -> (SignatureHelp, bool) {
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
	if position_context.call == nil {
		return signature_help, true
	}

	get_globals(document.ast, &ast_context)

	if position_context.function != nil {
		get_locals(document.ast, position_context.function, &ast_context, &position_context)
	}

	for comma, i in position_context.call_commas {
		if position_context.position > comma {
			signature_help.activeParameter = i + 1
		} else if position_context.position == comma {
			signature_help.activeParameter = i
		}
	}

	if position_context.arrow {
		signature_help.activeParameter += 1
	}

	call: Symbol
	call, ok = resolve_type_expression(&ast_context, position_context.call)

	if !ok {
		return signature_help, true
	}

	seperate_proc_field_arguments(&call)

	signature_information := make([dynamic]SignatureInformation, context.temp_allocator)

	if value, ok := call.value.(SymbolProcedureValue); ok {
		parameters := make([]ParameterInformation, len(value.orig_arg_types), context.temp_allocator)

		for arg, i in value.orig_arg_types {
			if arg.type != nil {
				if _, is_ellipsis := arg.type.derived.(^ast.Ellipsis); is_ellipsis {
					signature_help.activeParameter = min(i, signature_help.activeParameter)
				}
			}

			parameters[i].label = node_to_string(arg)
		}

		build_procedure_symbol_signature(&call)

		info := SignatureInformation {
			label         = concatenate_symbol_information(&ast_context, call, false),
			documentation = call.doc,
			parameters    = parameters,
		}
		append(&signature_information, info)
	} else if value, ok := call.value.(SymbolAggregateValue); ok {
		//function overloaded procedures
		for symbol in value.symbols {
			symbol := symbol

			if value, ok := symbol.value.(SymbolProcedureValue); ok {
				parameters := make([]ParameterInformation, len(value.orig_arg_types), context.temp_allocator)

				for arg, i in value.orig_arg_types {
					if arg.type != nil {
						if _, is_ellipsis := arg.type.derived.(^ast.Ellipsis); is_ellipsis {
							signature_help.activeParameter = min(i, signature_help.activeParameter)
						}
					}

					parameters[i].label = node_to_string(arg)
				}

				build_procedure_symbol_signature(&symbol)

				info := SignatureInformation {
					label         = concatenate_symbol_information(&ast_context, symbol, false),
					documentation = symbol.doc,
				}

				append(&signature_information, info)
			}
		}
	}

	signature_help.signatures = signature_information[:]

	return signature_help, true
}
