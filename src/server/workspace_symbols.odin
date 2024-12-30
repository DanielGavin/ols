package server


import "core:fmt"
import "core:log"
import "core:os"
import "core:path/filepath"
import "core:strings"

import "src:common"

dir_blacklist :: []string{"node_modules", ".git"}

@(private)
walk_dir :: proc(info: os.File_Info, in_err: os.Errno, user_data: rawptr) -> (err: os.Error, skip_dir: bool) {
	pkgs := cast(^[dynamic]string)user_data

	if info.is_dir {
		dir, _ := filepath.to_slash(info.fullpath, context.temp_allocator)
		dir_name := filepath.base(dir)

		for blacklist in dir_blacklist {
			if blacklist == dir_name {
				return nil, true
			}
		}
		append(pkgs, dir)
	}

	return nil, false
}

get_workspace_symbols :: proc(query: string) -> (workspace_symbols: []WorkspaceSymbol, ok: bool) {
	workspace := common.config.workspace_folders[0]
	uri := common.parse_uri(workspace.uri, context.temp_allocator) or_return
	pkgs := make([dynamic]string, 0, context.temp_allocator)
	symbols := make([dynamic]WorkspaceSymbol, 0, 100, context.temp_allocator)

	filepath.walk(uri.path, walk_dir, &pkgs)

	log.error(pkgs)

	_pkg: for pkg in pkgs {
		matches, err := filepath.glob(fmt.tprintf("%v/*.odin", pkg), context.temp_allocator)

		if len(matches) == 0 {
			continue
		}

		for exclude_path in common.config.profile.exclude_path {
			exclude_forward, _ := filepath.to_slash(exclude_path, context.temp_allocator)

			if exclude_forward[len(exclude_forward) - 2:] == "**" {
				lower_pkg := strings.to_lower(pkg)
				lower_exclude := strings.to_lower(exclude_forward[:len(exclude_forward) - 3])
				if strings.contains(lower_pkg, lower_exclude) {
					continue _pkg
				}
			} else {
				lower_pkg := strings.to_lower(pkg)
				lower_exclude := strings.to_lower(exclude_forward)
				if lower_pkg == lower_exclude {
					continue _pkg
				}
			}
		}

		try_build_package(pkg)

		if results, ok := fuzzy_search(query, {pkg}); ok {
			for result in results {
				symbol := WorkspaceSymbol {
					name = result.symbol.name,
					location = {range = result.symbol.range, uri = result.symbol.uri},
					kind = symbol_kind_to_type(result.symbol.type),
				}

				append(&symbols, symbol)
			}
		}
	}


	return symbols[:], true
}
