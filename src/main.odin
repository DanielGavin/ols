package main

import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"
import "core:strings"
import "core:slice"
import "core:strconv"
import "core:thread"
import "core:encoding/json"
import "core:reflect"
import "core:sync"

import "core:intrinsics"

import "shared:server"
import "shared:common"

os_read :: proc(handle: rawptr, data: []byte) -> (int, int) {
	ptr := cast(^os.Handle)handle
	a, b := os.read(ptr^, data)
	return a, cast(int)b
}

os_write :: proc(handle: rawptr, data: []byte) -> (int, int) {
	ptr := cast(^os.Handle)handle
	a, b := os.write(ptr^, data)
	return a, cast(int)b
}

//Note(Daniel, Should look into handling errors without crashing from parsing)

request_thread: ^thread.Thread

logger: log.Logger

run :: proc(reader: ^server.Reader, writer: ^server.Writer) {
	common.config.collections = make(map[string]string)

	log.info("Starting Odin Language Server")

	common.config.running = true

	request_thread_data := server.RequestThreadData {
		reader = reader,
		writer = writer,
	}

	/*
	tracking_allocator: mem.Tracking_Allocator
    mem.tracking_allocator_init(&tracking_allocator, context.allocator)
    context.allocator = mem.tracking_allocator(&tracking_allocator)
	*/

	server.requests = make([dynamic]server.Request, context.allocator)
	server.deletings = make([dynamic]server.Request, context.allocator)

	request_thread = thread.create_and_start_with_data(
		cast(rawptr)&request_thread_data,
		server.thread_request_main,
	)

	for common.config.running {
		if common.config.verbose {
			logger = server.create_lsp_logger(writer, log.Level.Info)
		} else {
			logger = server.create_lsp_logger(writer, log.Level.Error)
		}

		context.logger = logger

		server.consume_requests(&common.config, writer)
	}

	for k, v in common.config.collections {
		delete(k)
		delete(v)
	}

	delete(common.config.collections)
	delete(common.config.workspace_folders)

	server.document_storage_shutdown()

	server.free_index()

	/*
    for key, value in tracking_allocator.allocation_map {
        log.errorf("%v: Leaked %v bytes\n", value.location, value.size)
    }	
	*/
}

end :: proc() {
}

main :: proc() {

	reader := server.make_reader(os_read, cast(rawptr)&os.stdin)
	writer := server.make_writer(os_write, cast(rawptr)&os.stdout)

	/*
	fh, err := os.open("log.txt", os.O_RDWR|os.O_CREATE) 
	
	if err != os.ERROR_NONE {
		return
	}
	
	context.logger = log.create_file_logger(fh, log.Level.Info)
	*/

	when ODIN_DEBUG && ODIN_OS == .Windows {
		set_stacktrace()
	}

	init_global_temporary_allocator(mem.Megabyte * 100)


	run(&reader, &writer)
}
