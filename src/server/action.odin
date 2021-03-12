package server

CodeActionKind :: struct {}

CodeActionClientCapabilities :: struct {
	codeActionLiteralSupport: struct {
		codeActionKind: struct {
			valueSet: []CodeActionKind,
		},
	},
}

CodeActionOptions :: struct {
	codeActionKinds: []CodeActionKind,
	resolveProvider: bool,
}
