package main

import "base:intrinsics"

import "core:encoding/json"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"
import "core:reflect"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:sync"
import "core:thread"

import "core:sys/windows"

import "src:common"
import "src:server"

VERSION :: "dev-2024-11-9:g584f01b"

os_read :: proc(handle: rawptr, data: []byte) -> (int, int) {
	ptr := cast(^os.Handle)handle
	a, b := os.read(ptr^, data)
	return a, cast(int)(b != nil)
}

os_write :: proc(handle: rawptr, data: []byte) -> (int, int) {
	ptr := cast(^os.Handle)handle
	a, b := os.write(ptr^, data)
	return a, cast(int)(b != nil)
}

//Note(Daniel, Should look into handling errors without crashing from parsing)

request_thread: ^thread.Thread

logger: ^log.Logger


run :: proc(reader: ^server.Reader, writer: ^server.Writer) {
	common.config.collections = make(map[string]string)

	log.info("Starting Odin Language Server")

	common.config.running = true

	logger = new(log.Logger)

	request_thread_data := server.RequestThreadData {
		reader = reader,
		writer = writer,
		logger = logger,
	}

	/*
	tracking_allocator: mem.Tracking_Allocator
    mem.tracking_allocator_init(&tracking_allocator, context.allocator)
    context.allocator = mem.tracking_allocator(&tracking_allocator)
	*/

	server.requests = make([dynamic]server.Request, context.allocator)
	server.deletings = make([dynamic]server.Request, context.allocator)

	request_thread = thread.create_and_start_with_data(cast(rawptr)&request_thread_data, server.thread_request_main)

	for common.config.running {
		if common.config.verbose {
			//Currently letting verbose use error, since some ast prints causes crashes - most likely a bug in core:fmt.
			logger^ = server.create_lsp_logger(writer, log.Level.Error)
		} else {
			logger^ = server.create_lsp_logger(writer, log.Level.Error)
		}

		context.logger = logger^

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
	if len(os.args) > 1 && os.args[1] == "version" {
		fmt.println("ols version", VERSION)
		os.exit(0)
	}
	reader := server.make_reader(os_read, cast(rawptr)&os.stdin)
	writer := server.make_writer(os_write, cast(rawptr)&os.stdout)

	/*
	fh, err := os.open("log.txt", os.O_RDWR|os.O_CREATE) 
	
	if err != os.ERROR_NONE {
		return
	}
	
	context.logger = log.create_file_logger(fh, log.Level.Info)
	*/

	init_global_temporary_allocator(mem.Megabyte * 100)

	run(&reader, &writer)
}
