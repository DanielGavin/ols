package common

import "core:fmt"
import "core:os"
import "core:strings"
import "core:path/filepath"

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
			name := fmt.tprintf("%v/%v.exe", directory, name)
			if os.exists(name) {
				return name, true
			}
		} else {
			name := fmt.tprintf("%v/%v", directory, name)
			if os.exists(name) {
				if info, err := os.stat(name, context.temp_allocator); err == os.ERROR_NONE && (File_Mode_User_Executable & info.mode) != 0 {
					return name, true
				}
			}
		}
	}

	return "", false
}
