package server

import "core:log"
import "core:odin/ast"
import "core:odin/parser"
import "core:odin/tokenizer"
import "core:strings"
import "core:unicode/utf8"

import "src:common"

DocumentPositionContextHint :: enum {
	Completion,
	SignatureHelp,
	Definition,
	Hover,
}

DocumentPositionContext :: struct {
	file:                   ast.File,
	position:               common.AbsolutePosition,
	nested_position:        common.AbsolutePosition, //When doing the non-mutable local gathering we still need to know where in the nested block the position is.
	line:                   int,
	function:               ^ast.Proc_Lit, //used to help with type resolving in function scope
	functions:              [dynamic]^ast.Proc_Lit, //stores all the functions that have been iterated through to find the position
	selector:               ^ast.Expr, //used for completion
	selector_expr:          ^ast.Node,
	identifier:             ^ast.Node,
	label:                  ^ast.Ident,
	implicit_context:       ^ast.Implicit,
	index:                  ^ast.Index_Expr,
	previous_index:         ^ast.Index_Expr,
	tag:                    ^ast.Node,
	field:                  ^ast.Expr, //used for completion
	call:                   ^ast.Expr, //used for signature help
	returns:                ^ast.Return_Stmt, //used for completion
	comp_lit:               ^ast.Comp_Lit, //used for completion
	parent_comp_lit:        ^ast.Comp_Lit, //used for completion
	basic_lit:              ^ast.Basic_Lit,
	struct_type:            ^ast.Struct_Type,
	union_type:             ^ast.Union_Type,
	bitset_type:            ^ast.Bit_Set_Type,
	enum_type:              ^ast.Enum_Type,
	field_value:            ^ast.Field_Value,
	bit_field_type:         ^ast.Bit_Field_Type,
	implicit:               bool, //used for completion
	arrow:                  bool,
	binary:                 ^ast.Binary_Expr, //used for completion
	parent_binary:          ^ast.Binary_Expr, //used for completion
	assign:                 ^ast.Assign_Stmt, //used for completion
	switch_stmt:            ^ast.Switch_Stmt, //used for completion
	switch_type_stmt:       ^ast.Type_Switch_Stmt, //used for completion
	case_clause:            ^ast.Case_Clause, //used for completion
	value_decl:             ^ast.Value_Decl, //used for completion
	implicit_selector_expr: ^ast.Implicit_Selector_Expr,
	abort_completion:       bool,
	hint:                   DocumentPositionContextHint,
	global_lhs_stmt:        bool,
	import_stmt:            ^ast.Import_Decl,
	type_cast:              ^ast.Type_Cast,
	call_commas:            []int,
}

get_document_position_decls :: proc(decls: []^ast.Stmt, position_context: ^DocumentPositionContext) -> bool {
	exists_in_decl := false
	for decl in decls {
		if position_in_node(decl, position_context.position) {
			get_document_position(decl, position_context)
			exists_in_decl = true
			#partial switch v in decl.derived {
			case ^ast.Expr_Stmt:
				position_context.global_lhs_stmt = true
			}
			break
		}
	}
	return exists_in_decl
}

/*
	Figure out what exactly is at the given position and whether it is in a function, struct, etc.
*/
get_document_position_context :: proc(
	document: ^Document,
	position: common.Position,
	hint: DocumentPositionContextHint,
) -> (
	DocumentPositionContext,
	bool,
) {
	position_context: DocumentPositionContext

	position_context.hint = hint
	position_context.file = document.ast
	position_context.line = position.line

	position_context.functions = make([dynamic]^ast.Proc_Lit, context.temp_allocator)

	absolute_position, ok := common.get_absolute_position(position, document.text)

	if !ok {
		log.error("failed to get absolute position")
		return position_context, false
	}

	position_context.position = absolute_position

	exists_in_decl := get_document_position_decls(document.ast.decls[:], &position_context)

	for import_stmt in document.ast.imports {
		if position_in_node(import_stmt, position_context.position) {
			position_context.import_stmt = import_stmt
			break
		}
	}

	if !exists_in_decl && position_context.import_stmt == nil {
		position_context.abort_completion = true
	}

	if !position_in_node(position_context.comp_lit, position_context.position) {
		position_context.comp_lit = nil
	}

	if !position_in_node(position_context.parent_comp_lit, position_context.position) {
		position_context.parent_comp_lit = nil
	}

	if !position_in_node(position_context.assign, position_context.position) {
		position_context.assign = nil
	}

	if !position_in_node(position_context.binary, position_context.position) {
		position_context.binary = nil
	}

	if !position_in_node(position_context.parent_binary, position_context.position) {
		position_context.parent_binary = nil
	}

	if hint == .Completion && position_context.selector == nil && position_context.field == nil {
		fallback_position_context_completion(document, position, &position_context)
	}

	if (hint == .SignatureHelp || hint == .Completion) && position_context.call == nil {
		fallback_position_context_signature(document, position, &position_context)
	}

	if hint == .SignatureHelp {
		get_call_commas(&position_context, document)
	}

	return position_context, true
}

//terrible fallback code
fallback_position_context_completion :: proc(
	document: ^Document,
	position: common.Position,
	position_context: ^DocumentPositionContext,
) {
	paren_count: int
	bracket_count: int
	end: int
	start: int
	empty_dot: bool
	empty_arrow: bool
	last_dot: bool
	last_arrow: bool
	dots_seen: int
	partial_arrow: bool

	i := position_context.position - 1

	end = i

	for i > 0 {
		c := position_context.file.src[i]

		if c == '(' && paren_count == 0 {
			start = i + 1
			break
		} else if c == '[' && bracket_count == 0 {
			start = i + 1
			break
		} else if c == ']' && !last_dot && !last_arrow {
			start = i + 1
			break
		} else if c == ')' && !last_dot && !last_arrow {
			start = i + 1
			break
		} else if c == ')' {
			paren_count -= 1
		} else if c == '(' {
			paren_count += 1
		} else if c == '[' {
			bracket_count += 1
		} else if c == ']' {
			bracket_count -= 1
		} else if c == '.' {
			dots_seen += 1
			last_dot = true
			i -= 1
			continue
		} else if position_context.file.src[max(0, i - 1)] == '-' && c == '>' {
			last_arrow = true
			i -= 2
			continue
		}

		//ignore everything in the bracket
		if bracket_count != 0 || paren_count != 0 {
			i -= 1
			continue
		}

		//yeah..
		if c == ' ' ||
		   c == '{' ||
		   c == ',' ||
		   c == '}' ||
		   c == '^' ||
		   c == ':' ||
		   c == '\n' ||
		   c == '\r' ||
		   c == '\t' ||
		   c == '=' ||
		   c == '<' ||
		   c == '-' ||
		   c == '!' ||
		   c == '+' ||
		   c == '&' ||
		   c == '|' {
			start = i + 1
			break
		} else if c == '>' {
			partial_arrow = true
		}

		last_dot = false
		last_arrow = false

		i -= 1
	}

	if i >= 0 && position_context.file.src[end] == '.' {
		empty_dot = true
		end -= 1
	} else if i >= 0 && position_context.file.src[max(0, end - 1)] == '-' && position_context.file.src[end] == '>' {
		empty_arrow = true
		end -= 2
		position_context.arrow = true
	}

	begin_offset := max(0, start)
	end_offset := max(start, end + 1)
	line_offset := begin_offset

	if line_offset < len(position_context.file.src) {
		for line_offset > 0 {
			c := position_context.file.src[line_offset]
			if c == '\n' || c == '\r' {
				line_offset += 1
				break
			}
			line_offset -= 1
		}
	}

	str := position_context.file.src[0:end_offset]

	if empty_dot && end_offset - begin_offset == 0 {
		position_context.implicit = true
		return
	}

	s := string(position_context.file.src[begin_offset:end_offset])

	if !partial_arrow {
		only_whitespaces := true

		for r in s {
			if !strings.is_space(r) {
				only_whitespaces = false
			}
		}

		if only_whitespaces {
			return
		}
	}

	p := parser.Parser {
		err   = common.parser_warning_handler, //empty
		warn  = common.parser_warning_handler, //empty
		flags = {.Optional_Semicolons},
		file  = &position_context.file,
	}

	tokenizer.init(&p.tok, str, position_context.file.fullpath, common.parser_warning_handler)

	p.tok.ch = ' '
	p.tok.line_count = position.line + 1
	p.tok.line_offset = line_offset
	p.tok.offset = begin_offset
	p.tok.read_offset = begin_offset

	tokenizer.advance_rune(&p.tok)

	if p.tok.ch == utf8.RUNE_BOM {
		tokenizer.advance_rune(&p.tok)
	}

	parser.advance_token(&p)

	context.allocator = context.temp_allocator

	e := parser.parse_expr(&p, true)

	if empty_dot || empty_arrow {
		position_context.selector = e
	} else if s, ok := e.derived.(^ast.Selector_Expr); ok {
		position_context.selector = s.expr
		position_context.field = s.field
	} else if s, ok := e.derived.(^ast.Implicit_Selector_Expr); ok {
		position_context.implicit = true
		position_context.implicit_selector_expr = s
	} else if s, ok := e.derived.(^ast.Tag_Expr); ok {
		position_context.tag = s.expr
	} else if bad_expr, ok := e.derived.(^ast.Bad_Expr); ok {
		//this is most likely because of use of 'in', 'context', etc.
		//try to go back one dot.

		src_with_dot := string(position_context.file.src[0:min(len(position_context.file.src), end_offset + 1)])
		last_dot := strings.last_index(src_with_dot, ".")

		if last_dot == -1 {
			return
		}

		tokenizer.init(
			&p.tok,
			position_context.file.src[0:last_dot],
			position_context.file.fullpath,
			common.parser_warning_handler,
		)

		p.tok.ch = ' '
		p.tok.line_count = position.line + 1
		p.tok.line_offset = line_offset
		p.tok.offset = begin_offset
		p.tok.read_offset = begin_offset

		tokenizer.advance_rune(&p.tok)

		if p.tok.ch == utf8.RUNE_BOM {
			tokenizer.advance_rune(&p.tok)
		}

		parser.advance_token(&p)

		e := parser.parse_expr(&p, true)

		if e == nil {
			position_context.abort_completion = true
			return
		} else if e, ok := e.derived.(^ast.Bad_Expr); ok {
			position_context.abort_completion = true
			return
		}

		position_context.selector = e

		ident := new_type(ast.Ident, e.pos, e.end, context.temp_allocator)
		ident.name = string(position_context.file.src[last_dot + 1:end_offset])

		if ident.name != "" {
			position_context.field = ident
		}
	} else {
		position_context.identifier = e
	}
}

fallback_position_context_signature :: proc(
	document: ^Document,
	position: common.Position,
	position_context: ^DocumentPositionContext,
) {
	end: int
	start: int
	i := position_context.position - 1
	end = i

	for i > 0 {

		c := position_context.file.src[i]

		if c == ' ' || c == '\n' || c == '\r' {
			start = i + 1
			break
		}

		i -= 1
	}

	if end < 0 {
		return
	}

	if position_context.file.src[end] != '(' {
		return
	}

	end -= 1

	begin_offset := max(0, start)
	end_offset := max(start, end + 1)

	if end_offset - begin_offset <= 1 {
		return
	}

	str := position_context.file.src[0:end_offset]

	p := parser.Parser {
		err  = common.parser_warning_handler, //empty
		warn = common.parser_warning_handler, //empty
		file = &position_context.file,
	}

	tokenizer.init(&p.tok, str, position_context.file.fullpath, common.parser_warning_handler)

	p.tok.ch = ' '
	p.tok.line_count = position.line
	p.tok.offset = begin_offset
	p.tok.read_offset = begin_offset

	tokenizer.advance_rune(&p.tok)

	if p.tok.ch == utf8.RUNE_BOM {
		tokenizer.advance_rune(&p.tok)
	}

	parser.advance_token(&p)

	context.allocator = context.temp_allocator

	position_context.call = parser.parse_expr(&p, true)

	if _, ok := position_context.call.derived.(^ast.Proc_Type); ok {
		position_context.call = nil
	}

	//log.error(string(position_context.file.src[begin_offset:end_offset]));
}

// Used to find which sub-expr is desired by the position.
// Eg. for map[Key]Value, do we want 'map', 'Key' or 'Value'
get_desired_expr :: proc(node: ^ast.Expr, position: common.AbsolutePosition) -> ^ast.Expr {
	#partial switch n in node.derived {
	case ^ast.Array_Type:
		if position_in_node(n.tag, position) {
			return n.tag
		}
		if position_in_node(n.elem, position) {
			return n.elem
		}
		if position_in_node(n.len, position) {
			return n.len
		}
	case ^ast.Map_Type:
		if position_in_node(n.key, position) {
			return n.key
		}
		if position_in_node(n.value, position) {
			return n.value
		}
	case ^ast.Dynamic_Array_Type:
		if position_in_node(n.tag, position) {
			return n.tag
		}
		if position_in_node(n.elem, position) {
			return n.elem
		}
	case ^ast.Bit_Set_Type:
		if position_in_node(n.elem, position) {
			return n.elem
		}
	case ^ast.Matrix_Type:
		if position_in_node(n.elem, position) {
			return n.elem
		}
		if position_in_node(n.row_count, position) {
			return n.row_count
		}
		if position_in_node(n.column_count, position) {
			return n.column_count
		}
	case ^ast.Bit_Field_Type:
		if position_in_node(n.backing_type, position) {
			return n.backing_type
		}
	}

	return node
}

/*
	All these fallback functions are not perfect and should be fixed. A lot of weird use of the odin tokenizer and parser.
*/

get_document_position :: proc {
	get_document_position_array,
	get_document_position_dynamic_array,
	get_document_position_node,
}

get_document_position_array :: proc(array: $A/[]^$T, position_context: ^DocumentPositionContext) {
	for elem, i in array {
		get_document_position(elem, position_context)
	}
}

get_document_position_dynamic_array :: proc(array: $A/[dynamic]^$T, position_context: ^DocumentPositionContext) {
	for elem, i in array {
		get_document_position(elem, position_context)
	}
}

position_in_node :: proc(node: ^ast.Node, position: common.AbsolutePosition) -> bool {
	return node != nil && node.pos.offset <= position && position <= node.end.offset
}

position_in_exprs :: proc(nodes: []^ast.Expr, position: common.AbsolutePosition) -> bool {
	for node in nodes {
		if node != nil && node.pos.offset <= position && position <= node.end.offset {
			return true
		}
	}

	return false
}

get_document_position_label :: proc(label: ^ast.Expr, position_context: ^DocumentPositionContext) {
	if label == nil {
		return
	}

	if ident, ok := label.derived.(^ast.Ident); ok {
		position_context.label = ident
	}
}

get_document_position_node :: proc(node: ^ast.Node, position_context: ^DocumentPositionContext) {
	using ast

	if node == nil {
		return
	}

	if !position_in_node(node, position_context.position) {
		return
	}

	#partial switch n in node.derived {
	case ^Bad_Expr:
	case ^Ident:
		position_context.identifier = node
	case ^Implicit:
		if n.tok.text == "context" {
			position_context.implicit_context = n
		}
	case ^Undef:
	case ^Basic_Lit:
		position_context.basic_lit = cast(^Basic_Lit)node
	case ^Matrix_Index_Expr:
		get_document_position(n.expr, position_context)
		get_document_position(n.row_index, position_context)
		get_document_position(n.column_index, position_context)
	case ^Matrix_Type:
		get_document_position(n.row_count, position_context)
		get_document_position(n.column_count, position_context)
		get_document_position(n.elem, position_context)
	case ^Ellipsis:
		get_document_position(n.expr, position_context)
	case ^Proc_Lit:
		if position_in_node(n.body, position_context.position) {
			get_document_position(n.type, position_context)
			position_context.function = cast(^Proc_Lit)node
			append(&position_context.functions, position_context.function)
			get_document_position(n.body, position_context)
		} else if position_in_node(n.type, position_context.position) {
			position_context.function = cast(^Proc_Lit)node
			get_document_position(n.type, position_context)
		} else {
			for clause in n.where_clauses {
				if position_in_node(clause, position_context.position) {
					position_context.function = cast(^Proc_Lit)node
					get_document_position(clause, position_context)
				}
			}
		}
	case ^Comp_Lit:
		//only set this for the parent comp literal, since we will need to walk through it to infer types.
		if position_context.parent_comp_lit == nil {
			position_context.parent_comp_lit = cast(^Comp_Lit)node
		}

		position_context.comp_lit = cast(^Comp_Lit)node

		get_document_position(n.type, position_context)
		get_document_position(n.elems, position_context)
	case ^Tag_Expr:
		get_document_position(n.expr, position_context)
	case ^Unary_Expr:
		get_document_position(n.expr, position_context)
	case ^Binary_Expr:
		if position_context.parent_binary == nil {
			position_context.parent_binary = n
		}
		position_context.binary = n
		get_document_position(n.left, position_context)
		get_document_position(n.right, position_context)
	case ^Paren_Expr:
		get_document_position(n.expr, position_context)
	case ^Call_Expr:
		position_context.call = n
		get_document_position(n.expr, position_context)
		get_document_position(n.args, position_context)
	case ^Selector_Call_Expr:
		if position_context.hint == .Definition ||
		   position_context.hint == .Hover ||
		   position_context.hint == .SignatureHelp ||
		   position_context.hint == .Completion {
			position_context.selector = n.expr
			position_context.field = n.call
			position_context.selector_expr = node

			if _, ok := n.call.derived.(^ast.Call_Expr); ok {
				position_context.call = n.call
			}

			get_document_position(n.expr, position_context)
			get_document_position(n.call, position_context)

			if position_context.hint == .SignatureHelp {
				position_context.arrow = true
			}
		}
	case ^Selector_Expr:
		if position_context.hint == .Definition || position_context.hint == .Hover && n.field != nil {
			position_context.selector = n.expr
			position_context.field = n.field
			position_context.selector_expr = node
			get_document_position(n.expr, position_context)
			get_document_position(n.field, position_context)
		} else {
			get_document_position(n.expr, position_context)
			get_document_position(n.field, position_context)
		}
	case ^Index_Expr:
		position_context.previous_index = position_context.index
		position_context.index = n
		get_document_position(n.expr, position_context)
		get_document_position(n.index, position_context)
	case ^Deref_Expr:
		get_document_position(n.expr, position_context)
	case ^Slice_Expr:
		get_document_position(n.expr, position_context)
		get_document_position(n.low, position_context)
		get_document_position(n.high, position_context)
	case ^Field_Value:
		position_context.field_value = n
		get_document_position(n.field, position_context)
		get_document_position(n.value, position_context)
	case ^Ternary_If_Expr:
		get_document_position(n.x, position_context)
		get_document_position(n.cond, position_context)
		get_document_position(n.y, position_context)
	case ^Ternary_When_Expr:
		get_document_position(n.x, position_context)
		get_document_position(n.cond, position_context)
		get_document_position(n.y, position_context)
	case ^Type_Assertion:
		get_document_position(n.expr, position_context)
		get_document_position(n.type, position_context)
	case ^Type_Cast:
		position_context.type_cast = cast(^Type_Cast)node
		get_document_position(n.type, position_context)
		get_document_position(n.expr, position_context)
	case ^Auto_Cast:
		get_document_position(n.expr, position_context)
	case ^Bad_Stmt:
	case ^Empty_Stmt:
	case ^Expr_Stmt:
		get_document_position(n.expr, position_context)
	case ^Tag_Stmt:
		r := n
		get_document_position(r.stmt, position_context)
	case ^Assign_Stmt:
		position_context.assign = n
		get_document_position(n.lhs, position_context)
		get_document_position(n.rhs, position_context)
	case ^Block_Stmt:
		get_document_position_label(n.label, position_context)
		get_document_position(n.stmts, position_context)
	case ^If_Stmt:
		get_document_position_label(n.label, position_context)
		get_document_position(n.init, position_context)
		get_document_position(n.cond, position_context)
		get_document_position(n.body, position_context)
		get_document_position(n.else_stmt, position_context)
	case ^When_Stmt:
		get_document_position(n.cond, position_context)
		get_document_position(n.body, position_context)
		get_document_position(n.else_stmt, position_context)
	case ^Return_Stmt:
		position_context.returns = n
		get_document_position(n.results, position_context)
	case ^Defer_Stmt:
		get_document_position(n.stmt, position_context)
	case ^For_Stmt:
		get_document_position_label(n.label, position_context)
		get_document_position(n.init, position_context)
		get_document_position(n.cond, position_context)
		get_document_position(n.post, position_context)
		get_document_position(n.body, position_context)
	case ^Range_Stmt:
		get_document_position_label(n.label, position_context)
		get_document_position(n.vals, position_context)
		get_document_position(n.expr, position_context)
		get_document_position(n.body, position_context)
	case ^Case_Clause:
		for elem in n.list {
			if position_in_node(elem, position_context.position) {
				position_context.case_clause = cast(^Case_Clause)node
				break
			}
		}

		get_document_position(n.list, position_context)
		get_document_position(n.body, position_context)
	case ^Switch_Stmt:
		position_context.switch_stmt = cast(^Switch_Stmt)node
		get_document_position_label(n.label, position_context)
		get_document_position(n.init, position_context)
		get_document_position(n.cond, position_context)
		get_document_position(n.body, position_context)
	case ^Type_Switch_Stmt:
		position_context.switch_type_stmt = cast(^Type_Switch_Stmt)node
		get_document_position_label(n.label, position_context)
		get_document_position(n.tag, position_context)
		get_document_position(n.expr, position_context)
		get_document_position(n.body, position_context)
	case ^Branch_Stmt:
		get_document_position_label(n.label, position_context)
	case ^Using_Stmt:
		get_document_position(n.list, position_context)
	case ^Bad_Decl:
	case ^Value_Decl:
		position_context.value_decl = cast(^Value_Decl)node
		get_document_position(n.attributes, position_context)

		for name in n.names {
			if position_in_node(name, position_context.position) && n.end.line - 1 == position_context.line {
				position_context.abort_completion = true
				break
			}
		}
		get_document_position(n.names, position_context)
		get_document_position(n.type, position_context)
		get_document_position(n.values, position_context)
	case ^Package_Decl:
	case ^Import_Decl:
	case ^Foreign_Block_Decl:
		get_document_position(n.attributes, position_context)
		get_document_position(n.foreign_library, position_context)
		get_document_position(n.body, position_context)
	case ^Foreign_Import_Decl:
		get_document_position(n.name, position_context)
	case ^Proc_Group:
		get_document_position(n.args, position_context)
	case ^Attribute:
		get_document_position(n.elems, position_context)
	case ^Field:
		get_document_position(n.names, position_context)
		get_document_position(n.type, position_context)
		get_document_position(n.default_value, position_context)
	case ^Field_List:
		get_document_position(n.list, position_context)
	case ^Typeid_Type:
		get_document_position(n.specialization, position_context)
	case ^Helper_Type:
		get_document_position(n.type, position_context)
	case ^Distinct_Type:
		get_document_position(n.type, position_context)
	case ^Poly_Type:
		get_document_position(n.type, position_context)
		get_document_position(n.specialization, position_context)
	case ^Proc_Type:
		get_document_position(n.params, position_context)
		get_document_position(n.results, position_context)
	case ^Pointer_Type:
		get_document_position(n.elem, position_context)
	case ^Array_Type:
		get_document_position(n.len, position_context)
		get_document_position(n.elem, position_context)
	case ^Dynamic_Array_Type:
		get_document_position(n.elem, position_context)
	case ^Multi_Pointer_Type:
		get_document_position(n.elem, position_context)
	case ^Struct_Type:
		position_context.struct_type = n
		get_document_position(n.poly_params, position_context)
		get_document_position(n.align, position_context)
		get_document_position(n.fields, position_context)
	case ^Union_Type:
		position_context.union_type = n
		get_document_position(n.poly_params, position_context)
		get_document_position(n.align, position_context)
		get_document_position(n.variants, position_context)
	case ^Enum_Type:
		position_context.enum_type = n
		get_document_position(n.base_type, position_context)
		get_document_position(n.fields, position_context)
	case ^Bit_Set_Type:
		position_context.bitset_type = n
		get_document_position(n.elem, position_context)
		get_document_position(n.underlying, position_context)
	case ^Map_Type:
		get_document_position(n.key, position_context)
		get_document_position(n.value, position_context)
	case ^Implicit_Selector_Expr:
		position_context.implicit = true
		position_context.implicit_selector_expr = n
		get_document_position(n.field, position_context)
	case ^Or_Else_Expr:
		get_document_position(n.x, position_context)
		get_document_position(n.y, position_context)
	case ^Or_Return_Expr:
		get_document_position(n.expr, position_context)
	case ^Or_Branch_Expr:
		get_document_position_label(n.label, position_context)
		get_document_position(n.expr, position_context)
	case ^Bit_Field_Type:
		position_context.bit_field_type = n
		get_document_position(n.backing_type, position_context)
		get_document_position(n.fields, position_context)
	case ^Bit_Field_Field:
		get_document_position(n.name, position_context)
		get_document_position(n.type, position_context)
		get_document_position(n.bit_size, position_context)
	case:
	}
}
