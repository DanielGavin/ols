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

get_hover_information :: proc(document: ^Document, position: common.Position) -> (Hover, bool) {

	hover := Hover {
		contents = {
			kind = "plaintext",
		},
	};

	ast_context := make_ast_context(document.ast, document.imports, document.package_name);

	position_context, ok := get_document_position_context(document, position, .Hover);

	get_globals(document.ast, &ast_context);

	if position_context.function != nil {
		get_locals(document.ast, position_context.function, &ast_context, &position_context);
	}

	if position_context.identifier != nil {
		if ident, ok := position_context.identifier.derived.(ast.Ident); ok {
			if _, ok := common.keyword_map[ident.name]; ok {
				hover.contents.kind = "plaintext";
				hover.range         = common.get_token_range(position_context.identifier^, ast_context.file.src);
				return hover, true;
			}
		}
	}

	if position_context.selector != nil && position_context.identifier != nil {

		hover.range = common.get_token_range(position_context.identifier^, ast_context.file.src);

		ast_context.use_locals      = true;
		ast_context.use_globals     = true;
		ast_context.current_package = ast_context.document_package;

		//if the base selector is the client wants to go to.
		if base, ok := position_context.selector.derived.(ast.Ident); ok && position_context.identifier != nil {

			ident := position_context.identifier.derived.(ast.Ident);

			if ident.name == base.name {

				if resolved, ok := resolve_type_identifier(&ast_context, ident); ok {
					resolved.name      = ident.name;
					resolved.signature = get_signature(&ast_context, ident, resolved);

					if is_variable, ok := ast_context.variables[ident.name]; ok && is_variable {
						resolved.pkg = ast_context.document_package;
					}

					hover.contents = write_hover_content(&ast_context, resolved);
					return hover, true;
				}
			}
		}

		selector: index.Symbol;
		selector, ok = resolve_type_expression(&ast_context, position_context.selector);

		if !ok {
			return hover, true;
		}

		field: string;

		if position_context.field != nil {

			switch v in position_context.field.derived {
			case ast.Ident:
				field = v.name;
			}
		}

		hover.range = common.get_token_range(position_context.identifier^, document.ast.src);

		#partial switch v in selector.value {
		case index.SymbolStructValue:
			for name, i in v.names {
				if strings.compare(name, field) == 0 {
					if symbol, ok := resolve_type_expression(&ast_context, v.types[i]); ok {
						symbol.name      = name;
						symbol.pkg       = selector.name;
						symbol.signature = index.node_to_string(v.types[i]);
						hover.contents   = write_hover_content(&ast_context, symbol);
						return hover, true;
					}
				}
			}
		case index.SymbolPackageValue:
			if symbol, ok := index.lookup(field, selector.pkg); ok {
				hover.contents = write_hover_content(&ast_context, symbol);
				return hover, true;
			}
		}
	} else if position_context.identifier != nil {

		ast_context.use_locals      = true;
		ast_context.use_globals     = true;
		ast_context.current_package = ast_context.document_package;

		ident := position_context.identifier.derived.(ast.Ident);

		hover.range = common.get_token_range(position_context.identifier^, document.ast.src);

		if resolved, ok := resolve_type_identifier(&ast_context, ident); ok {
			resolved.name      = ident.name;
			resolved.signature = get_signature(&ast_context, ident, resolved);

			if is_variable, ok := ast_context.variables[ident.name]; ok && is_variable {
				resolved.pkg = ast_context.document_package;
			}

			hover.contents = write_hover_content(&ast_context, resolved);
			return hover, true;
		}
	}

	return hover, true;
}
