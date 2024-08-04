package server


import "core:fmt"
import "core:log"
import "core:os"
import "core:path/filepath"

import "src:common"

@(private)
walk_dir :: proc(
	info: os.File_Info,
	in_err: os.Errno,
	user_data: rawptr,
) -> (
	err: os.Error,
	skip_dir: bool,
) {
	pkgs := cast(^[dynamic]string)user_data

	if info.is_dir {
		dir, _ := filepath.to_slash(info.fullpath, context.temp_allocator)
		append(pkgs, dir)
	}

	return nil, false
}

get_workspace_symbols :: proc(
	query: string,
) -> (
	workspace_symbols: []WorkspaceSymbol,
	ok: bool,
) {
	workspace := common.config.workspace_folders[0]
	uri := common.parse_uri(workspace.uri, context.temp_allocator) or_return
	pkgs := make([dynamic]string, 0, context.temp_allocator)
	symbols := make([dynamic]WorkspaceSymbol, 0, 100, context.temp_allocator)

	filepath.walk(uri.path, walk_dir, &pkgs)

	for pkg in pkgs {
		matches, err := filepath.glob(
			fmt.tprintf("%v/*.odin", pkg),
			context.temp_allocator,
		)

		if len(matches) == 0 {
			continue
		}

		try_build_package(pkg)

		if results, ok := fuzzy_search(query, {pkg}); ok {
			for result in results {
				symbol := WorkspaceSymbol {
					name = result.symbol.name,
					location = {
						range = result.symbol.range,
						uri = result.symbol.uri,
					},
					kind = symbol_kind_to_type(result.symbol.type),
				}

				append(&symbols, symbol)
			}
		}
	}


	return symbols[:], true
}
