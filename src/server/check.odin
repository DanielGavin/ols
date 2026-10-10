package server

import "base:runtime"
import "core:encoding/json"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"
import "core:path/filepath"
import path "core:path/slashpath"
import "core:slice"
import "core:strings"
import "core:sync/chan"
import "core:thread"
import "core:time"

import "src:common"
import "src:spall"

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

Check_Request :: struct {
	check_mode: Check_Mode,
	path:       string,
	config:     ^common.Config,
	buffers:    []Check_Buffer,
}

Check_Buffer :: struct {
	path: string,
	text: []u8,
}

Checker :: struct {
	allocator: mem.Allocator,
	send:      chan.Chan(Check_Request, .Send),
}

@(private = "file")
checker: Checker

@(private = "file")
overlay_dir: string

@(private = "file")
odin_without_workspace: string

queue_check_request :: proc(mode: Check_Mode, path: string, config: ^common.Config) {
	if !config.enable_diagnostics {
		return
	}
	path := strings.clone(path, checker.allocator)

	buffers := make([dynamic]Check_Buffer, 0, len(document_storage.documents), checker.allocator)
	for _, &document in document_storage.documents {
		if !document.client_owned || is_ols_builtin_file(document.fullpath) {
			continue
		}
		append(
			&buffers,
			Check_Buffer {
				path = strings.clone(document.fullpath, checker.allocator),
				text = slice.clone(document.text[:document.used_text], checker.allocator),
			},
		)
	}

	ok := chan.send(checker.send, Check_Request{check_mode = mode, path = path, config = config, buffers = buffers[:]})
	if !ok {
		log.errorf("Failed to queue check request for path %q", path)
		delete_check_buffers(buffers[:])
	}
}

@(private = "file")
delete_check_buffers :: proc(buffers: []Check_Buffer) {
	for b in buffers {
		delete(b.path, checker.allocator)
		delete(b.text, checker.allocator)
	}
	delete(buffers, checker.allocator)
}

stop_check_worker :: proc() {
	chan.close(checker.send)
	if overlay_dir != "" {
		_ = os.remove_all(overlay_dir)
	}
}

create_and_start_check_worker :: proc(writer: ^Writer) {
	allocator := runtime.heap_allocator()
	check_chan, _ := chan.create(chan.Chan(Check_Request), 8, context.allocator)
	check_send := chan.as_send(check_chan)
	checker = Checker {
		allocator = runtime.heap_allocator(),
		send      = check_send,
	}
	check_recv := chan.as_recv(check_chan)
	thread.create_and_start_with_poly_data(
		Consumer{logger = context.logger, ch = check_recv, w = writer},
		run_check_consumer,
	)
}

Consumer :: struct {
	logger: log.Logger,
	ch:     chan.Chan(Check_Request, .Recv),
	w:      ^Writer,
}

run_check_consumer :: proc(c: Consumer) {
	context.logger = c.logger
	for {
		request, ok := chan.recv(c.ch)
		if !ok {
			break
		}
		paths := make([dynamic]string, allocator = context.temp_allocator)
		append(&paths, request.path)

		buffers := request.buffers
		for later in chan.try_recv(c.ch) {
			append(&paths, later.path)
			delete_check_buffers(buffers)
			buffers = later.buffers
		}

		check(request.check_mode, paths[:], buffers, request.config)

		push_diagnostics(c.w)
		for path in paths {
			delete(path, checker.allocator)
		}
		delete_check_buffers(buffers)

		free_all(context.temp_allocator)
	}
	free_all(context.temp_allocator)
}

//If the user does not specify where to call odin check, it'll just find all directory with odin, and call them seperately.
fallback_find_odin_directories :: proc(config: ^common.Config) -> []string {
	data := make([dynamic]string, context.temp_allocator)

	for workspace in config.workspace_folders {
		if uri, ok := common.parse_uri(workspace.uri, context.temp_allocator); ok {
			append_packages(uri.path, &data, config.checker_skip_packages, context.temp_allocator)
		}
	}

	return data[:]
}

check_unused_imports :: proc(document: ^Document, config: ^common.Config) {
	if !config.enable_unused_imports_reporting || !config.enable_diagnostics {
		return
	}

	spall.trace(#procedure, document.fullpath)

	path := document.uri.path

	when ODIN_OS == .Windows {
		path = common.get_case_sensitive_path(path, context.temp_allocator)
	}

	uri := common.create_uri(path, context.temp_allocator)

	remove_diagnostics(.Unused, uri.uri)
	if len(document.imports) == 0 {
		return
	}

	unused_imports := find_unused_imports(document, context.temp_allocator)

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

resolve_check_paths :: proc(mode: Check_Mode, paths: []string, config: ^common.Config) -> []string {
	if len(config.profile.checker_path) > 0 {
		return config.profile.checker_path[:]
	}

	if mode == .Saved || config.enable_checker_only_saved {
		results := make([dynamic]string, context.temp_allocator)
		for p in paths {
			if p == "" {
				continue
			}
			dir := path.dir(p, context.temp_allocator)
			if dir not_in config.checker_skip_packages {
				append(&results, dir)
			}
		}
		return results[:]
	}

	if mode == .Workspace && config.enable_checker_workspace_diagnostics {
		return fallback_find_odin_directories(config)
	}

	return {}
}

CheckProcess :: struct {
	process:  os.Process,
	reader:   ^os.File,
	finished: bool,
	buffer:   [dynamic]u8,
}

check :: proc(mode: Check_Mode, check_paths: []string, buffers: []Check_Buffer, config: ^common.Config) {
	write_overlay :: proc(buffers: []Check_Buffer) -> string {
		if len(buffers) == 0 {
			return ""
		}
		if overlay_dir == "" {
			temp, err := os.temp_directory(context.temp_allocator)
			if err != nil {
				log.errorf("Failed to find the temporary directory for the overlay: %v", err)
				return ""
			}
			overlay_dir = fmt.aprintf("%s/ols-%d", temp, os.get_pid(), allocator = checker.allocator)
			_ = os.make_directory(overlay_dir)
		}

		Overlay :: struct {
			replace: map[string]string `json:"Replace"`,
		}
		overlay := Overlay {
			replace = make(map[string]string, len(buffers), context.temp_allocator),
		}
		for b, i in buffers {
			file := fmt.tprintf("%s/%d.odin", overlay_dir, i)
			if err := os.write_entire_file(file, b.text); err != nil {
				log.errorf("Failed to write the overlay file %q: %v", file, err)
				return ""
			}
			overlay.replace[b.path] = file
		}

		data, err := json.marshal(overlay, allocator = context.temp_allocator)
		if err != nil {
			log.errorf("Failed to make the overlay: %v", err)
			return ""
		}
		path := fmt.tprintf("%s/overlay.json", overlay_dir)
		if err := os.write_entire_file(path, data); err != nil {
			log.errorf("Failed to write the overlay %q: %v", path, err)
			return ""
		}
		return path
	}

	paths := resolve_check_paths(mode, check_paths, config)

	if len(paths) == 0 {
		return
	}

	clear_diagnostics(.Check)

	command := config.odin_command
	if command == "" {
		command = "odin"
	}

	collections := make([dynamic]string, context.temp_allocator)

	for k, v in common.config.collections {
		if k == "" || k == "core" || k == "vendor" || k == "base" {
			continue
		}
		append(&collections, fmt.aprintf("-collection:%v=%v", k, v))
	}

	jobs := make([dynamic][]string, 0, len(paths), context.temp_allocator)
	overlay := ""
	use_workspace := command != odin_without_workspace
	if use_workspace {
		overlay = write_overlay(buffers)

		// NOTE(bill): This is here just to keep the command line well within Windows' limit of 32767 characters
		MAX_WORKSPACE_PATHS_LEN :: 16384

		dirs := make([dynamic]string, 0, len(paths), context.temp_allocator)
		dirs_len := 0
		for p, i in paths {
			if filepath.ext(p) == ".odin" {
				append(&jobs, paths[i:i + 1])
				continue
			}
			if dirs_len + len(p) > MAX_WORKSPACE_PATHS_LEN && len(dirs) > 0 {
				append(&jobs, dirs[:])
				dirs = make([dynamic]string, 0, len(paths), context.temp_allocator)
				dirs_len = 0
			}
			append(&dirs, p)
			dirs_len += len(p) + 3
		}
		if len(dirs) > 0 {
			append(&jobs, dirs[:])
		}
	} else {
		for _, i in paths {
			append(&jobs, paths[i:i + 1])
		}
	}

	max_concurrent_checks := max(1, os.get_processor_core_count())
	processes := make([dynamic]CheckProcess, 0, len(jobs))

	errors := make([dynamic]Json_Errors, 0, len(jobs), context.temp_allocator)
	lacks_workspace := false

	next_index := 0
	running_count := 0
	start := time.now()

	for running_count > 0 || next_index < len(jobs) {
		for running_count < max_concurrent_checks && next_index < len(jobs) {
			p, ok := start_check_process(command, jobs[next_index], collections[:], overlay, config)
			next_index += 1
			if !ok {
				continue
			}
			append(&processes, p)
			running_count += 1
		}

		if time.since(start) > 20 * time.Second {
			log.error("`odin check` timed out")
			for &p in processes {
				if !p.finished {
					if err := os.process_kill(p.process); err != nil {
						log.error("Failed to kill `odin check` process: %v", err)
					}
				}
			}
			break
		}

		for &p in processes {
			if p.finished {
				continue
			}

			buf: [1024]u8
			n, _ := os.read(p.reader, buf[:])
			if n > 0 {
				_, _ = append(&p.buffer, ..buf[:n])
			}

			state, err := os.process_wait(p.process, 0)
			if err != nil {
				continue
			}

			if !state.exited {
				continue
			}

			p.finished = true
			running_count -= 1

			for {
				n, read_err := os.read(p.reader, buf[:])
				if n > 0 {
					_, _ = append(&p.buffer, ..buf[:n])
				}
				if read_err != nil {
					break
				}
			}

			os.close(p.reader)
			p.reader = nil

			output := string(p.buffer[:])
			if use_workspace && (strings.contains(output, "Unknown flag: 'workspace'") || strings.contains(output, "Unknown flag: 'overlay'")) {
				lacks_workspace = true
				continue
			}

			if len(p.buffer) > 0 {
				json_errors: Json_Errors
				if res := json.unmarshal(
					p.buffer[:],
					&json_errors,
					json.DEFAULT_SPECIFICATION,
					context.temp_allocator,
				); res != nil {
					log.errorf("Failed to unmarshal check results: %v, %v", res, string(p.buffer[:]))
					continue
				}
				append(&errors, json_errors)
			}
		}

		if running_count > 0 || next_index < len(jobs) {
			time.sleep(1 * time.Millisecond)
		}
	}

	for p in processes {
		os.close(p.reader)
	}

	if lacks_workspace {
		log.infof("`%s` has no `-workspace` or `-overlay`, so packages are checked one at a time from disk", command)
		delete(odin_without_workspace, checker.allocator)
		odin_without_workspace = strings.clone(command, checker.allocator)
		check(mode, check_paths, buffers, config)
		return
	}

	DiagnosticKey :: struct {
		path:    string,
		message: string,
		line:    int,
		column:  int,
	}

	diagnostics := make(map[DiagnosticKey]struct{}, context.temp_allocator)
	for e in errors {
		for error in e.errors {
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
				path, _ = filepath.replace_separators(path, '/', context.temp_allocator)
			}

			key := DiagnosticKey {
				path    = path,
				message = message,
				line    = error.pos.line,
				column  = error.pos.column,
			}
			if key in diagnostics {
				continue
			}

			diagnostics[key] = {}

			if is_ols_builtin_file(path) {
				continue
			}

			uri := common.create_uri(path, context.temp_allocator)

			diagnostic_severity := DiagnosticSeverity.Error
			if strings.equal_fold(error.type, "warning") {
				diagnostic_severity = .Warning
			}

			add_diagnostics(
				.Check,
				uri.uri,
				Diagnostic {
					code = "checker",
					severity = diagnostic_severity,
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
start_check_process :: proc(
	command: string,
	check_paths: []string,
	collections: []string,
	overlay: string,
	config: ^common.Config,
) -> (
	CheckProcess,
	bool,
) {
	entry_point_opt := filepath.ext(check_paths[0]) == ".odin" ? "-file" : "-no-entry-point"
	cmd := make([dynamic]string, context.temp_allocator)
	append(&cmd, command, "check")
	append(&cmd, ..check_paths)
	for c in collections {
		append(&cmd, c)
	}
	for k, v in config.profile.defines {
		append(&cmd, fmt.tprintf("-define:%s=%s", k, v))
	}
	append(&cmd, entry_point_opt, "-json-errors")
	if len(check_paths) > 1 {
		// TODO(bill): is this a good idea to change the limit to 1000?
		append(&cmd, "-workspace", "-max-error-count:1000")
	}
	if overlay != "" {
		append(&cmd, fmt.tprintf("-overlay:%s", overlay))
	}
	args, _ := strings.split(config.checker_args, " ", context.temp_allocator)
	for arg in args {
		if arg != "" {
			append(&cmd, arg)
		}
	}

	r, w, err := os.pipe()
	if err != nil {
		log.errorf("failed to create pipe for `odin check`: %v\n", err)
		return CheckProcess{}, false
	}
	defer os.close(w)

	desc := os.Process_Desc {
		command = cmd[:],
		stdout  = w,
		stderr  = w,
	}

	p, perr := os.process_start(desc)
	if perr != nil {
		os.close(r)
		log.errorf("failed to start process for `odin check`: %v\n", perr)
		return CheckProcess{}, false
	}

	buffer := make([dynamic]u8, 0, mem.Kilobyte * 200, context.temp_allocator)
	return CheckProcess{process = p, reader = r, buffer = buffer}, true
}
