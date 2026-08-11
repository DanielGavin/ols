package ols_testing

import "core:terminal/ansi"
import "core:math"
import "core:strconv"
import "core:strings"
import "src:common"

uri_to_path :: proc (uri: string, allocator := context.allocator) -> string {
	path := common.uri_to_path(uri, context.temp_allocator)
	path = strings.trim_prefix(path, "test/")
	return path
}

find_source_file_by_path :: proc (src: Source, path: string) -> (File, bool) {

	for file in src.files {
		if path == file.name do return file, true
	}

	for pkg in src.packages {
		for file in pkg.files {
			if path == file.name do return file, true
		}
	}

	return {}, false
}

ANSI_RESET    :: ansi.CSI + ansi.RESET + ansi.SGR
ANSI_WHITE_BG :: ansi.CSI + ansi.BG_WHITE + ";" + ansi.FG_BLACK + ";" + ansi.BOLD + ansi.SGR
ANSI_RED_BG   :: ansi.CSI + ansi.BG_RED   + ";" + ansi.FG_BLACK + ";" + ansi.BOLD + ansi.SGR
ANSI_GREEN_BG :: ansi.CSI + ansi.BG_GREEN + ";" + ansi.FG_BLACK + ";" + ansi.BOLD + ansi.SGR

source_location_display :: proc (
	src:      Source,
	location: common.Location,
	before    := ANSI_WHITE_BG,
	after     := ANSI_RESET,
	allocator := context.allocator,
) -> string {

	TAB :: "    "
	LINES_BEFORE :: 2

	start, end := **location.range
	path := uri_to_path(location.uri, context.temp_allocator)

	sb := strings.builder_make(allocator)

	// Write location path as `uri/path(start_line:start_col-end_line:end_col)`
	{
		strings.write_string(&sb, path)
		strings.write_rune(&sb, '(')
		strings.write_int(&sb, start.line)
		strings.write_rune(&sb, ':')
		strings.write_int(&sb, start.character)
		strings.write_rune(&sb, '-')
		strings.write_int(&sb, end.line)
		strings.write_rune(&sb, ':')
		strings.write_int(&sb, end.character)
		strings.write_rune(&sb, ')')
	}

	// Write source lines around the location
	// with location highlighted by the `before` and `after` strings

	file, found_file := find_source_file_by_path(src, path)
	if !found_file {
		return strings.to_string(sb)
	}

	strings.write_rune(&sb, '\n')

	max_digits := math.count_digits_of_base(end.line, 10)

	line_idx := 0
	in_location: bool
	it := file.source
	for line in strings.split_lines_iterator(&it) {
		defer line_idx += 1

		if start.line - line_idx > LINES_BEFORE {
			continue // before
		}
		if line_idx > end.line {
			break // after
		}

		// Write line number aligned to largest
		{
			if in_location {
				strings.write_string(&sb, after)
			}

			buf: [4]byte
			line_idx_str := strconv.write_int(buf[:], i64(line_idx), 10)
			for _ in 0..<max_digits-len(line_idx_str) {
				strings.write_rune(&sb, ' ')
			}
			strings.write_string(&sb, line_idx_str)
			strings.write_rune(&sb, '|')

			if in_location {
				strings.write_string(&sb, before)
			}
		}

		if start.line > line_idx { // before but include
			// Write line
			strings.write_string(&sb, line)
			strings.write_rune(&sb, '\n')
			continue
		}

		// Write line with colored location
		for ch, i in line {
			if !in_location && start.line == line_idx && i == start.character {
				in_location = true
				strings.write_string(&sb, before)
			}

			strings.write_rune(&sb, ch)

			if in_location && end.line == line_idx && i == end.character-1 {
				in_location = false
				strings.write_string(&sb, after)
			}
		}

		if in_location && line_idx >= end.line {
			in_location = false
			strings.write_string(&sb, after)
		}

		strings.write_rune(&sb, '\n')
	}

	if in_location {
		strings.write_string(&sb, after)
	}

	return strings.to_string(sb)
}

compare_expected_slice_set :: proc (
	actual, expected: []$T,
	excluded: []T = nil,
	equals: proc (a, e: T) -> bool,
	allocator := context.allocator,
) -> (
	extra_expected: []int,
	extra_actual:   []int,
	all_good:       bool,
) {
	all_good = true

	extra_expected_dyn := make([dynamic]int, allocator)
	extra_actual_dyn   := make([dynamic]int, allocator)

	defer shrink(&extra_expected_dyn)
	defer shrink(&extra_actual_dyn)

	found_expected := make([]bool, len(expected), context.temp_allocator)

	actual_loop: for a, ai in actual {

		if excluded != nil do for e, ei in excluded {
			if equals(a, e) {
				append(&extra_actual_dyn, ai)
				all_good = false
				continue actual_loop
			}
		}

		for e, ei in expected {
			if !found_expected[ei] && equals(a, e) {
				found_expected[ei] = true
				continue actual_loop
			}
		}

		append(&extra_actual_dyn, ai)
		all_good = false
	}

	for _, ei in expected {
		if found_expected[ei] {
			continue
		}
		all_good = false
		append(&extra_expected_dyn, ei)
	}

	extra_expected = extra_expected_dyn[:]
	extra_actual   = extra_actual_dyn[:]
	return
}
