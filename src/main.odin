package main

import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"
import "core:strings"
import "core:slice"
import "core:strconv"
import "core:encoding/json"

running: bool;

os_read :: proc(handle: rawptr, data: [] byte) -> (int, int)
{
    return os.read(cast(os.Handle)handle, data);
}

os_write :: proc(handle: rawptr, data: [] byte) -> (int, int)
{
    return os.write(cast(os.Handle)handle, data);
}

//Note(Daniel, Should look into handling errors without crashing from parsing)

run :: proc(reader: ^Reader, writer: ^Writer) {

    config: Config;

    log.info("Starting Odin Language Server");

    running = true;

    for running {

        header, success := read_and_parse_header(reader);

        if(!success) {
            log.error("Failed to read and parse header");
            return;
        }


        value: json.Value;
        value, success = read_and_parse_body(reader, header);

        if(!success) {
            log.error("Failed to read and parse body");
            return;
        }

        success = handle_request(value, &config, writer);

        if(!success) {
            log.error("Unrecoverable handle request");
            return;
        }

        free_all(context.temp_allocator);

    }

}

end :: proc() {

}


main :: proc() {

    reader := make_reader(os_read, cast(rawptr)os.stdin);
    writer := make_writer(os_write, cast(rawptr)os.stdout);

    context.logger = create_lsp_logger(&writer);

    run(&reader, &writer);
}

