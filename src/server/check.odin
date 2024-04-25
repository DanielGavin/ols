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

//Store uris we have reported on since last save. We use this to clear them on next save.
uris_reported := make([dynamic]string)

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
	walk_proc :: proc(
		info: os.File_Info,
		in_err: os.Errno,
		user_data: rawptr,
	) -> (
		err: os.Errno,
		skip_dir: bool,
	) {
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
		if uri, ok := common.parse_uri(
			config.workspace_folders[0].uri,
			context.temp_allocator,
		); ok {
			filepath.walk(uri.path, walk_proc, &data)
		}
	}

	return data[:]
}

check :: proc(paths: []string, uri: common.Uri, writer: ^Writer, config: ^common.Config) {
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
		strings.write_string(
			&collection_builder,
			fmt.aprintf("-collection:%v=%v ", k, v),
		)
	}

	errors := make(map[string][dynamic]Diagnostic, 0, context.temp_allocator)

	for path in paths {
		command: string

		if config.odin_command != "" {
			command = config.odin_command
		} else {
			command = "odin"
		}

		entry_point_opt :=
			filepath.ext(path) == ".odin" ? "-file" : "-no-entry-point"

		slice.zero(data)

		if code, ok, buffer = common.run_executable(
			fmt.tprintf(
				"%v check %s %s %s %s %s %s",
				command,
				path,
				strings.to_string(collection_builder),
				entry_point_opt,
				config.checker_args,
				"-json-errors",
				ODIN_OS == .Linux || ODIN_OS == .Darwin ? "2>&1" : "",
			),
			&data,
		); !ok {
			log.errorf(
				"Odin check failed with code %v for file %v",
				code,
				path,
			)
			return
		}

		if len(buffer) == 0 {
			continue
		}

		json_errors: Json_Errors

		if res := json.unmarshal(
			buffer,
			&json_errors,
			json.DEFAULT_SPECIFICATION,
			context.temp_allocator,
		); res != nil {
			log.errorf("Failed to unmarshal check results: %v", res)
		}

		for error in json_errors.errors {
			if len(error.msgs) == 0 {
				break
			}

			message := strings.join(error.msgs, " ", context.temp_allocator)

			if strings.contains(
				message,
				"Redeclaration of 'main' in this scope",
			) {
				continue
			}

			if error.pos.file not_in errors {
				errors[error.pos.file] = make(
					[dynamic]Diagnostic,
					context.temp_allocator,
				)
			}

			append(
				&errors[error.pos.file],
				Diagnostic {
					code = "checker",
					severity = .Error if error.type == "error" else .Warning,
					range =  {
						start =  {
							character = error.pos.column - 1,
							line = error.pos.line - 1,
						},
						end =  {
							character = error.pos.end_column - 1,
							line = error.pos.line - 1,
						},
					},
					message = message,
				},
			)
		}
	}

	for uri in uris_reported {
		params := NotificationPublishDiagnosticsParams {
			uri         = uri,
			diagnostics = {},
		}

		notifaction := Notification {
			jsonrpc = "2.0",
			method  = "textDocument/publishDiagnostics",
			params  = params,
		}

		if writer != nil {
			send_notification(notifaction, writer)
		}

		delete(uri)
	}

	clear(&uris_reported)

	for k, v in errors {
		uri := common.create_uri(k, context.temp_allocator)

		//Find the unique diagnostics, since some poor profile settings make the checker check the same file multiple times
		unique := slice.unique(v[:])

		params := NotificationPublishDiagnosticsParams {
			uri         = uri.uri,
			diagnostics = unique,
		}

		notifaction := Notification {
			jsonrpc = "2.0",
			method  = "textDocument/publishDiagnostics",
			params  = params,
		}

		append(&uris_reported, strings.clone(uri.uri))

		if writer != nil {
			send_notification(notifaction, writer)
		}
	}


}
