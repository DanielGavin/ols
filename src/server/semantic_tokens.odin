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

SemanticTokenInternal :: struct {
	line: uint,
	column: uint,
	length: uint,
};


convert_to_finished_tokens :: proc(tokens: [dynamic]SemanticTokenInternal) -> [] SemanticTokens {
	return {};
}

get_semantic_tokens :: proc(document: ^Document) -> [] SemanticTokens {

	tokens := make([dynamic]SemanticTokenInternal, context.temp_allocator);

	/*
		Temp parse the document again, right now there is too many leaks that need to be fixued in the parser.
	*/


	return {};
}


/*
extract_semantic_tokens :: proc {
	extract_semantic_tokens_node,
	extract_semantic_tokens_dynamic_array,
    extract_semantic_tokens_array,
};

extract_semantic_tokens_node :: proc() {

}
*/