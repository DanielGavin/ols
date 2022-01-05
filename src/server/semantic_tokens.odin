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
	requests: struct {
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

	builder := make_token_builder();

	if document.ast.pkg_decl != nil {
		write_semantic_token(&builder, document.ast.pkg_token, document.ast.src, .Keyword, .None);
	}

	resolve_entire_file(document, context.temp_allocator);

	for decl in document.ast.decls {
		if range.start.line <= decl.pos.line && decl.end.line <= range.end.line {
			
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

write_semantic_string :: proc(builder: ^SemanticTokenBuilder, pos: tokenizer.Pos, name: string, src: string, type: SemanticTokenTypes, modifier: SemanticTokenModifiers) {
	position := common.get_relative_token_position(pos.offset, transmute([]u8)src, builder.current_start);

	append(&builder.tokens, cast(u32)position.line, cast(u32)position.character, cast(u32)len(name), cast(u32)type, 0);

	builder.current_start = pos.offset;
}

