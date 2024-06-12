/*

LSP Reference:
https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_semanticTokens

*/

package server

import "core:fmt"
import "core:log"
import "core:odin/ast"
import "core:odin/tokenizer"
import "core:unicode/utf8"

import "src:common"

SemanticTokenTypes :: enum u8 {
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
// Need to be in the same order as SemanticTokenTypes
semantic_token_type_names: []string = {
	"namespace",
	"type",
	"enum",
	"struct",
	"parameter",
	"variable",
	"enumMember",
	"function",
	"member",
	"keyword",
	"modifier",
	"comment",
	"string",
	"number",
	"operator",
	"property",
	"method",
}

SemanticTokenModifier :: enum u8 {
	Declaration,
	Definition,
	Deprecated,
	ReadOnly,
}
// Need to be in the same order as SemanticTokenModifier
semantic_token_modifier_names: []string = {
	"declaration",
	"definition",
	"deprecated",
	"readonly",
}
SemanticTokenModifiers :: bit_set[SemanticTokenModifier;u32]

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
	src:           string,
}

get_semantic_tokens :: proc(
	document: ^Document,
	range: common.Range,
	symbols: map[uintptr]SymbolAndNode,
) -> SemanticTokens {
	ast_context := make_ast_context(
		document.ast,
		document.imports,
		document.package_name,
		document.uri.uri,
		document.fullpath,
	)
	ast_context.current_package = ast_context.document_package

	builder: SemanticTokenBuilder = {
		tokens  = make([dynamic]u32, 0, 10000, context.temp_allocator),
		symbols = symbols,
		src     = ast_context.file.src,
	}

	for decl in document.ast.decls {
		if range.start.line <= decl.pos.line &&
		   decl.end.line <= range.end.line {
			visit_node(decl, &builder)
		}
	}

	return {data = builder.tokens[:]}
}

write_semantic_at_pos :: proc(
	builder: ^SemanticTokenBuilder,
	pos: int,
	len: int,
	type: SemanticTokenTypes,
	modifiers: SemanticTokenModifiers = {},
) {
	position := common.get_relative_token_position(
		pos,
		transmute([]u8)builder.src,
		builder.current_start,
	)
	append(
		&builder.tokens,
		cast(u32)position.line,
		cast(u32)position.character,
		cast(u32)len,
		cast(u32)type,
		transmute(u32)modifiers,
	)
	builder.current_start = pos
}

write_semantic_node :: proc(
	builder: ^SemanticTokenBuilder,
	node: ^ast.Node,
	type: SemanticTokenTypes,
	modifiers: SemanticTokenModifiers = {},
) {
	//Sometimes odin ast uses "_" for empty params.
	if ident, ok := node.derived.(^ast.Ident); ok && ident.name == "_" {
		return
	}

	name := common.get_ast_node_string(node, builder.src)

	write_semantic_at_pos(builder, node.pos.offset, len(name), type, modifiers)
}

write_semantic_token :: proc(
	builder: ^SemanticTokenBuilder,
	token: tokenizer.Token,
	type: SemanticTokenTypes,
	modifiers: SemanticTokenModifiers = {},
) {
	write_semantic_at_pos(
		builder,
		token.pos.offset,
		len(token.text),
		type,
		modifiers,
	)
}

visit_nodes :: proc(array: []$T/^ast.Node, builder: ^SemanticTokenBuilder) {
	for elem in array {
		visit_node(elem, builder)
	}
}

visit_node :: proc(node: ^ast.Node, builder: ^SemanticTokenBuilder) {
	using ast

	if node == nil {
		return
	}

	#partial switch n in node.derived {
	case ^Ellipsis:
		visit_node(n.expr, builder)
	case ^Ident:
		visit_ident(n, n, {}, builder)
	case ^Selector_Expr:
		visit_node(n.expr, builder)
		visit_ident(n.field, n, {}, builder)
	case ^When_Stmt:
		visit_node(n.cond, builder)
		visit_node(n.body, builder)
		visit_node(n.else_stmt, builder)
	case ^Pointer_Type:
		visit_node(n.elem, builder)
	case ^Value_Decl:
		visit_value_decl(n^, builder)
	case ^Block_Stmt:
		visit_nodes(n.stmts, builder)
	case ^Foreign_Block_Decl:
		visit_node(n.body, builder)
	case ^Expr_Stmt:
		visit_node(n.expr, builder)
	case ^Matrix_Type:
		visit_node(n.row_count, builder)
		visit_node(n.column_count, builder)
		visit_node(n.elem, builder)
	case ^Matrix_Index_Expr:
		visit_node(n.expr, builder)
		visit_node(n.row_index, builder)
		visit_node(n.column_index, builder)
	case ^Poly_Type:
		visit_node(n.type, builder)
		visit_node(n.specialization, builder)
	case ^Range_Stmt:
		for val in n.vals {
			if ident, ok := val.derived.(^Ident); ok {
				write_semantic_node(builder, val, .Variable)
			}
		}

		visit_node(n.expr, builder)
		visit_node(n.body, builder)
	case ^If_Stmt:
		visit_node(n.init, builder)
		visit_node(n.cond, builder)
		visit_node(n.body, builder)

		if n.else_stmt != nil {
			visit_node(n.else_stmt, builder)
		}
	case ^For_Stmt:
		visit_node(n.init, builder)
		visit_node(n.cond, builder)
		visit_node(n.post, builder)
		visit_node(n.body, builder)
	case ^Switch_Stmt:
		visit_node(n.init, builder)
		visit_node(n.cond, builder)
		visit_node(n.body, builder)
	case ^Type_Switch_Stmt:
		visit_node(n.tag, builder)
		visit_node(n.expr, builder)
		visit_node(n.body, builder)
	case ^Assign_Stmt:
		for l in n.lhs {
			if ident, ok := l.derived.(^Ident); ok {
				write_semantic_node(builder, l, .Variable)
			} else {
				visit_node(l, builder)
			}
		}
		visit_nodes(n.rhs, builder)
	case ^Case_Clause:
		visit_nodes(n.list, builder)
		visit_nodes(n.body, builder)
	case ^Call_Expr:
		visit_node(n.expr, builder)
		visit_nodes(n.args, builder)
	case ^Implicit_Selector_Expr:
		write_semantic_node(builder, n.field, .EnumMember)
	case ^Array_Type:
		visit_node(n.len, builder)
		visit_node(n.elem, builder)
	case ^Binary_Expr:
		visit_node(n.left, builder)
		visit_node(n.right, builder)
	case ^Comp_Lit:
		visit_node(n.type, builder)
		visit_nodes(n.elems, builder)
	case ^Struct_Type:
		visit_struct_fields(n^, builder)
	case ^Type_Assertion:
		visit_node(n.expr, builder)
		visit_node(n.type, builder)
	case ^Type_Cast:
		visit_node(n.type, builder)
		visit_node(n.expr, builder)
	case ^Paren_Expr:
		visit_node(n.expr, builder)
	case ^Deref_Expr:
		visit_node(n.expr, builder)
	case ^Return_Stmt:
		visit_nodes(n.results, builder)
	case ^Dynamic_Array_Type:
		visit_node(n.elem, builder)
	case ^Multi_Pointer_Type:
		visit_node(n.elem, builder)
	case ^Field_Value:
		if ident, ok := n.field.derived.(^Ident); ok {
			write_semantic_node(builder, n.field, .Property)
		} else {
			visit_node(n.field, builder)
		}

		visit_node(n.value, builder)
	case ^Index_Expr:
		visit_node(n.expr, builder)
		visit_node(n.index, builder)
	case ^Unary_Expr:
		visit_node(n.expr, builder)
	case ^Implicit:
	case ^Slice_Expr:
		visit_node(n.expr, builder)
	case ^Using_Stmt:
		visit_nodes(n.list, builder)
	case ^Map_Type:
		visit_node(n.key, builder)
		visit_node(n.value, builder)
	case ^Bit_Set_Type:
		visit_node(n.elem, builder)
		visit_node(n.underlying, builder)
	case ^Defer_Stmt:
		visit_node(n.stmt, builder)
	case ^Import_Decl:
		visit_import_decl(n, builder)
	case ^Or_Return_Expr:
		visit_node(n.expr, builder)
	case ^Or_Else_Expr:
		visit_node(n.x, builder)
		visit_node(n.y, builder)
	case ^ast.Or_Branch_Expr:
		visit_node(n.expr, builder)
		visit_node(n.label, builder)
	case ^Ternary_If_Expr:
		if n.op1.text == "if" {
			visit_node(n.x, builder)
			visit_node(n.cond, builder)
			visit_node(n.y, builder)
		} else {
			visit_node(n.cond, builder)
			visit_node(n.x, builder)
			visit_node(n.y, builder)
		}
	case ^Ternary_When_Expr:
		visit_node(n.cond, builder)
		visit_node(n.x, builder)
		visit_node(n.y, builder)
	case ^Union_Type:
		visit_nodes(n.variants, builder)
	case ^Enum_Type:
		visit_enum_fields(n^, builder)
	case ^Proc_Type:
		visit_proc_type(n, builder)
	case ^Proc_Lit:
		visit_proc_type(n.type, builder)
		visit_node(n.body, builder)
	case ^Proc_Group:
		for arg in n.args {
			ident := arg.derived.(^Ident) or_continue
			write_semantic_node(builder, arg, .Function)
		}
	case ^Bit_Field_Type:
		visit_bit_field_fields(n^, builder)
	case:
	}
}

visit_value_decl :: proc(
	value_decl: ast.Value_Decl,
	builder: ^SemanticTokenBuilder,
) {
	using ast

	modifiers: SemanticTokenModifiers =
		value_decl.is_mutable ? {} : {.ReadOnly}

	for name in value_decl.names {
		ident := name.derived.(^Ident) or_continue
		visit_ident(ident, ident, modifiers, builder)
	}

	visit_node(value_decl.type, builder)

	for value in value_decl.values {
		visit_node(value, builder)
	}
}

visit_proc_type :: proc(node: ^ast.Proc_Type, builder: ^SemanticTokenBuilder) {
	using ast

	if node == nil {
		return
	}

	if node.params != nil {
		for param in node.params.list {
			for name in param.names {
				if ident, ok := name.derived.(^Ident); ok {
					write_semantic_node(builder, name, .Parameter)
				}
			}

			visit_node(param.type, builder)
		}
	}

	if node.results != nil {
		for result in node.results.list {
			visit_nodes(result.names, builder)
			visit_node(result.type, builder)
		}
	}
}

visit_enum_fields :: proc(
	node: ast.Enum_Type,
	builder: ^SemanticTokenBuilder,
) {
	using ast

	if node.fields == nil {
		return
	}

	for field in node.fields {
		if ident, ok := field.derived.(^Ident); ok {
			write_semantic_node(builder, field, .EnumMember)
		} else if f, ok := field.derived.(^Field_Value); ok {
			if _, ok := f.field.derived.(^Ident); ok {
				write_semantic_node(builder, f.field, .EnumMember)
			}
			visit_node(f.value, builder)
		}
	}
}

visit_struct_fields :: proc(
	node: ast.Struct_Type,
	builder: ^SemanticTokenBuilder,
) {
	if node.fields == nil {
		return
	}

	for field in node.fields.list {
		for name in field.names {
			if ident, ok := name.derived.(^ast.Ident); ok {
				write_semantic_node(builder, ident, .Property)
			}
		}

		visit_node(field.type, builder)
	}
}

visit_bit_field_fields :: proc(
	node: ast.Bit_Field_Type,
	builder: ^SemanticTokenBuilder,
) {
	if node.fields == nil {
		return
	}

	for field in node.fields {
		if ident, ok := field.name.derived.(^ast.Ident); ok {
			write_semantic_node(builder, ident, .Property)
		}

		visit_node(field.type, builder)
		visit_node(field.bit_size, builder)
	}
}

visit_import_decl :: proc(
	decl: ^ast.Import_Decl,
	builder: ^SemanticTokenBuilder,
) {
	/*
	hightlight the namespace in the import declaration
	
	import "pkg"
	        ^^^
	import "core:fmt"
	             ^^^
	import "core:odin/ast"
	                  ^^^
	import foo "core:fmt"
	       ^^^
	*/

	if decl.name.text != "" {
		write_semantic_token(builder, decl.name, .Namespace)
	} else if len(decl.relpath.text) > 2 {

		end := len(decl.relpath.text) - 1
		pos := end

		for {
			if pos > 1 {
				ch, w := utf8.decode_last_rune_in_string(
					decl.relpath.text[:pos],
				)

				switch ch {
				case ':', '/': // break
				case:
					pos -= w
					continue
				}
			}

			break
		}

		write_semantic_at_pos(
			builder,
			decl.relpath.pos.offset + pos,
			end - pos,
			.Namespace,
		)
	}
}

visit_ident :: proc(
	ident: ^ast.Ident,
	symbol_ptr: rawptr,
	modifiers: SemanticTokenModifiers,
	builder: ^SemanticTokenBuilder,
) {
	using ast

	symbol_and_node, in_symbols := builder.symbols[cast(uintptr)symbol_ptr]
	if !in_symbols {
		return
	}
	symbol := symbol_and_node.symbol

	modifiers := modifiers
	if symbol.type != .Variable {
		modifiers += {.ReadOnly}
	}

	/* variable idents */
	#partial switch symbol.type {
	case .Variable, .Constant, .Function:
		#partial switch _ in symbol.value {
		case SymbolProcedureValue, SymbolProcedureGroupValue, SymbolAggregateValue:
			write_semantic_node(builder, ident, .Function, modifiers)
		case:
			write_semantic_node(builder, ident, .Variable, modifiers)
		}
	case .EnumMember:
		write_semantic_node(builder, ident, .EnumMember, modifiers)
	}

	/* type idents */
	switch v in symbol.value {
	case SymbolPackageValue:
		write_semantic_node(builder, ident, .Namespace, modifiers)
	case SymbolStructValue, SymbolBitFieldValue:
		write_semantic_node(builder, ident, .Struct, modifiers)
	case SymbolEnumValue, SymbolUnionValue:
		write_semantic_node(builder, ident, .Enum, modifiers)
	case SymbolProcedureValue,
	     SymbolMatrixValue,
	     SymbolBitSetValue,
	     SymbolDynamicArrayValue,
	     SymbolFixedArrayValue,
	     SymbolSliceValue,
	     SymbolMapValue,
	     SymbolMultiPointer,
	     SymbolBasicValue:
		write_semantic_node(builder, ident, .Type, modifiers)
	case SymbolUntypedValue:
	// handled by static syntax highlighting
	case SymbolGenericValue, SymbolProcedureGroupValue, SymbolAggregateValue:
	// unused
	case:
	// log.errorf("Unexpected symbol value: %v", symbol.value);
	// panic(fmt.tprintf("Unexpected symbol value: %v", symbol.value));
	}
}
