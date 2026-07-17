package odin_format

import "core:encoding/json"
import "core:fmt"
import "core:odin/ast"
import "core:odin/parser"
import "core:os"
import "core:path/filepath"
import "src:odin/printer"

default_style := printer.default_style

simplify :: proc(file: ^ast.File) {

}

find_config_file_or_default :: proc(path: string) -> printer.Config {
	//go up the directory until we find odinfmt.json
	path := path

	err: os.Error
	if path, err = filepath.abs(path, context.temp_allocator); err != nil {
		return default_style
	}

	name := fmt.tprintf("%v/odinfmt.json", path)
	found := false
	config := default_style

	if os.exists(name) {
		if data, err := os.read_entire_file(name, context.temp_allocator); err == nil {
			if json.unmarshal(data, &config) == nil {
				found = true
			}
		}
	} else {
		new_path, _ := filepath.join(elems = {path, ".."}, allocator = context.temp_allocator)
		//Currently the filepath implementation seems to stop at the root level, this might not be the best solution.
		if new_path == path {
			return default_style
		}
		return find_config_file_or_default(new_path)
	}

	if !found {
		return default_style
	}

	return config
}

// Tries to read the config file from a given path instead
// of searching for it up a directory tree of a path
read_config_file_from_path_or_default :: proc(config_path: string) -> printer.Config {
    path := config_path
	err: os.Error
	if path, err = filepath.abs(config_path, context.temp_allocator); err != nil {
		return default_style
	}
    config := default_style
    if os.exists(path) {
        if data, err := os.read_entire_file(path, context.temp_allocator); err == nil {
            if json.unmarshal(data, &config) == nil {
                return config
            }
        }
    }

    return default_style
}

format :: proc(
	filepath: string,
	source: string,
	config: printer.Config,
	parser_flags := parser.Flags{.Optional_Semicolons},
	allocator := context.allocator,
) -> (
	string,
	bool,
) {
	config := config

	pkg := ast.Package {
		kind = .Normal,
	}

	file := ast.File {
		pkg      = &pkg,
		src      = source,
		fullpath = filepath,
	}

	config.newline_limit = clamp(config.newline_limit, 0, 16)
	config.spaces = clamp(config.spaces, 1, 16)

	p := parser.default_parser(parser_flags)

	ok := parser.parse_file(&p, &file)

	if !ok || file.syntax_error_count > 0 {
		return {}, false
	}

	prnt := printer.make_printer(config, allocator)

	src := printer.print(&prnt, &file)

	return src, !prnt.errored_out
}
