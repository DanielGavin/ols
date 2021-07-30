package server

import "core:odin/tokenizer"
import "core:odin/ast"
import "core:log"

import "shared:common"
import "shared:index"
import "shared:analysis"

/*
	Right now I might be setting the wrong types, since there is no documentation as to what should be what, and looking at other LSP there is no consistancy.
*/

SemanticTokenTypes :: enum {
	Namespace,
	Type,
	Enum,
	Struct,
	Parameter,
	Variable,
	EnumMember,
	Function,
	Member,
	Keyword,
	Modifier,
	Comment,
	String,
	Number,
	Operator,
	Property,
	Method,
}

SemanticTokenModifiers :: enum {
	None,
	Declaration,
	Definition,
	Deprecated,
}

SemanticTokensClientCapabilities :: struct {
	requests:                struct {
		range: bool,
	},
	tokenTypes:              []string,
	tokenModifiers:          []string,
	formats:                 []string,
	overlappingTokenSupport: bool,
	multilineTokenSupport:   bool,
}

SemanticTokensLegend :: struct {
	tokenTypes:     []string,
	tokenModifiers: []string,
}

SemanticTokensOptions :: struct {
	legend: SemanticTokensLegend,
	range:  bool,
	full:   bool,
}

SemanticTokensParams :: struct {
	textDocument: TextDocumentIdentifier,
}

SemanticTokensRangeParams :: struct {
	textDocument: TextDocumentIdentifier,
	range:        common.Range,
}

SemanticTokens :: struct {
	data: []u32,
}

SemanticTokenBuilder :: struct {
	current_function: ^ast.Node,
	current_start:    int,
	selector_member:  bool,
	selector_package: bool,
	tokens:           [dynamic]u32,
}

make_token_builder :: proc(allocator := context.temp_allocator) -> SemanticTokenBuilder {

	return {
		tokens = make([dynamic]u32, context.temp_allocator),
	};
}

get_tokens :: proc(builder: SemanticTokenBuilder) -> SemanticTokens {
	return {
		data = builder.tokens[:],
	};
}

get_semantic_tokens :: proc(document: ^common.Document, range: common.Range) -> SemanticTokens {

	using analysis;

	ast_context := make_ast_context(document.ast, document.imports, document.package_name, document.uri.uri, context.temp_allocator);
	builder     := make_token_builder();

	get_globals(document.ast, &ast_context);

	if document.ast.pkg_decl != nil {
		write_semantic_token(&builder, document.ast.pkg_token, document.ast.src, .Keyword, .None);
	}

	for decl in document.ast.decls {
		if range.start.line <= decl.pos.line && decl.end.line <= range.end.line {
			write_semantic_tokens(decl, &builder, &ast_context);
		}
	}

	return get_tokens(builder);
}

write_semantic_node :: proc(builder: ^SemanticTokenBuilder, node: ^ast.Node, src: string, type: SemanticTokenTypes, modifier: SemanticTokenModifiers) {

	position := common.get_relative_token_position(node.pos.offset, transmute([]u8)src, builder.current_start);

	name := common.get_ast_node_string(node, src);

	append(&builder.tokens, cast(u32)position.line, cast(u32)position.character, cast(u32)len(name), cast(u32)type, 0);

	builder.current_start = node.pos.offset;
}

write_semantic_token :: proc(builder: ^SemanticTokenBuilder, token: tokenizer.Token, src: string, type: SemanticTokenTypes, modifier: SemanticTokenModifiers) {

	position := common.get_relative_token_position(token.pos.offset, transmute([]u8)src, builder.current_start);

	append(&builder.tokens, cast(u32)position.line, cast(u32)position.character, cast(u32)len(token.text), cast(u32)type, 0);

	builder.current_start = token.pos.offset;
}

write_semantic_token_pos :: proc(builder: ^SemanticTokenBuilder, pos: tokenizer.Pos, name: string, src: string, type: SemanticTokenTypes, modifier: SemanticTokenModifiers) {

	position := common.get_relative_token_position(pos.offset, transmute([]u8)src, builder.current_start);

	append(&builder.tokens, cast(u32)position.line, cast(u32)position.character, cast(u32)len(name), cast(u32)type, 0);

	builder.current_start = pos.offset;
}

resolve_and_write_ident :: proc(node: ^ast.Node, builder: ^SemanticTokenBuilder, ast_context: ^analysis.AstContext) -> (is_member: bool, is_package: bool, package_name: string) {

	using analysis;

	n := node.derived.(ast.Ident);

	package_name                = ast_context.document_package;
	ast_context.current_package = ast_context.document_package;
	ast_context.use_globals     = true;
	ast_context.use_locals      = true;

	if resolve_ident_is_variable(ast_context, n) {
		write_semantic_node(builder, node, ast_context.file.src, .Variable, .None);
		is_member = true;
	} else if symbol, ok := resolve_type_identifier(ast_context, n); ok {
		#partial switch v in symbol.value {
		case index.SymbolPackageValue:
			write_semantic_node(builder, node, ast_context.file.src, .Namespace, .None);
			is_package   = true;
			package_name = symbol.pkg;
		case index.SymbolStructValue:
			write_semantic_node(builder, node, ast_context.file.src, .Struct, .None);
		case index.SymbolEnumValue:
			write_semantic_node(builder, node, ast_context.file.src, .Enum, .None);
		case index.SymbolUnionValue:
			write_semantic_node(builder, node, ast_context.file.src, .Enum, .None);
		case index.SymbolProcedureValue:
			write_semantic_node(builder, node, ast_context.file.src, .Function, .None);
		case index.SymbolProcedureGroupValue:
			write_semantic_node(builder, node, ast_context.file.src, .Function, .None);
		case index.SymbolGenericValue:
			#partial switch symbol.type {
			case .Keyword:
				write_semantic_node(builder, node, ast_context.file.src, .Keyword, .None);
			}
		}
	}

	return;
}

write_semantic_tokens :: proc {
	write_semantic_tokens_node,
	write_semantic_tokens_dynamic_array,
	write_semantic_tokens_array,
	write_semantic_tokens_stmt,
};

write_semantic_tokens_array :: proc(array: $A/[]^$T, builder: ^SemanticTokenBuilder, ast_context: ^analysis.AstContext) {

	for elem, i in array {
		write_semantic_tokens(elem, builder, ast_context);
	}
}

write_semantic_tokens_dynamic_array :: proc(array: $A/[dynamic]^$T, builder: ^SemanticTokenBuilder, ast_context: ^analysis.AstContext) {

	for elem, i in array {
		write_semantic_tokens(elem, builder, ast_context);
	}
}

write_semantic_tokens_stmt :: proc(node: ^ast.Stmt, builder: ^SemanticTokenBuilder, ast_context: ^analysis.AstContext) {
	ast_context.current_package = ast_context.document_package;
	ast_context.use_globals     = true;
	ast_context.use_locals      = true;
	builder.selector_member     = false;
	write_semantic_tokens_node(node, builder, ast_context);
}

write_semantic_tokens_node :: proc(node: ^ast.Node, builder: ^SemanticTokenBuilder, ast_context: ^analysis.AstContext) {

	using ast;

	if node == nil {
		return;
	}

	switch n in node.derived {
	case Ellipsis:
		write_semantic_token_pos(builder, node.pos, "..", ast_context.file.src, .Operator, .None);
		write_semantic_tokens(n.expr, builder, ast_context);
	case Ident:
		/*EXPENSIVE!! But alas i can't just get locals per scope, but have to the exact position, because you can do shit like this:
			log.println("hello"); //log is namespace
			log := 2; //log is now variable
			a := log + 2;
		*/

		get_locals_at(builder.current_function, node, ast_context);
		resolve_and_write_ident(node, builder, ast_context);
	case Selector_Expr:
		write_semantic_selector(cast(^Selector_Expr)node, builder, ast_context);
	case Pointer_Type:
		write_semantic_token_pos(builder, node.pos, "^", ast_context.file.src, .Operator, .None);
		write_semantic_tokens(n.elem, builder, ast_context);
	case Value_Decl:
		write_semantic_tokens_value_decl(n, builder, ast_context);
	case Block_Stmt:
		write_semantic_tokens(n.stmts, builder, ast_context);
	case Expr_Stmt:
		write_semantic_tokens(n.expr, builder, ast_context);
	case Range_Stmt:
		write_semantic_token_pos(builder, n.for_pos, "for", ast_context.file.src, .Keyword, .None);

		for val in n.vals {
			if ident, ok := val.derived.(Ident); ok {
				write_semantic_node(builder, val, ast_context.file.src, .Variable, .None);
			}
		}

		write_semantic_token_pos(builder, n.in_pos, "in", ast_context.file.src, .Keyword, .None);
		write_semantic_tokens(n.expr, builder, ast_context);
		write_semantic_tokens(n.body, builder, ast_context);
	case If_Stmt:
		write_semantic_token_pos(builder, n.if_pos, "if", ast_context.file.src, .Keyword, .None);
		write_semantic_tokens(n.init, builder, ast_context);
		write_semantic_tokens(n.cond, builder, ast_context);
		write_semantic_tokens(n.body, builder, ast_context);
		if n.else_stmt != nil {
			write_semantic_token_pos(builder, n.else_pos, "else", ast_context.file.src, .Keyword, .None);
			write_semantic_tokens(n.else_stmt, builder, ast_context);
		}
	case For_Stmt:
		write_semantic_token_pos(builder, n.for_pos, "for", ast_context.file.src, .Keyword, .None);
		write_semantic_tokens(n.init, builder, ast_context);
		write_semantic_tokens(n.cond, builder, ast_context);
		write_semantic_tokens(n.post, builder, ast_context);
		write_semantic_tokens(n.body, builder, ast_context);
	case Switch_Stmt:
		write_semantic_token_pos(builder, n.switch_pos, "switch", ast_context.file.src, .Keyword, .None);
		write_semantic_tokens(n.init, builder, ast_context);
		write_semantic_tokens(n.cond, builder, ast_context);
		write_semantic_tokens(n.body, builder, ast_context);
	case Type_Switch_Stmt:
		write_semantic_token_pos(builder, n.switch_pos, "switch", ast_context.file.src, .Keyword, .None);
		write_semantic_tokens(n.tag, builder, ast_context);
		write_semantic_tokens(n.expr, builder, ast_context);
		write_semantic_tokens(n.body, builder, ast_context);
	case Assign_Stmt:
		for l in n.lhs {
			if ident, ok := l.derived.(Ident); ok {
				write_semantic_node(builder, l, ast_context.file.src, .Variable, .None);
			} else {
				write_semantic_tokens(l, builder, ast_context);
			}
		}

		write_semantic_token_op(builder, n.op, ast_context.file.src);
		write_semantic_tokens(n.rhs, builder, ast_context);
	case Case_Clause:
		write_semantic_token_pos(builder, n.case_pos, "case", ast_context.file.src, .Keyword, .None);
		write_semantic_tokens(n.list, builder, ast_context);
		write_semantic_tokens(n.body, builder, ast_context);
	case Call_Expr:
		//could there be any other type then .Function for call expr?  No point of computing it if not.
		if ident, ok := n.expr.derived.(Ident); ok {
			write_semantic_node(builder, n.expr, ast_context.file.src, .Function, .None);
		} else {
			write_semantic_tokens(n.expr, builder, ast_context);
		}
		write_semantic_tokens(n.args, builder, ast_context);
	case Implicit_Selector_Expr:
		write_semantic_node(builder, n.field, ast_context.file.src, .Enum, .None);
	case Array_Type:
		write_semantic_tokens(n.elem, builder, ast_context);
	case Binary_Expr:
		write_semantic_tokens(n.left, builder, ast_context);
		write_semantic_token_op(builder, n.op, ast_context.file.src);
		write_semantic_tokens(n.right, builder, ast_context);
	case Comp_Lit:
		write_semantic_tokens(n.type, builder, ast_context);
		write_semantic_tokens(n.elems, builder, ast_context);
	case Struct_Type:
		write_semantic_token_pos(builder, n.pos, "struct", ast_context.file.src, .Keyword, .None);
		write_semantic_struct_fields(n, builder, ast_context);
	case Type_Assertion:
		write_semantic_tokens(n.expr, builder, ast_context);
		write_semantic_tokens(n.type, builder, ast_context);
	case Type_Cast:
		write_semantic_token_pos(builder, n.pos, "cast", ast_context.file.src, .Keyword, .None);
		write_semantic_tokens(n.type, builder, ast_context);
		write_semantic_tokens(n.expr, builder, ast_context);
	case Paren_Expr:
		write_semantic_tokens(n.expr, builder, ast_context);
	case Deref_Expr:
		write_semantic_tokens(n.expr, builder, ast_context);
	case Return_Stmt:
		write_semantic_token_pos(builder, n.pos, "return", ast_context.file.src, .Keyword, .None);
		write_semantic_tokens(n.results, builder, ast_context);
	case Dynamic_Array_Type:
		write_semantic_token_pos(builder, n.dynamic_pos, "dynamic", ast_context.file.src, .Keyword, .None);
		write_semantic_tokens(n.elem, builder, ast_context);
	case Field_Value:
		if ident, ok := n.field.derived.(Ident); ok {
			write_semantic_node(builder, n.field, ast_context.file.src, .Property, .None);
		}

		write_semantic_tokens(n.value, builder, ast_context);
	case Index_Expr:
		write_semantic_tokens(n.expr, builder, ast_context);
		write_semantic_tokens(n.index, builder, ast_context);
	case Basic_Lit:
		write_semantic_token_basic_lit(n, builder, ast_context);
	case Unary_Expr:
		write_semantic_tokens(n.expr, builder, ast_context);
	case Implicit:
	case Slice_Expr:
		write_semantic_tokens(n.expr, builder, ast_context);
	case Using_Stmt:
		write_semantic_token_pos(builder, n.pos, "using", ast_context.file.src, .Keyword, .None);
		write_semantic_tokens(n.list, builder, ast_context);
	case Map_Type:
		write_semantic_token_pos(builder, n.tok_pos, "map", ast_context.file.src, .Keyword, .None);
		write_semantic_tokens(n.key, builder, ast_context);
		write_semantic_tokens(n.value, builder, ast_context);
	case Defer_Stmt:
		write_semantic_token_pos(builder, n.pos, "defer", ast_context.file.src, .Keyword, .None);
		write_semantic_tokens(n.stmt, builder, ast_context);
	case Import_Decl:
		write_semantic_token(builder, n.import_tok, ast_context.file.src, .Keyword, .None);

		if n.name.text != "" {
			write_semantic_token(builder, n.name, ast_context.file.src, .Namespace, .None);
		}

		write_semantic_token(builder, n.relpath, ast_context.file.src, .String, .None);
	case:
		log.warnf("unhandled write node %v", n);
	}
}

write_semantic_token_basic_lit :: proc(basic_lit: ast.Basic_Lit, builder: ^SemanticTokenBuilder, ast_context: ^analysis.AstContext) {

	using analysis;

	if symbol, ok := resolve_basic_lit(ast_context, basic_lit); ok {

		if generic, ok := symbol.value.(index.SymbolGenericValue); ok {

			ident := generic.expr.derived.(ast.Ident);

			if ident.name == "string" {
				write_semantic_node(builder, generic.expr, ast_context.file.src, .String, .None);
			} else if ident.name == "int" {
				write_semantic_node(builder, generic.expr, ast_context.file.src, .Number, .None);
			} else {
			}
		}
	}
}

write_semantic_tokens_value_decl :: proc(value_decl: ast.Value_Decl, builder: ^SemanticTokenBuilder, ast_context: ^analysis.AstContext) {

	using ast;

	if value_decl.type != nil {

		for name in value_decl.names {
			write_semantic_node(builder, name, ast_context.file.src, .Variable, .None);
		}

		write_semantic_tokens(value_decl.type, builder, ast_context);

		return;
	}

	if len(value_decl.values) == 1 {

		switch v in value_decl.values[0].derived {
		case Struct_Type:
			write_semantic_node(builder, value_decl.names[0], ast_context.file.src, .Struct, .None);
			write_semantic_token_pos(builder, v.pos, "struct", ast_context.file.src, .Keyword, .None);
			write_semantic_struct_fields(v, builder, ast_context);
		case Enum_Type:
			write_semantic_node(builder, value_decl.names[0], ast_context.file.src, .Enum, .None);
			write_semantic_token_pos(builder, v.pos, "enum", ast_context.file.src, .Keyword, .None);
			write_semantic_enum_fields(v, builder, ast_context);
		case Proc_Group:
			write_semantic_node(builder, value_decl.names[0], ast_context.file.src, .Function, .None);
			write_semantic_token_pos(builder, v.pos, "proc", ast_context.file.src, .Keyword, .None);
			for arg in v.args {
				if ident, ok := arg.derived.(Ident); ok {
					write_semantic_node(builder, arg, ast_context.file.src, .Function, .None);
				}
			}
		case Proc_Lit:
			write_semantic_node(builder, value_decl.names[0], ast_context.file.src, .Function, .None);
			write_semantic_token_pos(builder, v.pos, "proc", ast_context.file.src, .Keyword, .None);
			write_semantic_proc_type(v.type, builder, ast_context);

			last_function := builder.current_function;
			builder.current_function = value_decl.values[0];
			write_semantic_tokens(v.body, builder, ast_context);
			builder.current_function = last_function;
		case:
			for name in value_decl.names {
				write_semantic_node(builder, name, ast_context.file.src, .Variable, .None);
			}

			write_semantic_tokens(value_decl.values[0], builder, ast_context);
		}
	} else {

		for name in value_decl.names {
			write_semantic_node(builder, name, ast_context.file.src, .Variable, .None);
		}

		for value in value_decl.values {
			write_semantic_tokens(value, builder, ast_context);
		}
	}
}

write_semantic_token_op :: proc(builder: ^SemanticTokenBuilder, token: tokenizer.Token, src: string) {

	if token.text == "=" {
		write_semantic_token_pos(builder, token.pos, token.text, src, .Operator, .None);
	} else if token.text == "in" {
		write_semantic_token_pos(builder, token.pos, token.text, src, .Keyword, .None);
	}
}

write_semantic_proc_type :: proc(node: ^ast.Proc_Type, builder: ^SemanticTokenBuilder, ast_context: ^analysis.AstContext) {

	using ast;

	if node == nil {
		return;
	}

	if node.params != nil {

		for param in node.params.list {

			for name in param.names {

				if ident, ok := name.derived.(Ident); ok {
					write_semantic_node(builder, name, ast_context.file.src, .Parameter, .None);
				}
			}

			write_semantic_tokens(param.type, builder, ast_context);
		}
	}

	if node.results != nil {

		for result in node.results.list {

			for name in result.names {

				if ident, ok := name.derived.(Ident); ok {
					//write_semantic_node(builder, name, ast_context.file.src, .Parameter, .None);
				}
			}

			write_semantic_tokens(result.type, builder, ast_context);
		}
	}
}

write_semantic_enum_fields :: proc(node: ast.Enum_Type, builder: ^SemanticTokenBuilder, ast_context: ^analysis.AstContext) {

	using ast;

	if node.fields == nil {
		return;
	}

	for field in node.fields {

		if ident, ok := field.derived.(Ident); ok {
			write_semantic_node(builder, field, ast_context.file.src, .EnumMember, .None);
		}
	}
}

write_semantic_struct_fields :: proc(node: ast.Struct_Type, builder: ^SemanticTokenBuilder, ast_context: ^analysis.AstContext) {

	using ast;

	if node.fields == nil {
		return;
	}

	for field in node.fields.list {

		for name in field.names {
			if ident, ok := name.derived.(Ident); ok {
				write_semantic_node(builder, name, ast_context.file.src, .Property, .None);
			}
		}

		write_semantic_tokens(field.type, builder, ast_context);
	}
}

write_semantic_selector :: proc(selector: ^ast.Selector_Expr, builder: ^SemanticTokenBuilder, ast_context: ^analysis.AstContext) {

	using analysis;
	using ast;

	if _, ok := selector.expr.derived.(Selector_Expr); !ok {
		get_locals_at(builder.current_function, selector.expr, ast_context);

		if symbol, ok := resolve_type_expression(ast_context, selector.expr); ok {
			
			#partial switch v in symbol.value {
			case index.SymbolStructValue:
				builder.selector_member = true;
			}

		}

	} else {
		write_semantic_tokens(selector.expr, builder, ast_context);
	}

	if symbol, ok := resolve_type_expression(ast_context, selector); ok && !builder.selector_member {

		#partial switch v in symbol.value {
		case index.SymbolPackageValue:
			write_semantic_node(builder, selector.field, ast_context.file.src, .Namespace, .None);
		case index.SymbolStructValue:
			write_semantic_node(builder, selector.field, ast_context.file.src, .Struct, .None);
		case index.SymbolEnumValue:
			write_semantic_node(builder, selector.field, ast_context.file.src, .Enum, .None);
		case index.SymbolUnionValue:
			write_semantic_node(builder, selector.field, ast_context.file.src, .Enum, .None);
		case index.SymbolProcedureGroupValue:
			write_semantic_node(builder, selector.field, ast_context.file.src, .Function, .None);
		case index.SymbolGenericValue:
			#partial switch symbol.type {
			case .Keyword:
				write_semantic_node(builder, selector.field, ast_context.file.src, .Keyword, .None);
			}
		}
	} else if (builder.selector_member) {
		write_semantic_node(builder, selector.field, ast_context.file.src, .Property, .None);
	}
}

get_locals_at :: proc(function: ^ast.Node, position: ^ast.Node, ast_context: ^analysis.AstContext) {

	using analysis;

	clear_locals(ast_context);

	if function == nil {
		return;
	}

	if position == nil {
		return;
	}

	document_position := DocumentPositionContext {
		position = position.end.offset,
	};

	get_locals(ast_context.file, function, ast_context, &document_position);
}
