package common

import "core:fmt"
import "core:os"
import "core:strings"
import "core:path/filepath"
foreign import libc "system:c"
import "core:mem"
import "core:bytes"

when ODIN_OS == .Windows {
	delimiter :: ";"
} else {
	delimiter :: ":"
}

//TODO(daniel): This is temporary and should not be needed after os2
File_Mode_User_Executable :: os.File_Mode(1 << 8)

lookup_in_path :: proc(name: string) -> (string, bool) {
	path := os.get_env("PATH", context.temp_allocator)

	for directory in strings.split_iterator(&path, delimiter) {
		when ODIN_OS == .Windows {
			name := filepath.join(elems = {directory, fmt.tprintf("%v.exe", name)}, allocator = context.temp_allocator)
			if os.exists(name) {
				return name, true
			}
		} else {
			name := filepath.join(elems = {directory, name}, allocator = context.temp_allocator)
			if os.exists(name) {
				if info, err := os.stat(name, context.temp_allocator); err == os.ERROR_NONE && (File_Mode_User_Executable & info.mode) != 0 {
					return name, true
				}
			}
		}
	}

	return "", false
}

when ODIN_OS == .Darwin || ODIN_OS == .Linux {
	FILE :: struct {}

	run_executable :: proc(command: string, stdout: ^[]byte) -> (u32, bool, []byte) {
		fp := popen(strings.clone_to_cstring(command, context.temp_allocator), "r")
		if fp == nil {
			return 0, false, stdout[0:]
		}
		defer pclose(fp)
	
		read_buffer: [50]byte
		index: int
	
		for fgets(&read_buffer[0], size_of(read_buffer), fp) != nil {
			read := bytes.index_byte(read_buffer[:], 0)
			defer index += cast(int)read
	
			if read > 0 && index + cast(int)read <= len(stdout) {
				mem.copy(&stdout[index], &read_buffer[0], cast(int)read)
			}
		}
	
		
	
		return 0, true, stdout[0:index]
	}
	
	foreign libc 
	{
		popen :: proc(command: cstring, type: cstring) -> ^FILE ---
		pclose :: proc(stream: ^FILE) -> i32 ---
		fgets :: proc "cdecl" (s: [^]byte, n: i32, stream: ^FILE) -> [^]u8 ---
		fgetc :: proc "cdecl" (stream: ^FILE) -> i32 ---
	}
}
