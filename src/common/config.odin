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
	enable_format:            bool,
	enable_hover:             bool,
	enable_document_symbols:  bool,
	enable_semantic_tokens:   bool, 
	thread_count:             int,
}

config: Config;