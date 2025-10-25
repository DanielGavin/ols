package tests

import "core:log"
import "src:common"
import "core:testing"

@(test)
common_get_absolute_range_starting_newline :: proc(t: ^testing.T) {
	src := `
	package foo

	main :: proc() {

	}
	`

	range := common.Range{
		start = {
			line = 0,
			character = 0,
		},
		end = {
			line = 1,
			character = 0,
		}
	}

	absolute_range, ok := common.get_absolute_range(range, transmute([]u8)(src))
	if !ok {
		log.error(t, "failed to get absolute_range")
	}

	if absolute_range != {0, 1} {
		log.error(t, "incorrect absolute_range", absolute_range, ok)
	}
}
