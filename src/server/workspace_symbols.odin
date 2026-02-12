package server

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"

import "src:common"

dir_blacklist :: []string{"node_modules", ".git"}

WorkspaceCache :: struct {
	time:      time.Time,
	pkgs:      [dynamic]string,
}

@(thread_local, private = "file")
cache: WorkspaceCache

get_workspace_symbols :: proc(query: string) -> (workspace_symbols: []WorkspaceSymbol, ok: bool) {
	if time.since(cache.time) > 20 * time.Second {
		for pkg in cache.pkgs {
			delete(pkg)
		}
		clear(&cache.pkgs)
		for workspace in common.config.workspace_folders {
			uri := common.parse_uri(workspace.uri, context.temp_allocator) or_return
			pkgs := make([dynamic]string, 0, context.temp_allocator)

			w := os.walker_create(uri.path)
			for info in os.walker_walk(&w) {
				if info.type == .Directory {
					dir := filepath.dir(info.fullpath, context.temp_allocator)
					dir_name := filepath.base(dir)
					found := false
					for blacklist in dir_blacklist {
						if blacklist == dir_name {
							found = true
							break
						}
					}
					if !found {
						append(&pkgs, dir)
					}
				}
			}

			_pkg: for pkg in pkgs {
				matches, err := filepath.glob(fmt.tprintf("%v/*.odin", pkg), context.temp_allocator)

				if len(matches) == 0 {
					continue
				}

				for exclude_path in common.config.profile.exclude_path {
					exclude_forward, _ := filepath.replace_path_separators(exclude_path, '/', context.temp_allocator)

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
				append(&cache.pkgs, strings.clone(pkg, context.allocator))
			}
		}
		cache.time = time.now()
	}

	limit :: 100
	symbols := make([dynamic]WorkspaceSymbol, 0, limit, context.temp_allocator)
	if results, ok := fuzzy_search(query, cache.pkgs[:], "", resolve_fields = false, limit = limit); ok {
		for result in results {
			symbol := WorkspaceSymbol {
				name = result.symbol.name,
				location = {range = result.symbol.range, uri = result.symbol.uri},
				kind = symbol_kind_to_type(result.symbol.type),
			}

			append(&symbols, symbol)
		}
	}


	return symbols[:], true
}
