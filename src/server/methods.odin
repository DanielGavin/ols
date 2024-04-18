package server

import "core:fmt"
import "core:log"
import "core:mem"
import "core:odin/ast"
import "core:odin/parser"
import "core:odin/tokenizer"
import "core:os"
import "core:path/filepath"
import path "core:path/slashpath"
import "core:slice"
import "core:sort"
import "core:strconv"
import "core:strings"


import "src:common"


@(private)
create_remove_edit :: proc(
	position_context: ^DocumentPositionContext,
) -> (
	[]TextEdit,
	bool,
) {
	range, ok := get_range_from_selection_start_to_dot(position_context)

	if !ok {
		return {}, false
	}

	remove_range := common.Range {
		start = range.start,
		end   = range.end,
	}

	remove_edit := TextEdit {
		range   = remove_range,
		newText = "",
	}

	additionalTextEdits := make([]TextEdit, 1, context.temp_allocator)
	additionalTextEdits[0] = remove_edit

	return additionalTextEdits, true
}

append_method_completion :: proc(
	ast_context: ^AstContext,
	selector_symbol: Symbol,
	position_context: ^DocumentPositionContext,
	items: ^[dynamic]CompletionItem,
	receiver: string,
) {
	if selector_symbol.type != .Variable && selector_symbol.type != .Struct {
		return
	}

	remove_edit, ok := create_remove_edit(position_context)

	if !ok {
		return
	}

	for k, v in indexer.index.collection.packages {
		method := Method {
			name = selector_symbol.name,
			pkg  = selector_symbol.pkg,
		}
		if symbols, ok := &v.methods[method]; ok {
			for &symbol in symbols {
				resolve_unresolved_symbol(ast_context, &symbol)
				build_procedure_symbol_signature(&symbol)

				range, ok := get_range_from_selection_start_to_dot(
					position_context,
				)

				if !ok {
					return
				}

				value: SymbolProcedureValue
				value, ok = symbol.value.(SymbolProcedureValue)

				if !ok {
					continue
				}

				if len(value.arg_types) == 0 ||
				   value.arg_types[0].type == nil {
					continue
				}

				first_arg: Symbol
				first_arg, ok = resolve_type_expression(
					ast_context,
					value.arg_types[0].type,
				)

				if !ok {
					continue
				}

				pointers_to_add :=
					first_arg.pointers - selector_symbol.pointers

				references := ""
				dereferences := ""

				if pointers_to_add > 0 {
					for i in 0 ..< pointers_to_add {
						references = fmt.tprintf("%v&", references)
					}
				} else if pointers_to_add < 0 {
					for i in pointers_to_add ..< 0 {
						dereferences = fmt.tprintf("%v^", dereferences)
					}
				}

				new_text := ""

				if symbol.pkg != ast_context.document_package {
					new_text = fmt.tprintf(
						"%v.%v",
						path.base(
							get_symbol_pkg_name(ast_context, symbol),
							false,
							ast_context.allocator,
						),
						symbol.name,
					)
				} else {
					new_text = fmt.tprintf("%v", symbol.name)
				}

				if len(symbol.value.(SymbolProcedureValue).arg_types) > 1 {
					new_text = fmt.tprintf(
						"%v(%v%v%v$0)",
						new_text,
						references,
						receiver,
						dereferences,
					)
				} else {
					new_text = fmt.tprintf(
						"%v(%v%v%v)$0",
						new_text,
						references,
						receiver,
						dereferences,
					)
				}

				item := CompletionItem {
					label = symbol.name,
					kind = symbol_type_to_completion_kind(symbol.type),
					detail = concatenate_symbol_information(
						ast_context,
						symbol,
						true,
					),
					additionalTextEdits = remove_edit,
					textEdit = TextEdit {
						newText = new_text,
						range = {start = range.end, end = range.end},
					},
					insertTextFormat = .Snippet,
					InsertTextMode = .adjustIndentation,
					documentation = symbol.doc,
				}

				append(items, item)
			}
		}
	}
}
