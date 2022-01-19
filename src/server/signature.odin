package server

import "core:odin/parser"
import "core:odin/ast"
import "core:odin/tokenizer"
import "core:fmt"
import "core:log"
import "core:strings"
import path "core:path/slashpath"
import "core:mem"
import "core:strconv"
import "core:path/filepath"
import "core:sort"
import "core:slice"

import "shared:common"
import "shared:index"
import "shared:analysis"

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
	activeParameter: int,
}

/*
	Lazily build the signature and returns from ast.Nodes
*/
build_procedure_symbol_signature :: proc(symbol: ^index.Symbol) {
	if value, ok := symbol.value.(index.SymbolProcedureValue); ok {
		builder := strings.make_builder(context.temp_allocator);
	
		strings.write_string(&builder, "proc");
		strings.write_string(&builder, "(");
		for arg, i in value.arg_types {
			strings.write_string(&builder, common.node_to_string(arg));
			if i != len(value.arg_types) - 1 {
				strings.write_string(&builder, ", ");
			}
		}
		strings.write_string(&builder, ")");

		if len(value.return_types) != 0 {
			strings.write_string(&builder, " -> ");

			if len(value.return_types) > 1 {
				strings.write_string(&builder, "(");
			}
	
			for arg, i in value.return_types {
				strings.write_string(&builder, common.node_to_string(arg));
				if i != len(value.return_types) - 1 {
					strings.write_string(&builder, ", ");
				}
			}
			
			if len(value.return_types) > 1 {
				strings.write_string(&builder, ")");
			}
		}
		symbol.signature = strings.to_string(builder);
	} else if value, ok := symbol.value.(index.SymbolAggregateValue); ok {
		symbol.signature = "proc";
	}
}

seperate_proc_field_arguments :: proc(procedure: ^index.Symbol) {
	if value, ok := &procedure.value.(index.SymbolProcedureValue); ok {
		types := make([dynamic]^ast.Field, context.temp_allocator);
				
		for arg, i in value.arg_types {
			if len(arg.names) == 1 {
				append(&types, arg);
				continue;
			}

			for name in arg.names {
				field : ^ast.Field = index.new_type(ast.Field, {}, {}, context.temp_allocator);
				field.names = make([]^ast.Expr, 1, context.temp_allocator);
				field.names[0] = name;
				field.type = arg.type;
				append(&types, field);
			}
		}

		value.arg_types = types[:];
	}
}

get_signature_information :: proc(document: ^common.Document, position: common.Position) -> (SignatureHelp, bool) {
	using analysis;

	signature_help: SignatureHelp;

	ast_context := make_ast_context(document.ast, document.imports, document.package_name, document.uri.uri);

	position_context, ok := get_document_position_context(document, position, .SignatureHelp);

	if !ok {
		return signature_help, true;
	}

	//TODO(should probably not be an ast.Expr, but ast.Call_Expr)
	if position_context.call == nil {
		return signature_help, true;
	}

	get_globals(document.ast, &ast_context);

	if position_context.function != nil {
		get_locals(document.ast, position_context.function, &ast_context, &position_context);
	}

	for comma, i in position_context.call_commas {
		if position_context.position > comma {
			signature_help.activeParameter = i+1;
		} else if position_context.position == comma {
			signature_help.activeParameter = i;
		}
	}

	call: index.Symbol;
	call, ok = resolve_type_expression(&ast_context, position_context.call);

	if !ok {
		return signature_help, true; 
	}

	seperate_proc_field_arguments(&call);

	signature_information := make([dynamic]SignatureInformation, context.temp_allocator);

	if value, ok := call.value.(index.SymbolProcedureValue); ok {
		parameters := make([]ParameterInformation, len(value.arg_types), context.temp_allocator);
		
		for arg, i in value.arg_types {
			if arg.type != nil {
				if _, is_ellipsis := arg.type.derived.(ast.Ellipsis); is_ellipsis {
					signature_help.activeParameter = min(i, signature_help.activeParameter);
				}
			}

			parameters[i].label = common.node_to_string(arg);
		}

		build_procedure_symbol_signature(&call);

		info := SignatureInformation {
			label = concatenate_symbol_information(&ast_context, call, false),
			documentation = call.doc,
			parameters = parameters,
		};	
		append(&signature_information, info);
	} else if value, ok := call.value.(index.SymbolAggregateValue); ok {
		//function overloaded procedures
		for symbol in value.symbols {

			symbol := symbol;

			if value, ok := symbol.value.(index.SymbolProcedureValue); ok {

				parameters := make([]ParameterInformation, len(value.arg_types), context.temp_allocator);

				for arg, i in value.arg_types {
				
					if arg.type != nil {
						if _, is_ellipsis := arg.type.derived.(ast.Ellipsis); is_ellipsis {
							signature_help.activeParameter = min(i, signature_help.activeParameter);
						}
					}

					parameters[i].label = common.node_to_string(arg);
					parameters[i].activeParameter = i;
				}

				build_procedure_symbol_signature(&symbol);

				info := SignatureInformation {
					label = concatenate_symbol_information(&ast_context, symbol, false),
					documentation = symbol.doc,
					parameters = parameters,
				};	

				append(&signature_information, info);
			}
		}
	}

	signature_help.signatures = signature_information[:];

	return signature_help, true;
}