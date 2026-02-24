package server

import "base:runtime"

import "core:encoding/json"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:path/filepath"
import path "core:path/slashpath"
import "core:slice"
import "core:strings"

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

Check_Mode :: enum {
	Saved,
	Workspace,
}

//If the user does not specify where to call odin check, it'll just find all directory with odin, and call them seperately.
fallback_find_odin_directories :: proc(config: ^common.Config) -> []string {
	data := make([dynamic]string, context.temp_allocator)

	for workspace in config.workspace_folders {
		if uri, ok := common.parse_uri(workspace.uri, context.temp_allocator); ok {
			log.error(config.checker_skip_packages)
			append_packages(uri.path, &data, config.checker_skip_packages, context.temp_allocator)
		}
	}

	return data[:]
}

path_has_prefix :: proc(path: string, prefix: string) -> bool {
	if len(prefix) == 0 || len(path) < len(prefix) {
		return false
	}

	if !strings.equal_fold(path[:len(prefix)], prefix) {
		return false
	}

	if len(path) == len(prefix) {
		return true
	}

	return path[len(prefix)] == '/' || prefix[len(prefix) - 1] == '/'
}

path_matches_checker_scope :: proc(file_path: string, checker_path: string) -> bool {
	if filepath.ext(checker_path) == ".odin" {
		return strings.equal_fold(file_path, checker_path)
	}

	return path_has_prefix(file_path, checker_path)
}

clear_check_diagnostics_for_paths :: proc(paths: []string) {
	for uri, _ in diagnostics[.Check] {
		parsed_uri, ok := common.parse_uri(uri, context.temp_allocator)
		if !ok {
			continue
		}

		for checker_path in paths {
			if path_matches_checker_scope(parsed_uri.path, checker_path) {
		remove_diagnostics(.Check, uri)
				break
			}
		}
	}
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

resolve_check_paths :: proc(mode: Check_Mode, uri: common.Uri, config: ^common.Config) -> ([]string, bool) {
	if len(config.profile.checker_path) > 0 {
		return config.profile.checker_path[:], true
	}

	if mode == .Saved && config.enable_checker_only_saved && uri.path != "" {
		paths := make([dynamic]string, context.temp_allocator)
		dir := path.dir(uri.path, context.temp_allocator)
		if dir not_in config.checker_skip_packages {
			append(&paths, dir)
		}
		return paths[:], false
	}

	return fallback_find_odin_directories(config), true
}

check :: proc(mode: Check_Mode, uri: common.Uri, config: ^common.Config) {
	paths, clear_all := resolve_check_paths(mode, uri, config)

	if clear_all {
		clear_diagnostics(.Check)
	} else {
		clear_check_diagnostics_for_paths(paths)
	}

	if len(paths) == 0 {
		return
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

	builtin_path := config.builtin_path
	for check_path in paths {
		command: string

		if config.odin_command != "" {
			command = config.odin_command
		} else {
			command = "odin"
		}

		entry_point_opt := filepath.ext(check_path) == ".odin" ? "-file" : "-no-entry-point"

		slice.zero(data)

		if code, ok, buffer = common.run_executable(
			fmt.tprintf(
				"%v check \"%s\" %s %s %s %s %s",
				command,
				check_path,
				strings.to_string(collection_builder),
				entry_point_opt,
				config.checker_args,
				"-json-errors",
				ODIN_OS in runtime.Odin_OS_Types{.Linux, .Darwin, .FreeBSD, .OpenBSD, .NetBSD} ? "2>&1" : "",
			),
			&data,
		); !ok {
			log.errorf("Odin check failed with code %v for file %v", code, check_path)
			continue
		}

		if len(buffer) == 0 {
			continue
		}

		json_errors: Json_Errors

		if res := json.unmarshal(buffer, &json_errors, json.DEFAULT_SPECIFICATION, context.temp_allocator);
		   res != nil {
			log.errorf("Failed to unmarshal check results: %v, %v", res, string(buffer))
			continue
		}

		for error in json_errors.errors {
			if len(error.msgs) == 0 {
				continue
			}

			message := strings.join(error.msgs, "\n", context.temp_allocator)

			if strings.contains(message, "Redeclaration of 'main' in this scope") {
				continue
			}

			path := error.pos.file

			when ODIN_OS == .Windows {
				path = common.get_case_sensitive_path(path, context.temp_allocator)
				path, _ = filepath.replace_path_separators(path, '/', context.temp_allocator)
			}

			if is_ols_builtin_file(path) {
				continue
			}

			uri := common.create_uri(path, context.temp_allocator)

			add_diagnostics(
				.Check,
				uri.uri,
				Diagnostic {
					code = "checker",
					severity = map_diagnostic_severity(error.type),
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

@(private = "file")
map_diagnostic_severity :: proc(type: string) -> DiagnosticSeverity {
	if strings.equal_fold(type, "warning") {
		return .Warning
	}

	return .Error
}

