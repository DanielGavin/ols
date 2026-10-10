package server

import "base:runtime"
import "core:encoding/json"
import "core:fmt"
import "core:hash"
import "core:log"
import "core:mem"
import "core:os"
import "core:path/filepath"
import path "core:path/slashpath"
import "core:slice"
import "core:strings"
import "core:sync"
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

// In order of how much is checked, as requests checked together check as much as the largest
Check_Mode :: enum {
	Changed,
	Saved,
	Workspace,
}

Check_Request :: struct {
	check_mode: Check_Mode,
	path:       string,
	config:     ^common.Config,
	buffers:    []Check_Buffer,
	sequence:   u64, // when it was queued, so the newest buffers are checked
}

Check_Buffer :: struct {
	path:    string,
	text:    []u8,
	version: Maybe(int),
}

Checker :: struct {
	allocator:              mem.Allocator,
	odin_without_workspace: string,
	dir:                    string, // Used by the -overlay and -exported-semantics
	overlay:                Check_Overlay,

	mutex:                  sync.Mutex,
	cond:                   sync.Cond,
	queue:                  [dynamic]Check_Request,
	changed:                Maybe(Check_Request), // only the newest change matters, so it replaces the one before
	sequence:               u64,
	stopped:                bool,
}

Check_Overlay :: struct {
	files: map[string]Check_Overlay_File, // by path
	json:  []u8,                          // as last written
}

Check_Overlay_File :: struct {
	file:    string,
	hash:    u64, // unchanged documents are not written again based of the text last written to `file`
	written: bool,
}

@(private = "file")
checker: Checker

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
				path    = strings.clone(document.fullpath, checker.allocator),
				text    = slice.clone(document.text[:document.used_text], checker.allocator),
				version = document.version,
			},
		)
	}

	request := Check_Request{
		check_mode = mode,
		path       = path,
		config     = config,
		buffers    = buffers[:],
	}

	sync.mutex_lock(&checker.mutex)
	checker.sequence += 1
	request.sequence = checker.sequence
	if mode == .Changed {
		if older, has_older := checker.changed.?; has_older {
			delete(older.path, checker.allocator)
			delete_check_buffers(older.buffers)
		}
		checker.changed = request
	} else {
		append(&checker.queue, request)
	}
	sync.mutex_unlock(&checker.mutex)

	sync.cond_signal(&checker.cond)
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
	sync.mutex_lock(&checker.mutex)
	checker.stopped = true
	sync.mutex_unlock(&checker.mutex)

	sync.cond_broadcast(&checker.cond)

	if checker.dir != "" {
		_ = os.remove_all(checker.dir)
	}
}

@(private = "file")
checker_dir :: proc() -> string {
	if checker.dir == "" {
		temp, err := os.temp_directory(context.temp_allocator)
		if err != nil {
			log.errorf("Failed to find the temporary directory: %v", err)
			return ""
		}
		checker.dir = fmt.aprintf("%s/ols-%d", temp, os.get_pid(), allocator = checker.allocator)
		_ = os.make_directory(checker.dir)
	}
	return checker.dir
}

create_and_start_check_worker :: proc(writer: ^Writer) {
	checker = Checker {
		allocator = runtime.heap_allocator(),
		queue     = make([dynamic]Check_Request, runtime.heap_allocator()),
	}
	thread.create_and_start_with_poly_data(Consumer{logger = context.logger, w = writer}, run_check_consumer)
}

Consumer :: struct {
	logger: log.Logger,
	w:      ^Writer,
}

@(private = "file")
Check_Batch :: struct {
	mode:     Check_Mode,
	paths:    [dynamic]string,
	buffers:  []Check_Buffer,
	sequence: u64, // Where the request `buffers` came from
	config:   ^common.Config,
}

@(private = "file")
add_to_check_batch :: proc(batch: ^Check_Batch, request: Check_Request) {
	if request.path != "" {
		append(&batch.paths, request.path)
	}
	if request.sequence > batch.sequence {
		delete_check_buffers(batch.buffers)
		batch.buffers = request.buffers
		batch.sequence = request.sequence
		batch.config = request.config
	} else {
		delete_check_buffers(request.buffers)
	}
	if request.check_mode > batch.mode {
		batch.mode = request.check_mode
	}
}

run_check_consumer :: proc(c: Consumer) {
	context.logger = c.logger
	for {
		batch := Check_Batch {
			paths = make([dynamic]string, allocator = context.temp_allocator),
		}

		sync.mutex_lock(&checker.mutex)
		for !checker.stopped && len(checker.queue) == 0 && checker.changed == nil {
			sync.cond_wait(&checker.cond, &checker.mutex)
		}
		if checker.stopped {
			sync.mutex_unlock(&checker.mutex)
			break
		}

		last_change: time.Tick
		for {
			for request in checker.queue {
				add_to_check_batch(&batch, request)
			}
			clear(&checker.queue)
			if changed, has_changed := checker.changed.?; has_changed {
				add_to_check_batch(&batch, changed)
				checker.changed = nil
				last_change = time.tick_now()
			}

			if batch.mode != .Changed || checker.stopped {
				break
			}
			remaining := time.Duration(batch.config.checker_on_change_delay) * time.Millisecond - time.tick_since(last_change)
			if remaining <= 0 {
				break
			}
			sync.cond_wait_with_timeout(&checker.cond, &checker.mutex, remaining)
		}
		sync.mutex_unlock(&checker.mutex)

		semantics := check(batch.mode, batch.paths[:], batch.buffers, batch.config)
		push_diagnostics(c.w)
		load_semantics(semantics, batch.buffers)
		for path in batch.paths {
			delete(path, checker.allocator)
		}
		delete_check_buffers(batch.buffers)

		free_all(context.temp_allocator)
	}
	free_all(context.temp_allocator)
}

fallback_find_odin_directories :: proc(config: ^common.Config) -> []string {
	data := make([dynamic]string, context.temp_allocator)

	for workspace in config.workspace_folders {
		uri := common.parse_uri(workspace.uri, context.temp_allocator) or_continue
		append_packages(uri.path, &data, config.checker_skip_packages, context.temp_allocator)
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

	if mode != .Workspace || config.enable_checker_only_saved {
		results := make([dynamic]string, context.temp_allocator)
		for p in paths {
			if p == "" {
				continue
			}
			dir := path.dir(p, context.temp_allocator)
			if dir not_in config.checker_skip_packages && !slice.contains(results[:], dir) {
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

check :: proc(mode: Check_Mode, check_paths: []string, buffers: []Check_Buffer, config: ^common.Config) -> (semantics: []string) {
	write_overlay :: proc(o: ^Check_Overlay, buffers: []Check_Buffer) -> string {
		dir := checker_dir()
		if len(buffers) == 0 || dir == "" {
			return ""
		}

		Overlay :: struct {
			replace: map[string]string `json:"Replace"`,
		}
		overlay := Overlay {
			replace = make(map[string]string, len(buffers), context.temp_allocator),
		}
		if o.files == nil {
			o.files = make(map[string]Check_Overlay_File, 16, checker.allocator)
		}
		for b in buffers {
			entry := &o.files[b.path]
			if entry == nil {
				path := strings.clone(b.path, checker.allocator)
				o.files[path] = {file = fmt.aprintf("%s/%d.odin", dir, len(o.files), allocator = checker.allocator)}
				entry = &o.files[path]
			}
			h := hash.fnv64a(b.text)
			if !entry.written || entry.hash != h {
				if err := os.write_entire_file(entry.file, b.text); err != nil {
					log.errorf("Failed to write the overlay file %q: %v", entry.file, err)
					return ""
				}
				entry.hash = h
				entry.written = true
			}
			overlay.replace[b.path] = entry.file
		}

		data, err := json.marshal(overlay, {sort_maps_by_key = true}, context.temp_allocator)
		if err != nil {
			log.errorf("Failed to make the overlay: %v", err)
			return ""
		}
		path := fmt.tprintf("%s/overlay.json", dir)
		if !slice.equal(data, o.json) {
			if err := os.write_entire_file(path, data); err != nil {
				log.errorf("Failed to write the overlay %q: %v", path, err)
				return ""
			}
			delete(o.json, checker.allocator)
			o.json = slice.clone(data, checker.allocator)
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
	use_workspace := command != checker.odin_without_workspace
	if use_workspace {
		overlay = write_overlay(&checker.overlay, buffers)

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

	errors   := make([dynamic]Json_Errors, 0, len(jobs), context.temp_allocator)
	exported := make([dynamic]string, 0, len(jobs), context.temp_allocator)
	lacks_workspace := false

	next_index := 0
	running_count := 0
	start := time.now()

	for running_count > 0 || next_index < len(jobs) {
		for running_count < max_concurrent_checks && next_index < len(jobs) {
			semantics_file := ""
			if use_workspace && checker_dir() != "" {
				semantics_file = fmt.tprintf("%s/semantics-%d.cbor", checker_dir(), next_index)
				_ = os.remove(semantics_file)
			}
			p, ok := start_check_process(command, jobs[next_index], collections[:], overlay, semantics_file, config)
			next_index += 1
			if !ok {
				continue
			}
			if semantics_file != "" {
				append(&exported, semantics_file)
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
			if use_workspace {
				for flag in ([]string{"'workspace'", "'overlay'", "'export-semantics'"}) {
					lacks_workspace ||= strings.contains(output, fmt.tprintf("Unknown flag: %s", flag))
				}
				if lacks_workspace {
					continue
				}
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
		delete(checker.odin_without_workspace, checker.allocator)
		checker.odin_without_workspace = strings.clone(command, checker.allocator)
		return check(mode, check_paths, buffers, config)
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

	return exported[:]
}


@(private = "file")
start_check_process :: proc(
	command:     string,
	check_paths: []string,
	collections: []string,
	overlay:     string,
	semantics:   string,
	config:      ^common.Config,
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
		append(&cmd, "-workspace")
	}
	if len(check_paths) > 1 || semantics != "" {
		// TODO(bill): is this a good idea to change the limit to 1000?
		// NOTE(bill): The semantics are not exported once the errors reach it either
		append(&cmd, "-max-error-count:1000")
	}
	if overlay != "" {
		append(&cmd, fmt.tprintf("-overlay:%s", overlay))
	}
	if semantics != "" {
		append(&cmd, "-export-semantics:cbor", fmt.tprintf("-export-semantics-file:%s", semantics))
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
