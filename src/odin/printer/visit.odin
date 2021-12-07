package odin_printer

import "core:odin/ast"
import "core:odin/tokenizer"
import "core:strings"
import "core:fmt"
import "core:sort"

//right now the attribute order is not linearly parsed(bug?)
@(private)
sort_attribute :: proc(s: ^[dynamic]^ast.Attribute) -> sort.Interface {
	return sort.Interface {
		collection = rawptr(s),
		len = proc(it: sort.Interface) -> int {
			s := (^[dynamic]^ast.Attribute)(it.collection)
			return len(s^)
		},
		less = proc(it: sort.Interface, i, j: int) -> bool {
			s := (^[dynamic]^ast.Attribute)(it.collection)
			return s[i].pos.offset < s[j].pos.offset
		},
		swap = proc(it: sort.Interface, i, j: int) {
			s := (^[dynamic]^ast.Attribute)(it.collection)
			s[i], s[j] = s[j], s[i]
		},
	}
}

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

text_position :: proc(p: ^Printer, value: string, pos: tokenizer.Pos) -> ^Document {
	document, _ := visit_comments(p, pos)
	return cons(document, text(value))
}

newline_position :: proc(p: ^Printer, amount: int, pos: tokenizer.Pos) -> ^Document {
	document, _ := visit_comments(p, pos)
	return cons(document, newline(amount))
}

@(private)
set_source_position :: proc(p: ^Printer, pos: tokenizer.Pos) {
	p.source_position = pos
}

@(private)
move_line :: proc(p: ^Printer, pos: tokenizer.Pos) -> ^Document {
	l, _ := move_line_limit(p, pos, p.config.newline_limit+1)
	return l
}

@(private)
move_line_limit :: proc(p: ^Printer, pos: tokenizer.Pos, limit: int) -> (^Document, bool) {
	lines := pos.line - p.source_position.line

	if lines < 0 {
		return empty(), false
	}

	document, comments_newlined := visit_comments(p, pos)

	p.source_position = pos

	return cons(document, newline(max(min(lines-comments_newlined, limit), 0))), lines > 0
}

@(private)
visit_comment :: proc(p: ^Printer, comment: tokenizer.Token, end_newline := true) -> (int, ^Document) {	
	document := empty()
	if len(comment.text) == 0 {
		return 0, document
	}
	
	newlines_before_comment := min(comment.pos.line - p.source_position.line, p.config.newline_limit + 1)

	document = cons(document, newline(newlines_before_comment))

	if comment.text[:2] != "/*" {
		if comment.pos.line in p.disabled_lines {
			p.source_position = comment.pos
			return 1, empty()
		} else if comment.pos.line == p.source_position.line {
			p.source_position = comment.pos
			return newlines_before_comment, cons_with_opl(document, text(comment.text))
		} else {
			p.source_position = comment.pos
			return newlines_before_comment, cons(document, text(comment.text))
		}
	} else {		
		newlines := strings.count(comment.text, "\n")

		if comment.pos.line in p.disabled_lines {
			p.source_position = comment.pos
			p.source_position.line += newlines
			return 1, empty()
		} else if comment.pos.line == p.source_position.line {
			p.source_position = comment.pos
			p.source_position.line += newlines
			return newlines_before_comment+newlines, cons_with_opl(document, text(comment.text))
		} else {
			p.source_position = comment.pos
			p.source_position.line += newlines
			return newlines_before_comment+newlines, cons(document, text(comment.text))
		}

		return 0, document
	}
}

@(private)
visit_comments :: proc(p: ^Printer, pos: tokenizer.Pos, end_newline := true) -> (^Document, int) {
	document := empty()
	lines := 0

	for comment_before_position(p, pos) {
		comment_group := p.comments[p.latest_comment_index]

		for comment, i in comment_group.list {
			newlined, tmp_document := visit_comment(p, comment, end_newline)
			lines += newlined
			document = cons(document, tmp_document)
		}

		next_comment_group(p)
	}

	return document, lines
}

visit_disabled :: proc(p: ^Printer, node: ^ast.Node) -> ^Document {
	disabled_text := p.disabled_lines[node.pos.line]

	if p.last_disabled_line + 1 == node.pos.line {
		return empty();
	}

	if disabled_text == "" {
		return empty()
	}

	move := move_line(p, node.pos)

	for comment_before_or_in_line(p, node.end.line) {
		next_comment_group(p)
	}

	p.last_disabled_line = node.pos.line
	
	p.source_position = node.end

	return cons(nest(-p.indentation_count, move), text(disabled_text))
}

@(private)
visit_decl :: proc(p: ^Printer, decl: ^ast.Decl, called_in_stmt := false) -> ^Document {
	using ast
	
	if decl == nil {
		return empty()
	}

	if decl.pos.line in p.disabled_lines {
		return visit_disabled(p, decl)
	}
	
	switch v in &decl.derived {
	case Expr_Stmt:
		document := move_line(p, decl.pos)
		return cons(document, visit_expr(p, v.expr))
	case When_Stmt:
		return visit_stmt(p, cast(^Stmt)decl)
	case Foreign_Import_Decl:
		document := empty()
		if len(v.attributes) > 0 {
			document = cons(document, visit_attributes(p, &v.attributes, v.pos))
		}

		document = cons(document, move_line(p, decl.pos))
		document = cons(document, cons_with_opl(text(v.foreign_tok.text), text(v.import_tok.text)))

		if v.name != nil {
			document = cons_with_opl(document, text_position(p, v.name.name, v.pos))
		}

		if len(v.fullpaths) > 1 {
			document = cons_with_nopl(document, text("{"))
			for path, i in v.fullpaths {
				document = cons(document, text(path))
				if i != len(v.fullpaths) - 1 {
					document = cons(document, cons(text(","), break_with_space()))
				} 
			}
			document = cons(document, text("}"))
		} else if len(v.fullpaths) == 1 {
			document = cons_with_nopl(document, text(v.fullpaths[0]))
		}

		return document
	case Foreign_Block_Decl:
		document := empty()
		if len(v.attributes) > 0 {
			document = cons(document, visit_attributes(p, &v.attributes, v.pos))
		}

		document = cons(document, move_line(p, decl.pos))
		document = cons(document, cons_with_opl(text("foreign"), visit_expr(p, v.foreign_library)))
		document = cons_with_nopl(document, visit_stmt(p, v.body))
		return document
	case Import_Decl:
		document := move_line(p, decl.pos)

		if v.name.text != "" {
			document = cons(document, text_token(p, v.import_tok))
			document = cons(document, break_with_space())
			document = cons(document, text_token(p, v.name))
			document = cons(document, break_with_space())
			document = cons(document, text(v.fullpath))
		} else {
			document = cons(document, text_token(p, v.import_tok))
			document = cons(document, break_with_space())
			document = cons(document, text(v.fullpath))
		}
		return document
	case Value_Decl:
		document := empty()
		if len(v.attributes) > 0 {
			document = cons(document, visit_attributes(p, &v.attributes, v.pos))
		}

		document = cons(document, move_line(p, decl.pos))

		lhs := empty()
		rhs := empty()

		if v.is_using {
			lhs = cons(lhs, cons(text("using"), break_with_no_newline()))
		}

		lhs = cons(lhs, visit_exprs(p, v.names, {.Add_Comma}))

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

			rhs = cons_with_nopl(rhs, visit_exprs(p, v.values, {.Add_Comma}, .Value_Decl))		
		} else if len(v.values) > 0 && v.type != nil {
			rhs = cons_with_nopl(rhs, cons_with_nopl(text(":"), visit_exprs(p, v.values, {.Add_Comma})))		
		} else {
			rhs = cons_with_nopl(rhs, visit_exprs(p, v.values, {.Add_Comma}, .Value_Decl))		
		}

		if is_values_binary(p, v.values) {
			return cons(document, fill_group(cons_with_opl(group(lhs), align(fill_group(rhs)))))
		} else {
			return cons(document, group(cons_with_nopl(group(lhs), group(rhs))))
		}		
	case:
		panic(fmt.aprint(decl.derived))
	}

	return empty()
}

@(private)
is_values_binary :: proc(p: ^Printer, list: []^ast.Expr) -> bool {
	for expr in list {
		if _, bin := expr.derived.(ast.Binary_Expr); bin {
			return true
		}
	}
	return false
}

@(private)
visit_exprs :: proc(p: ^Printer, list: []^ast.Expr, options := List_Options{}, called_from: Expr_Called_Type = .None) -> ^Document {
	if len(list) == 0 {
		return empty()
	}

	document := empty()

	for expr, i in list {

		if (.Enforce_Newline in options) {
			document = cons(document, visit_expr(p, expr, called_from, options))
		} else {
			document = cons_with_opl(document, visit_expr(p, expr, called_from, options))
		}

		if (i != len(list) - 1 || .Trailing in options) && .Add_Comma in options {
			document = cons(document, text(","))
		}

		if (i != len(list) - 1 && .Enforce_Newline in options) {
			comment, ok := visit_comments(p, list[i+1].pos, false)
			document = cons(document, cons(comment, newline(1)))
		}
	}

	return document
}

@(private)
visit_enum_exprs :: proc(p: ^Printer, list: []^ast.Expr, options := List_Options{}) -> ^Document {
	if len(list) == 0 {
		return empty()
	}

	document := empty()

	for expr, i in list {
		if (.Enforce_Newline in options) {
			alignment := get_possible_enum_alignment(p, list)

			if value, ok := expr.derived.(ast.Field_Value); ok && alignment > 0 {
				document = cons(document, cons_with_nopl(visit_expr(p, value.field), cons_with_nopl(cons(repeat_space(alignment - get_node_length(value.field)), text_position(p, "=", value.sep)), visit_expr(p, value.value))))
			} else {
				document = group(cons(document, visit_expr(p, expr, .None, options)))
			}
		} else {
			document = group(cons_with_opl(document, visit_expr(p, expr, .None, options)))
		}

		if (i != len(list) - 1 || .Trailing in options) && .Add_Comma in options {
			document = cons(document, text(","))
		}

		if (i != len(list) - 1 && .Enforce_Newline in options) {
			comment, ok := visit_comments(p, list[i+1].pos, false)
			document = cons(document, cons(comment, newline(1)))
		}
	}

	return document
}

@(private)
visit_comp_lit_exprs :: proc(p: ^Printer, list: []^ast.Expr, options := List_Options{}) -> ^Document {
	if len(list) == 0 {
		return empty()
	}

	document := empty()

	for expr, i in list {
		if (.Enforce_Newline in options) {
			alignment := get_possible_comp_lit_alignment(p, list)

			if value, ok := expr.derived.(ast.Field_Value); ok && alignment > 0 {
				document = cons(document, cons_with_nopl(visit_expr(p, value.field), cons_with_nopl(cons(repeat_space(alignment - get_node_length(value.field)), text_position(p, "=", value.sep)), visit_expr(p, value.value))))
			} else {
				document = group(cons(document, visit_expr(p, expr, .None, options)))
			}
		} else {
			document = group(cons_with_nopl(document, visit_expr(p, expr, .None, options)))
		}

		if (i != len(list) - 1 || .Trailing in options) && .Add_Comma in options {
			document = cons(document, text(","))
		}

		if (i != len(list) - 1 && .Enforce_Newline in options) {
			comment, ok := visit_comments(p, list[i+1].pos, false)
			document = cons(document, cons(comment, newline(1)))
		}
	}

	return document
}

@(private)
visit_attributes :: proc(p: ^Printer, attributes: ^[dynamic]^ast.Attribute, pos: tokenizer.Pos) -> ^Document {
	document := empty()
	if len(attributes) == 0 {
		return document
	}

	sort.sort(sort_attribute(attributes))
	document = cons(document, move_line(p, attributes[0].pos))

	for attribute, i in attributes {
		document = cons(document, cons(text("@"), text("(")))
		document = cons(document, visit_exprs(p, attribute.elems, {.Add_Comma}))
		document = cons(document, text(")"))

		if i != len(attributes) - 1 {
			document = cons(document, newline(1))
		} else if pos.line == attributes[0].pos.line {
			document = cons(document, newline(1))
		}
	}

	return document
}

@(private)
visit_stmt :: proc(p: ^Printer, stmt: ^ast.Stmt, block_type: Block_Type = .Generic, empty_block := false, block_stmt := false) -> ^Document {
	using ast

	if stmt == nil {
		return empty()
	}

	if stmt.pos.line in p.disabled_lines {
		return visit_disabled(p, stmt)
	}

	switch v in stmt.derived {
	case Import_Decl:
		return visit_decl(p, cast(^Decl)stmt, true)	 
	case Value_Decl:
		return visit_decl(p, cast(^Decl)stmt, true)
	case Foreign_Import_Decl:
		return visit_decl(p, cast(^Decl)stmt, true)
	case Foreign_Block_Decl:
		return visit_decl(p, cast(^Decl)stmt, true)
	}

	switch v in stmt.derived {
	case Using_Stmt:
		document := move_line(p, v.pos)
		document = cons(document, cons_with_nopl(text("using"), visit_exprs(p, v.list, {.Add_Comma})))
		return document
	case Block_Stmt:
		document := move_line(p, v.pos)

		if v.label != nil {
			document = cons(document, cons(visit_expr(p, v.label), cons(text(":"), break_with_space())))
		}

		if .Bounds_Check in v.state_flags {
			document = cons(document, cons(text("#bounds_check"), break_with_space()))
		}

		if !empty_block {
			document = cons(document, visit_begin_brace(p, v.pos, block_type, len(v.stmts)))
		}

		set_source_position(p, v.pos)

		block := visit_block_stmts(p, v.stmts, len(v.stmts) > 1)
		comment_end, _ := visit_comments(p, tokenizer.Pos {line = v.end.line, offset = v.end.offset}, false)

		if block_type == .Switch_Stmt && !p.config.indent_cases {
			document = cons(document, cons(block, comment_end))
		} else {
			document = cons(document, nest(p.indentation_count, cons(block, comment_end)))
		}

		if !empty_block {
			document = cons(document, visit_end_brace(p, v.end))
		}
		return document
	case If_Stmt:
		document := move_line(p, v.pos)

		if v.label != nil {
			document = cons(document, cons(visit_expr(p, v.label), cons(text(":"), break_with_space())))
		}

		if_document := text("if")

		if v.init != nil {
			if_document = cons_with_nopl(if_document, cons(group(visit_stmt(p, v.init)), cons(text(";"), break_with(""))))
		}

		if v.cond != nil {
			if_document = cons_with_nopl(if_document, hang(3, fill_group(visit_expr(p, v.cond))))
		}

		document = cons(document, group(if_document))

		uses_do := false

		if check_stmt, ok := v.body.derived.(Block_Stmt); ok {
			uses_do = check_stmt.uses_do
		}

		if uses_do && !p.config.convert_do {
			document = cons_with_nopl(document, cons_with_nopl(text("do"), visit_stmt(p, v.body, .If_Stmt, true)))
		} else {
			if uses_do {
				document = cons(document, newline(1))
			}

			set_source_position(p, v.body.pos)

			document = cons_with_nopl(document, visit_stmt(p, v.body, .If_Stmt))

			set_source_position(p, v.body.end)
		}

		if v.else_stmt != nil {

			if p.config.brace_style == .Allman || p.config.brace_style == .Stroustrup {
				document = cons(document, newline(1))
			}

			set_source_position(p, v.else_stmt.pos)

			if _, ok := v.else_stmt.derived.(ast.If_Stmt); ok {
				document = cons_with_opl(document, cons_with_nopl(text("else"), visit_stmt(p, v.else_stmt)))
			} else {
				document = cons_with_opl(document, cons_with_nopl(text("else"), visit_stmt(p, v.else_stmt)))
			}
		}
		return document
	case Switch_Stmt:
		document := move_line(p, v.pos)

		if v.label != nil {
			document = cons(document, cons(visit_expr(p, v.label), cons(text(":"), break_with_space())))
		}

		if v.partial {
			document = cons(document, cons(text("#partial"), break_with_space()))
		}

		document = cons(document, text("switch"))

		if v.init != nil {
			document = cons_with_opl(document, visit_stmt(p, v.init))
		}

		if v.init != nil && v.cond != nil {
			document = cons(document, text(";"))
		}

		document = cons_with_opl(document, visit_expr(p, v.cond))
		document = cons_with_nopl(document, visit_stmt(p, v.body, .Switch_Stmt))
		return document
	case Case_Clause:
		document := move_line(p, v.pos)
		document = cons(document, text("case"))

		if v.list != nil {
			document = cons_with_nopl(document, visit_exprs(p, v.list, {.Add_Comma}))
		}

		document = cons(document, text(v.terminator.text))

		if len(v.body) != 0 {
			set_source_position(p, v.body[0].pos)
			document = cons(document, nest(p.indentation_count,  cons(newline(1), visit_block_stmts(p, v.body))))
		}

		return document
	case Type_Switch_Stmt:
		document := move_line(p, v.pos)

		if v.label != nil {
			document = cons(document, cons(visit_expr(p, v.label), cons(text(":"), break_with_space())))
		}

		if v.partial {
			document = cons(document, cons(text("#partial"), break_with_space()))
		}

		document = cons(document, text("switch"))

		document = cons_with_nopl(document, visit_stmt(p, v.tag))
		document = cons_with_nopl(document, visit_stmt(p, v.body, .Switch_Stmt))
		return document
	case Assign_Stmt:
		document := move_line(p, v.pos)

		assign_document := group(cons_with_nopl(visit_exprs(p, v.lhs, {.Add_Comma}), text(v.op.text)))

		if block_stmt {
			assign_document = fill_group(cons(assign_document, align(cons(break_with_space(), visit_exprs(p, v.rhs, {.Add_Comma})))))
		} else {
			assign_document = cons_with_nopl(assign_document, visit_exprs(p, v.rhs, {.Add_Comma}))
		}
		return cons(document, group(assign_document))
	case Expr_Stmt:
		document := move_line(p, v.pos)
		document = cons(document, visit_expr(p, v.expr))
		return document
	case For_Stmt:
		document := move_line(p, v.pos)

		if v.label != nil {
			document = cons(document, cons(visit_expr(p, v.label), cons(text(":"), break_with_space())))
		}

		for_document := text("for")

		if v.init != nil {
			set_source_position(p, v.init.pos);
			for_document = cons_with_nopl(for_document, cons(group(visit_stmt(p, v.init)), cons(text(";"), break_with(""))))
		} else if v.post != nil {
			for_document = cons_with_nopl(for_document, text(";"))
		}

		if v.cond != nil {
			set_source_position(p, v.cond.pos);
			for_document = cons_with_nopl(for_document, fill_group(visit_expr(p, v.cond)))
		}

		if v.post != nil {
			set_source_position(p, v.post.pos);
			for_document = cons(for_document, text(";"))
			for_document = cons_with_opl(for_document, group(visit_stmt(p, v.post)))
		} else if v.post == nil && v.cond != nil && v.init != nil {
			for_document = cons(for_document, text(";"))
		}

		document = cons(document, group(hang(4, for_document)))

		uses_do := false

		if check_stmt, ok := v.body.derived.(Block_Stmt); ok {
			uses_do = check_stmt.uses_do
		}

		if uses_do && !p.config.convert_do {
			document = cons_with_nopl(document, cons_with_nopl(text("do"), visit_stmt(p, v.body, {}, true)))
		} else {
			if uses_do {
				document = cons(document, newline(1))
			}

			set_source_position(p, v.body.pos)
			document = cons_with_nopl(document,  visit_stmt(p, v.body))
			set_source_position(p, v.body.end)
		}

		return document
	case Inline_Range_Stmt:
		document := move_line(p, v.pos)

		if v.label != nil {
			document = cons(document, cons(visit_expr(p, v.label), cons(text(":"), break_with_space())))
		}

		document = cons(document, text("#unroll"))
		document = cons_with_nopl(document, text("for"))

		document = cons_with_nopl(document, visit_expr(p, v.val0))

		if v.val1 != nil {
			document = cons(document, cons_with_opl(text(","), visit_expr(p, v.val1)))
		}

		document = cons_with_nopl(document, text("in"))

		document = cons_with_nopl(document, visit_expr(p, v.expr))

		uses_do := false

		if check_stmt, ok := v.body.derived.(Block_Stmt); ok {
			uses_do = check_stmt.uses_do
		}

		if uses_do && !p.config.convert_do {
			document = cons_with_nopl(document, cons_with_nopl(text("do"), visit_stmt(p, v.body, {}, true)))
		} else {
			if uses_do {
				document = cons(document, newline(1))
			}

			set_source_position(p, v.body.pos)
			document = cons_with_nopl(document,  visit_stmt(p, v.body))
			set_source_position(p, v.body.end)
		}

		return document
	case Range_Stmt:
		document := move_line(p, v.pos)

		if v.label != nil {
			document = cons(document, cons(visit_expr(p, v.label), cons(text(":"), break_with_space())))
		}

		document = cons(document, text("for"))

		if len(v.vals) >= 1 {
			document = cons_with_opl(document, visit_expr(p, v.vals[0]))
		}

		if len(v.vals) >= 2 {
			document = cons(document, cons_with_opl(text(","), visit_expr(p, v.vals[1])))
		}

		document = cons_with_opl(document, text("in"))

		document = cons_with_opl(document, visit_expr(p, v.expr))
		
		uses_do := false

		if check_stmt, ok := v.body.derived.(Block_Stmt); ok {
			uses_do = check_stmt.uses_do
		}

		if uses_do && !p.config.convert_do {
			document = cons_with_nopl(document, cons_with_nopl(text("do"), visit_stmt(p, v.body, {}, true)))
		} else {
			if uses_do {
				document = cons(document, newline(1))
			}

			set_source_position(p, v.body.pos)
			document = cons_with_nopl(document,  visit_stmt(p, v.body))
			set_source_position(p, v.body.end)
		}

		return document
	case Return_Stmt:
		document := move_line(p, v.pos)

		document = cons(document, text("return"))

		if v.results != nil {
			document = cons_with_opl(document, visit_exprs(p, v.results, {.Add_Comma}))
		}

		return document
	case Defer_Stmt:
		document := move_line(p, v.pos)
		document = cons(document, text("defer"))
		document = cons_with_opl(document, visit_stmt(p, v.stmt))
		return document
	case When_Stmt:
		document := move_line(p, v.pos)

		document = cons(document, cons_with_opl(text("when"), visit_expr(p, v.cond)))

		document = cons_with_nopl(document, visit_stmt(p, v.body))

		if v.else_stmt != nil {
			if p.config.brace_style == .Allman {
				document = cons(document, newline(1))
			}

			set_source_position(p, v.else_stmt.pos)

			document = cons(document, cons_with_opl(text("else"), visit_stmt(p, v.else_stmt)))
		}
		return document
	case Branch_Stmt:
		document := move_line(p, v.pos)

		document = cons(document, text(v.tok.text))

		if v.label != nil {
			document = cons_with_nopl(document, visit_expr(p, v.label))
		}
		return document
	case:
		panic(fmt.aprint(stmt.derived))
	}

	set_source_position(p, stmt.end)

	return empty()
}

@(private)
push_where_clauses :: proc(p: ^Printer, clauses: []^ast.Expr) -> ^Document {
	if len(clauses) == 0 {
		return empty()
	}
	
	return group(nest(p.indentation_count, cons_with_nopl(text("where"), visit_exprs(p, clauses, {.Add_Comma, .Enforce_Newline}))))
}

@(private)
visit_poly_params :: proc(p: ^Printer, poly_params: ^ast.Field_List) -> ^Document {
	if poly_params != nil {
		return cons(text("("), cons(visit_field_list(p, poly_params, {.Add_Comma, .Enforce_Poly_Names}), text(")")))
	} else {
		return empty()
	}
}

@(private)
visit_expr :: proc(p: ^Printer, expr: ^ast.Expr, called_from: Expr_Called_Type = .None, options := List_Options{}) -> ^Document {
	using ast

	if expr == nil {
		return empty()
	}

	set_source_position(p, expr.pos)

	defer {
		set_source_position(p, expr.end);
	}

	switch v in expr.derived {
	case Inline_Asm_Expr:
		document := cons(text_token(p, v.tok), text("("))
		document = cons(document, visit_exprs(p, v.param_types, {.Add_Comma}))
		document = cons(document, text(")"))
		document = cons_with_opl(document, cons(text("-"), text(">")))
		document = cons_with_opl(document, visit_expr(p, v.return_type))

		document = cons(document, text("{"))
		document = cons(document, visit_expr(p, v.asm_string))
		document = cons(document, text(","))
		document = cons(document, visit_expr(p, v.constraints_string))
		document = cons(document, text("}"))
	case Undef:
		return text("---")
	case Auto_Cast:
		return cons_with_nopl(text_token(p, v.op), visit_expr(p, v.expr))
	case Ternary_If_Expr:
		document := visit_expr(p, v.cond)
		document = cons_with_opl(document, text_token(p, v.op1))
		document = cons_with_opl(document, visit_expr(p, v.x))
		document = cons_with_opl(document, text_token(p, v.op2))
		document = cons_with_opl(document, visit_expr(p, v.y))
		return document
	case Ternary_When_Expr:
		document := visit_expr(p, v.cond)
		document = cons_with_opl(document, text_token(p, v.op1))
		document = cons_with_opl(document, visit_expr(p, v.x))
		document = cons_with_opl(document, text_token(p, v.op2))
		document = cons_with_opl(document, visit_expr(p, v.y))
		return document
	case Or_Else_Expr:
		document := visit_expr(p, v.x)
		document = cons_with_opl(document, text_token(p, v.token))
		document = cons_with_opl(document, visit_expr(p, v.y))
		return document
	case Or_Return_Expr:
		return cons_with_opl(visit_expr(p, v.expr), text_token(p, v.token))
	case Selector_Call_Expr:
		document := visit_expr(p, v.call.expr)
		document = cons(document, text("("))
		document = cons(document, visit_exprs(p, v.call.args, {.Add_Comma}))
		document = cons(document, text(")"))
		return document
	case Ellipsis:
		return cons_with_opl(text("..."), visit_expr(p, v.expr))
	case Relative_Type:
		return cons_with_opl(visit_expr(p, v.tag), visit_expr(p, v.type))
	case Slice_Expr:
		document := visit_expr(p, v.expr)
		document = cons(document, text("["))
		document = cons(document, visit_expr(p, v.low))
		document = cons(document, text(v.interval.text))
	
		if v.high != nil {
			document = cons(document, visit_expr(p, v.high))
		}
		document = cons(document, text("]"))
		return document
	case Ident:
		if .Enforce_Poly_Names in options {
			return cons(text("$"), text(v.name))
		} else {
			return text_position(p, v.name, v.pos)
		}
	case Deref_Expr:
		return cons(visit_expr(p, v.expr), text_token(p, v.op))
	case Type_Cast:
		document := cons(text_token(p, v.tok), text("("))
		document = cons(document, visit_expr(p, v.type))
		document = cons(document, text(")"))
		document = cons(document, visit_expr(p, v.expr))
		return document
	case Basic_Directive:
		return cons(text_token(p, v.tok), text_position(p, v.name, v.pos))
	case Distinct_Type:
		return cons_with_opl(text_position(p, "distinct", v.pos), visit_expr(p, v.type))
	case Dynamic_Array_Type:
		document := visit_expr(p, v.tag)
		document = cons(document, text("["))
		document = cons(document, text("dynamic"))
		document = cons(document, text("]"))
		document = cons(document, visit_expr(p, v.elem))
		return document
	case Bit_Set_Type:
		document := text_position(p, "bit_set", v.pos)
		document = cons(document, text("["))
		document = cons(document, visit_expr(p, v.elem))

		if v.underlying != nil {
			document = cons(document, cons(text(";"), visit_expr(p, v.underlying)))
		}

		document = cons(document, text("]"))
		return document
	case Union_Type:
		document := text_position(p, "union", v.pos)
		
		document = cons(document, visit_poly_params(p, v.poly_params))

		if v.is_maybe {
			document = cons_with_opl(document, text("#maybe"))
		}

		document = cons_with_nopl(document, push_where_clauses(p, v.where_clauses))

		if v.variants != nil && (len(v.variants) == 0 || v.pos.line == v.end.line) {
			document = cons_with_nopl(document, text("{"))
			document = cons(document, visit_exprs(p, v.variants, {.Add_Comma}))
			document = cons(document, text("}"))
		} else if v.variants != nil {
			document = cons_with_opl(document, visit_begin_brace(p, v.pos, .Generic))
			
			set_source_position(p, v.variants[0].pos)

			document = cons(document, nest(p.indentation_count, cons(newline_position(p, 1, v.variants[0].pos), visit_exprs(p, v.variants, {.Add_Comma, .Trailing, .Enforce_Newline}))))
			document = cons(document, visit_end_brace(p, v.end, 1))
		}
		return document
	case Enum_Type:
		document := text_position(p, "enum", v.pos)

		if v.base_type != nil {
			document = cons_with_nopl(document, visit_expr(p, v.base_type))
		}

		if len(v.fields) == 0 {
			document = cons_with_nopl(document, text("{"))
			document = cons(document, visit_enum_exprs(p, v.fields, {.Add_Comma}))
			document = cons(document, text("}"))
		} else {
			document = cons(document, cons(break_with_space(), visit_begin_brace(p, v.pos, .Generic)))		
			set_source_position(p, v.fields[0].pos)
			document = cons(document, nest(p.indentation_count, cons(newline_position(p, 1, v.fields[0].pos), visit_enum_exprs(p, v.fields, {.Add_Comma, .Trailing, .Enforce_Newline}))))
			document = cons(document, visit_end_brace(p, v.end, 1))
		}

		set_source_position(p, v.end)
		return document
	case Struct_Type:
		document := text_position(p, "struct", v.pos)
	
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

		document = cons_with_nopl(document, push_where_clauses(p, v.where_clauses))

		if v.fields != nil && len(v.fields.list) == 0 {
			document = cons_with_nopl(document, text("{"))
			document = cons(document, visit_field_list(p, v.fields, {.Add_Comma}))
			document = cons(document, text("}"))
		} else if v.fields != nil {
			document = cons(document, cons(break_with_space(), visit_begin_brace(p, v.pos, .Generic)))
			
			set_source_position(p, v.fields.pos)

			document = cons(document, nest(p.indentation_count, cons(newline_position(p, 1, v.fields.pos), visit_field_list(p, v.fields, {.Add_Comma, .Trailing, .Enforce_Newline}))))
			document = cons(document, visit_end_brace(p, v.end, 1))
		}

		set_source_position(p, v.end)
		return document
	case Proc_Lit:
		document := empty()

		switch v.inlining {
		case .None:
		case .Inline:
			document = cons(document, text("#force_inline"))
		case .No_Inline:
			document = cons(document, text("#force_no_inline"))
		}

		document = cons(document, visit_proc_type(p, v.type^))
		document = cons_with_nopl(document, push_where_clauses(p, v.where_clauses))

		if v.body != nil {
			set_source_position(p, v.body.pos)
			document = cons_with_nopl(document, group(visit_stmt(p, v.body, .Proc)))
		} else {
			document = cons_with_nopl(document, text("---"))
		}

		return document
	case Proc_Type:
		return group(visit_proc_type(p, v))
	case Basic_Lit:
		return text_token(p, v.tok)
	case Binary_Expr:
		return visit_binary_expr(p, v)
	case Implicit_Selector_Expr:
		return cons(text("."), text_position(p, v.field.name, v.field.pos))
	case Call_Expr:
		document := visit_expr(p, v.expr)
		document = cons(document, text("("))
		document = cons(document, nest(p.indentation_count, cons(break_with(""), visit_call_exprs(p, v.args, v.ellipsis.kind == .Ellipsis))))
		document = cons(document, cons(break_with(""), text(")")))
		return group(document)
	case Typeid_Type:
		document := text("typeid")

		if v.specialization != nil {
			document = cons(document, cons(text("/"), visit_expr(p, v.specialization)))			
		}
		return document
	case Selector_Expr:
		return cons(visit_expr(p, v.expr), cons(text_token(p, v.op), visit_expr(p, v.field)))
	case Paren_Expr:
		return cons(text("("), cons(visit_expr(p, v.expr), text(")")))
	case Index_Expr:
		document := visit_expr(p, v.expr)
		document = cons(document, text("["))
		document = cons(document, visit_expr(p, v.index))
		document = cons(document, text("]"))
		return document
	case Proc_Group:
		document := text_token(p, v.tok)

		if len(v.args) != 0 {
			document = cons(document, cons(break_with_space(), visit_begin_brace(p, v.pos, .Generic)))
			set_source_position(p, v.args[0].pos)
			document = cons(document, nest(p.indentation_count, cons(newline_position(p, 1, v.args[0].pos), visit_exprs(p, v.args, {.Add_Comma, .Trailing, .Enforce_Newline}))))
			document = cons(document, visit_end_brace(p, v.end, 1))
		} else {
			document = cons(document, text("{"))
			document = cons(document, visit_exprs(p, v.args, {.Add_Comma}))
			document = cons(document, text("}"))
		}
		return document
	case Comp_Lit:
		document := empty()
		if v.type != nil {
			document = cons(document, visit_expr(p, v.type))
		}

		//If we call from the value declartion, we want it to be nicly newlined and aligned
		if called_from == .Value_Decl && len(v.elems) != 0 {
			document = cons(document, cons(break_with_space(), visit_begin_brace(p, v.pos, .Generic)))
			set_source_position(p, v.elems[0].pos)
			document = cons(document, nest(p.indentation_count, cons(newline_position(p, 1, v.elems[0].pos), visit_comp_lit_exprs(p, v.elems, {.Add_Comma, .Trailing, .Enforce_Newline}))))
			document = cons(document, visit_end_brace(p, v.end, 1))
		} else {
			document = cons(document, text("{"))
			document = cons(document, nest(p.indentation_count, cons(break_with(""), visit_exprs(p, v.elems, {.Add_Comma}))))
			document = cons(document, cons(cons(if_break(","), break_with("")), text("}")))
			document = group(document)
		}

		return document
	case Unary_Expr:
		return cons(text_token(p, v.op), visit_expr(p, v.expr))
	case Field_Value:
		document := cons_with_nopl(visit_expr(p, v.field), cons_with_nopl(text_position(p, "=", v.sep), visit_expr(p, v.value)))
		return document
	case Type_Assertion:
		document := visit_expr(p, v.expr)

		if unary, ok := v.type.derived.(Unary_Expr); ok && unary.op.text == "?" {
			document = cons(document, cons(text("."), visit_expr(p, v.type)))
		} else {
			document = cons(document, text("."))
			document = cons(document, text("("))
			document = cons(document, visit_expr(p, v.type))
			document = cons(document, text(")"))
		}
		return document
	case Pointer_Type:
		return cons(text("^"), visit_expr(p, v.elem))
	case Multi_Pointer_Type:
		return cons(text("[^]"), visit_expr(p, v.elem))
	case Implicit:
		return text_token(p, v.tok)
	case Poly_Type:
		document := cons(text("$"), visit_expr(p, v.type))

		if v.specialization != nil {
			document = cons(document, text("/"))
			document = cons(document, visit_expr(p, v.specialization))
		}
		return document
	case Array_Type:
		document := visit_expr(p, v.tag)
		document = cons(document, text("["))
		document = cons(document, visit_expr(p, v.len))
		document = cons(document, text("]"))
		document = cons(document, visit_expr(p, v.elem))
		return document
	case Map_Type:
		document := cons(text("map"), text("["))
		document = cons(document, visit_expr(p, v.key))
		document = cons(document, text("]"))
		document = cons(document, visit_expr(p, v.value))
		return document
	case Helper_Type:
		return visit_expr(p, v.type)
	case Matrix_Type:
		document := text_position(p, "matrix", v.pos)
		document = cons(document, text("["))
		document = cons(document, visit_expr(p, v.row_count))
		document = cons(document, text(","))
		document = cons_with_opl(document, visit_expr(p, v.column_count))
		document = cons(document, text("]"))
		document = cons(document, visit_expr(p, v.elem))
		return document
	case Matrix_Index_Expr:
		document := visit_expr(p, v.expr)
		document = cons(document, text("["))
		document = cons(document, visit_expr(p, v.row_index))
		document = cons(document, text(","))
		document = cons_with_opl(document, visit_expr(p, v.column_index))
		document = cons(document, text("]"))
		return document
	case:
		panic(fmt.aprint(expr.derived))
	}

	return empty()
}

visit_begin_brace :: proc(p: ^Printer, begin: tokenizer.Pos, type: Block_Type, count := 0, same_line_spaces_before := 1) -> ^Document {
	set_source_position(p, begin)

	newline_braced := p.config.brace_style == .Allman
	newline_braced |= p.config.brace_style == .K_And_R && type == .Proc
	newline_braced &= p.config.brace_style != ._1TBS

	if newline_braced {
		document := newline(1)
		document = cons(document, text("{"))
		return document
	} else {
		return text("{")
	}
}

visit_end_brace :: proc(p: ^Printer, end: tokenizer.Pos, limit := 0) -> ^Document {
	if limit == 0 {
		return cons(move_line(p, end), text("}"))
	} else {
		document, newlined := move_line_limit(p, end, limit)
		if !newlined {
			return cons(document, cons(newline(1), text("}")))
		} else {
			return cons(document, text("}"))
		}
	}
}

visit_block_stmts :: proc(p: ^Printer, stmts: []^ast.Stmt, split := false) -> ^Document {
	document := empty()

	for stmt, i in stmts {
		document = cons(document, group(visit_stmt(p, stmt, .Generic, false, true)))
	}

	return document
}

List_Option :: enum u8 {
	Add_Comma,
	Trailing,
	Enforce_Newline,
	Enforce_Poly_Names,
}

List_Options :: distinct bit_set[List_Option]

visit_field_list :: proc(p: ^Printer, list: ^ast.Field_List, options := List_Options{}) -> ^Document {
	document := empty()
	if list.list == nil {
		return document
	}

	for field, i in list.list {

		align := empty()

		p.source_position = field.pos

		if .Using in field.flags {
			document = cons(document, cons(text("using"), break_with_no_newline()))
		}

		name_options := List_Options{.Add_Comma}
		if .Enforce_Poly_Names in options {
			name_options += {.Enforce_Poly_Names}
		}

		if (.Enforce_Newline in options) {
			alignment := get_possible_field_alignment(p, list.list)

			if alignment > 0 {
				length := 0
				for name in field.names {
					length += get_node_length(name) + 2
					if .Using in field.flags {
						length += 6
					}
				}
				align = repeat_space(alignment - length)
			} 
			document = cons(document, visit_exprs(p, field.names, name_options))			
		} else {
			document = cons_with_opl(document, visit_exprs(p, field.names, name_options))
		}

		if field.type != nil {
			if len(field.names) != 0 {
				document = cons(document, cons(text(":"), align))
			}
			document = cons_with_opl(document, visit_expr(p, field.type))
		} else {
			document = cons(document, cons(text(":"), text("=")))
			document = cons_with_opl(document, visit_expr(p, field.default_value))
		}

		if field.tag.text != "" {
			document = cons_with_nopl(document, text_token(p, field.tag))
		}

		if (i != len(list.list) - 1 || .Trailing in options) && .Add_Comma in options {
			document = cons(document, text(","))
		}

		if i != len(list.list) - 1 && .Enforce_Newline in options {
			comment, ok := visit_comments(p, list.list[i+1].pos, false)
			document = cons(document, cons(comment, newline(1)))
		} 
	}
	return document
}

visit_proc_type :: proc(p: ^Printer, proc_type: ast.Proc_Type) -> ^Document {

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

	document = cons(document, nest(p.indentation_count, cons(break_with(""), visit_signature_list(p, proc_type.params, false))))
	document = group(cons(document, cons(break_with(""), text(")"))))

	if proc_type.results != nil {
		document = cons_with_nopl(document, text("-"))
		document = cons(document, text(">"))

		use_parens := false

		if len(proc_type.results.list) > 1 {
			use_parens = true
		} else if len(proc_type.results.list) == 1 {
			for name in proc_type.results.list[0].names {
				if ident, ok := name.derived.(ast.Ident); ok {
					if ident.name != "_" {
						use_parens = true
					}
				}
			}
		}

		if use_parens {
			document = cons_with_nopl(document, text("("))
			document = cons(document, nest(p.indentation_count, cons(break_with(""), visit_signature_list(p, proc_type.results))))
			document = group(cons(document, cons(break_with(""), text(")"))))
		} else {
			document = cons(document, group(nest(p.indentation_count, cons(break_with(" "), group(visit_signature_list(p, proc_type.results))))))
		}
	}

	return document
}

visit_binary_expr :: proc(p: ^Printer, binary: ast.Binary_Expr) -> ^Document {
	lhs: ^Document
	rhs: ^Document

	if v, ok := binary.left.derived.(ast.Binary_Expr); ok {
		lhs = visit_binary_expr(p, v)
	} else {
		lhs = visit_expr(p, binary.left)
	}

	if v, ok := binary.right.derived.(ast.Binary_Expr); ok {
		rhs = visit_binary_expr(p, v)
	} else {
		rhs = visit_expr(p, binary.right)
	}

	op := text(binary.op.text)

	return cons_with_nopl(lhs, cons_with_opl(op, rhs))
}

visit_call_exprs :: proc(p: ^Printer, list: []^ast.Expr, ellipsis := false) -> ^Document {
	document := empty()

	for expr, i in list {
		if i == len(list) - 1 && ellipsis {
			document = cons(document, text("..."))
		}
		document = cons(document, visit_expr(p, expr))
		
		if i != len(list) - 1 {
			document = cons(document, text(","))
			document = cons(document, break_with_space())
		} else {
			document = cons(document, if_break(","))
		}	

	}
	return document
}

visit_signature_list :: proc(p: ^Printer, list: ^ast.Field_List, remove_blank := true) -> ^Document {
	document := empty()

	for field, i in list.list {

		if .Using in field.flags {
			document = cons(document, cons(text("using"), break_with_no_newline()))
		}

		named := false

		for name in field.names {
			if ident, ok := name.derived.(ast.Ident); ok {
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
			document = cons(document, visit_exprs(p, field.names, {.Add_Comma}))

			if len(field.names) != 0 && field.type != nil {
				document = cons(document, cons(text(":"), break_with_no_newline()))
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

		if i != len(list.list) - 1 {
			document = cons(document, cons(text(","), break_with_space()))
		} else {
			document = cons(document, if_break(","))
		}	
	}


	return document
}

repeat_space :: proc(amount: int) -> ^Document {
	document := empty()
	for i := 0; i < amount; i += 1 {
		document = cons(document, break_with_no_newline())
	}
	return document
}

get_node_length :: proc(node: ^ast.Node) -> int {
	switch v in node.derived {
	case ast.Ident:
		return len(v.name)
	case ast.Basic_Lit:
		return len(v.tok.text)
	case ast.Binary_Expr:
		return 0
	case: 
		panic(fmt.aprintf("unhandled get_node_length case %v", node.derived))
	}
}

get_possible_field_alignment :: proc(p: ^Printer, fields: []^ast.Field) -> int {
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

get_possible_comp_lit_alignment :: proc(p: ^Printer, exprs: []^ast.Expr) -> int {
	longest_name := 0

	for expr in exprs {

		value, ok := expr.derived.(ast.Field_Value)

		if !ok {
			return 0
		}

		if _, ok := value.value.derived.(ast.Comp_Lit); ok {
			return 0
		}

		longest_name = max(longest_name, get_node_length(value.field))
	}

	return longest_name
}

get_possible_enum_alignment :: proc(p: ^Printer, exprs: []^ast.Expr) -> int {
	longest_name := 0

	for expr in exprs {

		value, ok := expr.derived.(ast.Field_Value)

		if !ok {
			return 0
		}

		longest_name = max(longest_name, get_node_length(value.field))
	}

	return longest_name
}
