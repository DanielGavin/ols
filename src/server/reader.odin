package server

import "core:mem"
import "core:os"
import "core:strings"

ReaderFn :: proc(_: rawptr, _: []byte) -> (int, int)

Reader :: struct {
	reader_fn:      ReaderFn,
	reader_context: rawptr,
}

make_reader :: proc(reader_fn: ReaderFn, reader_context: rawptr) -> Reader {
	return Reader{reader_context = reader_context, reader_fn = reader_fn}
}

read_u8 :: proc(reader: ^Reader) -> (u8, bool) {
	value: [1]byte

	read, err := reader.reader_fn(reader.reader_context, value[:])

	if (err != 0 || read != 1) {
		return 0, false
	}

	return value[0], true
}

read_until_delimiter :: proc(reader: ^Reader, delimiter: u8, builder: ^strings.Builder) -> bool {
	for true {

		value, success := read_u8(reader)

		if (!success) {
			return false
		}

		strings.write_byte(builder, value)

		if (value == delimiter) {
			break
		}
	}

	return true
}

read_sized :: proc(reader: ^Reader, data: []u8) -> (ok: bool) {
	ok = true
	size := len(data)
	n := 0

	for n < size && ok {
		read: int
		err_code: int

		read, err_code = reader.reader_fn(reader.reader_context, data[n:])

		ok = err_code == 0

		n += read
	}

	if n >= size {
		ok = true
	}

	return
}
