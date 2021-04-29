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



get_signature_information :: proc(document: ^Document, position: common.Position) -> (SignatureHelp, bool) {

	signature_help: SignatureHelp;

	ast_context := make_ast_context(document.ast, document.imports, document.package_name, document.uri.uri);

	position_context, ok := get_document_position_context(document, position, .SignatureHelp);

	if !ok {
		return signature_help, true;
	}

	if position_context.call == nil {
		return signature_help, true;
	}

	get_globals(document.ast, &ast_context);

	if position_context.function != nil {
		get_locals(document.ast, position_context.function, &ast_context, &position_context);
	}

	call: index.Symbol;
	call, ok = resolve_type_expression(&ast_context, position_context.call);

	signature_information := make([dynamic]SignatureInformation, context.temp_allocator);

	if _, ok := call.value.(index.SymbolProcedureValue); ok {
		info := SignatureInformation {
			label = concatenate_symbols_information(&ast_context, call, false),
			documentation = call.doc,
		};	
		append(&signature_information, info);
	} else if value, ok := call.value.(index.SymbolAggregateValue); ok {
		for symbol in value.symbols {
			info := SignatureInformation {
				label = concatenate_symbols_information(&ast_context, symbol, false),
				documentation = symbol.doc,
			};	
			append(&signature_information, info);
		}
	}

	signature_help.signatures = signature_information[:];
	signature_help.activeSignature = 0;
	signature_help.activeParameter = 0;

	return signature_help, true;
}