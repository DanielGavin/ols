package server

import "shared:common"

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
};

SemanticTokenModifiers :: enum {
	Declaration,
	Definition,
	Deprecated,
};

SemanticTokensClientCapabilities :: struct {

	requests: struct {
		range: bool,
	},

	tokenTypes: [] string,
	tokenModifiers: [] string,
	formats: [] string,
	overlappingTokenSupport: bool,
	multilineTokenSupport: bool,
};

SemanticTokensLegend :: struct {
	tokenTypes: [] string,
	tokenModifiers: [] string,
};

SemanticTokensOptions :: struct {
	legend: SemanticTokensLegend,
	range: bool,
	full: bool,
};

SemanticTokensParams :: struct {
	textDocument: TextDocumentIdentifier,
};

SemanticTokensRangeParams :: struct {
	textDocument: TextDocumentIdentifier,
	range: common.Range,
};

SemanticTokens :: struct {
	data: [] uint,
};

get_semantic_tokens :: proc(document: ^Document) -> [] SemanticTokens {




	return {};
}
