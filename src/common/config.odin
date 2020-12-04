package common

Config :: struct {
    workspace_folders: [dynamic] WorkspaceFolder,
    completion_support_md: bool,
    hover_support_md: bool,
    signature_offset_support: bool,
    collections: map [string] string,
    thread_pool_count: int,
    running: bool,
};

