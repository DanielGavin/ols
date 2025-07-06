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

walk_directories :: proc(info: os.File_Info, in_err: os.Errno, user_data: rawptr) -> (err: os.Error, skip_dir: bool) {
	document := cast(^Document)user_data

	if info.is_dir {
		return nil, false
	}

	if info.fullpath == "" {
		return nil, false
	}

	if strings.contains(info.name, ".odin") {
		slash_path, _ := filepath.to_slash(info.fullpath, context.temp_allocator)
		if slash_path != document.fullpath {
			append(&fullpaths, strings.clone(info.fullpath, context.temp_allocator))
		}
	}

	return nil, false
}

prepare_references :: proc(
	document: ^Document,
	ast_context: ^AstContext,
	position_context: ^DocumentPositionContext,
) -> (
	symbol: Symbol,
	resolve_flag: ResolveReferenceFlag,
	ok: bool,
) {
	ok = false
	pkg := ""

	if position_context.struct_type != nil {
		found := false
		done_struct: for field in position_context.struct_type.fields.list {
			for name in field.names {
				if position_in_node(name, position_context.position) {
					symbol = Symbol {
						range = common.get_token_range(name, ast_context.file.src),
						pkg = ast_context.current_package,
					}
					found = true
					resolve_flag = .Field
					break done_struct
				}
			}
			if position_in_node(field.type, position_context.position) {
				if ident, ok := field.type.derived.(^ast.Ident); ok {
					symbol, ok = resolve_location_identifier(ast_context, ident^)
					if !ok {
						return
					}

					found = true
					resolve_flag = .Identifier
					break done_struct
				} else if selector, ok := field.type.derived.(^ast.Selector_Expr); ok {
					symbol, ok = resolve_location_identifier(ast_context, ident^)
					if !ok {
						return
					}

					found = true
					resolve_flag = .Identifier
					break done_struct
				}
			}
		}
		if !found {
			return
		}
	} else if position_context.enum_type != nil {
		found := false
		done_enum: for field in position_context.enum_type.fields {
			if ident, ok := field.derived.(^ast.Ident); ok {
				if position_in_node(ident, position_context.position) {
					symbol = Symbol {
						pkg = ast_context.current_package,
						range = common.get_token_range(ident, ast_context.file.src),
					}
					found = true
					resolve_flag = .Field
					break done_enum
				}
			} else if value, ok := field.derived.(^ast.Field_Value); ok {
				if position_in_node(value.field, position_context.position) {
					symbol = Symbol {
						range = common.get_token_range(value.field, ast_context.file.src),
						pkg = ast_context.current_package,
					}
					found = true
					resolve_flag = .Field
					break done_enum
				} else if position_in_node(value.value, position_context.position) {
					if ident, ok := value.value.derived.(^ast.Ident); ok {
						symbol, ok = resolve_location_identifier(ast_context, ident^)
						if !ok {
							return
						}

						found = true
						resolve_flag = .Identifier
						break done_enum
					}
				}
			}
		}
		if !found {
			return
		}
	} else if position_context.bitset_type != nil {
		return
	} else if position_context.union_type != nil {
		found := false
		for variant in position_context.union_type.variants {
			if position_in_node(variant, position_context.position) {
				if ident, ok := variant.derived.(^ast.Ident); ok {
					symbol, ok = resolve_location_identifier(ast_context, ident^)
					resolve_flag = .Identifier

					if !ok {
						return
					}

					found = true

					break
				} else {
					return
				}
			}
		}
		if !found {
			return
		}

	} else if position_context.field_value != nil &&
	   position_context.comp_lit != nil &&
	   !is_expr_basic_lit(position_context.field_value.field) &&
	   position_in_node(position_context.field_value.field, position_context.position) {
		symbol, ok = resolve_location_comp_lit_field(ast_context, position_context)

		if !ok {
			return
		}

		resolve_flag = .Field
	} else if position_context.selector_expr != nil {
		if position_in_node(position_context.selector, position_context.position) &&
		   position_context.identifier != nil {
			ident := position_context.identifier.derived.(^ast.Ident)

			symbol, ok = resolve_location_identifier(ast_context, ident^)

			if !ok {
				return
			}

			resolve_flag = .Identifier
		} else {
			symbol, ok = resolve_location_selector(ast_context, position_context.selector_expr)
			symbol.flags -= {.Local}

			resolve_flag = .Field
		}
	} else if position_context.implicit {
		resolve_flag = .Field

		symbol, ok = resolve_location_implicit_selector(
			ast_context,
			position_context,
			position_context.implicit_selector_expr,
		)
		symbol.flags -= {.Local}

		if !ok {
			return
		}
	} else if position_context.identifier != nil {
		ident := position_context.identifier.derived.(^ast.Ident)
		symbol, ok = resolve_location_identifier(ast_context, ident^)

		resolve_flag = .Identifier

		if !ok {
			return
		}
	} else {
		return
	}
	if symbol.uri == "" {
		symbol.uri = document.uri.uri
	}

	return symbol, resolve_flag, true
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

	symbol, resolve_flag, ok := prepare_references(document, ast_context, position_context)

	if !ok {
		return {}, true
	}

	when !ODIN_TEST {
		for workspace in common.config.workspace_folders {
			uri, _ := common.parse_uri(workspace.uri, context.temp_allocator)
			filepath.walk(uri.path, walk_directories, document)
		}
	}

	reset_ast_context(ast_context)


	arena: runtime.Arena

	_ = runtime.arena_init(&arena, mem.Megabyte * 40, runtime.default_allocator())

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
				log.errorf("failed to read entire file for indexing %v", fullpath)
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
				if !strings.contains(fullpath, "builtin.odin") && !strings.contains(fullpath, "intrinsics.odin") {
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

			if in_pkg || symbol.pkg == document.package_name {
				symbols_and_nodes := resolve_entire_file(&document, resolve_flag, context.allocator)
				for k, v in symbols_and_nodes {
					if v.symbol.uri == symbol.uri && v.symbol.range == symbol.range {
						node_uri := common.create_uri(v.node.pos.file, ast_context.allocator)
						range := common.get_token_range(v.node^, string(document.text))
						//We don't have to have the `.` with, otherwise it renames the dot.
						if _, ok := v.node.derived.(^ast.Implicit_Selector_Expr); ok {
							range.start.character += 1
						}
						location := common.Location {
							range = range,
							uri   = strings.clone(node_uri.uri, ast_context.allocator),
						}
						append(&locations, location)
					}
				}
			}

			free_all(context.allocator)
		}
	}

	symbols_and_nodes := resolve_entire_file(document, resolve_flag, context.allocator)

	for k, v in symbols_and_nodes {
		if v.symbol.uri == symbol.uri && v.symbol.range == symbol.range {
			node_uri := common.create_uri(v.node.pos.file, ast_context.allocator)

			range := common.get_token_range(v.node^, ast_context.file.src)

			//We don't have to have the `.` with, otherwise it renames the dot.
			if _, ok := v.node.derived.(^ast.Implicit_Selector_Expr); ok {
				range.start.character += 1
			}

			location := common.Location {
				range = range,
				uri   = strings.clone(node_uri.uri, ast_context.allocator),
			}

			append(&locations, location)
		}
	}

	return locations[:], true
}

get_references :: proc(document: ^Document, position: common.Position) -> ([]common.Location, bool) {
	ast_context := make_ast_context(
		document.ast,
		document.imports,
		document.package_name,
		document.uri.uri,
		document.fullpath,
		context.temp_allocator,
	)

	position_context, ok := get_document_position_context(document, position, .Hover)
	if !ok {
		log.warn("Failed to get position context")
		return {}, false
	}

	ast_context.position_hint = position_context.hint

	get_globals(document.ast, &ast_context)

	ast_context.current_package = ast_context.document_package

	if position_context.function != nil {
		get_locals(document.ast, position_context.function, &ast_context, &position_context)
	}

	locations, ok2 := resolve_references(document, &ast_context, &position_context)

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
