package common

import "core:bytes"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"
import "core:slice"

foreign import libc "system:c"

when ODIN_OS == .Windows {
	delimiter :: ";"
} else {
	delimiter :: ":"
}

lookup_in_path :: proc(name: string) -> (string, bool) {
	path := os.get_env("PATH", context.temp_allocator)

	for directory in strings.split_iterator(&path, delimiter) {
		when ODIN_OS == .Windows {
			possibility, _ := filepath.join(
				elems = {directory, fmt.tprintf("%v.exe", name)},
				allocator = context.temp_allocator,
			)
			if os.exists(possibility) {
				return possibility, true
			}
		} else {
			possibility, _ := filepath.join(elems = {directory, name}, allocator = context.temp_allocator)
			possibility = resolve_home_dir(possibility, context.temp_allocator)
			if os.exists(possibility) {
				if info, err := os.stat(possibility, context.temp_allocator);
				   err == os.ERROR_NONE && .Execute_User in info.mode {
					return possibility, true
				}
			}
		}
	}

	return "", false
}

resolve_home_dir :: proc(
	path: string,
	allocator := context.allocator,
) -> (
	resolved: string,
	allocated: bool,
) #optional_ok {
	when ODIN_OS == .Windows {
		return path, false
	} else {
		if strings.has_prefix(path, "~") {
			home := os.get_env("HOME", context.temp_allocator)
			if home == "" {
				log.error("could not find $HOME in the environment to be able to resolve ~ in collection paths")
				return path, false
			}

			path, _ := filepath.join({home, path[1:]}, allocator)
			return path, true
		} else if strings.has_prefix(path, "$HOME") {
			home := os.get_env("HOME", context.temp_allocator)
			if home == "" {
				log.error("could not find $HOME in the environment to be able to resolve $HOME in collection paths")
				return path, false
			}

			path, _ := filepath.join({home, path[5:]}, allocator)
			return path, true
		}
		return path, false
	}
}

FILE :: struct {}
when ODIN_OS == .Darwin || ODIN_OS == .FreeBSD || ODIN_OS == .Linux || ODIN_OS == .NetBSD {

	run_executable :: proc(command: string, stdout: ^[]byte) -> (u32, bool, []byte) {
		fp := popen(strings.clone_to_cstring(command, context.temp_allocator), "r")
		if fp == nil {
			return 0, false, stdout[0:]
		}
		defer pclose(fp)

		read_buffer: [50]byte
		index: int

		current_time := time.now()

		for fgets(&read_buffer[0], size_of(read_buffer), fp) != nil {
			read := bytes.index_byte(read_buffer[:], 0)
			defer index += cast(int)read

			if read > 0 && index + cast(int)read <= len(stdout) {
				mem.copy(&stdout[index], &read_buffer[0], cast(int)read)
			}

			elapsed_time := time.now()
			duration := time.diff(current_time, elapsed_time)

			if time.duration_seconds(duration) > 20 {
				log.error("odin check timed out")
				return 0, false, stdout[0:]
			}

			current_time = elapsed_time
		}


		return 0, true, stdout[0:index]
	}

	search_for_odin_files :: proc(base_path: string, exclude_file: string, dir_blacklist: []string, odin_files_out: ^[dynamic]string) {
		w := os.walker_create(base_path)
		defer os.walker_destroy(&w)
		for info in os.walker_walk(&w) {
			if info.type == .Directory {
				dir, _ := filepath.replace_separators(info.fullpath, '/', context.temp_allocator)
				dir_name := filepath.base(dir)
				if slice.contains(dir_blacklist, dir_name) {
					os.walker_skip_dir(&w)
				}
				continue
			}

			if info.fullpath == "" {
				continue
			}

			if strings.has_suffix(info.name, ".odin") {
				slash_path, _ := filepath.replace_separators(info.fullpath, '/', context.temp_allocator)
				if !strings.equal_fold(slash_path, exclude_file) {
					append(odin_files_out, strings.clone(info.fullpath, context.temp_allocator))
				}
			}
		}
	}

	foreign libc
	{
		popen :: proc(command: cstring, type: cstring) -> ^FILE ---
		pclose :: proc(stream: ^FILE) -> i32 ---
		fgets :: proc "cdecl" (s: [^]byte, n: i32, stream: ^FILE) -> [^]u8 ---
	}
}

get_executable_path :: proc(allocator := context.temp_allocator) -> string {
	exe_dir, err := os.get_executable_directory(context.temp_allocator)

	if err != nil {
		log.error("Failed to resolve executable path: ", err)
		return ""
	}

	return exe_dir
}
