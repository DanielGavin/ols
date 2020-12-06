package common

Config :: struct {
    workspace_folders: [dynamic] WorkspaceFolder,
    completion_support_md: bool,
    hover_support_md: bool,
    signature_offset_support: bool,
    collections: map [string] string,
    running: bool,
    debug_single_thread: bool,
};

