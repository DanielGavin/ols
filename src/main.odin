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
	ptr  := cast(^os.Handle)handle
	a, b := os.read(ptr^, data)
	return a, cast(int)b
}

os_write :: proc(handle: rawptr, data: []byte) -> (int, int) {
	ptr  := cast(^os.Handle)handle
	a, b := os.write(ptr^, data)
	return a, cast(int)b
}

//Note(Daniel, Should look into handling errors without crashing from parsing)

verbose_logger: log.Logger
file_logger: log.Logger
file_logger_init: bool
request_thread: ^thread.Thread

run :: proc(reader: ^server.Reader, writer: ^server.Writer) {
	common.config.collections = make(map[string]string)

	log.info("Starting Odin Language Server")

	common.config.running = true

	request_thread_data := server.RequestThreadData {
		reader = reader,
		writer = writer,
	}

	server.requests = make([dynamic]server.Request, context.allocator)
	server.deletings = make([dynamic]server.Request, context.allocator)

	request_thread = thread.create_and_start_with_data(cast(rawptr)&request_thread_data, server.thread_request_main)

	server.setup_index();
	
	for common.config.running {
		if common.config.file_log {
			if !file_logger_init {
				if fh, err := os.open("log.txt"); err == 0 {
					file_logger = log.create_file_logger(fh, log.Level.Info)
				} 
			}			
			context.logger = file_logger
		} else if common.config.verbose {
			context.logger = verbose_logger
		} else {
			context.logger = log.Logger {nil, nil, log.Level.Debug, nil}
		}

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
}

end :: proc() {
}

main :: proc() {

	reader := server.make_reader(os_read, cast(rawptr)&os.stdin)
	writer := server.make_writer(os_write, cast(rawptr)&os.stdout)

	verbose_logger := server.create_lsp_logger(&writer, log.Level.Error)

	context.logger = verbose_logger

	init_global_temporary_allocator(mem.Megabyte*100)
	
	run(&reader, &writer)
}
