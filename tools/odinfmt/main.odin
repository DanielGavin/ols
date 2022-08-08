package odinfmt

import "core:os"
import "core:odin/tokenizer"
import "shared:odin/printer"
import "shared:odin/format"
import "core:fmt"
import "core:strings"
import "core:path/filepath"
import "core:time"
import "core:mem"
import "core:encoding/json"
import "flag"

Args :: struct {
	write: Maybe(bool) `flag:"w" usage:"write the new format to file"`,
}

print_help :: proc(args: []string) {
	fmt.eprintln("usage: odinfmt -w {filepath}")
}

print_arg_error :: proc(args: []string, error: flag.Flag_Error) {
	switch error {
	case .None:
		print_help(args);
	case .No_Base_Struct:
		fmt.eprintln(args[0], "no base struct");
	case .Arg_Error:
		fmt.eprintln(args[0], "argument error");
	case .Arg_Unsupported_Field_Type:
		fmt.eprintln(args[0], "argument: unsupported field type");
	case .Arg_Not_Defined:
		fmt.eprintln(args[0], "argument: no defined");
	case .Arg_Non_Optional:
		fmt.eprintln(args[0], "argument: non optional");
	case .Value_Parse_Error:
		fmt.eprintln(args[0], "argument: value parse error");
	case .Tag_Error:
		fmt.eprintln(args[0], "argument: tag error");
	}
}


format_file :: proc(filepath: string, config: printer.Config, allocator := context.allocator) -> (string, bool) {
	if data, ok := os.read_entire_file(filepath, allocator); ok {
		return format.format(filepath, string(data), config, {.Optional_Semicolons}, allocator);
	} else {
		return "", false;
	}
}

files: [dynamic]string;

walk_files :: proc(info: os.File_Info, in_err: os.Errno) -> (err: os.Errno, skip_dir: bool) {
	if info.is_dir {
		return 0, false;
	}

	if filepath.ext(info.name) != ".odin" {
		return 0, false;
	}

	append(&files, strings.clone(info.fullpath));

	return 0, false;
}

main :: proc() {
	arena: mem.Arena;
	mem.init_arena(&arena, make([]byte, 50 * mem.Megabyte));

	arena_allocator := mem.arena_allocator(&arena);

	init_global_temporary_allocator(mem.Megabyte*20) //enough space for the walk

	args: Args;

	if len(os.args) < 2 {
		print_help(os.args);
		os.exit(1);
	}

	if res := flag.parse(args, os.args[1:len(os.args) - 1]); res != .None {
		print_arg_error(os.args, res);
		os.exit(1);
	}

	path := os.args[len(os.args) - 1];

	tick_time := time.tick_now();

	write_failure := false;

	watermark := 0

	if os.is_file(path) {
		config := format.find_config_file_or_default(path);
		if _, ok := args.write.(bool); ok {
			backup_path := strings.concatenate({path, "_bk"});
			defer delete(backup_path);

			if data, ok := format_file(path, config, arena_allocator); ok {
				os.rename(path, backup_path);

				if os.write_entire_file(path, transmute([]byte)data) {
					os.remove(backup_path);
				}
			} else {
				fmt.eprintf("Failed to write %v", path);
				write_failure = true;
			}
		} else {
			if data, ok := format_file(path, config, arena_allocator); ok {
				fmt.println(data);
			}
		}
	} else if os.is_dir(path) {
		config := format.find_config_file_or_default(path);
		filepath.walk(path, walk_files);

		for file in files {
			fmt.println(file);

			backup_path := strings.concatenate({file, "_bk"});
			defer delete(backup_path);

			if data, ok := format_file(file, config, arena_allocator); ok {
				if _, ok := args.write.(bool); ok {
					os.rename(file, backup_path);

					if os.write_entire_file(file, transmute([]byte)data) {
						os.remove(backup_path);
					}
				} else {
					fmt.println(data);
				}
			} else {
				fmt.eprintf("Failed to format %v", file);
				write_failure = true;
			}

			watermark = max(watermark, arena.offset)

			free_all(arena_allocator);
		}
		
		fmt.printf("Formatted %v files in %vms \n", len(files), time.duration_milliseconds(time.tick_lap_time(&tick_time)));
		fmt.printf("Peak memory used: %v \n", watermark / mem.Megabyte)
	} else {
		fmt.eprintf("%v is neither a directory nor a file \n", path);
		os.exit(1);
	}

	os.exit(1 if write_failure else 0);
}
