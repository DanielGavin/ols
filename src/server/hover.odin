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

write_hover_content :: proc(ast_context: ^AstContext, symbol: Symbol) -> MarkupContent {
	content: MarkupContent

	symbol := symbol

	if untyped, ok := symbol.value.(SymbolUntypedValue); ok {
		switch untyped.type {
		case .String:  symbol.signature = "string"
		case .Bool:	   symbol.signature = "bool"
		case .Float:   symbol.signature = "float"
		case .Integer: symbol.signature = "int"
		}
	}

	build_procedure_symbol_signature(&symbol)

	cat := concatenate_symbol_information(ast_context, symbol, false)

	if cat != "" {
		content.kind = "markdown"
		content.value = fmt.tprintf("```odin\n %v\n```\n%v", cat, symbol.doc)
	} else {
		content.kind = "plaintext"
	}

	return content
}

builtin_identifier_hover: map[string]string = {
	"context" = fmt.aprintf("```odin\n %v\n```\n%v", "runtime.context: Context", "This context variable is local to each scope and is implicitly passed by pointer to any procedure call in that scope (if the procedure has the Odin calling convention)."),
}


get_hover_information :: proc(document: ^common.Document, position: common.Position) -> (Hover, bool, bool) {
	hover := Hover {
		contents = {
			kind = "plaintext",
		},
	}

	ast_context := make_ast_context(document.ast, document.imports, document.package_name, document.uri.uri)

	position_context, ok := get_document_position_context(document, position, .Hover)

	get_globals(document.ast, &ast_context)

	if position_context.function != nil {
		get_locals(document.ast, position_context.function, &ast_context, &position_context)
	}

	if position_context.identifier != nil {
		if ident, ok := position_context.identifier.derived.(^ast.Ident); ok {
			if _, ok := common.keyword_map[ident.name]; ok {
				hover.contents.kind = "plaintext"
				hover.range = common.get_token_range(position_context.identifier^, ast_context.file.src)
				return hover, true, true
			}

			if str, ok := builtin_identifier_hover[ident.name]; ok {
				hover.contents.kind = "markdown"
				hover.contents.value = str
				hover.range = common.get_token_range(position_context.identifier^, ast_context.file.src)
				return hover, true, true
			}
		} 
	}

	if position_context.implicit_context != nil {
		if str, ok := builtin_identifier_hover[position_context.implicit_context.tok.text]; ok {
			hover.contents.kind = "markdown"
			hover.contents.value = str
			hover.range = common.get_token_range(position_context.implicit_context^, ast_context.file.src)
			return hover, true, true
		}
	}

	if position_context.selector != nil && position_context.identifier != nil {
		hover.range = common.get_token_range(position_context.identifier^, ast_context.file.src)
		ast_context.use_locals = true
		ast_context.use_globals = true
		ast_context.current_package = ast_context.document_package

		//if the base selector is the client wants to go to.
		if base, ok := position_context.selector.derived.(^ast.Ident); ok && position_context.identifier != nil && position_in_node(position_context.selector, position_context.position) {
			ident := position_context.identifier.derived.(^ast.Ident)^

			if ident.name == base.name {

				if resolved, ok := resolve_type_identifier(&ast_context, ident); ok {				
					resolved.signature = get_signature(&ast_context, ident, resolved)
					resolved.name = ident.name

					if resolved.type == .Variable {
						resolved.pkg = ast_context.document_package
					}

					hover.contents = write_hover_content(&ast_context, resolved)
					return hover, true, true
				}
			}
		}

		selector: Symbol
		selector, ok = resolve_type_expression(&ast_context, position_context.selector)

		if !ok {
			return hover, false, true
		}

		field: string

		if position_context.field != nil {
			#partial switch v in position_context.field.derived {
			case ^ast.Ident:
				field = v.name
			}
		}

	
		#partial switch v in selector.value {
		case SymbolStructValue:
			for name, i in v.names {
				if strings.compare(name, field) == 0 {
					if symbol, ok := resolve_type_expression(&ast_context, v.types[i]); ok {
						symbol.name = name //TODO refractor - never set symbol name after creation - change writer_hover_content
						symbol.pkg = selector.name
						symbol.signature = common.node_to_string(v.types[i])
						hover.contents = write_hover_content(&ast_context, symbol)
						return hover, true, true
					}
				}
			}
		case SymbolPackageValue:
			if position_context.field != nil {
				if ident, ok := position_context.field.derived.(^ast.Ident); ok {
					ast_context.current_package = selector.pkg
					if symbol, ok := resolve_type_identifier(&ast_context, ident^); ok {
						hover.contents = write_hover_content(&ast_context, symbol)
						return hover, true, true
					}
				}
			}
		}
	} else if position_context.identifier != nil {
		ast_context.use_locals = true
		ast_context.use_globals = true
		ast_context.current_package = ast_context.document_package

		ident := position_context.identifier.derived.(^ast.Ident)^

		hover.range = common.get_token_range(position_context.identifier^, document.ast.src)

		if resolved, ok := resolve_type_identifier(&ast_context, ident); ok {	
			resolved.signature = get_signature(&ast_context, ident, resolved)
			resolved.name = ident.name

			if resolved.type == .Variable {
				resolved.pkg = ast_context.document_package
			}

			hover.contents = write_hover_content(&ast_context, resolved)
			return hover, true, true
		}
	}

	return hover, false, true
}
