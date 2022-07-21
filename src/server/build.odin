package server

import "core:path/filepath"
import path "core:path/slashpath"
import "core:os"
import "core:fmt"
import "core:odin/parser"
import "core:odin/ast"
import "core:log"
import "core:odin/tokenizer"
import "core:strings"
import "core:mem"
import "core:runtime"
import "core:time"

import "shared:common"

platform_os: map[string]bool = {
	"windows" = true,
	"linux" = true, 
	"essence" = true,
	"js" = true,
	"freebsd" = true,
	"darwin" = true,
	"wasm32" = true,
}

os_enum_to_string: map[runtime.Odin_OS_Type]string = {
	.Windows = "windows",
	.Darwin = "darwin",
	.Linux = "linux",
	.Essence = "essence",
	.FreeBSD = "freebsd",
	.WASI = "wasi",
	.JS = "js",
	.Freestanding = "freestanding",
}

try_build_package :: proc(pkg_name: string) {
	if pkg, ok := build_cache.loaded_pkgs[pkg_name]; ok {
		return
	}

	matches, err := filepath.glob(fmt.tprintf("%v/*.odin", pkg_name), context.temp_allocator)

	if err != .None {
		log.errorf("Failed to glob %v for indexing package", pkg_name)
	}

	temp_arena: mem.Arena

	mem.init_arena(&temp_arena, make([]byte, mem.Megabyte*25, runtime.default_allocator()))
	
	{
		context.allocator = mem.arena_allocator(&temp_arena)

		for fullpath in matches {
			data, ok := os.read_entire_file(fullpath, context.allocator)

			if !ok {
				log.errorf("failed to read entire file for indexing %v", fullpath)
				continue
			}

			p := parser.Parser {
				err = log_error_handler,
				warn = log_warning_handler,
				flags = {.Optional_Semicolons},
			}

			dir := filepath.base(filepath.dir(fullpath, context.allocator))

			pkg := new(ast.Package)
			pkg.kind = .Normal
			pkg.fullpath = fullpath
			pkg.name = dir

			if dir == "runtime" {
				pkg.kind = .Runtime
			}

			file := ast.File {
				fullpath = fullpath,
				src = string(data),
				pkg = pkg,
			}

			ok = parser.parse_file(&p, &file)

			if !ok {
				log.errorf("error in parse file for indexing %v", fullpath)
				continue
			}

			uri := common.create_uri(fullpath, context.allocator)

			collect_symbols(&indexer.index.collection, file, uri.uri)

			free_all(context.allocator)
		}
	}

	delete(temp_arena.data)

	build_cache.loaded_pkgs[strings.clone(pkg_name, indexer.index.collection.allocator)] = PackageCacheInfo {
		timestamp = time.now(),
	} 
}

setup_index :: proc() {
	build_cache.loaded_pkgs = make(map[string]PackageCacheInfo, 50, context.allocator)
	symbol_collection := make_symbol_collection(context.allocator, &common.config)
	indexer.index = make_memory_index(symbol_collection)

	dir_exe := path.dir(os.args[0])
	
	try_build_package(path.join({dir_exe, "builtin"}))
}

free_index :: proc() {
	delete_symbol_collection(indexer.index.collection)
}

log_error_handler :: proc(pos: tokenizer.Pos, msg: string, args: ..any) {
	log.warnf("%v %v %v", pos, msg, args)
}

log_warning_handler :: proc(pos: tokenizer.Pos, msg: string, args: ..any) {
	log.warnf("%v %v %v", pos, msg, args)
}
