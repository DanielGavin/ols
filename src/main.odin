package main

import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"
import "core:strings"
import "core:slice"
import "core:strconv"
import "core:encoding/json"

import "intrinsics"

import "shared:index"
import "shared:server"
import "shared:common"

os_read :: proc(handle: rawptr, data: [] byte) -> (int, int)
{
    return os.read(cast(os.Handle)handle, data);
}

os_write :: proc(handle: rawptr, data: [] byte) -> (int, int)
{
    return os.write(cast(os.Handle)handle, data);
}

//Note(Daniel, Should look into handling errors without crashing from parsing)

run :: proc(reader: ^server.Reader, writer: ^server.Writer) {

    config: common.Config;

    /*
    tracking_allocator: mem.Tracking_Allocator;
    default_allocator := context.allocator;
    mem.tracking_allocator_init(&tracking_allocator, default_allocator);
    context.allocator = mem.tracking_allocator(&tracking_allocator);
    */

    //temporary collections being set manually, need to get client configuration set up.
    config.collections = make(map [string] string);

    config.collections["core"] = "C:/Users/danie/OneDrive/Desktop/Computer_Science/Odin/core";

    log.info("Starting Odin Language Server");

    index.build_static_index(context.allocator, &config);

    log.info("Finished indexing");

    config.running = true;

    for config.running {

        header, success := server.read_and_parse_header(reader);

        if(!success) {
            log.error("Failed to read and parse header");
            return;
        }


        value: json.Value;
        value, success = server.read_and_parse_body(reader, header);

        if(!success) {
            log.error("Failed to read and parse body");
            return;
        }

        success = server.handle_request(value, &config, writer);

        if(!success) {
            log.error("Unrecoverable handle request");
            return;
        }

        free_all(context.temp_allocator);
    }

    delete(config.collections);
    delete(config.workspace_folders);

    server.document_storage_shutdown();

    index.free_static_index();

    /*
    for k, v in tracking_allocator.allocation_map {
        fmt.println(v);
    }


    fmt.println(len(tracking_allocator.allocation_map));
    */
}

end :: proc() {

}


main :: proc() {

    reader := server.make_reader(os_read, cast(rawptr)os.stdin);
    writer := server.make_writer(os_write, cast(rawptr)os.stdout);

    init_global_temporary_allocator(mem.megabytes(10));

    //fd, err := os.open("C:/Users/danie/OneDrive/Desktop/Computer_Science/ols/log.txt", os.O_RDWR|os.O_CREATE|os.O_TRUNC );
    //context.logger = log.create_file_logger(fd);

    context.logger = server.create_lsp_logger(&writer);

    run(&reader, &writer);
}

