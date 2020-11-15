package server


SemanticTokenTypes :: enum {
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
	declaration,
	definition,
	deprecated,
};