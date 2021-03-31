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
import "core:os"


import "shared:common"
import "shared:index"

Completion_Type :: enum {
	Implicit,
	Selector,
	Switch_Type,
	Identifier,
	Comp_Lit,
	Directive,
	Package,
}

get_completion_list :: proc(document: ^Document, position: common.Position, completion_context: CompletionContext) -> (CompletionList, bool) {

	list: CompletionList;

	position_context, ok := get_document_position_context(document, position, .Completion);

	if !ok || position_context.abort_completion {
		return list, true;
	}

	if position_context.import_stmt == nil && strings.contains_any(completion_context.triggerCharacter, "/:\"") {
		return list, true;
	}

	ast_context := make_ast_context(document.ast, document.imports, document.package_name);

	get_globals(document.ast, &ast_context);

	ast_context.current_package = ast_context.document_package;
	ast_context.value_decl      = position_context.value_decl;

	if position_context.function != nil {
		get_locals(document.ast, position_context.function, &ast_context, &position_context);
	}

	completion_type: Completion_Type = .Identifier;

	if position_context.comp_lit != nil && is_lhs_comp_lit(&position_context) {
		completion_type = .Comp_Lit;
	}

	if position_context.selector != nil {
		completion_type = .Selector;
	}

	if position_context.tag != nil {
		completion_type = .Directive;
	}

	if position_context.implicit {
		completion_type = .Implicit;
	}

	if position_context.import_stmt != nil {
		completion_type = .Package;
	}

	if position_context.switch_type_stmt != nil && position_context.case_clause != nil {

		if assign, ok := position_context.switch_type_stmt.tag.derived.(ast.Assign_Stmt); ok && assign.rhs != nil && len(assign.rhs) == 1 {

			if symbol, ok := resolve_type_expression(&ast_context, assign.rhs[0]); ok {

				if union_value, ok := symbol.value.(index.SymbolUnionValue); ok {
					completion_type = .Switch_Type;
				}
			}
		}
	}

	switch completion_type {
	case .Comp_Lit:
		get_comp_lit_completion(&ast_context, &position_context, &list);
	case .Identifier:
		get_identifier_completion(&ast_context, &position_context, &list);
	case .Implicit:
		get_implicit_completion(&ast_context, &position_context, &list);
	case .Selector:
		get_selector_completion(&ast_context, &position_context, &list);
	case .Switch_Type:
		get_type_switch_Completion(&ast_context, &position_context, &list);
	case .Directive:
		get_directive_completion(&ast_context, &position_context, &list);
	case .Package:
		get_package_completion(&ast_context, &position_context, &list);
	}

	return list, true;
}

is_lhs_comp_lit :: proc(position_context: ^DocumentPositionContext) -> bool {

	if len(position_context.comp_lit.elems) == 0 {
		return true;
	}

	for elem in position_context.comp_lit.elems {

		if position_in_node(elem, position_context.position) {

			if ident, ok := elem.derived.(ast.Ident); ok {
				return true;
			} else if field, ok := elem.derived.(ast.Field_Value); ok {

				if position_in_node(field.value, position_context.position) {
					return false;
				}
			}
		}
	}

	return true;
}

field_exists_in_comp_lit :: proc(comp_lit: ^ast.Comp_Lit, name: string) -> bool {

	for elem in comp_lit.elems {

		if field, ok := elem.derived.(ast.Field_Value); ok {

			if field.field != nil {

				if ident, ok := field.field.derived.(ast.Ident); ok {

					if ident.name == name {
						return true;
					}
				}
			}
		}
	}

	return false;
}

get_attribute_completion :: proc(ast_context: ^AstContext, postition_context: ^DocumentPositionContext, list: ^CompletionList) {
}

get_directive_completion :: proc(ast_context: ^AstContext, postition_context: ^DocumentPositionContext, list: ^CompletionList) {

	list.isIncomplete = false;

	items := make([dynamic]CompletionItem, context.temp_allocator);

	/*
		Right now just return all the possible completions, but later on I should give the context specific ones
	*/

	directive_list := []string {
		"file",
		"line",
		"packed",
		"raw_union",
		"align",
		"no_nil",
		"complete",
		"no_alias",
		"caller_location",
		"require_results",
		"type",
		"bounds_check",
		"no_bounds_check",
		"assert",
		"defined",
		"procedure",
		"load",
		"partial",
	};

	for elem in directive_list {

		item := CompletionItem {
			detail = elem,
			label = elem,
			kind = .Constant,
		};

		append(&items, item);
	}

	list.items = items[:];
}

get_comp_lit_completion :: proc(ast_context: ^AstContext, position_context: ^DocumentPositionContext, list: ^CompletionList) {

	items := make([dynamic]CompletionItem, context.temp_allocator);

	if position_context.parent_comp_lit.type == nil {
		return;
	}

	if symbol, ok := resolve_type_expression(ast_context, position_context.parent_comp_lit.type); ok {

		if comp_symbol, ok := resolve_type_comp_literal(ast_context, position_context, symbol, position_context.parent_comp_lit); ok {

			#partial switch v in comp_symbol.value {
			case index.SymbolStructValue:
				for name, i in v.names {
					//ERROR no completion on name and hover
					if resolved, ok := resolve_type_expression(ast_context, v.types[i]); ok {

						if field_exists_in_comp_lit(position_context.comp_lit, name) {
							continue;
						}

						resolved.signature = index.node_to_string(v.types[i]);
						resolved.pkg       = comp_symbol.name;
						resolved.name      = name;
						resolved.type      = .Field;

						item := CompletionItem {
							label = resolved.name,
							kind = cast(CompletionItemKind)resolved.type,
							detail = concatenate_symbols_information(ast_context, resolved, true),
							documentation = resolved.doc,
						};

						append(&items, item);
					}
				}
			}
		}
	}

	list.items = items[:];
}

get_selector_completion :: proc(ast_context: ^AstContext, position_context: ^DocumentPositionContext, list: ^CompletionList) {

	items := make([dynamic]CompletionItem, context.temp_allocator);

	ast_context.current_package = ast_context.document_package;

	symbols := make([dynamic]index.Symbol, context.temp_allocator);

	selector: index.Symbol;
	ok:       bool;

	ast_context.use_locals  = true;
	ast_context.use_globals = true;

	selector, ok = resolve_type_expression(ast_context, position_context.selector);

	if !ok {
		return;
	}

	if ident, ok := position_context.selector.derived.(ast.Ident); ok {

		is_variable := resolve_ident_is_variable(ast_context, ident);
		is_package  := resolve_ident_is_package(ast_context, ident);

		if (!is_variable && !is_package && selector.type != .Enum && ident.name != "") || (is_variable && selector.type == .Enum) {
			return;
		}

	}

	if selector.pkg != "" {
		ast_context.current_package = selector.pkg;
	} else {
		ast_context.current_package = ast_context.document_package;
	}

	field: string;

	if position_context.field != nil {

		switch v in position_context.field.derived {
		case ast.Ident:
			field = v.name;
		}
	}

	if s, ok := selector.value.(index.SymbolProcedureValue); ok {
		if len(s.return_types) == 1 {
			if selector, ok = resolve_type_expression(ast_context, s.return_types[0].type); !ok {
				return;
			}
		}
	}

	#partial switch v in selector.value {
	case index.SymbolUnionValue:
		list.isIncomplete = false;

		for name, i in v.names {

			if symbol, ok := resolve_type_expression(ast_context, v.types[i]); ok {

				if symbol.pkg == ast_context.document_package {
					symbol.name = fmt.aprintf("(%v)", name);
				} else {
					symbol.name = fmt.aprintf("(%v.%v)", path.base(symbol.pkg, false, context.temp_allocator), name);
				}

				symbol.pkg  = selector.name;
				symbol.type = .EnumMember;
				append(&symbols, symbol);
			}
		}

	case index.SymbolEnumValue:
		list.isIncomplete = false;

		for name in v.names {
			symbol: index.Symbol;
			symbol.name = name;
			symbol.pkg  = selector.name;
			symbol.type = .EnumMember;
			append(&symbols, symbol);
		}

	case index.SymbolStructValue:
		list.isIncomplete = false;

		for name, i in v.names {

			if selector.pkg != "" {
				ast_context.current_package = selector.pkg;
			} else {
				ast_context.current_package = ast_context.document_package;
			}

			if symbol, ok := resolve_type_expression(ast_context, v.types[i]); ok {

				if expr, ok := position_context.selector.derived.(ast.Selector_Expr); ok {

					if expr.op.text == "->" && symbol.type != .Function {
						continue;
					}
				}

				if position_context.arrow && symbol.type != .Function {
					continue;
				}

				symbol.name      = name;
				symbol.type      = .Field;
				symbol.pkg       = selector.name;
				symbol.signature = index.node_to_string(v.types[i]);
				append(&symbols, symbol);
			} else {
				//just give some generic symbol with name.
				symbol: index.Symbol;
				symbol.name = name;
				symbol.type = .Field;
				append(&symbols, symbol);
			}
		}

	case index.SymbolPackageValue:

		list.isIncomplete = true;

		if searched, ok := index.fuzzy_search(field, {selector.pkg}); ok {

			for search in searched {
				append(&symbols, search.symbol);
			}
		} else {
			log.errorf("Failed to fuzzy search, field: %v, package: %v", field, selector.pkg);
			return;
		}
	}

	for symbol, i in symbols {

		item := CompletionItem {
			label = symbol.name,
			kind = cast(CompletionItemKind)symbol.type,
			detail = concatenate_symbols_information(ast_context, symbol, true),
			documentation = symbol.doc,
		};

		append(&items, item);
	}

	list.items = items[:];
}

unwrap_enum :: proc(ast_context: ^AstContext, node: ^ast.Expr) -> (index.SymbolEnumValue, bool) {

	if node == nil {
		return {}, false;
	}

	if enum_symbol, ok := resolve_type_expression(ast_context, node); ok {

		if enum_value, ok := enum_symbol.value.(index.SymbolEnumValue); ok {
			return enum_value, true;
		}
	}

	return {}, false;
}

unwrap_union :: proc(ast_context: ^AstContext, node: ^ast.Expr) -> (index.SymbolUnionValue, bool) {

	if union_symbol, ok := resolve_type_expression(ast_context, node); ok {

		if union_value, ok := union_symbol.value.(index.SymbolUnionValue); ok {
			return union_value, true;
		}
	}

	return {}, false;
}

unwrap_bitset :: proc(ast_context: ^AstContext, bitset_symbol: index.Symbol) -> (index.SymbolEnumValue, bool) {

	if bitset_value, ok := bitset_symbol.value.(index.SymbolBitSetValue); ok {
		if enum_symbol, ok := resolve_type_expression(ast_context, bitset_value.expr); ok {
			if enum_value, ok := enum_symbol.value.(index.SymbolEnumValue); ok {
				return enum_value, true;
			}
		}
	}

	return {}, false;
}

get_implicit_completion :: proc(ast_context: ^AstContext, position_context: ^DocumentPositionContext, list: ^CompletionList) {

	items := make([dynamic]CompletionItem, context.temp_allocator);

	list.isIncomplete = false;

	selector: index.Symbol;

	ast_context.use_locals  = true;
	ast_context.use_globals = true;

	if selector.pkg != "" {
		ast_context.current_package = selector.pkg;
	} else {
		ast_context.current_package = ast_context.document_package;
	}

	//enum switch infer
	if position_context.switch_stmt != nil && position_context.case_clause != nil && position_context.switch_stmt.cond != nil {

		used_enums := make(map[string]bool, 5, context.temp_allocator);

		if block, ok := position_context.switch_stmt.body.derived.(ast.Block_Stmt); ok {

			for stmt in block.stmts {

				if case_clause, ok := stmt.derived.(ast.Case_Clause); ok {

					for name in case_clause.list {

						if implicit, ok := name.derived.(ast.Implicit_Selector_Expr); ok {
							used_enums[implicit.field.name] = true;
						}
					}
				}
			}
		}

		if enum_value, ok := unwrap_enum(ast_context, position_context.switch_stmt.cond); ok {

			for name in enum_value.names {

				if name in used_enums {
					continue;
				}

				item := CompletionItem {
					label = name,
					kind = .EnumMember,
					detail = name,
				};

				append(&items, item);
			}

			list.items = items[:];
			return;
		}
	}

	if position_context.comp_lit != nil && position_context.assign != nil && position_context.assign.lhs != nil && len(position_context.assign.lhs) == 1 && is_bitset_assignment_operator(position_context.assign.op.text) {
		//bitsets
		if symbol, ok := resolve_type_expression(ast_context, position_context.assign.lhs[0]); ok {

			if value, ok := unwrap_bitset(ast_context, symbol); ok {

				for name in value.names {

					item := CompletionItem {
						label = name,
						kind = .EnumMember,
						detail = name,
					};

					append(&items, item);
				}

				list.items = items[:];
				return;
			}
		}
	}

	if position_context.comp_lit != nil && position_context.parent_binary != nil && is_bitset_binary_operator(position_context.binary.op.text) {
		//bitsets
		if symbol, ok := resolve_first_symbol_from_binary_expression(ast_context, position_context.parent_binary); ok {

			if value, ok := unwrap_bitset(ast_context, symbol); ok {

				for name in value.names {

					item := CompletionItem {
						label = name,
						kind = .EnumMember,
						detail = name,
					};

					append(&items, item);
				}

				list.items = items[:];
				return;
			}
		}
	}

	if position_context.comp_lit != nil {

		if position_context.parent_comp_lit.type == nil {
			return;
		}

		field_name: string;

		for elem in position_context.comp_lit.elems {

			if position_in_node(elem, position_context.position) {

				if field, ok := elem.derived.(ast.Field_Value); ok {
					field_name = field.field.derived.(ast.Ident).name;
				}
			}
		}

		if field_name == "" {
			return;
		}

		if symbol, ok := resolve_type_expression(ast_context, position_context.parent_comp_lit.type); ok {

			if comp_symbol, ok := resolve_type_comp_literal(ast_context, position_context, symbol, position_context.parent_comp_lit); ok {

				if s, ok := comp_symbol.value.(index.SymbolStructValue); ok {

					for name, i in s.names {

						if name != field_name {
							continue;
						}

						if enum_value, ok := unwrap_enum(ast_context, s.types[i]); ok {
							for enum_name in enum_value.names {
								item := CompletionItem {
									label = enum_name,
									kind = .EnumMember,
									detail = enum_name,
								};

								append(&items, item);
							}

							list.items = items[:];
							return;
						}
					}
				}
			}
		}
	}

	if position_context.binary != nil && (position_context.binary.op.text == "==" || position_context.binary.op.text == "!=") {

		context_node: ^ast.Expr;
		enum_node:    ^ast.Expr;

		if position_in_node(position_context.binary.right, position_context.position) {
			context_node = position_context.binary.right;
			enum_node    = position_context.binary.left;
		} else if position_in_node(position_context.binary.left, position_context.position) {
			context_node = position_context.binary.left;
			enum_node    = position_context.binary.right;
		}

		if context_node != nil && enum_node != nil {

			if enum_value, ok := unwrap_enum(ast_context, enum_node); ok {

				for name in enum_value.names {

					item := CompletionItem {
						label = name,
						kind = .EnumMember,
						detail = name,
					};

					append(&items, item);
				}

				list.items = items[:];
				return;
			}
		}
	}

	if position_context.assign != nil && position_context.assign.rhs != nil && position_context.assign.lhs != nil {

		rhs_index: int;

		for elem in position_context.assign.rhs {

			if position_in_node(elem, position_context.position) {
				break;
			} else {

				//procedures are the only types that can return more than one value
				if symbol, ok := resolve_type_expression(ast_context, elem); ok {

					if procedure, ok := symbol.value.(index.SymbolProcedureValue); ok {

						if procedure.return_types == nil {
							return;
						}

						rhs_index += len(procedure.return_types);
					} else {
						rhs_index += 1;
					}
				}
			}
		}

		if len(position_context.assign.lhs) > rhs_index {

			if enum_value, ok := unwrap_enum(ast_context, position_context.assign.lhs[rhs_index]); ok {

				for name in enum_value.names {

					item := CompletionItem {
						label = name,
						kind = .EnumMember,
						detail = name,
					};

					append(&items, item);
				}

				list.items = items[:];
				return;
			}
		}
	}

	if position_context.returns != nil && position_context.function != nil {

		return_index: int;

		if position_context.returns.results == nil {
			return;
		}

		for result, i in position_context.returns.results {

			if position_in_node(result, position_context.position) {
				return_index = i;
				break;
			}
		}

		if position_context.function.type == nil {
			return;
		}

		if position_context.function.type.results == nil {
			return;
		}

		if len(position_context.function.type.results.list) > return_index {

			if enum_value, ok := unwrap_enum(ast_context, position_context.function.type.results.list[return_index].type); ok {

				for name in enum_value.names {

					item := CompletionItem {
						label = name,
						kind = .EnumMember,
						detail = name,
					};

					append(&items, item);
				}

				list.items = items[:];
				return;
			}
		}
	}

	if position_context.call != nil {

		if call, ok := position_context.call.derived.(ast.Call_Expr); ok {

			parameter_index, parameter_ok := find_position_in_call_param(ast_context, call);

			if symbol, ok := resolve_type_expression(ast_context, call.expr); ok && parameter_ok {

				if proc_value, ok := symbol.value.(index.SymbolProcedureValue); ok {

					log.error("procedure symbol");

					if enum_value, ok := unwrap_enum(ast_context, proc_value.arg_types[parameter_index].type); ok {

						log.error("unwrap");

						for name in enum_value.names {
							item := CompletionItem {
								label = name,
								kind = .EnumMember,
								detail = name,
							};

							append(&items, item);
						}

						list.items = items[:];
						return;
					}
				}
			}
		}
	}
}

get_identifier_completion :: proc(ast_context: ^AstContext, position_context: ^DocumentPositionContext, list: ^CompletionList) {

	items := make([dynamic]CompletionItem, context.temp_allocator);

	list.isIncomplete = true;

	CombinedResult :: struct {
		score:    f32,
		symbol:   index.Symbol,
		variable: ^ast.Ident,
	};

	combined_sort_interface :: proc(s: ^[dynamic]CombinedResult) -> sort.Interface {
		return sort.Interface {
			collection = rawptr(s),
			len = proc(it: sort.Interface) -> int {
				s := (^[dynamic]CombinedResult)(it.collection);
				return len(s^);
			},
			less = proc(it: sort.Interface, i, j: int) -> bool {
				s := (^[dynamic]CombinedResult)(it.collection);
				return s[i].score > s[j].score;
			},
			swap = proc(it: sort.Interface, i, j: int) {
				s := (^[dynamic]CombinedResult)(it.collection);
				s[i], s[j] = s[j], s[i];
			},
		};
	};

	combined := make([dynamic]CombinedResult);

	lookup := "";

	if position_context.identifier != nil {
		if ident, ok := position_context.identifier.derived.(ast.Ident); ok {
			lookup = ident.name;
		}
	}

	pkgs := make([dynamic]string, context.temp_allocator);

	usings := get_using_packages(ast_context);

	for u in usings {
		append(&pkgs, u);
	}

	append(&pkgs, ast_context.document_package);

	if results, ok := index.fuzzy_search(lookup, pkgs[:]); ok {

		for r in results {
			append(&combined, CombinedResult {score = r.score, symbol = r.symbol});
		}
	}

	matcher := common.make_fuzzy_matcher(lookup);

	global: for k, v in ast_context.globals {

		if position_context.global_lhs_stmt {
			break;
		}

		//combined is sorted and should do binary search instead.
		for result in combined {
			if result.symbol.name == k {
				continue global;
			}
		}

		ast_context.use_locals      = true;
		ast_context.use_globals     = true;
		ast_context.current_package = ast_context.document_package;

		ident := index.new_type(ast.Ident, v.pos, v.end, context.temp_allocator);
		ident.name = k;

		if symbol, ok := resolve_type_identifier(ast_context, ident^); ok {
			symbol.name      = ident.name;
			symbol.signature = get_signature(ast_context, ident^, symbol);

			if score, ok := common.fuzzy_match(matcher, symbol.name); ok {
				append(&combined, CombinedResult {score = score * 1.1, symbol = symbol, variable = ident});
			}
		}
	}

	for k, v in ast_context.locals {

		if position_context.global_lhs_stmt {
			break;
		}

		ast_context.use_locals      = true;
		ast_context.use_globals     = true;
		ast_context.current_package = ast_context.document_package;

		ident := index.new_type(ast.Ident, {offset = position_context.position}, {offset = position_context.position}, context.temp_allocator);
		ident.name = k;

		if symbol, ok := resolve_type_identifier(ast_context, ident^); ok {
			symbol.name      = ident.name;
			symbol.signature = get_signature(ast_context, ident^, symbol);

			if score, ok := common.fuzzy_match(matcher, symbol.name); ok {
				append(&combined, CombinedResult {score = score * 1.1, symbol = symbol, variable = ident});
			}
		}
	}

	for pkg in ast_context.imports {

		if position_context.global_lhs_stmt {
			break;
		}

		symbol := index.Symbol {
			name = pkg.base,
			type = .Package,
		};

		if score, ok := common.fuzzy_match(matcher, symbol.name); ok {
			append(&combined, CombinedResult {score = score * 1.1, symbol = symbol});
		}
	}

	for keyword, _ in common.keyword_map {

		symbol := index.Symbol {
			name = keyword,
			type = .Keyword,
		};

		if score, ok := common.fuzzy_match(matcher, keyword); ok {
			append(&combined, CombinedResult {score = score * 1.1, symbol = symbol});
		}
	}

	language_keywords: []string = {
		"align_of","case","defer","enum","import","proc","transmute","when",
		"auto_cast","cast","distinct","fallthrough","in","notin","return","type_of",
		"bit_field","const","do","for","inline","offset_of","size_of","typeid",
		"bit_set","context","dynamic","foreign","opaque","struct","union",
		"break","continue","else","if","map","package","switch","using",
	};

	for keyword, _ in language_keywords {

		symbol := index.Symbol {
			name = keyword,
			type = .Keyword,
		};

		if score, ok := common.fuzzy_match(matcher, keyword); ok {
			append(&combined, CombinedResult {score = score * 1.1, symbol = symbol});
		}
	}

	sort.sort(combined_sort_interface(&combined));

	//hard code for now
	top_results := combined[0:(min(20, len(combined)))];

	for result in top_results {

		item := CompletionItem {
			label = result.symbol.name,
			detail = concatenate_symbols_information(ast_context, result.symbol, true),
		};

		if result.variable != nil {
			if ok := resolve_ident_is_variable(ast_context, result.variable^); ok {
				item.kind = .Variable;
			} else {
				item.kind = cast(CompletionItemKind)result.symbol.type;
			}
		} else {
			item.kind = cast(CompletionItemKind)result.symbol.type;
		}

		append(&items, item);
	}

	list.items = items[:];
}

get_package_completion :: proc(ast_context: ^AstContext, position_context: ^DocumentPositionContext, list: ^CompletionList) {

	items := make([dynamic]CompletionItem, context.temp_allocator);

	list.isIncomplete = false;

	fullpath_length := len(position_context.import_stmt.fullpath);

	if fullpath_length <= 1 {
		return;
	}

	without_quotes := position_context.import_stmt.fullpath[1:fullpath_length-1];
	absolute_path := without_quotes;
	colon_index := strings.index(without_quotes, ":");

	if colon_index >= 0 {
		c := without_quotes[0:colon_index];

		if colon_index+1 < len(without_quotes) {
			absolute_path = filepath.join(elems = {common.config.collections[c], filepath.dir(without_quotes[colon_index+1:], context.temp_allocator)}, allocator = context.temp_allocator);
		} else {
			absolute_path = common.config.collections[c];
		}
	} else {
		import_file_dir := filepath.dir(position_context.import_stmt.pos.file, context.temp_allocator);
		import_dir := filepath.dir(without_quotes, context.temp_allocator);
		absolute_path = filepath.join(elems = {import_file_dir, import_dir}, allocator = context.temp_allocator);
	}

	if !strings.contains(position_context.import_stmt.fullpath, "/") && !strings.contains(position_context.import_stmt.fullpath, ":") {

		for key, _ in common.config.collections {

			item := CompletionItem {
				detail = "collection",
				label = key,
				kind = .Module,
			};

			append(&items, item);
		}

	}

	for pkg in search_for_packages(absolute_path) {

		item := CompletionItem {
			detail = pkg,
			label = filepath.base(pkg),
			kind = .Folder,
		};

		if item.label[0] == '.' {
			continue;
		}

		append(&items, item);
	}

	list.items = items[:];
}

search_for_packages :: proc(fullpath: string) -> [] string {

	packages := make([dynamic]string, context.temp_allocator);

	fh, err := os.open(fullpath);

	if err != 0 {
		return {};
	}

	if files, err := os.read_dir(fh, 0, context.temp_allocator); err == 0 {

		for file in files {
			if file.is_dir {
				append(&packages, file.fullpath);
			}
		}

	}

	return packages[:];
}

get_type_switch_Completion :: proc(ast_context: ^AstContext, position_context: ^DocumentPositionContext, list: ^CompletionList) {

	items := make([dynamic]CompletionItem, context.temp_allocator);
	list.isIncomplete = false;

	used_unions := make(map[string]bool, 5, context.temp_allocator);

	if block, ok := position_context.switch_type_stmt.body.derived.(ast.Block_Stmt); ok {

		for stmt in block.stmts {

			if case_clause, ok := stmt.derived.(ast.Case_Clause); ok {

				for name in case_clause.list {

					if ident, ok := name.derived.(ast.Ident); ok {
						used_unions[ident.name] = true;
					}
				}
			}
		}
	}

	if assign, ok := position_context.switch_type_stmt.tag.derived.(ast.Assign_Stmt); ok && assign.rhs != nil && len(assign.rhs) == 1 {

		if union_value, ok := unwrap_union(ast_context, assign.rhs[0]); ok {

			for name, i in union_value.names {

				if name in used_unions {
					continue;
				}

				if symbol, ok := resolve_type_expression(ast_context, union_value.types[i]); ok {

					item := CompletionItem {
						kind = .EnumMember,
					};

					if symbol.pkg == ast_context.document_package {
						item.label  = fmt.aprintf("%v", name);
						item.detail = item.label;
					} else {
						item.label  = fmt.aprintf("%v.%v", path.base(symbol.pkg, false, context.temp_allocator), name);
						item.detail = item.label;
					}

					append(&items, item);
				}
			}
		}
	}

	list.items = items[:];
}

bitset_operators: map[string]bool = {
	"|" = true,
	"&" = true,
	"~" = true,
	"<" = true,
	">" = true,
	"==" = true,
};

bitset_assignment_operators: map[string]bool = {
	"|=" = true,
	"&=" = true,
	"~=" = true,
	"<=" = true,
	">=" = true,
	"=" = true,
};

is_bitset_binary_operator :: proc(op: string) -> bool {
	return op in bitset_operators;
}

is_bitset_assignment_operator :: proc(op: string) -> bool {
	return op in bitset_assignment_operators;
}
