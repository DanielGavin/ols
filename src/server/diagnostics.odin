package server

import "core:log"
import "core:slice"
import "core:strings"
import "core:sync"
import "src:common"

DiagnosticType :: enum {
	Syntax,
	Unused,
	Check,
}

diagnostics: [DiagnosticType]map[string][dynamic]Diagnostic
diagnostic_mutex: sync.Mutex

@(private = "file")
remove_diagnostics_locked :: proc(type: DiagnosticType, uri: string) {
	diagnostic_type := &diagnostics[type]

	if diagnostic_type == nil {
		log.errorf("Diagnostic type did not exist: %v", type)
		return
	}

	diagnostic_array := &diagnostic_type[uri]

	if diagnostic_array == nil {
		return
	}

	for diagnostic in diagnostic_array {
		delete(diagnostic.message)
		delete(diagnostic.code)
	}

	clear(diagnostic_array)
}

add_diagnostics :: proc(type: DiagnosticType, uri: string, diagnostic: Diagnostic) {
	sync.lock(&diagnostic_mutex)
	defer sync.unlock(&diagnostic_mutex)

	diagnostic_type := &diagnostics[type]

	if diagnostic_type == nil {
		log.errorf("Diagnostic type did not exist: %v", type)
		return
	}

	diagnostic_array := &diagnostic_type[uri]

	if diagnostic_array == nil {
		diagnostic_type[strings.clone(uri)] = make([dynamic]Diagnostic)
		diagnostic_array = &diagnostic_type[uri]
	}

	diagnostic := diagnostic

	diagnostic.message = strings.clone(diagnostic.message)
	diagnostic.code = strings.clone(diagnostic.code)

	append(diagnostic_array, diagnostic)
}

remove_diagnostics :: proc(type: DiagnosticType, uri: string) {
	sync.lock(&diagnostic_mutex)
	defer sync.unlock(&diagnostic_mutex)

	remove_diagnostics_locked(type, uri)
}

clear_diagnostics :: proc(type: DiagnosticType) {
	sync.lock(&diagnostic_mutex)
	defer sync.unlock(&diagnostic_mutex)

	diagnostic_type := &diagnostics[type]

	if diagnostic_type == nil {
		log.errorf("Diagnostic type did not exist: %v", type)
		return
	}

	for _, &diagnostic_array in diagnostic_type {
		for diagnostic in diagnostic_array {
			delete(diagnostic.message)
			delete(diagnostic.code)
		}
		clear(&diagnostic_array)
	}
}

clear_check_diagnostics_for_paths :: proc(paths: []string) {
	sync.lock(&diagnostic_mutex)
	defer sync.unlock(&diagnostic_mutex)

	for uri, _ in diagnostics[.Check] {
		parsed_uri, ok := common.parse_uri(uri, context.temp_allocator)
		if !ok {
			continue
		}

		for checker_path in paths {
			if path_matches_checker_scope(parsed_uri.path, checker_path) {
				remove_diagnostics_locked(.Check, uri)
				break
			}
		}
	}
}

get_merged_diagnostics :: proc() -> map[string][dynamic]Diagnostic {
	sync.lock(&diagnostic_mutex)
	defer sync.unlock(&diagnostic_mutex)

	merged_diagnostics := make(map[string][dynamic]Diagnostic, context.temp_allocator)

	for diagnostic_type in diagnostics {
		for k, v in diagnostic_type {
			diagnostic_array := &merged_diagnostics[k]

			if diagnostic_array == nil {
				merged_diagnostics[k] = make([dynamic]Diagnostic, context.temp_allocator)
				diagnostic_array = &merged_diagnostics[k]
			}

			append(diagnostic_array, ..v[:])
		}
	}
	return merged_diagnostics
}

push_diagnostics :: proc(writer: ^Writer) {
	merged_diagnostics := get_merged_diagnostics()

	for k, v in merged_diagnostics {
		//Find the unique diagnostics, since some poor profile settings make the checker check the same file multiple times
		unique := slice.unique(v[:])

		params := NotificationPublishDiagnosticsParams {
			uri         = k,
			diagnostics = unique,
		}

		notifaction := Notification {
			jsonrpc = "2.0",
			method  = "textDocument/publishDiagnostics",
			params  = params,
		}

		if writer != nil {
			send_notification(notifaction, writer)
		}
	}

}
