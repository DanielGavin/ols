#+private file

package server

import "core:fmt"
import "core:odin/ast"
import "core:odin/tokenizer"
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

SwitchBlockInfo :: struct {
	names:              []string,
	existing_cases:     map[string]struct{},
	switch_indentation: string,
	is_enum:            bool,
	pos:                tokenizer.Pos,
}

get_switch_cases_info :: proc(
	ast_context: ^AstContext,
	position_context: ^DocumentPositionContext,
) -> (
	SwitchBlockInfo,
	bool,
) {
	if position_context.switch_stmt == nil && position_context.switch_type_stmt == nil {
		return {}, false
	}

	if position_context.switch_stmt != nil && position_context.switch_stmt.cond == nil {
		return {}, false
	}

	switch_block: ^ast.Block_Stmt
	found_switch_block: bool
	is_enum: bool
	pos: tokenizer.Pos
	if position_context.switch_stmt != nil {
		switch_block, found_switch_block = position_context.switch_stmt.body.derived.(^ast.Block_Stmt)
		is_enum = true
		pos = position_context.switch_stmt.pos
	}

	if !found_switch_block && position_context.switch_type_stmt != nil {
		switch_block, found_switch_block = position_context.switch_type_stmt.body.derived.(^ast.Block_Stmt)
		pos = position_context.switch_type_stmt.pos
	}

	if !found_switch_block {
		return {}, false
	}
	switch_indentation := get_line_indentation(ast_context.file.src, switch_block.pos.offset)
	existing_cases := make(map[string]struct{}, context.temp_allocator)


	for stmt in switch_block.stmts {
		if case_clause, ok := stmt.derived.(^ast.Case_Clause); ok {
			for clause in case_clause.list {
				if is_enum {
					if name, ok := get_used_switch_name(clause); ok && name != "" {
						existing_cases[name] = {}
					}
				} else {
					reset_ast_context(ast_context)
					if symbol, ok := resolve_type_expression(ast_context, clause); ok {
						name := get_qualified_union_case_name(&symbol, ast_context, position_context)
						//TODO: this is wrong for anonymous enums and structs, where the name field is "enum" or "struct" respectively but we want to use the full signature
						//we also can't use the signature all the time because type aliases need to use specifically the alias name here and not the signature
						if name == "" {
							name = get_signature(ast_context, symbol)
						}
						if name != "" {
							existing_cases[name] = {}
						}
					}
				}
			}
			pos = case_clause.stmt_base.end
		}
	}
	if is_enum {
		enum_value, was_super_enum, unwrap_ok := unwrap_enum(ast_context, position_context.switch_stmt.cond)
		if !unwrap_ok {
			return {}, false
		}
		return SwitchBlockInfo {
				names = enum_value.names,
				existing_cases = existing_cases,
				switch_indentation = switch_indentation,
				is_enum = !was_super_enum,
				pos = pos,
			},
			true
	}

	st := position_context.switch_type_stmt
	if st == nil {
		return {}, false
	}
	reset_ast_context(ast_context)
	union_value, unwrap_ok := unwrap_union(ast_context, st.tag.derived.(^ast.Assign_Stmt).rhs[0])
	if !unwrap_ok {
		return {}, false
	}
	all_case_names := make([]string, len(union_value.types), context.temp_allocator)
	for t, i in union_value.types {
		reset_ast_context(ast_context)
		if symbol, ok := resolve_type_expression(ast_context, t); ok {
			case_name := get_qualified_union_case_name(&symbol, ast_context, position_context)
			//TODO: this is wrong for anonymous enums and structs, where the name field is "enum" or "struct" respectively but we want to use the full signature
			//we also can't use the signature all the time because type aliases need to use specifically the alias name here and not the signature
			if case_name == "" {
				case_name = get_signature(ast_context, symbol)
			}
			all_case_names[i] = case_name
		} else {
			all_case_names[i] = "invalid type expression"
		}
	}
	return SwitchBlockInfo {
			names = all_case_names,
			existing_cases = existing_cases,
			switch_indentation = switch_indentation,
			is_enum = false,
			pos = pos,
		},
		true
}

create_populate_switch_cases_edit :: proc(
	position_context: ^DocumentPositionContext,
	info: SwitchBlockInfo,
) -> (
	TextEdit,
	bool,
) {
	//we need to be either in a switch stmt or a switch type stmt
	if position_context.switch_stmt == nil && position_context.switch_type_stmt == nil {
		return {}, false
	}

	pos := info.pos
	pos.line += 1
	pos.column = 1

	position := common.token_pos_to_position(pos, position_context.file.src)

	range := common.Range {
		start = position,
		end   = position,
	}

	replacement_builder := strings.builder_make()
	dot := info.is_enum ? "." : ""
	b := &replacement_builder
	for name in info.names {
		if name in info.existing_cases {continue}
		fmt.sbprintln(b, info.switch_indentation, "case ", dot, name, ":", sep = "")
	}
	return TextEdit{range = range, newText = strings.to_string(replacement_builder)}, true
}

@(private = "package")
add_populate_switch_cases_action :: proc(
	ast_context: ^AstContext,
	position_context: ^DocumentPositionContext,
	uri: string,
	actions: ^[dynamic]CodeAction,
) {
	info, ok := get_switch_cases_info(ast_context, position_context)
	if !ok {return}

	if len(info.existing_cases) == len(info.names) {return} 	//action not needed
	edit, edit_ok := create_populate_switch_cases_edit(position_context, info)
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
