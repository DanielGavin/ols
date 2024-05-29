package server

import "base:runtime"

import "core:fmt"
import "core:log"
import "core:mem"
import "core:odin/ast"
import "core:odin/parser"
import "core:os"
import "core:path/filepath"
import path "core:path/slashpath"
import "core:slice"
import "core:strings"

import "src:common"

fullpaths: [dynamic]string

walk_directories :: proc(
	info: os.File_Info,
	in_err: os.Errno,
	user_data: rawptr,
) -> (
	err: os.Errno,
	skip_dir: bool,
) {
	document := cast(^Document)user_data

	if info.is_dir {
		return 0, false
	}

	if info.fullpath == "" {
		return 0, false
	}

	if strings.contains(info.name, ".odin") {
		slash_path, _ := filepath.to_slash(info.fullpath)
		if slash_path != document.fullpath {
			append(&fullpaths, strings.clone(info.fullpath))
		}
	}

	return 0, false
}

position_in_struct_names :: proc(
	position_context: ^DocumentPositionContext,
	type: ^ast.Struct_Type,
) -> bool {
	for field in type.fields.list {
		for name in field.names {
			if position_in_node(name, position_context.position) {
				return true
			}
		}
	}

	return false
}


resolve_references :: proc(
	document: ^Document,
	ast_context: ^AstContext,
	position_context: ^DocumentPositionContext,
) -> (
	[]common.Location,
	bool,
) {
	locations := make([dynamic]common.Location, 0, ast_context.allocator)
	fullpaths = make([dynamic]string, 0, ast_context.allocator)

	resolve_flag: ResolveReferenceFlag
	reference := ""
	symbol: Symbol
	ok: bool
	pkg := ""

	filepath.walk(common.get_executable_path(), walk_directories, document)

	for workspace in common.config.workspace_folders {
		uri, _ := common.parse_uri(workspace.uri, context.temp_allocator)
		filepath.walk(uri.path, walk_directories, document)
	}

	reset_ast_context(ast_context)

	if position_context.struct_type != nil &&
	   position_in_struct_names(
		   position_context,
		   position_context.struct_type,
	   ) {
		return {}, true
	} else if position_context.enum_type != nil {
		return {}, true
	} else if position_context.bitset_type != nil {
		return {}, true
	} else if position_context.union_type != nil {
		return {}, true
	} else if position_context.selector_expr != nil {
		if resolved, ok := resolve_type_expression(
			ast_context,
			position_context.selector,
		); ok {
			if _, is_package := resolved.value.(SymbolPackageValue);
			   !is_package {
				return {}, true
			}
			resolve_flag = .Constant
		}

		symbol, ok = resolve_location_selector(
			ast_context,
			position_context.selector_expr,
		)

		if !ok {
			return {}, true
		}

		if ident, ok := position_context.identifier.derived.(^ast.Ident); ok {
			reference = ident.name
		} else {
			return {}, true
		}
	} else if position_context.implicit {
		return {}, true
	} else if position_context.identifier != nil {
		ident := position_context.identifier.derived.(^ast.Ident)

		if resolved, ok := resolve_type_identifier(ast_context, ident^); ok {
			if resolved.type == .Variable {
				resolve_flag = .Variable
			} else {
				resolve_flag = .Constant
			}
		} else {
			log.errorf(
				"Failed to resolve identifier for indexing: %v",
				ident.name,
			)
			return {}, true
		}

		reference = ident.name
		symbol, ok = resolve_location_identifier(ast_context, ident^)

		if !ok {
			return {}, true
		}
	}

	arena: runtime.Arena

	_ = runtime.arena_init(
		&arena,
		mem.Megabyte * 40,
		runtime.default_allocator(),
	)

	defer runtime.arena_destroy(&arena)

	context.allocator = runtime.arena_allocator(&arena)

	fullpaths := slice.unique(fullpaths[:])

	if .Local not_in symbol.flags {
		for fullpath in fullpaths {
			dir := filepath.dir(fullpath)
			base := filepath.base(dir)
			forward_dir, _ := filepath.to_slash(dir)

			data, ok := os.read_entire_file(fullpath, context.allocator)

			if !ok {
				log.errorf(
					"failed to read entire file for indexing %v",
					fullpath,
				)
				continue
			}

			p := parser.Parser {
				err   = log_error_handler,
				warn  = log_warning_handler,
				flags = {.Optional_Semicolons},
			}


			pkg := new(ast.Package)
			pkg.kind = .Normal
			pkg.fullpath = fullpath
			pkg.name = base

			if base == "runtime" {
				pkg.kind = .Runtime
			}

			file := ast.File {
				fullpath = fullpath,
				src      = string(data),
				pkg      = pkg,
			}

			ok = parser.parse_file(&p, &file)

			if !ok {
				if !strings.contains(fullpath, "builtin.odin") &&
				   !strings.contains(fullpath, "intrinsics.odin") {
					log.errorf("error in parse file for indexing %v", fullpath)
				}
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
				if pkg.name == symbol.pkg {
					in_pkg = true
					continue
				}
			}

			if in_pkg {
				symbols_and_nodes := resolve_entire_file(
					&document,
					resolve_flag,
					context.allocator,
				)

				for k, v in symbols_and_nodes {
					if v.symbol.uri == symbol.uri &&
					   v.symbol.range == symbol.range {
						node_uri := common.create_uri(
							v.node.pos.file,
							ast_context.allocator,
						)

						location := common.Location {
							range = common.get_token_range(
								v.node^,
								string(document.text),
							),
							uri   = strings.clone(
								node_uri.uri,
								ast_context.allocator,
							),
						}
						append(&locations, location)
					}
				}
			}

			free_all(context.allocator)
		}
	}

	symbols_and_nodes := resolve_entire_file(
		document,
		resolve_flag,
		context.allocator,
	)

	for k, v in symbols_and_nodes {
		if v.symbol.uri == symbol.uri && v.symbol.range == symbol.range {
			node_uri := common.create_uri(
				v.node.pos.file,
				ast_context.allocator,
			)

			location := common.Location {
				range = common.get_token_range(v.node^, string(document.text)),
				uri   = strings.clone(node_uri.uri, ast_context.allocator),
			}
			append(&locations, location)
		}
	}

	return locations[:], true
}

get_references :: proc(
	document: ^Document,
	position: common.Position,
) -> (
	[]common.Location,
	bool,
) {
	ast_context := make_ast_context(
		document.ast,
		document.imports,
		document.package_name,
		document.uri.uri,
		document.fullpath,
		context.temp_allocator,
	)

	position_context, ok := get_document_position_context(
		document,
		position,
		.Hover,
	)

	get_globals(document.ast, &ast_context)

	ast_context.current_package = ast_context.document_package

	if position_context.function != nil {
		get_locals(
			document.ast,
			position_context.function,
			&ast_context,
			&position_context,
		)
	}

	locations, ok2 := resolve_references(
		document,
		&ast_context,
		&position_context,
	)

	temp_locations := make([dynamic]common.Location, 0, context.temp_allocator)

	for location in locations {
		temp_location := common.Location {
			range = location.range,
			uri   = strings.clone(location.uri, context.temp_allocator),
		}
		append(&temp_locations, temp_location)
	}

	return temp_locations[:], ok2
}
