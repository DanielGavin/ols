package odinfmt_testing

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"
import "core:text/scanner"

import "src:odin/format"
import "src:odin/printer"

format_file :: proc(filepath: string, allocator := context.allocator) -> (string, bool) {
	if data, ok := os.read_entire_file(filepath, allocator); ok {
		config := read_config_file_or_default(filepath)
		return format.format(filepath, string(data), config, {.Optional_Semicolons}, allocator)
	} else {
		return "", false
	}
}

read_config_file_or_default :: proc(fullpath: string, allocator := context.allocator) -> printer.Config {
	default_style := format.default_style
	default_style.character_width = 80
	default_style.newline_style = .LF //We want to make sure it works on linux and windows.

	dirpath := filepath.dir(fullpath, allocator)
	configpath := fmt.tprintf("%v/odinfmt.json", dirpath)

	if (os.exists(configpath)) {
		json_config := default_style
		if data, ok := os.read_entire_file(configpath, allocator); ok {
			if json.unmarshal(data, &json_config) == nil {
				return json_config
			}
		}
	}

	return default_style

}

snapshot_directory :: proc(directory: string) -> bool {
	matches, err := filepath.glob(fmt.tprintf("%v/*", directory))

	if err != .None {
		fmt.eprintf("Error in globbing directory: %v", directory)
	}

	for match in matches {
		if strings.contains(match, ".odin") {
			snapshot_file(match) or_return
		}
	}

	for match in matches {
		if !strings.contains(match, ".snapshots") {
			if os.is_dir(match) {
				snapshot_directory(match)
			}
		}
	}

	return true
}

snapshot_file :: proc(path: string) -> bool {
	fmt.printf("Testing snapshot %v", path)


	snapshot_path := filepath.join(
		elems = {filepath.dir(path, context.temp_allocator), "/.snapshots", filepath.base(path)},
		allocator = context.temp_allocator,
	)

	formatted, ok := format_file(path, context.temp_allocator)

	if !ok {
		fmt.eprintf("Format failed on file %v", path)
		return false
	}

	if os.exists(snapshot_path) {
		if snapshot_data, ok := os.read_entire_file(snapshot_path, context.temp_allocator); ok {
			snapshot_scanner := scanner.Scanner{}
			scanner.init(&snapshot_scanner, string(snapshot_data))
			formatted_scanner := scanner.Scanner{}
			scanner.init(&formatted_scanner, string(formatted))
			for {
				s_ch := scanner.next(&snapshot_scanner)
				f_ch := scanner.next(&formatted_scanner)
				if s_ch == scanner.EOF && f_ch == scanner.EOF {
					break
				}

				if s_ch == '\r' {
					if scanner.peek(&snapshot_scanner) == '\n' {
						s_ch = scanner.next(&snapshot_scanner)
					}
				}
				if f_ch == '\r' {
					if scanner.peek(&formatted_scanner) == '\n' {
						f_ch = scanner.next(&formatted_scanner)
					}
				}

				if s_ch != f_ch {
					fmt.eprintf("\nFormatted file was different from snapshot file: %v\n", snapshot_path)
					os.write_entire_file(fmt.tprintf("%v_failed", snapshot_path), transmute([]u8)formatted)
					return false
				}
			}
			os.remove(fmt.tprintf("%v_failed", snapshot_path))
		} else {
			fmt.eprintf("Failed to read snapshot file %v", snapshot_path)
			return false
		}
	} else {
		os.make_directory(filepath.dir(snapshot_path, context.temp_allocator))
		ok = os.write_entire_file(snapshot_path, transmute([]byte)formatted)
		if !ok {
			fmt.eprintf("Failed to write snapshot file %v", snapshot_path)
			return false
		}
	}

	fmt.print(" - SUCCESS \n")

	return true
}
