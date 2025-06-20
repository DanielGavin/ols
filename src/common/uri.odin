package common

import "core:fmt"
import "core:mem"
import "core:path/filepath"
import "core:strconv"
import "core:strings"
import "core:unicode/utf8"

Uri :: struct {
	uri:         string,
	decode_full: string,
	path:        string,
}

//Note(Daniel, This is an extremely incomplete uri parser and for now ignores fragment and query and only handles file schema)
parse_uri :: proc(value: string, allocator: mem.Allocator) -> (Uri, bool) {
	uri: Uri

	decoded, ok := decode_percent(value, allocator)

	if !ok {
		return uri, false
	}

	starts := "file:///"

	start_index := len(starts)

	if !starts_with(decoded, starts) {
		return uri, false
	}

	when ODIN_OS != .Windows {
		start_index -= 1
	}

	uri.uri = strings.clone(value, allocator)

	uri.decode_full = decoded
	uri.path = decoded[start_index:]

	return uri, true
}

//Note(Daniel, Again some really incomplete and scuffed uri writer)
create_uri :: proc(path: string, allocator: mem.Allocator) -> Uri {
	path_forward, _ := filepath.to_slash(path, context.temp_allocator)

	builder := strings.builder_make(allocator)

	//bad
	when ODIN_OS == .Windows && !ODIN_TEST {
		strings.write_string(&builder, "file:///")
	} else {
		strings.write_string(&builder, "file://")
	}

	strings.write_string(&builder, encode_percent(path_forward, context.temp_allocator))

	uri: Uri

	uri.uri = strings.to_string(builder)
	uri.decode_full = strings.clone(path_forward, allocator)
	uri.path = uri.decode_full

	return uri
}

delete_uri :: proc(uri: Uri) {
	if uri.uri != "" {
		delete(uri.uri)
	}

	if uri.decode_full != "" {
		delete(uri.decode_full)
	}
}

encode_percent :: proc(value: string, allocator: mem.Allocator) -> string {
	builder := strings.builder_make(allocator)

	data := transmute([]u8)value
	index: int

	for index < len(value) {
		r, w := utf8.decode_rune(data[index:])

		if r > 127 || r == ':' {
			for i := 0; i < w; i += 1 {
				strings.write_string(
					&builder,
					strings.concatenate({"%", fmt.tprintf("%X", data[index + i])}, context.temp_allocator),
				)
			}
		} else {
			strings.write_byte(&builder, data[index])
		}

		index += w
	}

	return strings.to_string(builder)
}

@(private)
starts_with :: proc(value: string, starts_with: string) -> bool {
	if len(value) < len(starts_with) {
		return false
	}

	for i := 0; i < len(starts_with); i += 1 {
		if value[i] != starts_with[i] {
			return false
		}
	}

	return true
}

@(private)
decode_percent :: proc(value: string, allocator: mem.Allocator) -> (string, bool) {
	builder := strings.builder_make(allocator)

	for i := 0; i < len(value); i += 1 {
		if value[i] == '%' {
			if i + 2 < len(value) {
				v, ok := strconv.parse_i64_of_base(value[i + 1:i + 3], 16)

				if !ok {
					strings.builder_destroy(&builder)
					return "", false
				}

				strings.write_byte(&builder, cast(byte)v)

				i += 2
			} else {
				strings.builder_destroy(&builder)
				return "", false
			}
		} else {
			strings.write_byte(&builder, value[i])
		}
	}

	return strings.to_string(builder), true
}
