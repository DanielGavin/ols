package server

import "core:sync"

WriterFn :: proc(_: rawptr, _: []byte) -> (int, int)

Writer :: struct {
	writer_fn:      WriterFn,
	writer_context: rawptr,
	writer_mutex:   sync.Mutex,
}

make_writer :: proc(writer_fn: WriterFn, writer_context: rawptr) -> Writer {
	writer := Writer {
		writer_context = writer_context,
		writer_fn      = writer_fn,
	}
	return writer
}

// The header and data are written under one lock, so another thread's message cannot land between them
write_sized :: proc(writer: ^Writer, header, data: []byte) -> bool {
	sync.mutex_lock(&writer.writer_mutex)
	defer sync.mutex_unlock(&writer.writer_mutex)

	if _, err := writer.writer_fn(writer.writer_context, header); err != 0 {
		return false
	}

	_, err := writer.writer_fn(writer.writer_context, data)
	return err == 0
}
