package common

import "core:strings"
import "core:mem"
import "core:fmt"
import "core:log"

import "core:sys/win32"

FORMAT_MESSAGE_FROM_SYSTEM :: 0x00001000
FORMAT_MESSAGE_IGNORE_INSERTS :: 0x00000200


foreign import kernel32 "system:kernel32.lib"

@(default_calling_convention = "std")
foreign kernel32 {
	@(link_name = "CreatePipe") create_pipe :: proc(hReadPipe, hWritePipe: ^win32.Handle, lpPipeAttributes: ^win32.Security_Attributes, nSize: i32) -> i32 ---
	@(link_name = "GetFinalPathNameByHandleA") get_final_pathname_by_handle_a :: proc(handle: win32.Handle, lpszFilePath: cstring, cchFilePath: u32, dwFlags: u32) -> u32 ---
	@(link_name = "FormatMessageA")
	format_message_a :: proc(
		flags: i32,
		source: rawptr,
		message_id: i32,
		langauge_id: i32,
		buffer: cstring,
		size: i32,
		va: rawptr,
	) -> i32 ---
}

get_case_sensitive_path :: proc(path: string, allocator := context.temp_allocator) -> string {
	file := win32.create_file_a(strings.clone_to_cstring(path, context.temp_allocator), 0, win32.FILE_SHARE_READ, nil, win32.OPEN_EXISTING, win32.FILE_FLAG_BACKUP_SEMANTICS, nil)

	if(file == win32.INVALID_HANDLE)
    {
		log_last_error()
        return "";
    }

	buffer := make([]u8, 512, context.temp_allocator)

	ret := get_final_pathname_by_handle_a(file, cast(cstring)&buffer[0], cast(u32)len(buffer), 0)

	return strings.clone_from_cstring(cast(cstring)&buffer[4], allocator)
}

log_last_error :: proc() {
	err_text: [512]byte

	err := win32.get_last_error()

	error_string := cstring(&err_text[0])

	if (format_message_a(
		   FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
		   nil,
		   err,
		   (1 << 10) | 0,
		   error_string,
		   len(err_text) - 1,
		   nil,
	   ) != 0) {
		log.error(error_string)
	}
}


run_executable :: proc(command: string, stdout: ^[]byte) -> (u32, bool, []byte) {

	stdout_read:  win32.Handle
	stdout_write: win32.Handle

	command := strings.clone_to_cstring(command, context.temp_allocator)

	attributes: win32.Security_Attributes
	attributes.length              = size_of(win32.Security_Attributes)
	attributes.inherit_handle      = true
	attributes.security_descriptor = nil

	if create_pipe(&stdout_read, &stdout_write, &attributes, 0) == 0 {
		return 0, false, stdout[0:]
	}

	if !win32.set_handle_information(stdout_read, win32.HANDLE_FLAG_INHERIT, 0) {
		return 0, false, stdout[0:]
	}

	startup_info: win32.Startup_Info
	process_info: win32.Process_Information

	startup_info.cb = size_of(win32.Startup_Info)

	startup_info.stderr = stdout_write
	startup_info.stdout = stdout_write
	startup_info.flags |= win32.STARTF_USESTDHANDLES

	if !win32.create_process_a(nil, command, nil, nil, true, 0, nil, nil, &startup_info, &process_info) {
		return 0, false, stdout[0:]
	}

	win32.close_handle(stdout_write)

	index: int
	read:  i32

	read_buffer: [50]byte

	success: win32.Bool = true

	for success {

		success = win32.read_file(stdout_read, &read_buffer[0], len(read_buffer), &read, nil)

		if read > 0 && index + cast(int)read <= len(stdout) {
			mem.copy(&stdout[index], &read_buffer[0], cast(int)read)
		}

		index += cast(int)read
	}

	stdout[index + 1] = 0

	exit_code: u32

	win32.wait_for_single_object(process_info.process, win32.INFINITE)

	win32.get_exit_code_process(process_info.process, &exit_code)

	win32.close_handle(stdout_read)

	return exit_code, true, stdout[0:index]
}