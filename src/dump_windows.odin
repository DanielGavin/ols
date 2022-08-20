package main

import "core:os"
import "core:slice"
import "core:strings"
import "core:intrinsics"
import "core:runtime"
import "core:io"
import "core:sync"
import "core:path/filepath"
import "core:log"
import "core:fmt"

import "pdb"

import windows "core:sys/windows"

set_stacktrace :: proc() {
	pdb.SetUnhandledExceptionFilter(dump_stack_trace_on_exception_logger)
}

print_source_code_location_builder :: proc(
	using scl: runtime.Source_Code_Location,
) -> string {
	using runtime

	builder := strings.builder_make()

	strings.write_string(&builder, file_path)
	when ODIN_ERROR_POS_STYLE == .Unix {
		strings.write_string(&builder, ':')
		strings.write_i64(&builder, cast(i64)line)
		strings.write_string(&builder, ':')
		strings.write_i64(&builder, cast(i64)column)
		strings.write_string(&builder, ':')
	} else {
		strings.write_string(&builder, "(")
		strings.write_i64(&builder, cast(i64)line)
		strings.write_string(&builder, ":")
		strings.write_i64(&builder, cast(i64)column)
		strings.write_string(&builder, ")")
	}
	strings.write_string(&builder, procedure)
	strings.write_string(&builder, "()\n")

	return strings.to_string(builder)
}


dump_stack_trace_on_exception_logger :: proc "stdcall" (
	ExceptionInfo: ^windows.EXCEPTION_POINTERS,
) -> windows.LONG {
	using pdb
	context = runtime.default_context() // TODO: use a more efficient one-off allocators
	context.logger = logger

	builder := strings.builder_make()

	sync.guard(&_dumpStackTrackMutex)

	if ExceptionInfo.ExceptionRecord != nil {
		strings.write_string(
			&builder,
			fmt.tprintf(
				"%v, Flags: 0x %v",
				ExceptionInfo.ExceptionRecord.ExceptionCode,
				ExceptionInfo.ExceptionRecord.ExceptionFlags,
			),
		)
	}

	ctxt := cast(^CONTEXT)ExceptionInfo.ContextRecord
	traceBuf: [64]StackFrame
	traceCount := capture_stack_trace_from_context(ctxt, traceBuf[:])
	strings.write_string(&builder, " Stacktrace:")
	strings.write_uint(&builder, traceCount)
	strings.write_string(&builder, "\n")
	srcCodeLocs: RingBuffer(runtime.Source_Code_Location)
	init_rb(&srcCodeLocs, 64)
	parse_stack_trace(traceBuf[:traceCount], true, &srcCodeLocs)
	for i in 0 ..< srcCodeLocs.len {
		scl := get_rb(&srcCodeLocs, i)
		strings.write_string(&builder, print_source_code_location_builder(scl))
	}

	log.error(strings.to_string(builder))

	return windows.EXCEPTION_CONTINUE_SEARCH
}
