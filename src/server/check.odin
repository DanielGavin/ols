package server

import "core:encoding/json"
import "core:fmt"
import "core:intrinsics"
import "core:log"
import "core:mem"
import "core:os"
import "core:path/filepath"
import path "core:path/slashpath"
import "core:runtime"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:sync"
import "core:text/scanner"
import "core:thread"

import "shared:common"

//Store uris we have reported on since last save. We use this to clear them on next save.
uris_reported := make([dynamic]string)

check :: proc(paths: []string, writer: ^Writer, config: ^common.Config) {
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
				"%v check %s %s %s %s %s",
				command,
				path,
				strings.to_string(collection_builder),
				entry_point_opt,
				config.checker_args,
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

		s: scanner.Scanner

		scanner.init(&s, string(buffer))

		s.whitespace = {'\t', ' '}

		current: rune

		ErrorSeperator :: struct {
			message: string,
			line:    int,
			column:  int,
			uri:     string,
		}

		error_seperators := make(
			[dynamic]ErrorSeperator,
			context.temp_allocator,
		)

		//find all the signatures string(digit:digit)
		loop: for scanner.peek(&s) != scanner.EOF {

			scan_line: {
				error: ErrorSeperator

				source_pos := s.src_pos

				if source_pos == 1 {
					source_pos = 0
				}

				for scanner.peek(&s) != '(' {
					n := scanner.scan(&s)

					if n == scanner.EOF {
						break loop
					}
					if n == '\n' {
						source_pos = s.src_pos - 1
					}
				}

				error.uri = strings.clone(string(buffer[source_pos:s.src_pos - 1]), context.temp_allocator)

				left_paren := scanner.scan(&s)

				if left_paren != '(' {
					break scan_line
				}

				lhs_digit := scanner.scan(&s)

				if lhs_digit != scanner.Int {
					break scan_line
				}

				line, column: int
				ok: bool

				line, ok = strconv.parse_int(scanner.token_text(&s))

				if !ok {
					break scan_line
				}

				seperator := scanner.scan(&s)

				if seperator != ':' {
					break scan_line
				}
				
				rhs_digit := scanner.scan(&s)

				if rhs_digit != scanner.Int {
					break scan_line
				}

				column, ok = strconv.parse_int(scanner.token_text(&s))

				if !ok {
					break scan_line
				}
	
				right_paren := scanner.scan(&s)

				if right_paren != ')' {
					break scan_line
				}

				source_pos = s.src_pos

				for scanner.peek(&s) != '\n' {
					n := scanner.scan(&s)

					if n == scanner.EOF {
						break
					}
				}

				if source_pos == s.src_pos {
					continue
				}

				error.message = strings.clone(string(buffer[source_pos:s.src_pos - 1]), context.temp_allocator)
				error.column = column
				error.line = line

				append(&error_seperators, error)
				continue loop
			}

			// line scan failed, skip to the next line
			for scanner.peek(&s) != '\n' {
				n := scanner.scan(&s)
				if n == scanner.EOF {
					break
				}
			}
		}

		for error in error_seperators {
			if strings.contains(
				error.message,
				"Redeclaration of 'main' in this scope",
			) {
				continue
			}

			if error.uri not_in errors {
				errors[error.uri] = make(
					[dynamic]Diagnostic,
					context.temp_allocator,
				)
			}

			append(
				&errors[error.uri],
				Diagnostic {
					code = "checker",
					severity = .Error,
					range =  {
						start =  {
							character = error.column,
							line = error.line - 1,
						},
						end = {character = 0, line = error.line},
					},
					message = error.message,
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

		params := NotificationPublishDiagnosticsParams {
			uri         = uri.uri,
			diagnostics = v[:],
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
