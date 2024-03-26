package server

import "core:fmt"
import "core:log"
import "core:odin/ast"
import "core:odin/tokenizer"

import "src:common"

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

SemanticTokenModifiers :: enum (u8) {
	None        = 0,
	Declaration = 1,
	Definition  = 2,
	Deprecated  = 4,
	ReadOnly    = 8,
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
	current_start: int,
	tokens:        [dynamic]u32,
	symbols:       map[uintptr]SymbolAndNode,
	selector:      bool,
}

make_token_builder :: proc(
	allocator := context.temp_allocator,
) -> SemanticTokenBuilder {
	return {tokens = make([dynamic]u32, 10000, context.temp_allocator)}
}

get_tokens :: proc(builder: SemanticTokenBuilder) -> SemanticTokens {
	return {data = builder.tokens[:]}
}

get_semantic_tokens :: proc(
	document: ^Document,
	range: common.Range,
	symbols: map[uintptr]SymbolAndNode,
) -> SemanticTokens {
	builder := make_token_builder()

	if document.ast.pkg_decl != nil {
		write_semantic_token(
			&builder,
			document.ast.pkg_token,
			document.ast.src,
			.Keyword,
			.None,
		)
	}

	ast_context := make_ast_context(
		document.ast,
		document.imports,
		document.package_name,
		document.uri.uri,
		document.fullpath,
	)

	builder.symbols = symbols

	ast_context.current_package = ast_context.document_package

	for decl in document.ast.decls {
		if range.start.line <= decl.pos.line &&
		   decl.end.line <= range.end.line {
			visit(decl, &builder, &ast_context)
		}
	}

	return get_tokens(builder)
}

write_semantic_node :: proc(
	builder: ^SemanticTokenBuilder,
	node: ^ast.Node,
	src: string,
	type: SemanticTokenTypes,
	modifier: SemanticTokenModifiers,
) {
	//Sometimes odin ast uses "_" for empty params.
	if ident, ok := node.derived.(^ast.Ident); ok && ident.name == "_" {
		return
	}

	position := common.get_relative_token_position(
		node.pos.offset,
		transmute([]u8)src,
		builder.current_start,
	)
	name := common.get_ast_node_string(node, src)
	append(
		&builder.tokens,
		cast(u32)position.line,
		cast(u32)position.character,
		cast(u32)len(name),
		cast(u32)type,
		cast(u32)modifier,
	)
	builder.current_start = node.pos.offset
}

write_semantic_token :: proc(
	builder: ^SemanticTokenBuilder,
	token: tokenizer.Token,
	src: string,
	type: SemanticTokenTypes,
	modifier: SemanticTokenModifiers,
) {
	position := common.get_relative_token_position(
		token.pos.offset,
		transmute([]u8)src,
		builder.current_start,
	)
	append(
		&builder.tokens,
		cast(u32)position.line,
		cast(u32)position.character,
		cast(u32)len(token.text),
		cast(u32)type,
		cast(u32)modifier,
	)
	builder.current_start = token.pos.offset
}

write_semantic_string :: proc(
	builder: ^SemanticTokenBuilder,
	pos: tokenizer.Pos,
	name: string,
	src: string,
	type: SemanticTokenTypes,
	modifier: SemanticTokenModifiers,
) {
	position := common.get_relative_token_position(
		pos.offset,
		transmute([]u8)src,
		builder.current_start,
	)
	append(
		&builder.tokens,
		cast(u32)position.line,
		cast(u32)position.character,
		cast(u32)len(name),
		cast(u32)type,
		cast(u32)modifier,
	)
	builder.current_start = pos.offset
}

visit :: proc {
	visit_node,
	visit_dynamic_array,
	visit_array,
	visit_stmt,
}

visit_array :: proc(
	array: $A/[]^$T,
	builder: ^SemanticTokenBuilder,
	ast_context: ^AstContext,
) {
	for elem, i in array {
		visit(elem, builder, ast_context)
	}
}

visit_dynamic_array :: proc(
	array: $A/[dynamic]^$T,
	builder: ^SemanticTokenBuilder,
	ast_context: ^AstContext,
) {
	for elem, i in array {
		visit(elem, builder, ast_context)
	}
}

visit_stmt :: proc(
	node: ^ast.Stmt,
	builder: ^SemanticTokenBuilder,
	ast_context: ^AstContext,
) {
	visit_node(node, builder, ast_context)
}

visit_node :: proc(
	node: ^ast.Node,
	builder: ^SemanticTokenBuilder,
	ast_context: ^AstContext,
) {
	using ast

	if node == nil {
		return
	}

	#partial switch n in node.derived {
	case ^Ellipsis:
		visit(n.expr, builder, ast_context)
	case ^Ident:
		modifier: SemanticTokenModifiers

		if symbol_and_node, ok := builder.symbols[cast(uintptr)node]; ok {
			if symbol_and_node.symbol.type == .Constant ||
			   symbol_and_node.symbol.type != .Variable {
				//modifier = .ReadOnly
			}

			if .Distinct in symbol_and_node.symbol.flags &&
			   symbol_and_node.symbol.type == .Constant {
				write_semantic_node(
					builder,
					node,
					ast_context.file.src,
					.Type,
					.None,
				)
				return
			}

			_, is_proc := symbol_and_node.symbol.value.(SymbolProcedureValue)

			if symbol_and_node.symbol.type == .Variable && !is_proc {
				write_semantic_node(
					builder,
					node,
					ast_context.file.src,
					.Variable,
					modifier,
				)
				return
			}

			#partial switch v in symbol_and_node.symbol.value {
			case SymbolPackageValue:
				write_semantic_node(
					builder,
					node,
					ast_context.file.src,
					.Namespace,
					.None,
				)
			case SymbolStructValue:
				write_semantic_node(
					builder,
					node,
					ast_context.file.src,
					.Struct,
					modifier,
				)
			case SymbolEnumValue:
				write_semantic_node(
					builder,
					node,
					ast_context.file.src,
					.Enum,
					modifier,
				)
			case SymbolUnionValue:
				write_semantic_node(
					builder,
					node,
					ast_context.file.src,
					.Enum,
					modifier,
				)
			case SymbolProcedureValue:
				write_semantic_node(
					builder,
					node,
					ast_context.file.src,
					.Function,
					modifier,
				)
			case SymbolProcedureGroupValue:
				write_semantic_node(
					builder,
					node,
					ast_context.file.src,
					.Function,
					modifier,
				)
			case SymbolMatrixValue:
				write_semantic_node(
					builder,
					node,
					ast_context.file.src,
					.Type,
					modifier,
				)
			case:
			//log.errorf("Unexpected symbol value: %v", symbol.value);
			//panic(fmt.tprintf("Unexpected symbol value: %v", symbol.value));
			}
		}
	case ^Selector_Expr:
		visit_selector(cast(^Selector_Expr)node, builder, ast_context)
		builder.selector = false
	case ^When_Stmt:
		write_semantic_string(
			builder,
			n.when_pos,
			"when",
			ast_context.file.src,
			.Keyword,
			.None,
		)
		visit(n.cond, builder, ast_context)
		visit(n.body, builder, ast_context)
		visit(n.else_stmt, builder, ast_context)
	case ^Pointer_Type:
		write_semantic_string(
			builder,
			node.pos,
			"^",
			ast_context.file.src,
			.Operator,
			.None,
		)
		visit(n.elem, builder, ast_context)
	case ^Value_Decl:
		visit_value_decl(n^, builder, ast_context)
	case ^Block_Stmt:
		visit(n.stmts, builder, ast_context)
	case ^ast.Foreign_Block_Decl:
		visit(n.body, builder, ast_context)
	case ^Expr_Stmt:
		visit(n.expr, builder, ast_context)
	case ^Matrix_Type:
		write_semantic_string(
			builder,
			n.tok_pos,
			"matrix",
			ast_context.file.src,
			.Keyword,
			.None,
		)
		visit(n.row_count, builder, ast_context)
		visit(n.column_count, builder, ast_context)
		visit(n.elem, builder, ast_context)
	case ^ast.Matrix_Index_Expr:
		visit(n.expr, builder, ast_context)
		visit(n.row_index, builder, ast_context)
		visit(n.column_index, builder, ast_context)
	case ^Branch_Stmt:
		write_semantic_token(
			builder,
			n.tok,
			ast_context.file.src,
			.Keyword,
			.None,
		)
	case ^Poly_Type:
		write_semantic_string(
			builder,
			n.dollar,
			"$",
			ast_context.file.src,
			.Operator,
			.None,
		)
		visit(n.type, builder, ast_context)
		visit(n.specialization, builder, ast_context)
	case ^Range_Stmt:
		write_semantic_string(
			builder,
			n.for_pos,
			"for",
			ast_context.file.src,
			.Keyword,
			.None,
		)

		for val in n.vals {
			if ident, ok := val.derived.(^Ident); ok {
				write_semantic_node(
					builder,
					val,
					ast_context.file.src,
					.Variable,
					.None,
				)
			}
		}

		write_semantic_string(
			builder,
			n.in_pos,
			"in",
			ast_context.file.src,
			.Keyword,
			.None,
		)
		visit(n.expr, builder, ast_context)
		visit(n.body, builder, ast_context)
	case ^If_Stmt:
		write_semantic_string(
			builder,
			n.if_pos,
			"if",
			ast_context.file.src,
			.Keyword,
			.None,
		)
		visit(n.init, builder, ast_context)
		visit(n.cond, builder, ast_context)
		visit(n.body, builder, ast_context)
		if n.else_stmt != nil {
			write_semantic_string(
				builder,
				n.else_pos,
				"else",
				ast_context.file.src,
				.Keyword,
				.None,
			)
			visit(n.else_stmt, builder, ast_context)
		}
	case ^For_Stmt:
		write_semantic_string(
			builder,
			n.for_pos,
			"for",
			ast_context.file.src,
			.Keyword,
			.None,
		)
		visit(n.init, builder, ast_context)
		visit(n.cond, builder, ast_context)
		visit(n.post, builder, ast_context)
		visit(n.body, builder, ast_context)
	case ^Switch_Stmt:
		write_semantic_string(
			builder,
			n.switch_pos,
			"switch",
			ast_context.file.src,
			.Keyword,
			.None,
		)
		visit(n.init, builder, ast_context)
		visit(n.cond, builder, ast_context)
		visit(n.body, builder, ast_context)
	case ^Type_Switch_Stmt:
		write_semantic_string(
			builder,
			n.switch_pos,
			"switch",
			ast_context.file.src,
			.Keyword,
			.None,
		)
		visit(n.tag, builder, ast_context)
		visit(n.expr, builder, ast_context)
		visit(n.body, builder, ast_context)
	case ^Assign_Stmt:
		for l in n.lhs {
			if ident, ok := l.derived.(^Ident); ok {
				write_semantic_node(
					builder,
					l,
					ast_context.file.src,
					.Variable,
					.None,
				)
			} else {
				visit(l, builder, ast_context)
			}
		}

		visit_token_op(builder, n.op, ast_context.file.src)
		visit(n.rhs, builder, ast_context)
	case ^Case_Clause:
		write_semantic_string(
			builder,
			n.case_pos,
			"case",
			ast_context.file.src,
			.Keyword,
			.None,
		)
		visit(n.list, builder, ast_context)
		visit(n.body, builder, ast_context)
	case ^Call_Expr:
		visit(n.expr, builder, ast_context)
		visit(n.args, builder, ast_context)
	case ^Implicit_Selector_Expr:
		write_semantic_node(
			builder,
			n.field,
			ast_context.file.src,
			.EnumMember,
			.None,
		)
	case ^Array_Type:
		visit(n.len, builder, ast_context)
		visit(n.elem, builder, ast_context)
	case ^Binary_Expr:
		visit(n.left, builder, ast_context)
		visit_token_op(builder, n.op, ast_context.file.src)
		visit(n.right, builder, ast_context)
	case ^Comp_Lit:
		visit(n.type, builder, ast_context)
		visit(n.elems, builder, ast_context)
	case ^Struct_Type:
		write_semantic_string(
			builder,
			n.pos,
			"struct",
			ast_context.file.src,
			.Keyword,
			.None,
		)
		visit_struct_fields(n^, builder, ast_context)
	case ^Type_Assertion:
		visit(n.expr, builder, ast_context)
		visit(n.type, builder, ast_context)
	case ^Type_Cast:
		visit(n.type, builder, ast_context)
		visit(n.expr, builder, ast_context)
	case ^Paren_Expr:
		visit(n.expr, builder, ast_context)
	case ^Deref_Expr:
		visit(n.expr, builder, ast_context)
	case ^Return_Stmt:
		write_semantic_string(
			builder,
			n.pos,
			"return",
			ast_context.file.src,
			.Keyword,
			.None,
		)
		visit(n.results, builder, ast_context)
	case ^Dynamic_Array_Type:
		write_semantic_string(
			builder,
			n.dynamic_pos,
			"dynamic",
			ast_context.file.src,
			.Keyword,
			.None,
		)
		visit(n.elem, builder, ast_context)
	case ^Multi_Pointer_Type:
		write_semantic_string(
			builder,
			n.pos,
			"[^]",
			ast_context.file.src,
			.Keyword,
			.None,
		)
		visit(n.elem, builder, ast_context)
	case ^Field_Value:
		if ident, ok := n.field.derived.(^Ident); ok {
			write_semantic_node(
				builder,
				n.field,
				ast_context.file.src,
				.Property,
				.None,
			)
		} else {
			visit(n.field, builder, ast_context)
		}

		visit(n.value, builder, ast_context)
	case ^Index_Expr:
		visit(n.expr, builder, ast_context)
		visit(n.index, builder, ast_context)
	case ^Basic_Lit:
		visit_basic_lit(n^, builder, ast_context)
	case ^Unary_Expr:
		visit(n.expr, builder, ast_context)
	case ^Implicit:
	case ^Slice_Expr:
		visit(n.expr, builder, ast_context)
	case ^Using_Stmt:
		write_semantic_string(
			builder,
			n.pos,
			"using",
			ast_context.file.src,
			.Keyword,
			.None,
		)
		visit(n.list, builder, ast_context)
	case ^Map_Type:
		write_semantic_string(
			builder,
			n.tok_pos,
			"map",
			ast_context.file.src,
			.Keyword,
			.None,
		)
		visit(n.key, builder, ast_context)
		visit(n.value, builder, ast_context)
	case ^Defer_Stmt:
		write_semantic_string(
			builder,
			n.pos,
			"defer",
			ast_context.file.src,
			.Keyword,
			.None,
		)
		visit(n.stmt, builder, ast_context)
	case ^Import_Decl:
		write_semantic_token(
			builder,
			n.import_tok,
			ast_context.file.src,
			.Keyword,
			.None,
		)

		if n.name.text != "" {
			write_semantic_token(
				builder,
				n.name,
				ast_context.file.src,
				.Namespace,
				.None,
			)
		}

	case ^Or_Return_Expr:
		visit(n.expr, builder, ast_context)
		write_semantic_token(
			builder,
			n.token,
			ast_context.file.src,
			.Keyword,
			.None,
		)
	case ^Or_Else_Expr:
		visit(n.x, builder, ast_context)
		write_semantic_token(
			builder,
			n.token,
			ast_context.file.src,
			.Keyword,
			.None,
		)
		visit(n.y, builder, ast_context)
	case ^Ternary_If_Expr:
		if n.op1.text == "if" {
			visit(n.x, builder, ast_context)
			visit(n.cond, builder, ast_context)
			visit(n.y, builder, ast_context)
		} else {
			visit(n.cond, builder, ast_context)
			visit(n.x, builder, ast_context)
			visit(n.y, builder, ast_context)
		}
	case ^Ternary_When_Expr:
		visit(n.cond, builder, ast_context)
		visit(n.x, builder, ast_context)
		visit(n.y, builder, ast_context)
	case ^Union_Type:
		write_semantic_string(
			builder,
			n.pos,
			"union",
			ast_context.file.src,
			.Keyword,
			.None,
		)
		visit(n.variants, builder, ast_context)
	case ^ast.Enum_Type:
		write_semantic_string(
			builder,
			n.pos,
			"enum",
			ast_context.file.src,
			.Keyword,
			.None,
		)
		visit_enum_fields(n^, builder, ast_context)
	case ^Proc_Type:
		write_semantic_string(
			builder,
			n.pos,
			"proc",
			ast_context.file.src,
			.Keyword,
			.None,
		)
		visit_proc_type(n, builder, ast_context)
	case ^Proc_Lit:
		write_semantic_string(
			builder,
			n.pos,
			"proc",
			ast_context.file.src,
			.Keyword,
			.None,
		)
		visit_proc_type(n.type, builder, ast_context)

		visit(n.body, builder, ast_context)
	case:
	}
}

visit_basic_lit :: proc(
	basic_lit: ast.Basic_Lit,
	builder: ^SemanticTokenBuilder,
	ast_context: ^AstContext,
) {
	if symbol, ok := resolve_basic_lit(ast_context, basic_lit); ok {
		if untyped, ok := symbol.value.(SymbolUntypedValue); ok {
			#partial switch untyped.type {
			case .Bool:
				write_semantic_token(
					builder,
					basic_lit.tok,
					ast_context.file.src,
					.Keyword,
					.None,
				)
			case .Float, .Integer:
				write_semantic_token(
					builder,
					basic_lit.tok,
					ast_context.file.src,
					.Number,
					.None,
				)
			}
		}
	}
}

visit_value_decl :: proc(
	value_decl: ast.Value_Decl,
	builder: ^SemanticTokenBuilder,
	ast_context: ^AstContext,
) {
	using ast

	if value_decl.type != nil {
		for name in value_decl.names {
			write_semantic_node(
				builder,
				name,
				ast_context.file.src,
				.Variable,
				.None,
			)
		}

		visit(value_decl.type, builder, ast_context)

		if len(value_decl.values) == 1 {
			visit(value_decl.values[0], builder, ast_context)
		}

		return
	}

	if len(value_decl.values) == 1 {
		#partial switch v in value_decl.values[0].derived {
		case ^Union_Type:
			write_semantic_node(
				builder,
				value_decl.names[0],
				ast_context.file.src,
				.Enum,
				.None,
			)
			visit(value_decl.values[0], builder, ast_context)
		case ^Struct_Type:
			write_semantic_node(
				builder,
				value_decl.names[0],
				ast_context.file.src,
				.Struct,
				.None,
			)
			visit(value_decl.values[0], builder, ast_context)
		case ^Enum_Type:
			write_semantic_node(
				builder,
				value_decl.names[0],
				ast_context.file.src,
				.Enum,
				.None,
			)
			visit(value_decl.values[0], builder, ast_context)
		case ^Proc_Group:
			write_semantic_node(
				builder,
				value_decl.names[0],
				ast_context.file.src,
				.Function,
				.None,
			)
			write_semantic_string(
				builder,
				v.pos,
				"proc",
				ast_context.file.src,
				.Keyword,
				.None,
			)
			for arg in v.args {
				if ident, ok := arg.derived.(^Ident); ok {
					write_semantic_node(
						builder,
						arg,
						ast_context.file.src,
						.Function,
						.None,
					)
				}
			}
		case ^Proc_Lit:
			write_semantic_node(
				builder,
				value_decl.names[0],
				ast_context.file.src,
				.Function,
				.None,
			)
			visit(value_decl.values[0], builder, ast_context)
		case ^ast.Proc_Type:
			write_semantic_string(
				builder,
				v.pos,
				"proc",
				ast_context.file.src,
				.Keyword,
				.None,
			)
			visit_proc_type(v, builder, ast_context)
		case:
			for name in value_decl.names {
				write_semantic_node(
					builder,
					name,
					ast_context.file.src,
					.Variable,
					.None,
				)
			}

			visit(value_decl.values[0], builder, ast_context)
		}
	} else {
		for name in value_decl.names {
			write_semantic_node(
				builder,
				name,
				ast_context.file.src,
				.Variable,
				.None,
			)
		}

		for value in value_decl.values {
			visit(value, builder, ast_context)
		}
	}
}

visit_token_op :: proc(
	builder: ^SemanticTokenBuilder,
	token: tokenizer.Token,
	src: string,
) {
	if token.text == "in" {
		write_semantic_string(
			builder,
			token.pos,
			token.text,
			src,
			.Keyword,
			.None,
		)
	} else {
		write_semantic_string(
			builder,
			token.pos,
			token.text,
			src,
			.Operator,
			.None,
		)
	}
}

visit_proc_type :: proc(
	node: ^ast.Proc_Type,
	builder: ^SemanticTokenBuilder,
	ast_context: ^AstContext,
) {
	using ast

	if node == nil {
		return
	}

	if node.params != nil {
		for param in node.params.list {
			for name in param.names {
				if ident, ok := name.derived.(^Ident); ok {
					write_semantic_node(
						builder,
						name,
						ast_context.file.src,
						.Parameter,
						.None,
					)
				}
			}

			visit(param.type, builder, ast_context)
		}
	}

	if node.results != nil {
		for result in node.results.list {
			visit(result.names, builder, ast_context)
			visit(result.type, builder, ast_context)
		}
	}
}

visit_enum_fields :: proc(
	node: ast.Enum_Type,
	builder: ^SemanticTokenBuilder,
	ast_context: ^AstContext,
) {
	using ast

	if node.fields == nil {
		return
	}

	for field in node.fields {
		if ident, ok := field.derived.(^Ident); ok {
			write_semantic_node(
				builder,
				field,
				ast_context.file.src,
				.EnumMember,
				.None,
			)
		} else if f, ok := field.derived.(^Field_Value); ok {
			if _, ok := f.field.derived.(^Ident); ok {
				write_semantic_node(
					builder,
					f.field,
					ast_context.file.src,
					.EnumMember,
					.None,
				)
			}
			visit(f.value, builder, ast_context)
		}
	}
}

visit_struct_fields :: proc(
	node: ast.Struct_Type,
	builder: ^SemanticTokenBuilder,
	ast_context: ^AstContext,
) {
	using ast

	if node.fields == nil {
		return
	}

	for field in node.fields.list {
		for name in field.names {
			if ident, ok := name.derived.(^Ident); ok {
				write_semantic_node(
					builder,
					name,
					ast_context.file.src,
					.Property,
					.None,
				)
			}
		}

		visit(field.type, builder, ast_context)
	}
}

visit_selector :: proc(
	selector: ^ast.Selector_Expr,
	builder: ^SemanticTokenBuilder,
	ast_context: ^AstContext,
) {
	if _, ok := selector.expr.derived.(^ast.Selector_Expr); ok {
		visit_selector(
			cast(^ast.Selector_Expr)selector.expr,
			builder,
			ast_context,
		)
	} else {
		visit(selector.expr, builder, ast_context)
		builder.selector = true
	}

	if symbol_and_node, ok := builder.symbols[cast(uintptr)selector]; ok {
		if symbol_and_node.symbol.type == .Variable {
			write_semantic_node(
				builder,
				selector.field,
				ast_context.file.src,
				.Property,
				.None,
			)
		}
		#partial switch v in symbol_and_node.symbol.value {
		case SymbolPackageValue:
			write_semantic_node(
				builder,
				selector.field,
				ast_context.file.src,
				.Namespace,
				.None,
			)
		case SymbolStructValue:
			write_semantic_node(
				builder,
				selector.field,
				ast_context.file.src,
				.Struct,
				.None,
			)
		case SymbolEnumValue:
			write_semantic_node(
				builder,
				selector.field,
				ast_context.file.src,
				.Enum,
				.None,
			)
		case SymbolUnionValue:
			write_semantic_node(
				builder,
				selector.field,
				ast_context.file.src,
				.Enum,
				.None,
			)
		case SymbolProcedureValue:
			write_semantic_node(
				builder,
				selector.field,
				ast_context.file.src,
				.Function,
				.None,
			)
		case SymbolProcedureGroupValue:
			write_semantic_node(
				builder,
				selector.field,
				ast_context.file.src,
				.Function,
				.None,
			)
		}
	}
}
