package server

import "base:intrinsics"
import "base:runtime"

import "core:encoding/json"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"
import "core:path/filepath"
import path "core:path/slashpath"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:sync"
import "core:text/scanner"
import "core:thread"

import "src:common"

Json_Error :: struct {
	type: string,
	pos:  Json_Type_Error,
	msgs: []string,
}

Json_Type_Error :: struct {
	file:       string,
	offset:     int,
	line:       int,
	column:     int,
	end_column: int,
}

Json_Errors :: struct {
	error_count: int,
	errors:      []Json_Error,
}


//If the user does not specify where to call odin check, it'll just find all directory with odin, and call them seperately.
fallback_find_odin_directories :: proc(config: ^common.Config) -> []string {
	walk_proc :: proc(info: os.File_Info, in_err: os.Errno, user_data: rawptr) -> (err: os.Errno, skip_dir: bool) {
		data := cast(^[dynamic]string)user_data

		if !info.is_dir && filepath.ext(info.name) == ".odin" {
			dir := filepath.dir(info.fullpath, context.temp_allocator)
			if !slice.contains(data[:], dir) {
				append(data, dir)
			}
		}

		return in_err, false
	}

	data := make([dynamic]string, context.temp_allocator)

	if len(config.workspace_folders) > 0 {
		if uri, ok := common.parse_uri(config.workspace_folders[0].uri, context.temp_allocator); ok {
			filepath.walk(uri.path, walk_proc, &data)
		}
	}

	return data[:]
}

check_unused_imports :: proc(document: ^Document, config: ^common.Config) {
	if !config.enable_unused_imports_reporting {
		return
	}

	unused_imports := find_unused_imports(document, context.temp_allocator)

	path := document.uri.path

	when ODIN_OS == .Windows {
		path = common.get_case_sensitive_path(path, context.temp_allocator)
	}

	uri := common.create_uri(path, context.temp_allocator)

	remove_diagnostics(.Unused, uri.uri)

	for imp in unused_imports {
		add_diagnostics(
			.Unused,
			uri.uri,
			Diagnostic {
				range = common.get_token_range(imp.import_decl, document.ast.src),
				severity = DiagnosticSeverity.Hint,
				code = "Unused",
				message = "unused import",
				tags = {.Unnecessary},
			},
		)
	}
}

check :: proc(paths: []string, uri: common.Uri, config: ^common.Config) {
	paths := paths

	if len(paths) == 0 {
		if config.enable_checker_only_saved {
			paths = {path.dir(uri.path, context.temp_allocator)}
		} else {
			paths = fallback_find_odin_directories(config)
		}
	}


	data := make([]byte, mem.Kilobyte * 200, context.temp_allocator)

	buffer: []byte
	code: u32
	ok: bool

	collection_builder := strings.builder_make(context.temp_allocator)

	for k, v in common.config.collections {
		if k == "" || k == "core" || k == "vendor" || k == "base" {
			continue
		}
		strings.write_string(&collection_builder, fmt.aprintf("-collection:%v=\"%v\" ", k, v))
	}

	errors := make(map[string][dynamic]Diagnostic, 0, context.temp_allocator)

	for path in paths {
		command: string

		if config.odin_command != "" {
			command = config.odin_command
		} else {
			command = "odin"
		}

		entry_point_opt := filepath.ext(path) == ".odin" ? "-file" : "-no-entry-point"

		slice.zero(data)

		if code, ok, buffer = common.run_executable(
			fmt.tprintf(
				"%v check \"%s\" %s %s %s %s %s",
				command,
				path,
				strings.to_string(collection_builder),
				entry_point_opt,
				config.checker_args,
				"-json-errors",
				ODIN_OS in runtime.Odin_OS_Types{.Linux, .Darwin, .FreeBSD, .OpenBSD, .NetBSD} ? "2>&1" : "",
			),
			&data,
		); !ok {
			log.errorf("Odin check failed with code %v for file %v", code, path)
			return
		}

		clear_diagnostics(.Check)

		if len(buffer) == 0 {
			continue
		}

		json_errors: Json_Errors

		if res := json.unmarshal(buffer, &json_errors, json.DEFAULT_SPECIFICATION, context.temp_allocator);
		   res != nil {
			log.errorf("Failed to unmarshal check results: %v, %v", res, string(buffer))
		}

		for error in json_errors.errors {
			if len(error.msgs) == 0 {
				break
			}

			message := strings.join(error.msgs, "\n", context.temp_allocator)

			if strings.contains(message, "Redeclaration of 'main' in this scope") {
				continue
			}

			path := error.pos.file

			when ODIN_OS == .Windows {
				path = common.get_case_sensitive_path(path, context.temp_allocator)
			}

			uri := common.create_uri(path, context.temp_allocator)

			add_diagnostics(
				.Check,
				uri.uri,
				Diagnostic {
					code = "checker",
					severity = .Error,
					range = {
						// odin will sometimes report errors on column 0, so we ensure we don't provide a negative column/line to the client
						start = {character = max(error.pos.column - 1, 0), line = max(error.pos.line - 1, 0)},
						end = {character = max(error.pos.end_column - 1, 0), line = max(error.pos.line - 1, 0)},
					},
					message = message,
				},
			)
		}
	}
}
