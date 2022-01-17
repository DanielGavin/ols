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
	enable_procedure_context: bool,
	enable_snippets:          bool,
	thread_count:             int,
	file_log:                 bool,
	formatter:                Format_Config,
	odin_command:             string,
	checker_args:             string,
}

Format_Config :: struct {
	tabs: bool,
	characters: int,
}

config: Config;