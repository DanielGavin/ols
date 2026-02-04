#+private file

package server

import "core:fmt"
import "core:odin/ast"
import "core:strings"

import "src:common"


// Get the offset of the start of the line containing the given offset
get_line_start_offset :: proc(src: string, offset: int) -> int {
	line_start := offset
	for line_start > 0 && src[line_start - 1] != '\n' {
		line_start -= 1
	}
	return line_start
}
get_block_original_text :: proc(block: []^ast.Stmt, document_text: string) -> string {
	if len(block) == 0 {
		return ""
	}
	start := get_line_start_offset(document_text, block[0].pos.offset)
	end := block[max(0, len(block) - 1)].end.offset
	return string(document_text[start:end])
}

SwitchCaseInfo :: struct {
	name:             string,
	body_indentation: string,
	body:             string,
}
get_switch_cases_info :: proc(
	document: ^Document,
	ast_context: ^AstContext,
	position_context: ^DocumentPositionContext,
) -> (
	existing_cases: []SwitchCaseInfo,
	all_case_names: []string,
	switch_indentation: string,
	is_enum: bool,
	ok: bool,
) {
	if (position_context.switch_stmt == nil && position_context.switch_type_stmt == nil) ||
	   (position_context.switch_stmt != nil && position_context.switch_stmt.cond == nil) {
		return nil, nil, "", false, false
	}
	switch_block: ^ast.Block_Stmt
	found_switch_block: bool
	if position_context.switch_stmt != nil {
		switch_block, found_switch_block = position_context.switch_stmt.body.derived.(^ast.Block_Stmt)
		is_enum = true
	}
	if !found_switch_block && position_context.switch_type_stmt != nil {
		switch_block, found_switch_block = position_context.switch_type_stmt.body.derived.(^ast.Block_Stmt)
	}
	if !found_switch_block {
		return nil, nil, "", false, false
	}
	switch_indentation = get_line_indentation(string(document.text), switch_block.pos.offset)
	existing_cases_in_order := make([dynamic]SwitchCaseInfo, context.temp_allocator)
	for stmt in switch_block.stmts {
		if case_clause, ok := stmt.derived.(^ast.Case_Clause); ok {
			case_name := ""
			for clause in case_clause.list {
				if is_enum {
					if name, ok := get_used_switch_name(clause); ok {
						case_name = name
						break
					}
				} else {
					reset_ast_context(ast_context)
					if symbol, ok := resolve_type_expression(ast_context, clause); ok {
						case_name = get_qualified_union_case_name(&symbol, ast_context, position_context)
						//TODO: this is wrong for anonymous enums and structs, where the name field is "enum" or "struct" respectively but we want to use the full signature
						//we also can't use the signature all the time because type aliases need to use specifically the alias name here and not the signature
						if case_name == "" {
							case_name = get_signature(ast_context, symbol)
						}
						break
					}
				}
			}
			if case_name != "" {
				case_info := SwitchCaseInfo {
					name = case_name,
					body = get_block_original_text(case_clause.body, string(document.text)),
				}
				append(&existing_cases_in_order, case_info)
			}
		}
	}
	if is_enum {
		enum_value, was_super_enum, unwrap_ok := unwrap_enum(ast_context, position_context.switch_stmt.cond)
		if !unwrap_ok {
			return nil, nil, "", true, false
		}
		return existing_cases_in_order[:], enum_value.names, switch_indentation, !was_super_enum, true
	} else {
		st := position_context.switch_type_stmt
		if st == nil {
			return nil, nil, "", false, false
		}
		reset_ast_context(ast_context)
		union_value, unwrap_ok := unwrap_union(ast_context, st.tag.derived.(^ast.Assign_Stmt).rhs[0])
		if !unwrap_ok {
			return nil, nil, "", false, false
		}
		case_names := make([]string, len(union_value.types), context.temp_allocator)
		for t, i in union_value.types {
			reset_ast_context(ast_context)
			if symbol, ok := resolve_type_expression(ast_context, t); ok {
				case_name := get_qualified_union_case_name(&symbol, ast_context, position_context)
				//TODO: this is wrong for anonymous enums and structs, where the name field is "enum" or "struct" respectively but we want to use the full signature
				//we also can't use the signature all the time because type aliases need to use specifically the alias name here and not the signature
				if case_name == "" {
					case_name = get_signature(ast_context, symbol)
				}
				case_names[i] = case_name
			} else {
				case_names[i] = "invalid type expression"
			}
		}
		return existing_cases_in_order[:], case_names, switch_indentation, false, true
	}
}

create_populate_switch_cases_edit :: proc(
	position_context: ^DocumentPositionContext,
	existing_cases: []SwitchCaseInfo,
	switch_indentation: string,
	all_case_names: []string,
	is_enum: bool,
) -> (
	TextEdit,
	bool,
) {
	//we need to be either in a switch stmt or a switch type stmt
	if position_context.switch_stmt == nil && position_context.switch_type_stmt == nil {
		return {}, false
	}
	//entirety of the switch block
	range: common.Range
	if is_enum {
		range = common.get_token_range(position_context.switch_stmt.body.stmt_base, position_context.file.src)
	} else {
		range = common.get_token_range(position_context.switch_type_stmt.body.stmt_base, position_context.file.src)
	}
	replacement_builder := strings.builder_make()
	dot := is_enum ? "." : ""
	b := &replacement_builder
	fmt.sbprintln(b, "{")
	existing_case_names := map[string]struct{}{}
	for case_info in existing_cases {
		existing_case_names[case_info.name] = {}
		fmt.sbprintln(b, switch_indentation, "case ", dot, case_info.name, ":", sep = "")
		case_body := case_info.body
		if case_body != "" {
			fmt.sbprintln(b, case_info.body)
		}
	}
	for name in all_case_names {
		if name in existing_case_names {continue} 	//covered by prev loop
		fmt.sbprintln(b, switch_indentation, "case ", dot, name, ":", sep = "")
	}
	fmt.sbprint(b, switch_indentation, "}", sep = "")
	return TextEdit{range = range, newText = strings.to_string(replacement_builder)}, true
}
@(private = "package")
add_populate_switch_cases_action :: proc(
	document: ^Document,
	ast_context: ^AstContext,
	position_context: ^DocumentPositionContext,
	uri: string,
	actions: ^[dynamic]CodeAction,
) {
	existing_cases, all_case_names, switch_indentation, is_enum, ok := get_switch_cases_info(
		document,
		ast_context,
		position_context,
	)
	if !ok {return}
	all_cases_covered := true
	{
		existing_case_names := map[string]struct{}{}
		for case_info in existing_cases {
			existing_case_names[case_info.name] = {}
		}
		for name in all_case_names {
			if name not_in existing_case_names {
				all_cases_covered = false
			}
		}
	}
	if all_cases_covered {return} 	//action not needed
	edit, edit_ok := create_populate_switch_cases_edit(
		position_context,
		existing_cases,
		switch_indentation,
		all_case_names,
		is_enum,
	)
	if !edit_ok {return}
	textEdits := make([dynamic]TextEdit, context.temp_allocator)
	append(&textEdits, edit)

	workspaceEdit: WorkspaceEdit
	workspaceEdit.changes = make(map[string][]TextEdit, 0, context.temp_allocator)
	workspaceEdit.changes[uri] = textEdits[:]
	append(
		actions,
		CodeAction {
			kind = "refactor.rewrite",
			isPreferred = true,
			title = "populate remaining switch cases",
			edit = workspaceEdit,
		},
	)
}
