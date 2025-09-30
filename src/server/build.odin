#+feature dynamic-literals
package server

import "base:runtime"

import "core:fmt"
import "core:log"
import "core:mem"
import "core:odin/ast"
import "core:odin/parser"
import "core:odin/tokenizer"
import "core:os"
import "core:path/filepath"
import path "core:path/slashpath"
import "core:strings"
import "core:time"

import "src:common"

platform_os: map[string]struct{} = {
	"windows" = {},
	"linux"   = {},
	"essence" = {},
	"js"      = {},
	"freebsd" = {},
	"darwin"  = {},
	"wasm32"  = {},
	"openbsd" = {},
	"wasi"    = {},
	"wasm"    = {},
	"haiku"   = {},
	"netbsd"  = {},
	"freebsd" = {},
}


os_enum_to_string: [runtime.Odin_OS_Type]string = {
	.Windows      = "windows",
	.Darwin       = "darwin",
	.Linux        = "linux",
	.Essence      = "essence",
	.FreeBSD      = "freebsd",
	.WASI         = "wasi",
	.JS           = "js",
	.Freestanding = "freestanding",
	.Haiku        = "haiku",
	.OpenBSD      = "openbsd",
	.NetBSD       = "netbsd",
	.Orca         = "orca",
	.Unknown      = "unknown",
}

os_string_to_enum: map[string]runtime.Odin_OS_Type = {
	"Windows"      = .Windows,
	"windows"      = .Windows,
	"Darwin"       = .Darwin,
	"darwin"       = .Darwin,
	"Linux"        = .Linux,
	"linux"        = .Linux,
	"Essence"      = .Essence,
	"essence"      = .Essence,
	"Freebsd"      = .FreeBSD,
	"freebsd"      = .FreeBSD,
	"Wasi"         = .WASI,
	"wasi"         = .WASI,
	"Js"           = .JS,
	"js"           = .JS,
	"Freestanding" = .Freestanding,
	"freestanding" = .Freestanding,
	"Wasm"         = .JS,
	"wasm"         = .JS,
	"Haiku"        = .Haiku,
	"haiku"        = .Haiku,
	"Openbsd"      = .OpenBSD,
	"openbsd"      = .OpenBSD,
	"Netbsd"       = .NetBSD,
	"netbsd"       = .NetBSD,
	"Orca"         = .Orca,
	"orca"         = .Orca,
	"Unknown"      = .Unknown,
	"unknown"      = .Unknown,
}

@(private = "file")
is_bsd_variant :: proc(name: string) -> bool {
	return(
		common.config.profile.os == os_enum_to_string[.FreeBSD] ||
		common.config.profile.os == os_enum_to_string[.OpenBSD] ||
		common.config.profile.os == os_enum_to_string[.NetBSD] \
	)
}

@(private = "file")
is_unix_variant :: proc(name: string) -> bool {
	return(
		common.config.profile.os == os_enum_to_string[.Linux] ||
		common.config.profile.os == os_enum_to_string[.Darwin] \
	)
}

skip_file :: proc(filename: string) -> bool {
	last_underscore_index := strings.last_index(filename, "_")
	last_dot_index := strings.last_index(filename, ".")

	if last_underscore_index + 1 < last_dot_index {
		name_between := filename[last_underscore_index + 1:last_dot_index]

		if name_between == "unix" {
			return !is_unix_variant(name_between)
		}

		if name_between == "bsd" {
			return !is_bsd_variant(name_between)
		}

		if _, ok := platform_os[name_between]; ok {
			return name_between != common.config.profile.os
		}
	}

	return false
}

should_collect_file :: proc(file_tags: parser.File_Tags) -> bool {
	if file_tags.ignore {
		return false
	}

	if len(file_tags.build) > 0 {
		if used_os, ok := os_string_to_enum[common.config.profile.os]; ok {
			found := false
			for tag in file_tags.build {
				if used_os in tag.os {
					found = true
					break
				}
			}
			if !found {
				return false
			}
		}
	}
	return true
}

try_build_package :: proc(pkg_name: string) {
	if pkg, ok := build_cache.loaded_pkgs[pkg_name]; ok {
		return
	}

	matches, err := filepath.glob(fmt.tprintf("%v/*.odin", pkg_name), context.temp_allocator)

	if err != .None {
		log.errorf("Failed to glob %v for indexing package", pkg_name)
		return
	}

	arena: runtime.Arena
	result := runtime.arena_init(&arena, mem.Megabyte * 40, runtime.default_allocator())
	defer runtime.arena_destroy(&arena)

	{
		context.allocator = runtime.arena_allocator(&arena)

		for fullpath in matches {
			if skip_file(filepath.base(fullpath)) {
				continue
			}

			data, ok := os.read_entire_file(fullpath, context.allocator)

			if !ok {
				log.errorf("failed to read entire file for indexing %v", fullpath)
				continue
			}

			p := parser.Parser {
				err   = log_error_handler,
				warn  = log_warning_handler,
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
				src      = string(data),
				pkg      = pkg,
			}

			ok = parser.parse_file(&p, &file)

			if !ok {
				if !strings.contains(fullpath, "builtin.odin") && !strings.contains(fullpath, "intrinsics.odin") {
					log.errorf("error in parse file for indexing %v", fullpath)
				}
				continue
			}

			uri := common.create_uri(fullpath, context.allocator)

			collect_symbols(&indexer.index.collection, file, uri.uri)

			runtime.arena_free_all(&arena)
		}
	}

	build_cache.loaded_pkgs[strings.clone(pkg_name, indexer.index.collection.allocator)] = PackageCacheInfo {
		timestamp = time.now(),
	}
}


remove_index_file :: proc(uri: common.Uri) -> common.Error {
	ok: bool

	fullpath := uri.path

	when ODIN_OS == .Windows {
		fullpath, _ = filepath.to_slash(fullpath, context.temp_allocator)
	}

	corrected_uri := common.create_uri(fullpath, context.temp_allocator)

	for k, &v in indexer.index.collection.packages {
		for k2, v2 in v.symbols {
			if strings.equal_fold(corrected_uri.uri, v2.uri) {
				free_symbol(v2, indexer.index.collection.allocator)
				delete_key(&v.symbols, k2)
			}
		}

		for method, &symbols in v.methods {
			for i := len(symbols) - 1; i >= 0; i -= 1 {
				#no_bounds_check symbol := symbols[i]
				if strings.equal_fold(corrected_uri.uri, symbol.uri) {
					unordered_remove(&symbols, i)
				}
			}
		}
	}

	return .None
}

index_file :: proc(uri: common.Uri, text: string) -> common.Error {
	ok: bool

	fullpath := uri.path

	p := parser.Parser {
		err   = log_error_handler,
		warn  = log_warning_handler,
		flags = {.Optional_Semicolons},
	}

	when ODIN_OS == .Windows {
		correct := common.get_case_sensitive_path(fullpath, context.temp_allocator)
		fullpath, _ = filepath.to_slash(correct, context.temp_allocator)
	}

	dir := filepath.base(filepath.dir(fullpath, context.temp_allocator))

	pkg := new(ast.Package)
	pkg.kind = .Normal
	pkg.fullpath = fullpath
	pkg.name = dir

	if dir == "runtime" {
		pkg.kind = .Runtime
	}

	file := ast.File {
		fullpath = fullpath,
		src      = text,
		pkg      = pkg,
	}

	{
		allocator := context.allocator
		context.allocator = context.temp_allocator
		defer context.allocator = allocator

		ok = parser.parse_file(&p, &file)

		if !ok {
			if !strings.contains(fullpath, "builtin.odin") && !strings.contains(fullpath, "intrinsics.odin") {
				log.errorf("error in parse file for indexing %v", fullpath)
			}
		}
	}

	corrected_uri := common.create_uri(fullpath, context.temp_allocator)

	for k, &v in indexer.index.collection.packages {
		for k2, v2 in v.symbols {
			if corrected_uri.uri == v2.uri {
				free_symbol(v2, indexer.index.collection.allocator)
				delete_key(&v.symbols, k2)
			}
		}

		for method, &symbols in v.methods {
			for i := len(symbols) - 1; i >= 0; i -= 1 {
				#no_bounds_check symbol := symbols[i]
				if corrected_uri.uri == symbol.uri {
					unordered_remove(&symbols, i)
				}
			}
		}
	}

	if ret := collect_symbols(&indexer.index.collection, file, corrected_uri.uri); ret != .None {
		log.errorf("failed to collect symbols on save %v", ret)
	}

	return .None
}


setup_index :: proc() {
	build_cache.loaded_pkgs = make(map[string]PackageCacheInfo, 50, context.allocator)
	symbol_collection := make_symbol_collection(context.allocator, &common.config)
	indexer.index = make_memory_index(symbol_collection)

	dir_exe := common.get_executable_path(context.temp_allocator)
	builtin_path := path.join({dir_exe, "builtin"}, context.temp_allocator)

	if !os.exists(builtin_path) {
		log.errorf(
			"Failed to find the builtin folder at `%v`.\nPlease ensure the `builtin` folder that ships with `ols` is located next to the `ols` binary as it is required for ols to work with builtins",
			builtin_path,
		)
		return
	}

	try_build_package(builtin_path)
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
