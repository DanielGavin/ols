package odinfmt

import "core:encoding/json"
import "core:flags"
import "core:fmt"
import "core:io"
import "core:mem"
import "core:odin/tokenizer"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"
import "src:odin/format"
import "src:odin/printer"

Args :: struct {
	write: bool `args:"name=w" usage:"write the new format to file"`,
	stdin: bool `usage:"formats code from standard input"`,
	path:  string `args:"pos=0" usage:"set the file or directory to format"`,
    config: string `usage:"path to a config file"`
}

format_file :: proc(filepath: string, config: printer.Config, allocator := context.allocator) -> (string, bool) {
	if data, ok := os.read_entire_file(filepath, allocator); ok {
		return format.format(filepath, string(data), config, {.Optional_Semicolons}, allocator)
	} else {
		return "", false
	}
}

files: [dynamic]string

walk_files :: proc(info: os.File_Info, in_err: os.Errno, user_data: rawptr) -> (err: os.Error, skip_dir: bool) {
	if info.is_dir {
		return nil, false
	}

	if filepath.ext(info.name) != ".odin" {
		return nil, false
	}

	append(&files, strings.clone(info.fullpath))

	return nil, false
}

main :: proc() {
	arena: mem.Arena
	mem.arena_init(&arena, make([]byte, 50 * mem.Megabyte))

	arena_allocator := mem.arena_allocator(&arena)

	init_global_temporary_allocator(mem.Megabyte * 20) //enough space for the walk

	args: Args
	flags.parse_or_exit(&args, os.args)

	// only allow the path to not be specified when formatting from stdin
	if args.path == "" {
		if args.stdin {
			// use current directory as the starting path to look for `odinfmt.json`
			args.path = "."
		} else {
			fmt.fprint(os.stderr, "Missing path to format\n")
			flags.write_usage(os.stream_from_handle(os.stderr), Args, os.args[0])
			os.exit(1)
		}
	}

	tick_time := time.tick_now()

	write_failure := false

	watermark := 0

    config: printer.Config
    if args.config == "" {
	    config = format.find_config_file_or_default(args.path)
    } else {
        config = format.read_config_file_from_path_or_default(args.config)
    }

	if args.stdin {
		data := make([dynamic]byte, arena_allocator)

		for {
			tmp: [mem.Kilobyte]byte

			r, err := os.read(os.stdin, tmp[:])
			if err != os.ERROR_NONE || r <= 0 do break

			append(&data, ..tmp[:r])
		}

		source, ok := format.format("<stdin>", string(data[:]), config, {.Optional_Semicolons}, arena_allocator)

		if ok {
			fmt.println(source)
		}

		write_failure = !ok
	} else if os.is_file(args.path) {
		if args.write {
			backup_path := strings.concatenate({args.path, "_bk"})
			defer delete(backup_path)

			if data, ok := format_file(args.path, config, arena_allocator); ok {
				os.rename(args.path, backup_path)

				if os.write_entire_file(args.path, transmute([]byte)data) {
					os.remove(backup_path)
				}
			} else {
				fmt.eprintf("Failed to write %v", args.path)
				write_failure = true
			}
		} else {
			if data, ok := format_file(args.path, config, arena_allocator); ok {
				fmt.println(data)
			}
		}
	} else if os.is_dir(args.path) {
		filepath.walk(args.path, walk_files, nil)

		for file in files {
			fmt.println(file)

			backup_path := strings.concatenate({file, "_bk"})
			defer delete(backup_path)

			if data, ok := format_file(file, config, arena_allocator); ok {
				if args.write {
					os.rename(file, backup_path)

					if os.write_entire_file(file, transmute([]byte)data) {
						os.remove(backup_path)
					}
				} else {
					fmt.println(data)
				}
			} else {
				fmt.eprintf("Failed to format %v", file)
				write_failure = true
			}

			watermark = max(watermark, arena.offset)

			free_all(arena_allocator)
		}

		fmt.printf(
			"Formatted %v files in %vms \n",
			len(files),
			time.duration_milliseconds(time.tick_lap_time(&tick_time)),
		)
		fmt.printf("Peak memory used: %v \n", watermark / mem.Megabyte)
	} else {
		fmt.eprintf("%v is neither a directory nor a file \n", args.path)
		os.exit(1)
	}

	os.exit(1 if write_failure else 0)
}
