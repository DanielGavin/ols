package server

import "core:os"
import "core:mem"
import "core:fmt"
import "core:strings"
import "core:sync"

WriterFn :: proc(_: rawptr, _: []byte) -> (int, int)

Writer :: struct {
	writer_fn:      WriterFn,
	writer_context: rawptr,
	writer_mutex:   sync.Mutex,
}

make_writer :: proc(writer_fn: WriterFn, writer_context: rawptr) -> Writer {
	writer := Writer {writer_context = writer_context, writer_fn = writer_fn}
	sync.mutex_init(&writer.writer_mutex)
	return writer
}

write_sized :: proc(writer: ^Writer, data: []byte) -> bool {

	sync.mutex_lock(&writer.writer_mutex)
	defer sync.mutex_unlock(&writer.writer_mutex)

	written, err := writer.writer_fn(writer.writer_context, data)

	if (err != 0) {
		return false
	}

	return true
}
