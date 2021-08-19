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

import "intrinsics"

import "shared:index"
import "shared:server"
import "shared:common"

os_read :: proc(handle: rawptr, data: []byte) -> (int, int) {
	ptr  := cast(^os.Handle)handle;
	a, b := os.read(ptr^, data);
	return a, cast(int)b;
}

os_write :: proc(handle: rawptr, data: []byte) -> (int, int) {
	ptr  := cast(^os.Handle)handle;
	a, b := os.write(ptr^, data);
	return a, cast(int)b;
}

//Note(Daniel, Should look into handling errors without crashing from parsing)

verbose_logger: log.Logger;

run :: proc(reader: ^server.Reader, writer: ^server.Writer) {

	common.config.debug_single_thread = true;
	common.config.collections = make(map[string]string);

	log.info("Starting Odin Language Server");

	common.config.running = true;

	for common.config.running {

		if common.config.verbose {
			context.logger = verbose_logger;
		} else {
			context.logger = log.Logger {nil, nil, log.Level.Debug, nil};
		}

		header, success := server.read_and_parse_header(reader);

		if (!success) {
			log.error("Failed to read and parse header");
			return;
		}

		value: json.Value;
		value, success = server.read_and_parse_body(reader, header);

		if (!success) {
			log.error("Failed to read and parse body");
			return;
		}

		success = server.handle_request(value, &common.config, writer);

		if (!success) {
			log.error("Unrecoverable handle request");
			return;
		}

		free_all(context.temp_allocator);
	}

	for k, v in config.collections {
		delete(k);
		delete(v);
	}

	delete(common.config.collections);
	delete(common.config.workspace_folders);

	server.document_storage_shutdown();

	index.free_static_index();

	common.pool_wait_and_process(&server.pool);
	common.pool_destroy(&server.pool);
}

end :: proc() {
}

main :: proc() {

	reader := server.make_reader(os_read, cast(rawptr)&os.stdin);
	writer := server.make_writer(os_write, cast(rawptr)&os.stdout);

	verbose_logger := server.create_lsp_logger(&writer, log.Level.Error);

	context.logger = verbose_logger;

	init_global_temporary_allocator(mem.megabytes(100));

	run(&reader, &writer);
}
