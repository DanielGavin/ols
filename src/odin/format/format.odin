package odin_format

import "shared:odin/printer"
import "core:odin/parser"
import "core:odin/ast"
import "core:encoding/json"
import "core:os"
import "core:path/filepath"
import "core:fmt"

default_style := printer.default_style

simplify :: proc(file: ^ast.File) {

}

find_config_file_or_default :: proc(path: string) -> printer.Config {
	//go up the directory until we find odinfmt.json
	path := path

	ok: bool
	if path, ok = filepath.abs(path); !ok {
		return default_style
	}

	name := fmt.tprintf("%v/odinfmt.json", path)
	found := false
	config := default_style

	if (os.exists(name)) {
		if data, ok := os.read_entire_file(name, context.temp_allocator); ok {
			if json.unmarshal(data, &config) == nil {
				found = true
			}
		}
	} else {
		new_path := filepath.join(
			elems = {path, ".."},
			allocator = context.temp_allocator,
		)
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

	return printer.print(&prnt, &file), true
}
