package server


import "core:path/filepath"
import "core:os"
import "core:log"

import "shared:common"

@(private)
walk_dir :: proc(
	info: os.File_Info,
	in_err: os.Errno,
	user_data: rawptr,
) -> (
	err: os.Errno,
	skip_dir: bool,
) {
	pkgs := cast(^[dynamic]string)user_data

	if info.is_dir {
		append(pkgs, info.name)
	}

	return 0, false
}

get_workspace_symbols :: proc(
	query: string,
) -> (
	symbols: []WorkspaceSymbol,
	ok: bool,
) {
	workspace := common.config.workspace_folders[0]
	uri := common.parse_uri(workspace.uri, context.temp_allocator) or_return
	pkgs := make([dynamic]string, 0, context.temp_allocator)

	filepath.walk(uri.path, walk_dir, &pkgs)

	for pkg in pkgs {
		//log.error(pkg)
	}

	return {}, true
}
