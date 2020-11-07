package common

Config :: struct {
    workspace_folders: [dynamic] WorkspaceFolder,
    completion_support_md: bool,
    hover_support_md: bool,
    collections: map [string] string,
    running: bool,
};

