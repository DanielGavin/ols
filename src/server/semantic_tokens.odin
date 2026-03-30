/*

LSP Reference:
https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_semanticTokens

*/
package server

import "core:odin/ast"
import "core:odin/tokenizer"
import "core:unicode/utf8"

import "src:common"

SemanticTokenTypes :: enum u32 {
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
	TypeParameter,
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
	"typeParameter",
}

SemanticTokenModifier :: enum u8 {
	Declaration,
	DefaultLibrary,
	Definition,
	Deprecated,
	ReadOnly,
}
// Need to be in the same order as SemanticTokenModifier
semantic_token_modifier_names: []string = {"declaration", "defaultLibrary", "definition", "deprecated", "readonly"}
SemanticTokenModifiers :: bit_set[SemanticTokenModifier;u32]

SemanticTokensRequest :: struct {
	range: bool,
}

SemanticTokensClientCapabilities :: struct {
	requests:                SemanticTokensRequest,
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

SemanticToken :: struct {
	// token line number, relative to the previous token
	delta_line: u32,
	// token start character, relative to the previous token
	// (relative to 0 or the previous token’s start if they are on the same line)
	delta_char: u32,
	len:        u32,
	type:       SemanticTokenTypes,
	modifiers:  SemanticTokenModifiers,
}
#assert(size_of(SemanticToken) == 5 * size_of(u32))

SemanticTokensResponseParams :: struct {
	data: []u32,
}

SemanticTokenBuilder :: struct {
	current_start: int,
	tokens:        [dynamic]SemanticToken,
	symbols:       map[uintptr]SymbolAndNode,
	src:           string,
}

semantic_tokens_to_response_params :: proc(tokens: []SemanticToken) -> SemanticTokensResponseParams {
	return {data = (cast([^]u32)raw_data(tokens))[:len(tokens) * 5]}
}

get_semantic_tokens :: proc(
	document: ^Document,
	range: common.Range,
	symbols: map[uintptr]SymbolAndNode,
) -> []SemanticToken {
	ast_context := make_ast_context(
		document.ast,
		document.imports,
		document.package_name,
		document.uri.uri,
		document.fullpath,
	)
	ast_context.current_package = ast_context.document_package

	builder: SemanticTokenBuilder = {
		tokens  = make([dynamic]SemanticToken, 0, 2000, context.temp_allocator),
		symbols = symbols,
		src     = ast_context.file.src,
	}

	margin := 20

	for decl in document.ast.decls {
		//Look for declarations that overlap with range
		if range.start.line - margin <= decl.end.line && decl.pos.line <= range.end.line + margin {
			visit_node(decl, &builder)
		}
	}

	return builder.tokens[:]
}

write_semantic_at_pos :: proc(
	builder: ^SemanticTokenBuilder,
	pos: int,
	len: int,
	type: SemanticTokenTypes,
	modifiers: SemanticTokenModifiers = {},
) {
	position := common.get_relative_token_position(pos, transmute([]u8)builder.src, builder.current_start)
	append(
		&builder.tokens,
		SemanticToken {
			delta_line = cast(u32)position.line,
			delta_char = cast(u32)position.character,
			len = cast(u32)len,
			type = type,
			modifiers = modifiers,
		},
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

	name := get_ast_node_string(node, builder.src)

	write_semantic_at_pos(builder, node.pos.offset, len(name), type, modifiers)
}

write_semantic_token :: proc(
	builder: ^SemanticTokenBuilder,
	token: tokenizer.Token,
	type: SemanticTokenTypes,
	modifiers: SemanticTokenModifiers = {},
) {
	write_semantic_at_pos(builder, token.pos.offset, len(token.text), type, modifiers)
}

visit_nodes :: proc(array: []$T/^ast.Node, builder: ^SemanticTokenBuilder) {
	for elem in array {
		visit_node(elem, builder)
	}
}

visit_node :: proc(node: ^ast.Node, builder: ^SemanticTokenBuilder) {
	if node == nil {
		return
	}

	#partial switch n in node.derived {
	case ^ast.Ellipsis:
		visit_node(n.expr, builder)
	case ^ast.Ident:
		visit_ident(n, n, {}, builder)
	case ^ast.Selector_Expr:
		visit_node(n.expr, builder)
		visit_ident(n.field, n, {}, builder)
	case ^ast.When_Stmt:
		visit_node(n.cond, builder)
		visit_node(n.body, builder)
		visit_node(n.else_stmt, builder)
	case ^ast.Pointer_Type:
		visit_node(n.elem, builder)
	case ^ast.Value_Decl:
		visit_value_decl(n^, builder)
	case ^ast.Block_Stmt:
		visit_nodes(n.stmts, builder)
	case ^ast.Foreign_Block_Decl:
		visit_node(n.body, builder)
	case ^ast.Expr_Stmt:
		visit_node(n.expr, builder)
	case ^ast.Matrix_Type:
		visit_node(n.row_count, builder)
		visit_node(n.column_count, builder)
		visit_node(n.elem, builder)
	case ^ast.Matrix_Index_Expr:
		visit_node(n.expr, builder)
		visit_node(n.row_index, builder)
		visit_node(n.column_index, builder)
	case ^ast.Poly_Type:
		write_semantic_node(builder, n.type, .TypeParameter)
		visit_node(n.specialization, builder)
	case ^ast.Range_Stmt:
		for val in n.vals {
			if ident, ok := val.derived.(^ast.Ident); ok {
				write_semantic_node(builder, val, .Variable)
			}
		}

		visit_node(n.expr, builder)
		visit_node(n.body, builder)
	case ^ast.If_Stmt:
		visit_node(n.init, builder)
		visit_node(n.cond, builder)
		visit_node(n.body, builder)

		if n.else_stmt != nil {
			visit_node(n.else_stmt, builder)
		}
	case ^ast.For_Stmt:
		visit_node(n.init, builder)
		visit_node(n.cond, builder)
		visit_node(n.post, builder)
		visit_node(n.body, builder)
	case ^ast.Switch_Stmt:
		visit_node(n.init, builder)
		visit_node(n.cond, builder)
		visit_node(n.body, builder)
	case ^ast.Type_Switch_Stmt:
		visit_node(n.tag, builder)
		visit_node(n.expr, builder)
		visit_node(n.body, builder)
	case ^ast.Assign_Stmt:
		for l in n.lhs {
			if ident, ok := l.derived.(^ast.Ident); ok {
				write_semantic_node(builder, l, .Variable)
			} else {
				visit_node(l, builder)
			}
		}
		visit_nodes(n.rhs, builder)
	case ^ast.Case_Clause:
		visit_nodes(n.list, builder)
		visit_nodes(n.body, builder)
	case ^ast.Call_Expr:
		visit_node(n.expr, builder)
		visit_nodes(n.args, builder)
	case ^ast.Implicit_Selector_Expr:
		write_semantic_node(builder, n.field, .EnumMember)
	case ^ast.Array_Type:
		visit_node(n.len, builder)
		visit_node(n.elem, builder)
	case ^ast.Binary_Expr:
		visit_node(n.left, builder)
		visit_node(n.right, builder)
	case ^ast.Comp_Lit:
		visit_node(n.type, builder)
		visit_nodes(n.elems, builder)
	case ^ast.Struct_Type:
		visit_poly_params(n.poly_params, builder)
		visit_struct_fields(n^, builder)
	case ^ast.Type_Assertion:
		visit_node(n.expr, builder)
		visit_node(n.type, builder)
	case ^ast.Type_Cast:
		visit_node(n.type, builder)
		visit_node(n.expr, builder)
	case ^ast.Paren_Expr:
		visit_node(n.expr, builder)
	case ^ast.Deref_Expr:
		visit_node(n.expr, builder)
	case ^ast.Return_Stmt:
		visit_nodes(n.results, builder)
	case ^ast.Dynamic_Array_Type:
		visit_node(n.elem, builder)
	case ^ast.Multi_Pointer_Type:
		visit_node(n.elem, builder)
	case ^ast.Field_Value:
		if ident, ok := n.field.derived.(^ast.Ident); ok {
			write_semantic_node(builder, n.field, .Property)
		} else {
			visit_node(n.field, builder)
		}

		visit_node(n.value, builder)
	case ^ast.Index_Expr:
		visit_node(n.expr, builder)
		visit_node(n.index, builder)
	case ^ast.Unary_Expr:
		visit_node(n.expr, builder)
	case ^ast.Implicit:
	case ^ast.Slice_Expr:
		visit_node(n.expr, builder)
	case ^ast.Using_Stmt:
		visit_nodes(n.list, builder)
	case ^ast.Map_Type:
		visit_node(n.key, builder)
		visit_node(n.value, builder)
	case ^ast.Bit_Set_Type:
		visit_node(n.elem, builder)
		visit_node(n.underlying, builder)
	case ^ast.Defer_Stmt:
		visit_node(n.stmt, builder)
	case ^ast.Import_Decl:
		visit_import_decl(n, builder)
	case ^ast.Or_Return_Expr:
		visit_node(n.expr, builder)
	case ^ast.Or_Else_Expr:
		visit_node(n.x, builder)
		visit_node(n.y, builder)
	case ^ast.Or_Branch_Expr:
		visit_node(n.expr, builder)
		visit_node(n.label, builder)
	case ^ast.Ternary_If_Expr:
		if n.op1.text == "if" {
			visit_node(n.x, builder)
			visit_node(n.cond, builder)
			visit_node(n.y, builder)
		} else {
			visit_node(n.cond, builder)
			visit_node(n.x, builder)
			visit_node(n.y, builder)
		}
	case ^ast.Ternary_When_Expr:
		visit_node(n.x, builder)
		visit_node(n.cond, builder)
		visit_node(n.y, builder)
	case ^ast.Union_Type:
		visit_poly_params(n.poly_params, builder)
		visit_nodes(n.variants, builder)
	case ^ast.Enum_Type:
		visit_enum_fields(n^, builder)
	case ^ast.Proc_Type:
		visit_proc_type(n, builder)
	case ^ast.Proc_Lit:
		visit_proc_type(n.type, builder)
		visit_node(n.body, builder)
	case ^ast.Proc_Group:
		for arg in n.args {
			ident := arg.derived.(^ast.Ident) or_continue
			write_semantic_node(builder, arg, .Function)
		}
	case ^ast.Bit_Field_Type:
		visit_bit_field_fields(n^, builder)
	case ^ast.Helper_Type:
		visit_node(n.type, builder)
	case:
	}
}

visit_value_decl :: proc(value_decl: ast.Value_Decl, builder: ^SemanticTokenBuilder) {
	modifiers: SemanticTokenModifiers = value_decl.is_mutable ? {} : {.ReadOnly}

	for name in value_decl.names {
		ident := name.derived.(^ast.Ident) or_continue
		visit_ident(ident, ident, modifiers, builder)
	}

	visit_node(value_decl.type, builder)

	for value in value_decl.values {
		visit_node(value, builder)
	}
}

visit_proc_type :: proc(node: ^ast.Proc_Type, builder: ^SemanticTokenBuilder) {
	if node == nil {
		return
	}

	if node.params != nil {
		for param in node.params.list {
			for name in param.names {
				if ident, ok := name.derived.(^ast.Ident); ok {
					write_semantic_node(builder, name, .Parameter)
				}
			}

			visit_node(param.type, builder)
			visit_node(param.default_value, builder)
		}
	}

	if node.results != nil {
		for result in node.results.list {
			visit_nodes(result.names, builder)
			visit_node(result.type, builder)
		}
	}
}

visit_enum_fields :: proc(node: ast.Enum_Type, builder: ^SemanticTokenBuilder) {
	if node.fields == nil {
		return
	}

	for field in node.fields {
		if ident, ok := field.derived.(^ast.Ident); ok {
			write_semantic_node(builder, field, .EnumMember)
		} else if f, ok := field.derived.(^ast.Field_Value); ok {
			if _, ok := f.field.derived.(^ast.Ident); ok {
				write_semantic_node(builder, f.field, .EnumMember)
			}
			visit_node(f.value, builder)
		}
	}
}

visit_struct_fields :: proc(node: ast.Struct_Type, builder: ^SemanticTokenBuilder) {
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

visit_poly_params :: proc(params: ^ast.Field_List, builder: ^SemanticTokenBuilder) {
	if params == nil {
		return
	}

	for param in params.list {
		for name in param.names {
			if poly, ok := name.derived.(^ast.Poly_Type); ok {
				write_semantic_node(builder, poly.type, .TypeParameter)
			}
		}
		visit_node(param.type, builder)
	}
}

visit_bit_field_fields :: proc(node: ast.Bit_Field_Type, builder: ^SemanticTokenBuilder) {
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

visit_import_decl :: proc(decl: ^ast.Import_Decl, builder: ^SemanticTokenBuilder) {
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
				ch, w := utf8.decode_last_rune_in_string(decl.relpath.text[:pos])

				switch ch {
				case ':', '/': // break
				case:
					pos -= w
					continue
				}
			}

			break
		}

		write_semantic_at_pos(builder, decl.relpath.pos.offset + pos, end - pos, .Namespace)
	}
}

visit_ident :: proc(
	ident: ^ast.Ident,
	symbol_ptr: rawptr,
	modifiers: SemanticTokenModifiers,
	builder: ^SemanticTokenBuilder,
) {
	symbol_and_node, in_symbols := builder.symbols[cast(uintptr)symbol_ptr]
	if !in_symbols {
		return
	}
	symbol := symbol_and_node.symbol

	modifiers := modifiers

	if .Builtin in symbol.flags {
		modifiers += {.DefaultLibrary}
	}

	if .Mutable not_in symbol.flags {
		modifiers += {.ReadOnly}
	}

	if .PolyType in symbol.flags {
		write_semantic_node(builder, ident, .TypeParameter, modifiers)
		return
	}

	if .Variable in symbol.flags {
		write_semantic_node(builder, ident, .Variable, modifiers)
		return
	}

	/* variable idents */
	#partial switch symbol.type {
	case .Variable, .Constant, .Function:
		#partial switch _ in symbol.value {
		case SymbolProcedureValue, SymbolProcedureGroupValue, SymbolAggregateValue:
			write_semantic_node(builder, ident, .Function, modifiers)
		case:
			if .Parameter in symbol.flags {
				write_semantic_node(builder, ident, .Parameter, modifiers)
			} else {
				write_semantic_node(builder, ident, .Variable, modifiers)
			}
		}
	case .EnumMember:
		write_semantic_node(builder, ident, .EnumMember, modifiers)
	case .Field:
		write_semantic_node(builder, ident, .Property, modifiers)
	case:
		/* type idents */
		switch v in symbol.value {
		case SymbolPackageValue:
			write_semantic_node(builder, ident, .Namespace, modifiers)
		case SymbolStructValue, SymbolBitFieldValue:
			write_semantic_node(builder, ident, .Struct, modifiers)
		case SymbolEnumValue, SymbolUnionValue:
			write_semantic_node(builder, ident, .Enum, modifiers)
		case SymbolPolyTypeValue:
			write_semantic_node(builder, ident, .TypeParameter, modifiers)
		case SymbolProcedureValue,
		     SymbolMatrixValue,
		     SymbolBitSetValue,
		     SymbolDynamicArrayValue,
		     SymbolFixedArrayValue,
		     SymbolSliceValue,
		     SymbolMapValue,
		     SymbolMultiPointerValue,
		     SymbolBasicValue:
			write_semantic_node(builder, ident, .Type, modifiers)
		case SymbolUntypedValue:
		// handled by static syntax highlighting
		case SymbolGenericValue, SymbolProcedureGroupValue, SymbolAggregateValue:
		// unused
		case:
		}
	}
}
