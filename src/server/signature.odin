package server

import "core:odin/parser"
import "core:odin/ast"
import "core:odin/tokenizer"
import "core:fmt"
import "core:log"
import "core:strings"
import "core:path"
import "core:mem"
import "core:strconv"
import "core:path/filepath"
import "core:sort"
import "core:slice"

import "shared:common"
import "shared:index"

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

get_signature_information :: proc(document: ^Document, position: common.Position) -> (SignatureHelp, bool) {

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

	signature_information := make([dynamic]SignatureInformation, context.temp_allocator);

	if value, ok := call.value.(index.SymbolProcedureValue); ok {

		parameters := make([]ParameterInformation, len(value.arg_types), context.temp_allocator);

		for arg, i in value.arg_types {
			parameters[i].label = common.get_ast_node_string(arg, document.ast.src);
		}

		info := SignatureInformation {
			label = concatenate_symbols_information(&ast_context, call, false),
			documentation = call.doc,
			parameters = parameters,
		};	
		append(&signature_information, info);
	} else if value, ok := call.value.(index.SymbolAggregateValue); ok {
		//function overloaded procedures
		for symbol in value.symbols {
			info := SignatureInformation {
				label = concatenate_symbols_information(&ast_context, symbol, false),
				documentation = symbol.doc,
			};	
			append(&signature_information, info);
		}
	}

	signature_help.signatures = signature_information[:];

	return signature_help, true;
}