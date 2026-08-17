package ols_spall

import "base:runtime"

import "core:fmt"
import "core:time"
import "core:prof/spall"
import "core:sync"
import "core:os"

SPALL_ENABLED           :: #config(SPALL_ENABLED, false)
INSTRUMENTATION_ENABLED :: #config(INSTRUMENTATION_ENABLED, false)

when SPALL_ENABLED {

	spall_ctx: spall.Context
	@(thread_local) spall_buffer: spall.Buffer
	buffer_backing: []u8

	@init _init :: proc "contextless" () {
		context = runtime.default_context()

		dirname, _ := os.join_path({#directory, "..", "..", "traces"}, context.temp_allocator)
		os.make_directory(dirname)

		filename, _ := os.join_path({dirname, fmt.tprintf("%i.spall", time.time_to_unix(time.now()))}, context.temp_allocator)
		spall_ctx = spall.context_create(filename)

		buffer_backing = make([]u8, spall.BUFFER_DEFAULT_SIZE)

		spall_buffer = spall.buffer_create(buffer_backing, u32(sync.current_thread_id()))

		spall._buffer_name_process(&spall_ctx, &spall_buffer, "OLS")
	}

	@fini _fini :: proc "contextless" () {
		context = runtime.default_context()

		spall.buffer_destroy(&spall_ctx, &spall_buffer)
		delete(buffer_backing)
		spall.context_destroy(&spall_ctx)
	}

	when INSTRUMENTATION_ENABLED {
		@(instrumentation_enter)
		_spall_enter :: proc "contextless" (proc_address, call_site_return_address: rawptr, loc: runtime.Source_Code_Location) {
			trace_begin("", "", loc)
		}

		@(instrumentation_exit)
		_spall_exit :: proc "contextless" (proc_address, call_site_return_address: rawptr, loc: runtime.Source_Code_Location) {
			trace_end()
		}
	}

	@(no_instrumentation)
	name_thread :: proc "contextless" (name: string, loc := #caller_location) {
		spall._buffer_name_thread(&spall_ctx, &spall_buffer, name, loc)
	}
	@(no_instrumentation)
	trace_begin :: proc "contextless" (name: string, args: string = "", loc := #caller_location) {
		spall._buffer_begin(&spall_ctx, &spall_buffer, name, args, loc)
	}
	@(no_instrumentation)
	trace_end :: proc "contextless" () {
		spall._buffer_end(&spall_ctx, &spall_buffer)
	}
	@(no_instrumentation, deferred_none=trace_end)
	trace :: proc "contextless" (name: string, args: string = "", loc:= #caller_location) {
		trace_begin(name, args, loc)
	}
} else {
	@(no_instrumentation, disabled=true)
	name_thread :: proc "contextless" (name: string, loc := #caller_location) {}
	@(no_instrumentation, disabled=true)
	trace_begin :: proc "contextless" (name: string, args: string = "", loc := #caller_location) {}
	@(no_instrumentation, disabled=true)
	trace_end :: proc "contextless" () {}
	@(no_instrumentation, disabled=true)
	trace :: proc "contextless" (name: string, args: string = "", loc := #caller_location) {}
}

