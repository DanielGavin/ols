package common

ConfigProfile :: struct {
	os:           string,
	name:         string,
	checker_path: [dynamic]string,
	defines:      map[string]string,
}

Config :: struct {
	workspace_folders:                 [dynamic]WorkspaceFolder,
	completion_support_md:             bool,
	hover_support_md:                  bool,
	signature_offset_support:          bool,
	collections:                       map[string]string,
	running:                           bool,
	verbose:                           bool,
	enable_format:                     bool,
	enable_hover:                      bool,
	enable_document_symbols:           bool,
	enable_semantic_tokens:            bool,
	enable_inlay_hints:                bool,
	enable_inlay_hints_params:         bool,
	enable_inlay_hints_default_params: bool,
	enable_procedure_context:          bool,
	enable_snippets:                   bool,
	enable_references:                 bool,
	enable_rename:                     bool,
	enable_label_details:              bool,
	enable_std_references:             bool,
	enable_import_fixer:               bool,
	enable_fake_method:                bool,
	enable_procedure_snippet:          bool,
	enable_checker_only_saved:         bool,
	disable_parser_errors:             bool,
	thread_count:                      int,
	file_log:                          bool,
	odin_command:                      string,
	checker_args:                      string,
	checker_targets:                   []string,
	client_name:                       string,
	profile:                           ConfigProfile,
}

config: Config
