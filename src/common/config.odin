package common

Config :: struct {
	workspace_folders:        [dynamic]WorkspaceFolder,
	completion_support_md:    bool,
	hover_support_md:         bool,
	signature_offset_support: bool,
	collections:              map[string]string,
	running:                  bool,
	verbose:                  bool,
	debug_single_thread:      bool,
	enable_semantic_tokens:   bool, //This will be removed when vscode client stops sending me semantic tokens after disabling it in requests initialize.
}

config: Config;