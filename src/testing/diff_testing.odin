package ols_testing

// ============================================================================
// Diff-based Code Action Testing
// ============================================================================
//
// A more robust way to test code actions using a unified diff-like format.
// Instead of manually specifying line numbers and positions, write the source
// with inline diff markers showing the expected transformation.
//
// Format:
//   - Lines starting with " " (space) or no prefix: common to before/after
//   - Lines starting with "-": only in "before" (will be removed/changed)
//   - Lines starting with "+": only in "after" (will be added)
//   - Selection markers {<} and {>} go in the "before" lines (- or common)
//
// Example:
//   ```
//   package test
//   main :: proc() {
//   -	x := {<}a + b{>}
//   +	extracted := a + b
//   +	x := extracted
//   }
//   ```
//
// This will:
//   1. Parse to get "before" code with selection markers
//   2. Parse to get expected "after" code
//   3. Apply the code action to "before"
//   4. Verify result matches "after"

import "core:strings"
import "core:testing"

import "src:common"
import "src:server"

// Test a code action using diff format.
// The diff_source contains:
//   - Lines starting with "-": before only (contain selection markers {<} {>})
//   - Lines starting with "+": after only (expected result)
//   - Lines starting with " " or no prefix: common to both
expect_code_action_diff :: proc(t: ^testing.T, diff_source: string, action_name: string, packages: []Package = {}) {
	before_code, expected_after, parse_ok := parse_diff_source(diff_source)
	if !parse_ok {
		testing.expect(t, false, "Failed to parse diff source")
		return
	}

	// Create source with the "before" code
	src := Source {
		main     = before_code,
		packages = packages,
	}

	setup(&src)
	defer teardown(&src)

	input_range := build_action_range(&src)
	actions, ok := server.get_code_actions(src.document, input_range, &src.config)
	if !ok {
		testing.expect(t, false, "Failed to get code actions")
		return
	}

	// Find the requested action
	for action in actions {
		if action.title != action_name do continue
		edits, found := action.edit.changes[src.document.uri.uri]
		if !found {
			testing.expect(t, false, "Action found but has no edits")
			return
		}

		source := string(src.document.text)

		actual_after := apply_text_edits(source, edits)

		normalized_expected := normalize_source(expected_after)
		normalized_actual := normalize_source(actual_after)

		if normalized_expected != normalized_actual {
			testing.expectf(
				t,
				false,
				"\nCode action result mismatch.\n\nExpected:\n%s\n\nActual:\n%s",
				normalized_expected,
				normalized_actual,
			)
		}
		return
	}

	testing.expectf(t, false, "Action '%s' not found", action_name)
}

// Parses a diff-formatted source into before and after code.
// Returns: before_code (with markers), after_code (without markers), success
@(private = "file")
parse_diff_source :: proc(diff_source: string) -> (before: string, after: string, ok: bool) {
	before_builder := strings.builder_make(context.temp_allocator)
	after_builder := strings.builder_make(context.temp_allocator)

	lines := strings.split_lines(diff_source, context.temp_allocator)

	for line in lines {
		if len(line) == 0 {
			// Empty line goes to both
			strings.write_string(&before_builder, "\n")
			strings.write_string(&after_builder, "\n")
			continue
		}

		first_char := line[0]
		rest := line[1:] if len(line) > 1 else ""

		switch first_char {
		case '-':
			// Only in "before"
			strings.write_string(&before_builder, rest)
			strings.write_string(&before_builder, "\n")
		case '+':
			// Only in "after"
			strings.write_string(&after_builder, rest)
			strings.write_string(&after_builder, "\n")
		case ' ':
			// Common to both (space prefix)
			strings.write_string(&before_builder, rest)
			strings.write_string(&before_builder, "\n")
			strings.write_string(&after_builder, rest)
			strings.write_string(&after_builder, "\n")
		case:
			// No prefix - treat as common (for convenience)
			strings.write_string(&before_builder, line)
			strings.write_string(&before_builder, "\n")
			strings.write_string(&after_builder, line)
			strings.write_string(&after_builder, "\n")
		}
	}

	before_code := strings.to_string(before_builder)
	after_code := strings.to_string(after_builder)

	// Remove selection markers from after_code (they shouldn't be there but just in case)
	after_code, _ = strings.replace_all(after_code, "{<}", "", context.temp_allocator)
	after_code, _ = strings.replace_all(after_code, "{>}", "", context.temp_allocator)
	after_code, _ = strings.replace_all(after_code, "{*}", "", context.temp_allocator)

	return before_code, after_code, true
}

// Apply text edits to source code and return the result.
// Edits are sorted and applied from end to start to preserve positions.
@(private = "file")
apply_text_edits :: proc(source: string, edits: []server.TextEdit) -> string {
	if len(edits) == 0 {
		return source
	}

	// Sort edits by position (reverse order so we can apply from end to start)
	sorted_edits := make([]server.TextEdit, len(edits), context.temp_allocator)
	copy(sorted_edits, edits)

	// Simple bubble sort (edits are usually small in number)
	for i in 0 ..< len(sorted_edits) {
		for j in i + 1 ..< len(sorted_edits) {
			// Compare by line first, then by character
			if sorted_edits[j].range.start.line > sorted_edits[i].range.start.line ||
			   (sorted_edits[j].range.start.line == sorted_edits[i].range.start.line &&
					   sorted_edits[j].range.start.character > sorted_edits[i].range.start.character) {
				sorted_edits[i], sorted_edits[j] = sorted_edits[j], sorted_edits[i]
			}
		}
	}

	result := strings.clone(source, context.temp_allocator)

	// Apply edits from end to start to preserve positions
	for edit in sorted_edits {
		start_offset := position_to_offset(result, edit.range.start)
		end_offset := position_to_offset(result, edit.range.end)

		if start_offset < 0 || end_offset < 0 || start_offset > len(result) || end_offset > len(result) {
			continue
		}

		// Build new string: before + newText + after
		new_result := strings.concatenate(
			{result[:start_offset], edit.newText, result[end_offset:]},
			context.temp_allocator,
		)
		result = new_result
	}

	return result
}

// Convert a Position to a byte offset in the source.
@(private = "file")
position_to_offset :: proc(source: string, pos: common.Position) -> int {
	line := 0
	offset := 0

	for offset < len(source) {
		if line == pos.line {
			// Found the line, now add character offset
			char_offset := 0
			for offset + char_offset < len(source) && char_offset < pos.character {
				if source[offset + char_offset] == '\n' {
					break
				}
				char_offset += 1
			}
			return offset + char_offset
		}

		if source[offset] == '\n' {
			line += 1
		}
		offset += 1
	}

	// If we're looking for a position past the end, return end
	if line == pos.line {
		return offset
	}

	return -1
}

// Normalize source code for comparison (trim trailing whitespace from lines, normalize line endings).
@(private = "file")
normalize_source :: proc(source: string) -> string {
	lines := strings.split_lines(source, context.temp_allocator)
	builder := strings.builder_make(context.temp_allocator)

	// Find the last non-empty line to avoid trailing blank lines
	last_non_empty := len(lines) - 1
	for last_non_empty >= 0 && strings.trim_space(lines[last_non_empty]) == "" {
		last_non_empty -= 1
	}

	for i in 0 ..= last_non_empty {
		trimmed := strings.trim_right_space(lines[i])
		strings.write_string(&builder, trimmed)
		if i < last_non_empty {
			strings.write_string(&builder, "\n")
		}
	}

	return strings.to_string(builder)
}
