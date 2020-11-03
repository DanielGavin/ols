package main

import "core:os"
import "core:mem"
import "core:fmt"
import "core:strings"

WriterFn :: proc(rawptr, [] byte) -> (int, int);

Writer :: struct {
    writer_fn: WriterFn,
    writer_context: rawptr,
};

make_writer :: proc(writer_fn: WriterFn, writer_context: rawptr) -> Writer {
    return Writer { writer_context = writer_context, writer_fn = writer_fn };
}

write_sized :: proc(writer: ^Writer, data: []byte) -> bool {
    written, err := writer.writer_fn(writer.writer_context, data);

    if(err != 0 || written != len(data)) {
        return false;
    }

    return true;
}


