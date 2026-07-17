package tests

import "core:log"
import "core:testing"
import "src:common"

@(test)
common_get_absolute_range_starting_newline :: proc(t: ^testing.T) {
	src := `
	package foo

	main :: proc() {

	}
	`

	range := common.Range {
		start = {line = 0, character = 0},
		end = {line = 1, character = 0},
	}

	absolute_range, ok := common.get_absolute_range(range, transmute([]u8)(src))
	if !ok {
		log.error(t, "failed to get absolute_range")
	}

	if absolute_range != {0, 1} {
		log.error(t, "incorrect absolute_range", absolute_range, ok)
	}
}

@(test)
common_create_uri :: proc(t: ^testing.T) {
	when ODIN_OS == .Windows {
		result := common.create_uri("C:\\Hello\\my folder\\main.odin", context.temp_allocator)

		// NOTE: `create_uri` has a guard for testing, and removing it breaks all the other tests.
		// So here we just assume it should only have 2 '/' after the 'file://'. It still tests the important parts.
		expected := "file://C%3A/Hello/my%20folder/main.odin"

		testing.expect_value(t, result.uri, expected)
	} else {
		result := common.create_uri("/User/Hello/my folder/main.odin", context.temp_allocator)
		expected := "file:///User/Hello/my%20folder/main.odin"

		testing.expect_value(t, result.uri, expected)
	}
}

@(test)
common_parse_uri :: proc(t: ^testing.T) {
	when ODIN_OS == .Windows {
		to_test := []string{"file:///C:\\Hello\\my folder\\main.odin", "file:///C%3A\\Hello\\my%20folder\\main.odin"}

		// NOTE: `create_uri` has a guard for testing, and removing it breaks all the other tests.
		// So here we just assume it should only have 2 '/' after the 'file://'. It still tests the important parts.
		expected := "file://C%3A/Hello/my%20folder/main.odin"
		for s, i in to_test {
			result, ok := common.parse_uri(s, context.temp_allocator)
			if !ok {
				log.errorf("index %d: failed to parse uri %v", i, s)
			}

			if result.uri != expected {
				log.errorf("index %d: expected uri %v, got %v", i, expected, result.uri)
			}
		}
	} else {
		expected := "file:///User/Hello/my%20folder/main.odin"
		to_test := []string{"file:///User/Hello/my folder/main.odin", "file:///User/Hello/my%20folder/main.odin"}
		for s, i in to_test {
			result, ok := common.parse_uri(s, context.temp_allocator)
			if !ok {
				log.errorf("index %d: failed to parse uri %v", i, s)
			}

			if result.uri != expected {
				log.errorf("index %d: expected uri %v, got %v", i, expected, result.uri)
			}
		}
	}
}
