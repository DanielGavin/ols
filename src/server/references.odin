package server 


import "shared:common"

import "core:strings"
import "core:odin/ast"
import "core:odin/parser"
import path "core:path/slashpath"
import "core:log"
import "core:path/filepath"
import "core:fmt"
import "core:os"
import "core:mem"
import "core:runtime"

fullpaths: [dynamic]string

walk_directories :: proc(info: os.File_Info, in_err: os.Errno) -> (err: os.Errno, skip_dir: bool) {
	if info.is_dir {
		return 0, false
	}

	if info.fullpath == "" {
		return 0, false
	}

	if strings.contains(info.name, ".odin") {
		append(&fullpaths, strings.clone(info.fullpath, runtime.default_allocator()))
	}

	return 0, false
}


resolve_references :: proc(ast_context: ^AstContext, position_context: ^DocumentPositionContext) -> ([]common.Location, bool)  {
	locations := make([dynamic]common.Location, 0, context.allocator)
	fullpaths = make([dynamic]string, 10, context.allocator)

	resolve_flag: ResolveReferenceFlag
	reference := ""
	symbol: Symbol
	ok: bool
	pkg := ""

	if position_context.selector != nil {

	} else if position_context.call != nil {

	} else if position_context.identifier != nil {
		resolve_flag = .Identifier
		ident := position_context.identifier.derived.(^ast.Ident)
		reference = ident.name
		symbol, ok = resolve_location_identifier(ast_context, ident^)

		location := common.Location {
			range = common.get_token_range(position_context.identifier^, string(ast_context.file.src)),
			uri = strings.clone(symbol.uri, runtime.default_allocator()),
		} 
		append(&locations, location)
	}
	
	if !ok {
		return {}, false
	}

	symbol_uri := strings.clone(symbol.uri, context.allocator)
	symbol_pkg := strings.clone(symbol.pkg, context.allocator)
	symbol_range := symbol.range

	temp_arena: mem.Arena

	mem.init_arena(&temp_arena, make([]byte, mem.Megabyte*25, runtime.default_allocator()))

	context.allocator = mem.arena_allocator(&temp_arena)

	{
		context.temp_allocator = context.allocator
		filepath.walk(filepath.dir(os.args[0], context.temp_allocator), walk_directories)
	}

	for fullpath in fullpaths {
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

		document := Document {
			ast = file,
		}

		document.uri = uri 
		document.text = transmute([]u8)file.src
		document.used_text = len(file.src)

		document_setup(&document)

		parse_imports(&document, &common.config)

		in_pkg := false

		for pkg in document.imports {
			if pkg.name == symbol_pkg || symbol.pkg == ast_context.document_package {
				in_pkg = true
			}
		}

		if in_pkg {
			symbols_and_nodes := resolve_entire_file(&document, reference, resolve_flag, context.allocator)

			for k, v in symbols_and_nodes {
				if v.symbol.uri  == symbol_uri && v.symbol.range == symbol_range {
					location := common.Location {
						range = common.get_token_range(v.node^, string(document.text)),
						uri = strings.clone(v.symbol.uri, runtime.default_allocator()),
					} 
					append(&locations, location)
				}
			}
		}

		

		delete(fullpath)
		free_all(context.allocator)
	}

	delete(fullpaths)
	delete(temp_arena.data)
	delete(symbol_uri)



	return locations[:], true
}

get_references :: proc(document: ^Document, position: common.Position) -> ([]common.Location, bool) {
	ast_context := make_ast_context(document.ast, document.imports, document.package_name, document.uri.uri, document.fullpath)

	position_context, ok := get_document_position_context(document, position, .Hover)

	get_globals(document.ast, &ast_context)

	ast_context.current_package = ast_context.document_package

	if position_context.function != nil {
		get_locals(document.ast, position_context.function, &ast_context, &position_context)
	}

	return resolve_references(&ast_context, &position_context)
}