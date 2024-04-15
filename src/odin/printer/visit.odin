package odin_printer

import "core:fmt"
import "core:odin/ast"
import "core:odin/parser"
import "core:odin/tokenizer"
import "core:slice"
import "core:strconv"
import "core:strings"

@(private)
comment_before_position :: proc(p: ^Printer, pos: tokenizer.Pos) -> bool {
	if len(p.comments) <= p.latest_comment_index {
		return false
	}

	comment := p.comments[p.latest_comment_index]

	return comment.pos.offset < pos.offset
}

@(private)
comment_before_or_in_line :: proc(p: ^Printer, line: int) -> bool {
	if len(p.comments) <= p.latest_comment_index {
		return false
	}

	comment := p.comments[p.latest_comment_index]

	return comment.pos.line < line
}

@(private)
next_comment_group :: proc(p: ^Printer) {
	p.latest_comment_index += 1
}

@(private)
text_token :: proc(p: ^Printer, token: tokenizer.Token) -> ^Document {
	document, _ := visit_comments(p, token.pos)
	return cons(document, text(token.text))
}

@(private)
text_position :: proc(
	p: ^Printer,
	value: string,
	pos: tokenizer.Pos,
) -> ^Document {
	document, _ := visit_comments(p, pos)
	return cons(document, text(value))
}

@(private)
newline_position :: proc(
	p: ^Printer,
	amount: int,
	pos: tokenizer.Pos,
) -> ^Document {
	document, _ := visit_comments(p, pos)
	return cons(document, newline(amount))
}

@(private)
set_source_position :: proc(p: ^Printer, pos: tokenizer.Pos) {
	p.source_position = pos
}

@(private)
move_line :: proc(p: ^Printer, pos: tokenizer.Pos) -> ^Document {
	l, _ := move_line_limit(p, pos, p.config.newline_limit + 1)
	return l
}

@(private)
move_line_limit :: proc(
	p: ^Printer,
	pos: tokenizer.Pos,
	limit: int,
) -> (
	^Document,
	bool,
) {
	lines := pos.line - p.source_position.line

	if lines < 0 {
		return empty(), false
	}

	document, comments_newlined := visit_comments(p, pos)

	p.source_position = pos

	return cons(
			document,
			newline(max(min(lines - comments_newlined, limit), 0)),
		),
		lines > 0
}

@(private)
visit_comment :: proc(
	p: ^Printer,
	comment: tokenizer.Token,
) -> (
	int,
	^Document,
) {
	document := empty()
	if len(comment.text) == 0 {
		return 0, document
	}

	newlines_before_comment := comment.pos.line - p.source_position.line
	newlines_before_comment_limited := min(
		newlines_before_comment,
		p.config.newline_limit + 1,
	)

	document = cons(document, newline(newlines_before_comment_limited))

	if comment.text[:2] != "/*" {
		if info, is_disabled := p.disabled_lines[comment.pos.line];
		   is_disabled {
			p.source_position = comment.pos
			if info.start_line == comment.pos.line && info.empty {
				return info.end_line - info.start_line, cons(escape_nest(document), text(info.text))
			}
			return 1, empty()
		} else if comment.pos.line == p.source_position.line &&
		   p.source_position.column != 1 {
			p.source_position = comment.pos
			if comment_option, exist := p.comments_option[comment.pos.line];
			   exist && comment_option == .Indent {
				delete_key(&p.comments_option, comment.pos.line)
				return newlines_before_comment, cons_with_nopl(
					document,
					cons(text(p.indentation), line_suffix(comment.text)),
				)
			} else {
				return newlines_before_comment, cons_with_nopl(
					document,
					line_suffix(comment.text),
				)
			}
		} else {
			p.source_position = comment.pos
			return newlines_before_comment, cons(
				document,
				line_suffix(comment.text),
			)
		}
	} else {
		newlines := strings.count(comment.text, "\n")

		if comment.pos.line in p.disabled_lines {
			p.source_position = comment.pos
			p.source_position.line += newlines
			return 1, empty()
		} else if comment.pos.line == p.source_position.line &&
		   p.source_position.column != 1 {
			p.source_position = comment.pos
			p.source_position.line += newlines
			return newlines_before_comment + newlines, cons_with_opl(document, text(comment.text))
		} else {
			p.source_position = comment.pos
			p.source_position.line += newlines
			return newlines_before_comment + newlines, cons(document, text(comment.text))
		}

		return 0, document
	}
}

@(private)
visit_comments :: proc(p: ^Printer, pos: tokenizer.Pos) -> (^Document, int) {
	document := empty()
	lines := 0

	for comment_before_position(p, pos) {
		comment_group := p.comments[p.latest_comment_index]

		for comment in comment_group.list {
			newlined, tmp_document := visit_comment(p, comment)
			lines += newlined
			document = cons(document, tmp_document)
		}

		next_comment_group(p)
	}

	return document, lines
}

@(private)
visit_disabled :: proc(p: ^Printer, node: ^ast.Node) -> ^Document {
	if node.pos.line not_in p.disabled_lines {
		return empty()
	}

	disabled_info := p.disabled_lines[node.pos.line]

	if disabled_info.text == "" {
		return empty()
	}

	if p.disabled_until_line > node.pos.line {
		return empty()
	}

	node_pos := node.pos

	#partial switch v in node.derived {
	case ^ast.Value_Decl:
		if len(v.attributes) > 0 {
			node_pos = v.attributes[0].pos
		}
	}

	pos_one_line_before := node_pos
	pos_one_line_before.line -= 1

	move := cons(
		move_line(p, pos_one_line_before),
		escape_nest(move_line(p, node_pos)),
	)

	for comment_before_or_in_line(p, disabled_info.end_line + 1) {
		next_comment_group(p)
	}

	p.disabled_until_line = disabled_info.end_line
	p.source_position = node.end
	p.source_position.line = disabled_info.end_line

	return cons(move, text(disabled_info.text))
}

@(private)
visit_decl :: proc(
	p: ^Printer,
	decl: ^ast.Decl,
	called_in_stmt := false,
) -> ^Document {
	using ast

	if decl == nil {
		return empty()
	}

	if decl.pos.line in p.disabled_lines {
		return visit_disabled(p, decl)
	}

	defer {
		set_source_position(p, decl.end)
	}

	#partial switch v in decl.derived {
	case ^Assign_Stmt:
		return visit_stmt(p, v)
	case ^Expr_Stmt:
		document := move_line(p, decl.pos)
		return cons(document, visit_expr(p, v.expr))
	case ^When_Stmt:
		return visit_stmt(p, cast(^Stmt)decl)
	case ^Foreign_Import_Decl:
		document := empty()
		if len(v.attributes) > 0 {
			document = cons(
				document,
				visit_attributes(p, &v.attributes, v.pos),
			)
		}

		document = cons(document, move_line(p, decl.pos))
		document = cons(
			document,
			cons_with_opl(text(v.foreign_tok.text), text(v.import_tok.text)),
		)

		if v.name != nil {
			document = cons_with_opl(
				document,
				text_position(p, v.name.name, v.pos),
			)
		}

		if len(v.fullpaths) > 1 {
			document = cons_with_nopl(document, text("{"))
			for path, i in v.fullpaths {
				document = cons(document, text(path))
				if i != len(v.fullpaths) - 1 {
					document = cons(document, text(","), break_with_space())
				}
			}
			document = cons(document, text("}"))
		} else if len(v.fullpaths) == 1 {
			document = cons_with_nopl(document, text(v.fullpaths[0]))
		}

		return document
	case ^Foreign_Block_Decl:
		document := empty()
		if len(v.attributes) > 0 {
			document = cons(
				document,
				visit_attributes(p, &v.attributes, v.pos),
			)
		}

		document = cons(document, move_line(p, decl.pos))
		document = cons(
			document,
			cons_with_opl(text("foreign"), visit_expr(p, v.foreign_library)),
		)

		if v.body != nil && is_foreign_block_only_procedures(v.body) {
			p.force_statement_fit = true
			document = cons_with_nopl(document, visit_stmt(p, v.body))
			p.force_statement_fit = false
		} else {
			document = cons_with_nopl(document, visit_stmt(p, v.body))
		}

		return document
	case ^Import_Decl:
		document := move_line(p, decl.pos)

		if v.name.text != "" {
			document = cons(
				document,
				text_token(p, v.import_tok),
				break_with_space(),
				text_token(p, v.name),
				break_with_space(),
				text(v.fullpath),
			)
		} else {
			document = cons(
				document,
				text_token(p, v.import_tok),
				break_with_space(),
				text(v.fullpath),
			)
		}
		return document
	case ^Value_Decl:
		document := empty()
		if len(v.attributes) > 0 {
			document = cons(
				document,
				visit_attributes(p, &v.attributes, v.pos),
			)
		}

		document = cons(
			document,
			move_line(p, decl.pos),
			visit_state_flags(p, v.state_flags),
		)

		lhs := empty()
		rhs := empty()

		if v.is_using {
			lhs = cons(lhs, text("using"), break_with_no_newline())
		}

		lhs = cons(lhs, visit_exprs(p, v.names, {.Add_Comma, .Glue}))

		if v.type != nil {
			lhs = cons(lhs, text(":"))
			lhs = cons_with_nopl(lhs, visit_expr(p, v.type))
		} else {
			if !v.is_mutable {
				lhs = cons_with_nopl(lhs, cons(text(":"), text(":")))
			} else {
				lhs = cons_with_nopl(lhs, text(":"))
			}
		}

		if len(v.values) > 0 && v.is_mutable {
			if v.type != nil {
				lhs = cons_with_nopl(lhs, text("="))
			} else {
				lhs = cons(lhs, text("="))
			}

			rhs = cons_with_nopl(
				rhs,
				visit_exprs(p, v.values, {.Add_Comma}, .Value_Decl),
			)
		} else if len(v.values) > 0 && v.type != nil {
			rhs = cons_with_nopl(
				rhs,
				cons_with_nopl(
					text(":"),
					visit_exprs(p, v.values, {.Add_Comma}),
				),
			)
		} else {
			rhs = cons_with_nopl(
				rhs,
				visit_exprs(p, v.values, {.Add_Comma}, .Value_Decl),
			)
		}

		if len(v.values) > 0 {
			if is_values_nestable_assign(v.values) {
				return cons(
					document,
					group(nest(cons_with_opl(lhs, group(rhs)))),
				)
			} else if is_values_nestable_if_break_assign(v.values) {
				assignments := cons(
					lhs,
					group(
						nest(break_with_space()),
						Document_Group_Options{id = "assignments"},
					),
				)
				assignments = cons(
					assignments,
					nest_if_break(group(rhs), "assignments"),
				)
				return cons(document, group(assignments))
			} else {
				return cons(
					document,
					group(cons_with_nopl(group(lhs), group(rhs))),
				)
			}
		} else {
			return cons(document, group(lhs))
		}
	case:
		panic(fmt.aprint(decl.derived))
	}

	return empty()
}

@(private)
exprs_contain_empty_idents :: proc(list: []^ast.Expr) -> bool {
	for expr in list {
		if ident, ok := expr.derived.(^ast.Ident); ok && ident.name == "_" {
			continue
		}
		return false
	}
	return true
}

@(private)
is_call_expr_nestable :: proc(list: []^ast.Expr) -> bool {
	if len(list) == 0 {
		return true
	}

	#partial switch v in list[len(list) - 1].derived {
	case ^ast.Comp_Lit, ^ast.Proc_Type, ^ast.Proc_Lit:
		return false
	}

	return true
}

@(private)
is_foreign_block_only_procedures :: proc(stmt: ^ast.Stmt) -> bool {
	return true
}

@(private)
is_value_decl_statement_ending_with_call :: proc(stmt: ^ast.Stmt) -> bool {
	if value_decl, ok := stmt.derived.(^ast.Value_Decl); ok {
		if len(value_decl.values) == 0 {
			return false
		}

		#partial switch v in
			value_decl.values[len(value_decl.values) - 1].derived {
		case ^ast.Call_Expr, ^ast.Selector_Call_Expr:
			return true
		}
	}

	return false
}

@(private)
is_assign_statement_ending_with_call :: proc(stmt: ^ast.Stmt) -> bool {
	if assign_stmt, ok := stmt.derived.(^ast.Assign_Stmt); ok {
		if len(assign_stmt.rhs) == 0 {
			return false
		}

		#partial switch v in
			assign_stmt.rhs[len(assign_stmt.rhs) - 1].derived {
		case ^ast.Call_Expr, ^ast.Selector_Call_Expr:
			return true
		}
	}

	return false
}

@(private)
is_value_expression_call :: proc(expr: ^ast.Expr) -> bool {
	#partial switch v in expr.derived {
	case ^ast.Call_Expr, ^ast.Selector_Call_Expr:
		return true
	case ^ast.Unary_Expr:
		#partial switch v2 in v.expr.derived {
		case ^ast.Call_Expr, ^ast.Selector_Call_Expr:
			return true
		}
	}

	return false
}


@(private)
is_values_nestable_assign :: proc(list: []^ast.Expr) -> bool {
	if len(list) > 1 {
		return true
	}

	for expr in list {
		#partial switch v in expr.derived {
		case ^ast.Ident, ^ast.Binary_Expr, ^ast.Index_Expr, ^ast.Selector_Expr, ^ast.Paren_Expr, ^ast.Ternary_If_Expr, ^ast.Ternary_When_Expr, ^ast.Or_Else_Expr:
			return true
		}
	}
	return false
}

//Should the return stmt list behave like a call expression.
@(private)
is_values_return_stmt_callable :: proc(list: []^ast.Expr) -> bool {
	if len(list) > 1 {
		return false
	}

	for expr in list {
		result := expr
		if paren, is_paren := expr.derived.(^ast.Paren_Expr); is_paren {
			result = paren.expr
		}

		#partial switch v in result.derived {
		case ^ast.Call_Expr:
			return false
		}
	}
	return true
}

@(private)
is_return_stmt_ending_with_call_expr :: proc(list: []^ast.Expr) -> bool {
	if len(list) == 0 {
		return false
	}

	if _, is_call := list[len(list) - 1].derived.(^ast.Call_Expr); is_call {
		return true
	}

	return false
}


@(private)
is_values_nestable_if_break_assign :: proc(list: []^ast.Expr) -> bool {
	for expr in list {
		#partial switch v in expr.derived {
		case ^ast.Call_Expr, ^ast.Comp_Lit, ^ast.Or_Return_Expr:
			return true
		case ^ast.Unary_Expr:
			#partial switch v2 in v.expr.derived {
			case ^ast.Call_Expr:
				return true
			}
		}
	}
	return false
}

@(private)
visit_exprs :: proc(
	p: ^Printer,
	list: []^ast.Expr,
	options := List_Options{},
	called_from: Expr_Called_Type = .Generic,
) -> ^Document {
	if len(list) == 0 {
		return empty()
	}

	document := empty()

	for expr, i in list {
		p.source_position = expr.pos

		if .Enforce_Newline in options {
			document = cons(
				document,
				.Group in options \
				? group(visit_expr(p, expr, called_from, options)) \
				: visit_expr(p, expr, called_from, options),
			)
		} else if .Glue in options {
			document = cons_with_nopl(
				document,
				.Group in options \
				? group(visit_expr(p, expr, called_from, options)) \
				: visit_expr(p, expr, called_from, options),
			)
		} else {
			document = cons_with_opl(
				document,
				.Group in options \
				? group(visit_expr(p, expr, called_from, options)) \
				: visit_expr(p, expr, called_from, options),
			)
		}

		if (i != len(list) - 1 || .Trailing in options) &&
		   .Add_Comma in options {
			document = cons(document, text(","))
		}

		if (i != len(list) - 1 && .Enforce_Newline in options) {
			comment, _ := visit_comments(p, list[i + 1].pos)
			document = cons(document, comment, newline(1))
		} else if .Enforce_Newline in options {
			comment, _ := visit_comments(p, list[i].end)
			document = cons(document, comment)
		}
	}

	return document
}

@(private)
visit_enum_exprs :: proc(
	p: ^Printer,
	enum_type: ast.Enum_Type,
	options := List_Options{},
) -> ^Document {
	if len(enum_type.fields) == 0 {
		return empty()
	}

	document := empty()

	for expr, i in enum_type.fields {
		if i == 0 && .Enforce_Newline in options {
			comment, _ := visit_comments(p, enum_type.fields[i].pos)
			if _, is_nil := comment.(Document_Nil); !is_nil {
				comment = cons(comment, newline(1))
			}
			document = cons(comment, document)
		}

		if (.Enforce_Newline in options) {
			alignment := get_possible_enum_alignment(enum_type.fields)

			if value, ok := expr.derived.(^ast.Field_Value);
			   ok && alignment > 0 {
				document = cons(
					document,
					cons_with_nopl(
						visit_expr(p, value.field),
						cons_with_nopl(
							cons(
								repeat_space(
									alignment - get_node_length(value.field),
								),
								text_position(p, "=", value.sep),
							),
							visit_expr(p, value.value),
						),
					),
				)
			} else {
				document = group(
					cons(document, visit_expr(p, expr, .Generic, options)),
				)
			}
		} else {
			document = group(
				cons_with_opl(
					document,
					visit_expr(p, expr, .Generic, options),
				),
			)
		}

		if (i != len(enum_type.fields) - 1 || .Trailing in options) &&
		   .Add_Comma in options {
			document = cons(document, text(","))
		}

		if (i != len(enum_type.fields) - 1 && .Enforce_Newline in options) {
			comment, _ := visit_comments(p, enum_type.fields[i + 1].pos)
			document = cons(document, comment, newline(1))
		} else if .Enforce_Newline in options {
			comment, _ := visit_comments(p, enum_type.end)
			document = cons(document, comment)
		}
	}

	return document
}

@(private)
visit_bit_field_fields :: proc(
	p: ^Printer,
	bit_field_type: ast.Bit_Field_Type,
	options := List_Options{},
) -> ^Document {
	if len(bit_field_type.fields) == 0 {
		return empty()
	}

	document := empty()

	name_alignment, type_alignment := get_possible_bit_field_alignment(bit_field_type.fields)

	for field, i in bit_field_type.fields {
		if i == 0 && .Enforce_Newline in options {
			comment, _ := visit_comments(p, bit_field_type.fields[i].pos)
			if _, is_nil := comment.(Document_Nil); !is_nil {
				comment = cons(comment, newline(1))
			}
			document = cons(comment, document)
		}

		if (.Enforce_Newline in options) {
			document = cons(
				document,
				cons_with_nopl(
					cons(
						visit_expr(p, field.name),
						text_position(p, ":", field.name.end),
					),
					cons_with_nopl(
						cons(
							repeat_space(
								name_alignment - get_node_length(field.name),
							),
							visit_expr(p, field.type),
						),
						cons_with_nopl(
							cons(
								repeat_space(
									type_alignment - get_node_length(field.type),
								),
								text_position(p, "|", field.type.end),
							),
							visit_expr(p, field.bit_size),
						),
					),
				),
			)
		} else {
			document = group(
				cons_with_opl(
					document,
					cons_with_nopl(
						cons(
							visit_expr(p, field.name),
							text_position(p, ":", field.name.end),
						),
						cons_with_nopl(
							cons_with_nopl(
								visit_expr(p, field.type),
								text_position(p, "|", field.type.end),
							),
							visit_expr(p, field.bit_size),
						),
					),
				),
			)
		}

		if (i != len(bit_field_type.fields) - 1 || .Trailing in options) &&
		   .Add_Comma in options {
			document = cons(document, text(","))
		}

		if (i != len(bit_field_type.fields) - 1 && .Enforce_Newline in options) {
			comment, _ := visit_comments(p, bit_field_type.fields[i + 1].pos)
			document = cons(document, comment, newline(1))
		} else if .Enforce_Newline in options {
			comment, _ := visit_comments(p, bit_field_type.end)
			document = cons(document, comment)
		}
	}

	return document
}

@(private)
visit_union_exprs :: proc(
	p: ^Printer,
	union_type: ast.Union_Type,
	options := List_Options{},
) -> ^Document {
	if len(union_type.variants) == 0 {
		return empty()
	}

	document := empty()

	for expr, i in union_type.variants {
		if i == 0 && .Enforce_Newline in options {
			comment, _ := visit_comments(p, union_type.variants[i].pos)
			if _, is_nil := comment.(Document_Nil); !is_nil {
				comment = cons(comment, newline(1))
			}
			document = cons(comment, document)
		}

		if (.Enforce_Newline in options) {
			alignment := get_possible_enum_alignment(union_type.variants)

			if value, ok := expr.derived.(^ast.Field_Value);
			   ok && alignment > 0 {
				document = cons(
					document,
					cons_with_nopl(
						visit_expr(p, value.field),
						cons_with_nopl(
							cons(
								repeat_space(
									alignment - get_node_length(value.field),
								),
								text_position(p, "=", value.sep),
							),
							visit_expr(p, value.value),
						),
					),
				)
			} else {
				document = group(
					cons(document, visit_expr(p, expr, .Generic, options)),
				)
			}
		} else {
			document = group(
				cons_with_opl(
					document,
					visit_expr(p, expr, .Generic, options),
				),
			)
		}

		if (i != len(union_type.variants) - 1 || .Trailing in options) &&
		   .Add_Comma in options {
			document = cons(document, text(","))
		}

		if (i != len(union_type.variants) - 1 && .Enforce_Newline in options) {
			comment, _ := visit_comments(p, union_type.variants[i + 1].pos)
			document = cons(document, comment, newline(1))
		} else if .Enforce_Newline in options {
			comment, _ := visit_comments(p, union_type.end)
			document = cons(document, comment)
		}
	}

	return document
}

@(private)
visit_comp_lit_exprs :: proc(
	p: ^Printer,
	comp_lit: ast.Comp_Lit,
	options := List_Options{},
) -> ^Document {
	if len(comp_lit.elems) == 0 {
		return empty()
	}

	document := empty()

	for expr, i in comp_lit.elems {
		if i == 0 && .Enforce_Newline in options {
			comment, _ := visit_comments(p, comp_lit.elems[i].pos)
			if _, is_nil := comment.(Document_Nil); !is_nil {
				comment = cons(comment, newline(1))
			}
			document = cons(comment, document)
		}

		if (.Enforce_Newline in options) {
			alignment := get_possible_comp_lit_alignment(comp_lit.elems)
			if value, ok := expr.derived.(^ast.Field_Value);
			   ok && alignment > 0 {
				align := empty()
				if should_align_comp_lit(p, comp_lit) {
					align = repeat_space(
						alignment - get_node_length(value.field),
					)
				}
				document = cons(
					document,
					cons_with_nopl(
						visit_expr(p, value.field),
						cons_with_nopl(
							cons(align, text_position(p, "=", value.sep)),
							visit_expr(p, value.value),
						),
					),
				)
			} else {
				document = group(
					cons(document, visit_expr(p, expr, .Generic, options)),
				)
			}
		} else {
			document = group(
				cons_with_nopl(
					document,
					visit_expr(p, expr, .Generic, options),
				),
			)
		}

		if (i != len(comp_lit.elems) - 1 || .Trailing in options) &&
		   .Add_Comma in options {
			document = cons(document, text(","))
		}

		if (i != len(comp_lit.elems) - 1 && .Enforce_Newline in options) {
			comment, _ := visit_comments(p, comp_lit.elems[i + 1].pos)
			document = cons(document, comment, newline(1))
		} else if .Enforce_Newline in options {
			comment, _ := visit_comments(p, comp_lit.end)
			document = cons(document, comment)
		}
	}

	return document
}

@(private)
visit_attributes :: proc(
	p: ^Printer,
	attributes: ^[dynamic]^ast.Attribute,
	pos: tokenizer.Pos,
) -> ^Document {
	document := empty()
	if len(attributes) == 0 {
		return document
	}

	slice.sort_by(attributes[:], proc(i, j: ^ast.Attribute) -> bool {
		return i.pos.offset < j.pos.offset
	})

	document = cons(document, move_line(p, attributes[0].pos))

	for attribute, i in attributes {
		document = cons(
			document,
			text("@"),
			text("("),
			visit_exprs(p, attribute.elems, {.Add_Comma}),
			text(")"),
		)

		if i != len(attributes) - 1 {
			document = cons(document, newline(1))
		} else if pos.line == attributes[0].pos.line {
			document = cons(document, newline(1))
		}
	}

	return document
}

@(private)
visit_state_flags :: proc(
	p: ^Printer,
	flags: ast.Node_State_Flags,
) -> ^Document {
	if .No_Bounds_Check in flags {
		return cons(text("#no_bounds_check"), break_with_no_newline())
	}
	if .Bounds_Check in flags {
		return cons(text("#bounds_check"), break_with_no_newline())
	}
	return empty()
}

@(private)
enforce_fit_if_do :: proc(stmt: ^ast.Stmt, document: ^Document) -> ^Document {
	if block_uses_do(stmt) {
		return enforce_fit(document)
	}

	return document
}

block_uses_do :: proc(stmt: ^ast.Stmt) -> bool {
	if v, ok := stmt.derived.(^ast.Block_Stmt); ok {
		return v.uses_do
	}

	return false
}

@(private)
visit_stmt :: proc(
	p: ^Printer,
	stmt: ^ast.Stmt,
	block_type: Block_Type = .Generic,
	empty_block := false,
	block_stmt := false,
) -> ^Document {
	using ast

	if stmt == nil {
		return empty()
	}

	if stmt.pos.line in p.disabled_lines {
		return visit_disabled(p, stmt)
	}

	#partial switch v in stmt.derived {
	case ^Import_Decl:
		return visit_decl(p, cast(^Decl)stmt, true)
	case ^Value_Decl:
		return visit_decl(p, cast(^Decl)stmt, true)
	case ^Foreign_Import_Decl:
		return visit_decl(p, cast(^Decl)stmt, true)
	case ^Foreign_Block_Decl:
		return visit_decl(p, cast(^Decl)stmt, true)
	}

	document := visit_state_flags(p, stmt.state_flags)
	comments := move_line(p, stmt.pos)

	#partial switch v in stmt.derived {
	case ^ast.Tag_Stmt:
		//Hack to fix a bug in the odin parser
		v.end = v.stmt.end

		document = cons(
			document,
			text(v.op.text),
			text(v.name),
			break_with_no_newline(),
			visit_stmt(p, v.stmt),
		)
	case ^Using_Stmt:
		document = cons(
			document,
			cons_with_nopl(
				text("using"),
				visit_exprs(p, v.list, {.Add_Comma}),
			),
		)
	case ^Block_Stmt:
		uses_do := v.uses_do

		if v.label != nil {
			document = cons(
				document,
				visit_expr(p, v.label),
				text(":"),
				break_with_space(),
			)
		}

		if .Bounds_Check in v.state_flags {
			document = cons(
				document,
				text("#bounds_check"),
				break_with_space(),
			)
		}

		if !uses_do {
			document = cons(document, visit_begin_brace(p, v.pos, block_type))
		} else {
			document = cons(document, text("do"), break_with(" ", false))
		}

		set_source_position(p, v.pos)

		block := visit_block_stmts(p, v.stmts, len(v.stmts) > 1)

		comment_end, _ := visit_comments(
			p,
			tokenizer.Pos{line = v.end.line, offset = v.end.offset},
		)

		if block_type == .Switch_Stmt && !p.config.indent_cases {
			document = cons(document, block, comment_end)
		} else if uses_do {
			document = cons(document, cons(block, comment_end))
		} else {
			document = cons(document, nest(cons(block, comment_end)))
		}

		if !uses_do {
			document = cons(document, visit_end_brace(p, v.end))
		}
	case ^If_Stmt:
		if v.label != nil {
			document = cons(
				document,
				visit_expr(p, v.label),
				text(":"),
				break_with_space(),
			)
		}

		begin_document := text("if")
		end_document := empty()

		if v.init != nil {
			begin_document = cons_with_nopl(
				begin_document,
				cons(
					group(
						visit_stmt(p, v.init),
						Document_Group_Options{id = "init"},
					),
					text(";"),
				),
			)
		}

		if v.cond != nil && v.init != nil {
			end_document = cons(
				group(cons(break_with_space(), group(visit_expr(p, v.cond)))),
			)
		} else if v.cond != nil {
			end_document = cons(
				break_with_no_newline(),
				group(visit_expr(p, v.cond)),
			)
		}


		if v.init != nil && is_value_decl_statement_ending_with_call(v.init) ||
		   v.init != nil && is_assign_statement_ending_with_call(v.init) ||
		   v.cond != nil && v.init == nil && is_value_expression_call(v.cond) {
			document = cons(
				document,
				group(
					cons(
						begin_document,
						if_break_or(
							end_document,
							hang(3, end_document),
							"init",
						),
					),
				),
			)
		} else {
			document = cons(
				document,
				group(hang(3, cons(begin_document, end_document))),
			)
		}

		set_source_position(p, v.body.pos)

		document = cons_with_nopl(document, visit_stmt(p, v.body, .If_Stmt))

		set_source_position(p, v.body.end)

		if v.else_stmt != nil {
			if p.config.brace_style == .Allman ||
			   p.config.brace_style == .Stroustrup ||
			   block_uses_do(v.body) {
				document = cons(document, newline(1))
			}

			set_source_position(p, v.else_stmt.pos)

			if block_uses_do(v.body) {
				document = cons(
					document,
					cons_with_nopl(text("else"), visit_stmt(p, v.else_stmt)),
				)
			} else {
				document = cons_with_opl(
					document,
					cons_with_nopl(text("else"), visit_stmt(p, v.else_stmt)),
				)
			}


		}
		document = enforce_fit_if_do(v.body, document)
	case ^Switch_Stmt:
		if v.partial {
			document = cons(document, text("#partial"), break_with_space())
		}

		if v.label != nil {
			document = cons(
				document,
				visit_expr(p, v.label),
				text(":"),
				break_with_space(),
			)
		}

		document = cons(document, text("switch"))

		if v.init != nil {
			document = cons_with_opl(document, visit_stmt(p, v.init))
		}

		if v.init != nil && v.cond != nil {
			document = cons(document, text(";"))
		}

		document = cons_with_opl(document, visit_expr(p, v.cond))
		document = cons_with_nopl(
			document,
			visit_stmt(p, v.body, .Switch_Stmt),
		)
	case ^Case_Clause:
		document = cons(document, text("case"))

		if v.list != nil {
			document = cons_with_nopl(
				document,
				visit_exprs(p, v.list, {.Add_Comma}),
			)
		}

		document = cons(document, text(v.terminator.text))

		if len(v.body) != 0 {
			set_source_position(p, v.body[0].pos)
			document = cons(
				document,
				nest(cons(newline(1), visit_block_stmts(p, v.body))),
			)
		}
	case ^Type_Switch_Stmt:
		if v.partial {
			document = cons(document, text("#partial"), break_with_space())
		}

		if v.label != nil {
			document = cons(
				document,
				visit_expr(p, v.label),
				text(":"),
				break_with_space(),
			)
		}

		document = cons(document, text("switch"))
		document = cons_with_nopl(document, visit_stmt(p, v.tag, .Switch_Stmt))
		document = cons_with_nopl(
			document,
			visit_stmt(p, v.body, .Switch_Stmt),
		)
	case ^Assign_Stmt:
		assign_document: ^Document

		//If the switch contains `switch in v`
		if exprs_contain_empty_idents(v.lhs) && block_type == .Switch_Stmt {
			assign_document = cons(
				document,
				text("_"),
				break_with_space(),
				text(v.op.text),
			)
		} else {
			assign_document = cons(
				document,
				group(
					cons(
						visit_exprs(p, v.lhs, {.Add_Comma, .Glue}),
						cons(text(" "), text(v.op.text)),
					),
				),
			)
		}

		rhs := visit_exprs(p, v.rhs, {.Add_Comma}, .Assignment_Stmt)
		if is_values_nestable_assign(v.rhs) {
			document = group(nest(cons_with_opl(assign_document, group(rhs))))
		} else if is_values_nestable_if_break_assign(v.rhs) {
			document = cons(
				assign_document,
				group(
					nest(break_with_space()),
					Document_Group_Options{id = "assignments"},
				),
			)
			document = cons(document, nest_if_break(group(rhs), "assignments"))
			document = group(document)
		} else {
			document = group(cons_with_opl(assign_document, group(rhs)))
		}
	case ^Expr_Stmt:
		document = cons(document, visit_expr(p, v.expr))
	case ^For_Stmt:
		if v.label != nil {
			document = cons(
				document,
				visit_expr(p, v.label),
				text(":"),
				break_with_space(),
			)
		}

		for_document := text("for")

		if v.init != nil {
			set_source_position(p, v.init.pos)
			for_document = cons_with_nopl(
				for_document,
				cons(group(visit_stmt(p, v.init)), text(";")),
			)
		} else if v.post != nil {
			for_document = cons_with_nopl(for_document, text(";"))
		}

		if v.cond != nil {
			set_source_position(p, v.cond.pos)
			for_document = cons(
				for_document,
				v.init != nil ? break_with_space() : break_with_no_newline(),
				group(visit_expr(p, v.cond)),
			)
		}

		if v.post != nil {
			set_source_position(p, v.post.pos)
			for_document = cons(for_document, text(";"))
			for_document = cons_with_opl(
				for_document,
				group(visit_stmt(p, v.post)),
			)
		} else if v.post == nil && v.cond != nil && v.init != nil {
			for_document = cons(for_document, text(";"))
		}

		document = cons(document, group(hang(4, for_document)))

		set_source_position(p, v.body.pos)
		document = cons_with_nopl(document, visit_stmt(p, v.body))
		set_source_position(p, v.body.end)

		document = enforce_fit_if_do(v.body, document)
	case ^Inline_Range_Stmt:
		if v.label != nil {
			document = cons(
				document,
				visit_expr(p, v.label),
				text(":"),
				break_with_space(),
			)
		}

		document = cons(document, text("#unroll"))
		document = cons_with_nopl(document, text("for"))

		document = cons_with_nopl(document, visit_expr(p, v.val0))

		if v.val1 != nil {
			document = cons(
				document,
				cons_with_opl(text(","), visit_expr(p, v.val1)),
			)
		}

		document = cons_with_nopl(document, text("in"))

		document = cons_with_nopl(document, visit_expr(p, v.expr))

		set_source_position(p, v.body.pos)
		document = cons_with_nopl(document, visit_stmt(p, v.body))
		set_source_position(p, v.body.end)

		document = enforce_fit_if_do(v.body, document)
	case ^Range_Stmt:
		if v.label != nil {
			document = cons(
				document,
				visit_expr(p, v.label),
				text(":"),
				break_with_space(),
			)
		}

		if v.reverse {
			document = cons(
				document,
				text("#reverse"),
				break_with_no_newline(),
			)
		}

		document = cons(document, text("for"))

		if len(v.vals) >= 1 {
			document = cons_with_opl(document, visit_expr(p, v.vals[0]))
		}

		if len(v.vals) >= 2 {
			document = cons(
				document,
				cons_with_opl(text(","), visit_expr(p, v.vals[1])),
			)
		}

		document = cons_with_opl(document, text("in"))

		document = cons_with_opl(document, visit_expr(p, v.expr))

		set_source_position(p, v.body.pos)
		document = cons_with_nopl(document, visit_stmt(p, v.body))
		set_source_position(p, v.body.end)

		document = enforce_fit_if_do(v.body, document)
	case ^Return_Stmt:
		if v.results == nil {
			document = cons(document, text("return"))
			break
		}

		if is_values_return_stmt_callable(v.results) {
			result := v.results[0]

			if paren, is_paren := result.derived.(^ast.Paren_Expr); is_paren {
				result = paren.expr
			}

			document = cons(
				text("return"),
				if_break("("),
				break_with(" "),
				visit_expr(p, result),
			)

			document = nest(document)
			document = group(
				cons(document, if_break(" \\"), break_with(""), if_break(")")),
			)
		} else {
			document = cons(document, text("return"))


			if !is_return_stmt_ending_with_call_expr(v.results) {
				document = cons_with_nopl(
					document,
					group(
						nest(visit_exprs(p, v.results, {.Add_Comma, .Group})),
					),
				)
			} else {
				document = cons_with_nopl(
					document,
					visit_exprs(p, v.results, {.Add_Comma}),
				)
			}
		}
	case ^Defer_Stmt:
		document = cons(document, text("defer"))
		document = cons_with_nopl(document, visit_stmt(p, v.stmt))
	case ^When_Stmt:
		document = cons(
			document,
			cons_with_nopl(text("when"), visit_expr(p, v.cond)),
		)

		document = cons_with_nopl(document, visit_stmt(p, v.body))

		if v.else_stmt != nil {
			if p.config.brace_style == .Allman {
				document = cons(document, newline(1))
			}

			set_source_position(p, v.else_stmt.pos)

			document = cons_with_nopl(
				document,
				cons_with_nopl(text("else"), visit_stmt(p, v.else_stmt)),
			)
		}
	case ^Branch_Stmt:
		document = cons(document, text(v.tok.text))

		if v.label != nil {
			document = cons_with_nopl(document, visit_expr(p, v.label))
		}
	case:
		panic(fmt.aprint(stmt.derived))
	}

	set_source_position(p, stmt.end)

	return cons(comments, document)
}

@(private)
should_align_comp_lit :: proc(p: ^Printer, comp_lit: ast.Comp_Lit) -> bool {
	if len(comp_lit.elems) == 0 {
		return false
	}

	for expr in comp_lit.elems {
		if field, ok := expr.derived.(^ast.Field_Value); ok {
			#partial switch v in field.value.derived {
			case ^ast.Proc_Type, ^ast.Proc_Lit:
				return false
			}
		}
	}

	return true
}

@(private)
comp_lit_contains_fields :: proc(comp_lit: ast.Comp_Lit) -> bool {

	if len(comp_lit.elems) == 0 {
		return false
	}

	for expr in comp_lit.elems {
		if _, ok := expr.derived.(^ast.Field_Value); ok {
			return true
		}
	}

	return false
}

@(private)
comp_lit_contains_blocks :: proc(p: ^Printer, comp_lit: ast.Comp_Lit) -> bool {
	if len(comp_lit.elems) == 0 {
		return false
	}

	for expr in comp_lit.elems {
		if field, ok := expr.derived.(^ast.Field_Value); ok {
			#partial switch v in field.value.derived {
			case ^ast.Proc_Type, ^ast.Proc_Lit:
				return true
			}
		}
	}

	return false
}

@(private)
contains_comments_in_range :: proc(
	p: ^Printer,
	pos: tokenizer.Pos,
	end: tokenizer.Pos,
) -> bool {
	for i := p.latest_comment_index; i < len(p.comments); i += 1 {
		for c in p.comments[i].list {
			if pos.offset <= c.pos.offset && c.pos.offset <= end.offset {
				return true
			}
		}
	}
	return false
}

@(private)
contains_do_in_expression :: proc(p: ^Printer, expr: ^ast.Expr) -> bool {
	found_do := false

	visit_fn :: proc(visitor: ^ast.Visitor, node: ^ast.Node) -> ^ast.Visitor {
		if node == nil {
			return nil
		}

		found_do := cast(^bool)visitor.data
		if block, ok := node.derived.(^ast.Block_Stmt); ok {
			if block.uses_do == true {
				found_do^ = true
			}
		}

		return visitor
	}

	visit := ast.Visitor {
		data  = &found_do,
		visit = visit_fn,
	}

	ast.walk(&visit, expr)

	return found_do
}

@(private)
visit_where_clauses :: proc(p: ^Printer, clauses: []^ast.Expr) -> ^Document {
	if len(clauses) == 0 {
		return empty()
	}

	return nest(
		cons_with_nopl(
			text("where"),
			visit_exprs(p, clauses, {.Add_Comma, .Enforce_Newline}),
		),
	)
}

@(private)
visit_poly_params :: proc(
	p: ^Printer,
	poly_params: ^ast.Field_List,
) -> ^Document {
	if poly_params != nil {
		return cons(
			text("("),
			visit_signature_list(p, poly_params, true, false),
			text(")"),
		)
	} else {
		return empty()
	}
}

@(private)
visit_expr :: proc(
	p: ^Printer,
	expr: ^ast.Expr,
	called_from: Expr_Called_Type = .Generic,
	options := List_Options{},
) -> ^Document {
	using ast

	if expr == nil {
		return empty()
	}

	set_source_position(p, expr.pos)

	defer {
		set_source_position(p, expr.end)
	}

	comments, _ := visit_comments(p, expr.pos)
	document := empty()

	#partial switch v in expr.derived {
	case ^Inline_Asm_Expr:
		document = cons(
			text_token(p, v.tok),
			text("("),
			visit_exprs(p, v.param_types, {.Add_Comma}),
			text(")"),
		)
		document = cons_with_opl(document, cons(text("-"), text(">")))
		document = cons_with_opl(document, visit_expr(p, v.return_type))

		document = cons(
			document,
			text("{"),
			visit_expr(p, v.asm_string),
			text(","),
			visit_expr(p, v.constraints_string),
			text("}"),
		)
	case ^Undef:
		document = text("---")
	case ^Auto_Cast:
		document = cons_with_nopl(text_token(p, v.op), visit_expr(p, v.expr))
	case ^Ternary_If_Expr:
		if v.op1.text == "if" {
			document = cons(
				group(visit_expr(p, v.x)),
				if_break(" \\"),
				break_with_space(),
				text_token(p, v.op1),
				break_with_no_newline(),
				group(visit_expr(p, v.cond)),
				if_break(" \\"),
				break_with_space(),
				text_token(p, v.op2),
				break_with_no_newline(),
				group(visit_expr(p, v.y)),
			)
		} else {
			document = cons(
				group(visit_expr(p, v.cond)),
				if_break(" \\"),
				break_with_space(),
				text_token(p, v.op1),
				break_with_no_newline(),
				group(visit_expr(p, v.x)),
				if_break(" \\"),
				break_with_space(),
				text_token(p, v.op2),
				break_with_no_newline(),
				group(visit_expr(p, v.y)),
			)
		}
		document = group(document)
	case ^Ternary_When_Expr:
		document = visit_expr(p, v.x)
		document = cons_with_nopl(document, text_token(p, v.op1))
		document = cons_with_nopl(document, visit_expr(p, v.cond))
		document = cons_with_nopl(document, text_token(p, v.op2))
		document = cons_with_nopl(document, visit_expr(p, v.y))
	case ^Or_Else_Expr:
		document = visit_expr(p, v.x)
		document = cons_with_nopl(document, text_token(p, v.token))
		document = cons_with_nopl(document, visit_expr(p, v.y))
	case ^ast.Or_Branch_Expr:
		document = visit_expr(p, v.expr)
		document = cons_with_nopl(document, text_token(p, v.token))
		document = cons_with_nopl(document, visit_expr(p, v.label))
	case ^Or_Return_Expr:
		document = cons_with_nopl(
			visit_expr(p, v.expr),
			text_token(p, v.token),
		)
	case ^Selector_Call_Expr:
		document = visit_expr(p, v.call)
	case ^Ellipsis:
		document = cons(text(".."), visit_expr(p, v.expr))
	case ^Relative_Type:
		document = cons_with_opl(visit_expr(p, v.tag), visit_expr(p, v.type))
	case ^Slice_Expr:
		document = visit_expr(p, v.expr)
		document = cons(
			visit_expr(p, v.expr),
			text("["),
			visit_expr(p, v.low),
			text(v.interval.text),
		)

		if v.high != nil {
			document = cons(document, visit_expr(p, v.high))
		}
		document = cons(document, text("]"))
	case ^Ident:
		document = text_position(p, v.name, v.pos)
	case ^Deref_Expr:
		document = cons(visit_expr(p, v.expr), text_token(p, v.op))
	case ^Type_Cast:
		document = cons(
			text_token(p, v.tok),
			text("("),
			visit_expr(p, v.type),
			text(")"),
			visit_expr(p, v.expr),
		)
	case ^Basic_Directive:
		document = cons(text_token(p, v.tok), text_position(p, v.name, v.pos))
	case ^Distinct_Type:
		document = cons_with_opl(
			text_position(p, "distinct", v.pos),
			visit_expr(p, v.type),
		)
	case ^Dynamic_Array_Type:
		document = cons(
			visit_expr(p, v.tag),
			document,
			text("["),
			text("dynamic"),
			text("]"),
			visit_expr(p, v.elem),
		)
	case ^Bit_Set_Type:
		document = cons(
			text_position(p, "bit_set", v.pos),
			document,
			text("["),
			visit_expr(p, v.elem),
		)

		if v.underlying != nil {
			document = cons(
				document,
				cons(text(";"), visit_expr(p, v.underlying)),
			)
		}

		document = cons(document, text("]"))
	case ^Union_Type:
		document = cons(
			text_position(p, "union", v.pos),
			visit_poly_params(p, v.poly_params),
		)

		#partial switch v.kind {
		case .no_nil:
			document = cons_with_opl(document, text("#no_nil"))
		case .shared_nil:
			document = cons_with_opl(document, text("#shared_nil"))
		}

		document = cons_with_nopl(
			document,
			visit_where_clauses(p, v.where_clauses),
		)

		if len(v.variants) == 0 {
			document = cons_with_nopl(document, text("{"))
			document = cons(document, text("}"))
		} else {
			document = cons_with_nopl(
				document,
				visit_begin_brace(p, v.pos, .Generic),
			)
			set_source_position(p, v.variants[0].pos)
			document = cons(
				document,
				nest(
					cons(
						newline_position(p, 1, v.pos),
						visit_union_exprs(
							p,
							v^,
							{.Add_Comma, .Trailing, .Enforce_Newline},
						),
					),
				),
			)
			set_source_position(p, v.end)

			document = cons(document, newline(1), text_position(p, "}", v.end))
		}
	case ^Enum_Type:
		document = text_position(p, "enum", v.pos)

		if v.base_type != nil {
			document = cons_with_nopl(document, visit_expr(p, v.base_type))
		}

		if len(v.fields) == 0 {
			document = cons_with_nopl(document, text("{"))
			document = cons(document, text("}"))
		} else {
			document = cons(
				document,
				break_with_space(),
				visit_begin_brace(p, v.pos, .Generic),
			)
			set_source_position(p, v.fields[0].pos)
			document = cons(
				document,
				nest(
					cons(
						newline_position(p, 1, v.open),
						visit_enum_exprs(
							p,
							v^,
							{.Add_Comma, .Trailing, .Enforce_Newline},
						),
					),
				),
			)
			set_source_position(p, v.end)

			document = cons(document, newline(1), text_position(p, "}", v.end))
		}

		set_source_position(p, v.end)
	case ^Struct_Type:
		document = text_position(p, "struct", v.pos)

		document = cons(document, visit_poly_params(p, v.poly_params))

		if v.is_packed {
			document = cons_with_nopl(document, text("#packed"))
		}

		if v.is_raw_union {
			document = cons_with_nopl(document, text("#raw_union"))
		}

		if v.align != nil {
			document = cons_with_nopl(document, text("#align"))
			document = cons_with_nopl(document, visit_expr(p, v.align))
		}

		if v.field_align != nil {
			document = cons_with_nopl(document, text("#field_align"))
			document = cons_with_nopl(document, visit_expr(p, v.field_align))
		}

		document = cons_with_nopl(
			document,
			visit_where_clauses(p, v.where_clauses),
		)

		if v.fields != nil && len(v.fields.list) == 0 {
			document = cons_with_nopl(document, text("{"))
			document = cons(
				document,
				visit_struct_field_list(p, v.fields, {.Add_Comma}),
				text("}"),
			)
		} else if v.fields != nil {
			document = cons(
				document,
				break_with_space(),
				visit_begin_brace(p, v.pos, .Generic),
			)

			set_source_position(p, v.fields.pos)
			document = cons(
				document,
				nest(
					cons(
						newline_position(p, 1, v.fields.open),
						visit_struct_field_list(
							p,
							v.fields,
							{.Add_Comma, .Trailing, .Enforce_Newline},
						),
					),
				),
			)
			set_source_position(p, v.fields.end)

			document = cons(document, newline(1), text_position(p, "}", v.end))
		}

		set_source_position(p, v.end)
	case ^Bit_Field_Type:
		document = text_position(p, "bit_field", v.pos)

		document = cons_with_nopl(document, visit_expr(p, v.backing_type))

		if len(v.fields) == 0 {
			document = cons_with_nopl(document, text("{"))
			document = cons(document, text("}"))
		} else {
			document = cons(document, break_with_space(), visit_begin_brace(p, v.pos, .Generic))
			set_source_position(p, v.fields[0].pos)
			document = cons(
				document,
				nest(
					cons(
						newline_position(p, 1, v.open),
						visit_bit_field_fields(
							p,
							v^,
							{.Add_Comma, .Trailing, .Enforce_Newline},
						),
					),
				),
			)
			set_source_position(p, v.end)

			document = cons(document, newline(1), text_position(p, "}", v.end))
		}

		set_source_position(p, v.end)
	case ^Proc_Lit:
		switch v.inlining {
		case .None:
		case .Inline:
			document = cons(document, text("#force_inline"))
		case .No_Inline:
			document = cons(document, text("#force_no_inline"))
		}

		document = cons_with_nopl(
			document,
			visit_proc_type(p, v.type^, v.body != nil),
		)

		document = cons_with_nopl(
			document,
			visit_where_clauses(p, v.where_clauses),
		)

		document = group(document)

		document = cons(document, visit_proc_tags(p, v.tags))

		if v.body != nil {
			set_source_position(p, v.body.pos)
			document = cons_with_nopl(
				document,
				group(visit_stmt(p, v.body, .Proc)),
			)
		} else {
			document = cons_with_nopl(document, text("---"))
		}
	case ^Proc_Type:
		document = group(visit_proc_type(p, v^, false))
	case ^Basic_Lit:
		document = text_token(p, v.tok)
	case ^Binary_Expr:
		document = visit_binary_expr(p, v^)
	case ^Implicit_Selector_Expr:
		document = cons(text("."), text_position(p, v.field.name, v.field.pos))
	case ^Call_Expr:
		switch v.inlining {
		case .None:
		case .Inline:
			document = cons(
				document,
				text("#force_inline"),
				break_with_no_newline(),
			)
		case .No_Inline:
			document = cons(
				document,
				text("#force_no_inline"),
				break_with_no_newline(),
			)
		}

		document = cons(document, visit_expr(p, v.expr), text("("))

		contains_comments := contains_comments_in_range(p, v.open, v.close)
		contains_do := false

		for arg in v.args {
			contains_do |= contains_do_in_expression(p, arg)
		}

		if is_call_expr_nestable(v.args) {
			document = cons(
				document,
				nest(cons(break_with(""), visit_call_exprs(p, v))),
			)
		} else {
			document = cons(
				document,
				nest_if_break(
					cons(break_with(""), visit_call_exprs(p, v)),
					"call_expr",
				),
			)
		}

		document = cons(document, break_with(""), text(")"))

		//Binary expression are nested on operators, and therefore undo the nesting in the call expression.
		if called_from == .Binary_Expr {
			document = escape_nest(document)
		}

		//We enforce a break if comments exists inside the call args
		if contains_comments {
			document = enforce_break(
				document,
				Document_Group_Options{id = "call_expr"},
			)
		} else if contains_do {
			document = enforce_fit(document)
		} else {
			document = group(
				document,
				Document_Group_Options{id = "call_expr"},
			)
		}
	case ^Typeid_Type:
		document = text("typeid")

		if v.specialization != nil {
			document = cons(
				document,
				text("/"),
				visit_expr(p, v.specialization),
			)
		}
	case ^Selector_Expr:
		document = enforce_fit(
			cons(
				visit_expr(p, v.expr),
				text_token(p, v.op),
				visit_expr(p, v.field),
			),
		)
	case ^Paren_Expr:
		document = group(
			cons(text("("), nest(visit_expr(p, v.expr)), text(")")),
		)
	case ^Index_Expr:
		//Switch back to enforce fit, it just doesn't look good when breaking.
		document = enforce_fit(
			cons(
				visit_expr(p, v.expr),
				text("["),
				nest(
					cons(
						break_with("", true),
						group(visit_expr(p, v.index)),
						if_break(" \\"),
					),
				),
				break_with("", true),
				text("]"),
			),
		)
	case ^Proc_Group:
		document = text_token(p, v.tok)

		if len(v.args) != 0 {
			document = cons_with_nopl(
				document,
				visit_begin_brace(p, v.pos, .Generic),
			)
			set_source_position(p, v.args[0].pos)
			document = cons(
				document,
				nest(
					cons(
						newline_position(p, 1, v.args[0].pos),
						visit_exprs(
							p,
							v.args,
							{.Add_Comma, .Trailing, .Enforce_Newline},
						),
					),
				),
			)
			document = cons(document, visit_end_brace(p, v.end, 1))
		} else {
			document = cons(
				document,
				text("{"),
				visit_exprs(p, v.args, {.Add_Comma}),
				text("}"),
			)
		}
	case ^Comp_Lit:
		if v.tag != nil {
			document = cons_with_nopl(document, visit_expr(p, v.tag))
		}

		if v.type != nil {
			document = cons_with_nopl(document, group(visit_expr(p, v.type)))

			if matrix_type, ok := v.type.derived.(^ast.Matrix_Type);
			   ok && len(v.elems) > 0 && is_matrix_type_constant(matrix_type) {
				document = cons(
					document,
					visit_begin_brace(p, v.pos, .Comp_Lit),
				)

				set_source_position(p, v.open)
				document = cons(
					document,
					nest(
						cons(
							newline_position(p, 1, v.elems[0].pos),
							visit_matrix_comp_lit(p, v, matrix_type),
						),
					),
				)
				set_source_position(p, v.end)

				document = cons(
					document,
					newline(1),
					text_position(p, "}", v.end),
				)

				break
			}
		}

		should_newline :=
			comp_lit_contains_fields(v^) ||
			contains_comments_in_range(p, v.pos, v.end)
		should_newline &=
			(called_from == .Value_Decl ||
				called_from == .Assignment_Stmt ||
				(called_from == .Call_Expr && comp_lit_contains_blocks(p, v^)))
		should_newline &= len(v.elems) != 0

		if should_newline {
			document = cons_with_nopl(
				document,
				visit_begin_brace(p, v.pos, .Comp_Lit),
			)

			set_source_position(p, v.open)
			document = cons(
				document,
				nest(
					cons(
						newline_position(p, 1, v.elems[0].pos),
						visit_comp_lit_exprs(
							p,
							v^,
							{.Add_Comma, .Trailing, .Enforce_Newline},
						),
					),
				),
			)
			set_source_position(p, v.end)

			document = cons(document, newline(1), text_position(p, "}", v.end))
		} else {
			document = cons(
				document,
				group(
					cons(
						if_break(" "),
						text("{"),
						nest(
							cons(
								break_with(""),
								visit_exprs(p, v.elems, {.Add_Comma, .Group}),
							),
						),
						if_break(","),
						break_with(""),
						text("}"),
					),
				),
			)
			document = group(document)
		}
	case ^Unary_Expr:
		document = cons(text_token(p, v.op), visit_expr(p, v.expr))
	case ^Field_Value:
		document = cons_with_nopl(
			visit_expr(p, v.field),
			cons_with_nopl(
				text_position(p, "=", v.sep),
				visit_expr(p, v.value),
			),
		)
	case ^Type_Assertion:
		document = visit_expr(p, v.expr)

		if unary, ok := v.type.derived.(^Unary_Expr);
		   ok && unary.op.text == "?" {
			document = cons(document, text("."), visit_expr(p, v.type))
		} else {
			document = cons(
				document,
				text("."),
				text("("),
				visit_expr(p, v.type),
				text(")"),
			)
		}
	case ^Pointer_Type:
		document = cons(visit_expr(p, v.tag), text("^"), visit_expr(p, v.elem))
	case ^Multi_Pointer_Type:
		document = cons(text("[^]"), visit_expr(p, v.elem))
	case ^Implicit:
		document = text_token(p, v.tok)
	case ^Poly_Type:
		document = cons(text("$"), visit_expr(p, v.type))

		if v.specialization != nil {
			document = cons(
				document,
				text("/"),
				visit_expr(p, v.specialization),
			)
		}
	case ^Array_Type:
		document = cons(
			visit_expr(p, v.tag),
			text("["),
			visit_expr(p, v.len),
			text("]"),
			visit_expr(p, v.elem),
		)
	case ^Map_Type:
		document = cons(
			text("map"),
			text("["),
			visit_expr(p, v.key),
			text("]"),
			visit_expr(p, v.value),
		)
	case ^Helper_Type:
		if v.tok == .Hash {
			document = cons(document, text("#type"))
		}
		document = cons_with_nopl(document, visit_expr(p, v.type))
	case ^Matrix_Type:
		document = cons(
			text_position(p, "matrix", v.pos),
			text("["),
			visit_expr(p, v.row_count),
			text(","),
		)
		document = cons_with_opl(document, visit_expr(p, v.column_count))
		document = cons(document, text("]"))
		document = cons(group(document), visit_expr(p, v.elem))
	case ^ast.Tag_Expr:
		document = cons(
			text(v.op.text),
			break_with_no_newline(),
			text(v.name),
			break_with_no_newline(),
			visit_expr(p, v.expr),
		)
	case ^Matrix_Index_Expr:
		document = cons(
			visit_expr(p, v.expr),
			text("["),
			visit_expr(p, v.row_index),
			text(","),
		)
		document = cons_with_opl(document, visit_expr(p, v.column_index))
		document = cons(document, text("]"))
	case:
		panic(fmt.aprint(expr.derived))
	}

	return cons(comments, document)
}

@(private)
is_matrix_type_constant :: proc(matrix_type: ^ast.Matrix_Type) -> bool {
	if row_count, is_lit := matrix_type.row_count.derived.(^ast.Basic_Lit);
	   is_lit {
		_, ok := strconv.parse_int(row_count.tok.text)
		return ok
	}

	if column_count, is_lit := matrix_type.column_count.derived.(^ast.Basic_Lit);
	   is_lit {
		_, ok := strconv.parse_int(column_count.tok.text)
		return ok
	}

	return false
}

@(private)
visit_matrix_comp_lit :: proc(
	p: ^Printer,
	comp_lit: ^ast.Comp_Lit,
	matrix_type: ^ast.Matrix_Type,
) -> ^Document {
	document := empty()

	//these values have already been validated
	row_count, _ := strconv.parse_int(
		matrix_type.row_count.derived.(^ast.Basic_Lit).tok.text,
	)
	column_count, _ := strconv.parse_int(
		matrix_type.column_count.derived.(^ast.Basic_Lit).tok.text,
	)

	for row := 0; row < row_count; row += 1 {
		for column := 0; column < column_count; column += 1 {
			document = cons(
				document,
				visit_expr(p, comp_lit.elems[column + row * column_count]),
			)
			document = cons(document, text(", "))
		}

		if row_count - 1 != row {
			document = cons(document, newline(1))
		}
	}

	return document
}


@(private)
visit_begin_brace :: proc(
	p: ^Printer,
	begin: tokenizer.Pos,
	type: Block_Type,
) -> ^Document {
	set_source_position(p, begin)
	set_comment_option(p, begin.line, .Indent)

	newline_braced := p.config.brace_style == .Allman
	newline_braced |= p.config.brace_style == .K_And_R && type == .Proc
	newline_braced &= p.config.brace_style != ._1TBS

	if newline_braced {
		if type == .Comp_Lit {
			return cons(text("\\"), newline(1), text("{"))
		}
		return cons(newline(1), text("{"))
	}

	return text("{")
}

@(private)
visit_end_brace :: proc(
	p: ^Printer,
	end: tokenizer.Pos,
	limit := 0,
) -> ^Document {
	if limit == 0 {
		return cons(move_line(p, end), text("}"))
	} else {
		document, newlined := move_line_limit(p, end, limit)
		if !newlined {
			return cons(document, newline(1), text("}"))
		} else {
			return cons(document, text("}"))
		}
	}
}

@(private)
visit_block_stmts :: proc(
	p: ^Printer,
	stmts: []^ast.Stmt,
	split := false,
) -> ^Document {
	document := empty()

	for stmt, i in stmts {
		last_index := max(0, i - 1)
		if stmts[last_index].end.line == stmt.pos.line &&
		   i != 0 &&
		   stmt.pos.line not_in p.disabled_lines {
			document = cons(document, break_with(";"))
		}

		if p.force_statement_fit {
			document = cons(
				document,
				enforce_fit(visit_stmt(p, stmt, .Generic, false, true)),
			)
		} else {
			document = cons(
				document,
				visit_stmt(p, stmt, .Generic, false, true),
			)
		}
	}

	return document
}

List_Option :: enum u8 {
	Add_Comma,
	Trailing,
	Enforce_Newline,
	Group,
	Glue,
}

List_Options :: distinct bit_set[List_Option]

@(private)
visit_struct_field_list :: proc(
	p: ^Printer,
	list: ^ast.Field_List,
	options := List_Options{},
) -> ^Document {
	document := empty()
	if list.list == nil {
		return document
	}

	for field, i in list.list {
		align := empty()

		p.source_position = field.pos

		if i == 0 && .Enforce_Newline in options {
			comment, ok := visit_comments(p, list.list[i].pos)
			if _, is_nil := comment.(Document_Nil); !is_nil {
				comment = cons(comment, newline(1))
			}
			document = cons(comment, document)
		}

		if .Using in field.flags {
			document = cons(document, text("using"), break_with_no_newline())
		}

		if .Subtype in field.flags {
			document = cons(
				document,
				text("#subtype"),
				break_with_no_newline(),
			)
		}

		name_options := List_Options{.Add_Comma}

		if (.Enforce_Newline in options) {
			alignment := get_possible_field_alignment(list.list)

			if alignment > 0 {
				length := 0
				for name in field.names {
					length += get_node_length(name) + 2
					if .Using in field.flags {
						length += 6
					}
					if .Subtype in field.flags {
						length += 9
					}
				}
				align = repeat_space(alignment - length)
			}
			document = cons(
				document,
				visit_exprs(p, field.names, name_options),
			)
		} else {
			document = cons_with_opl(
				document,
				visit_exprs(p, field.names, name_options),
			)
		}

		if field.type != nil {
			if len(field.names) != 0 {
				document = cons(document, text(":"), align)
			}
			document = cons_with_opl(document, visit_expr(p, field.type))
		} else {
			document = cons(document, text(":"), text("="))
			document = cons_with_opl(
				document,
				visit_expr(p, field.default_value),
			)
		}

		if field.tag.text != "" {
			document = cons_with_nopl(document, text_token(p, field.tag))
		}

		if (i != len(list.list) - 1 || .Trailing in options) &&
		   .Add_Comma in options {
			document = cons(document, text(","))
		}

		if i != len(list.list) - 1 && .Enforce_Newline in options {
			comment, _ := visit_comments(p, list.list[i + 1].pos)
			document = cons(document, comment, newline(1))
		} else {
			comment, _ := visit_comments(p, list.end)
			document = cons(document, comment)
		}
	}
	return document
}

@(private)
visit_proc_tags :: proc(p: ^Printer, proc_tags: ast.Proc_Tags) -> ^Document {
	document := empty()

	if .Bounds_Check in proc_tags {
		document = cons_with_opl(document, text("#bounds_check"))
	}

	if .No_Bounds_Check in proc_tags {
		document = cons_with_opl(document, text("#no_bounds_check"))
	}

	if .Optional_Ok in proc_tags {
		document = cons_with_opl(document, text("#optional_ok"))
	}

	if .Optional_Allocator_Error in proc_tags {
		document = cons_with_opl(document, text("#optional_allocator_error"))
	}

	return group(cons_with_nopl(if_break("\\"), document))
}

@(private)
visit_proc_type :: proc(
	p: ^Printer,
	proc_type: ast.Proc_Type,
	contains_body: bool,
) -> ^Document {
	document := text("proc")

	explicit_calling := false

	if v, ok := proc_type.calling_convention.(string); ok {
		explicit_calling = true
		document = cons_with_nopl(document, text(v))
	}

	if explicit_calling {
		document = cons_with_nopl(document, text("("))
	} else {
		document = cons(document, text("("))
	}

	document = cons(
		document,
		nest(
			cons(
				len(proc_type.params.list) > 0 ? break_with("") : empty(),
				visit_signature_list(p, proc_type.params, true, false),
			),
		),
	)
	document = cons(document, break_with(""), text(")"))

	if proc_type.results != nil && len(proc_type.results.list) > 0 {
		document = cons_with_nopl(document, text("-"))
		document = cons(document, text(">"))

		use_parens := false

		if len(proc_type.results.list) > 1 {
			use_parens = true
		} else if len(proc_type.results.list) == 1 {
			for name in proc_type.results.list[0].names {
				if ident, ok := name.derived.(^ast.Ident); ok {
					if ident.name != "_" {
						use_parens = true
					}
				}
			}
		}

		if use_parens {
			document = cons_with_nopl(document, text("("))
			document = cons(
				document,
				nest(
					cons(
						break_with(""),
						visit_signature_list(
							p,
							proc_type.results,
							contains_body,
							true,
						),
					),
				),
			)
			document = cons(document, break_with(""), text(")"))
		} else {
			document = cons_with_nopl(
				document,
				nest(
					group(
						visit_signature_list(
							p,
							proc_type.results,
							contains_body,
							true,
						),
					),
				),
			)
		}
	} else if proc_type.diverging {
		document = cons_with_nopl(document, text("-"))
		document = cons(document, text(">"))
		document = cons_with_nopl(document, text("!"))
	}

	return document
}


@(private)
visit_binary_expr :: proc(
	p: ^Printer,
	binary: ast.Binary_Expr,
	nested := false,
) -> ^Document {
	document := empty()

	nest_expression := false

	if binary.left != nil {
		if b, ok := binary.left.derived.(^ast.Binary_Expr); ok {
			pa := parser.Parser {
				allow_in_expr = true,
			}
			nest_expression =
				parser.token_precedence(&pa, b.op.kind) !=
				parser.token_precedence(&pa, binary.op.kind)
			document = cons(
				document,
				visit_binary_expr(p, b^, nest_expression),
			)
		} else {
			document = cons(
				document,
				visit_expr(p, binary.left, nested ? .Binary_Expr : .Generic),
			)
		}
	}

	if nest_expression {
		document = nest(document)
		document = group(document)
	}

	document = cons_with_nopl(document, text(binary.op.text))

	if binary.right != nil {
		if b, ok := binary.right.derived.(^ast.Binary_Expr); ok {
			document = cons_with_opl(
				document,
				group(nest(visit_binary_expr(p, b^, true))),
			)
		} else {
			document = cons_with_opl(
				document,
				group(nest(visit_expr(p, binary.right, .Binary_Expr))),
			)
		}
	}

	return document
}

@(private)
visit_call_exprs :: proc(p: ^Printer, call_expr: ^ast.Call_Expr) -> ^Document {
	document := empty()

	ellipsis := call_expr.ellipsis.kind == .Ellipsis


	for expr, i in call_expr.args {
		if call_expr.ellipsis.pos.offset <= expr.pos.offset && ellipsis {
			document = cons(document, text(".."))
			ellipsis = false
		}

		document = cons(document, group(visit_expr(p, expr, .Call_Expr)))

		if i != len(call_expr.args) - 1 {
			document = cons(document, text(","))

			//need to look for comments before we write the comma with break
			comments, _ := visit_comments(p, call_expr.args[i + 1].pos)

			document = cons(document, comments, break_with_space())
		} else {
			comments, _ := visit_comments(p, call_expr.close)
			document = cons(document, if_break(","), comments)
		}

	}
	return document
}

@(private)
visit_signature_field_flag :: proc(
	p: ^Printer,
	flags: ast.Field_Flags,
) -> ^Document {
	document := empty()

	if .Any_Int in flags {
		document = cons_with_nopl(document, text("#any_int"))
	}

	if .C_Vararg in flags {
		document = cons_with_nopl(document, text("#c_vararg"))
	}

	if .No_Alias in flags {
		document = cons_with_nopl(document, text("#no_alias"))
	}

	if .Subtype in flags {
		document = cons_with_nopl(document, text("#subtype"))
	}

	if .By_Ptr in flags {
		document = cons_with_nopl(document, text("#by_ptr"))
	}

	if .Using in flags {
		document = cons_with_nopl(document, text("using"))
	}

	return document
}

@(private)
visit_signature_list :: proc(
	p: ^Printer,
	list: ^ast.Field_List,
	contains_body: bool,
	remove_blank: bool,
) -> ^Document {
	document := empty()

	for field, i in list.list {
		document = cons(
			document,
			visit_signature_field(p, field, remove_blank),
		)

		if i != len(list.list) - 1 {
			document = cons(document, text(","), break_with_space())
		} else {
			document =
				len(list.list) > 1 || contains_body \
				? cons(document, if_break(",")) \
				: document
		}
	}

	return document
}

@(private)
visit_signature_field :: proc(
	p: ^Printer,
	field: ^ast.Field,
	remove_blank := true,
) -> ^Document {
	document := empty()
	flag := visit_signature_field_flag(p, field.flags)

	named := false

	for name in field.names {
		if ident, ok := name.derived.(^ast.Ident); ok {
			//for some reason the parser uses _ to mean empty
			if ident.name != "_" || !remove_blank {
				named = true
			}
		} else {
			//alternative is poly names
			named = true
		}
	}

	if named {
		document = cons(
			document,
			cons_with_nopl(flag, visit_exprs(p, field.names, {.Add_Comma})),
		)

		if len(field.names) != 0 && field.type != nil {
			document = cons(document, text(":"), break_with_no_newline())
		}
	}

	if field.type != nil && field.default_value != nil {
		document = cons(document, visit_expr(p, field.type))
		document = cons_with_nopl(document, text("="))
		document = cons_with_nopl(document, visit_expr(p, field.default_value))
	} else if field.type != nil {
		document = cons(document, visit_expr(p, field.type))
	} else {
		document = cons_with_nopl(document, text(":"))
		document = cons(document, text("="))
		document = cons_with_nopl(document, visit_expr(p, field.default_value))
	}
	return group(document)
}

@(private)
repeat_space :: proc(amount: int) -> ^Document {
	document := empty()
	for i := 0; i < amount; i += 1 {
		document = cons(document, break_with_no_newline())
	}
	return document
}

@(private)
get_node_length :: proc(node: ^ast.Node) -> int {
	#partial switch v in node.derived {
	case ^ast.Ident:
		return strings.rune_count(v.name)
	case ^ast.Basic_Lit:
		return strings.rune_count(v.tok.text)
	case ^ast.Implicit_Selector_Expr:
		return strings.rune_count(v.field.name) + 1
	case ^ast.Binary_Expr:
		return 0
	case ^ast.Paren_Expr:
		return 1 + get_node_length(v.expr) + 1
	case ^ast.Pointer_Type:
		return 1 + get_node_length(v.elem)
	case ^ast.Selector_Expr:
		return(
			get_node_length(v.expr) +
			strings.rune_count(v.op.text) +
			strings.rune_count(v.field.name) \
		)
	case:
		panic(fmt.aprintf("unhandled get_node_length case %v", node.derived))
	}
}

@(private)
get_possible_field_alignment :: proc(fields: []^ast.Field) -> int {
	longest_name := 0

	for field in fields {
		length := 0
		for name in field.names {
			length += get_node_length(name) + 2
		}

		if .Using in field.flags {
			length += 6
		}

		longest_name = max(longest_name, length)
	}

	return longest_name
}

@(private)
get_possible_comp_lit_alignment :: proc(exprs: []^ast.Expr) -> int {
	longest_name := 0

	for expr in exprs {
		value, is_field_value := expr.derived.(^ast.Field_Value)

		if !is_field_value {
			return 0
		}

		if comp, is_comp := value.value.derived.(^ast.Comp_Lit); is_comp {
			if comp_lit_contains_fields(comp^) {
				return 0
			}
		}

		longest_name = max(longest_name, get_node_length(value.field))
	}

	return longest_name
}

@(private)
get_possible_enum_alignment :: proc(exprs: []^ast.Expr) -> int {
	longest_name := 0

	for expr in exprs {
		value, ok := expr.derived.(^ast.Field_Value)

		if !ok {
			return 0
		}

		longest_name = max(longest_name, get_node_length(value.field))
	}

	return longest_name
}

@(private)
get_possible_bit_field_alignment :: proc(fields: []^ast.Bit_Field_Field) -> (longest_name: int, longest_type: int) {
	for field in fields {
		longest_name = max(longest_name, get_node_length(field.name))
		longest_type = max(longest_type, get_node_length(field.type))
	}

	return
}
