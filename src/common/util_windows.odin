package common

import "core:fmt"
import "core:log"
import "core:mem"
import "core:strings"
import "core:time"

import win32 "core:sys/windows"

FORMAT_MESSAGE_FROM_SYSTEM :: 0x00001000
FORMAT_MESSAGE_IGNORE_INSERTS :: 0x00000200


foreign import kernel32 "system:kernel32.lib"

@(default_calling_convention = "std")
foreign kernel32 {
	@(link_name = "FormatMessageA")
	format_message_a :: proc(flags: u32, source: rawptr, message_id: u32, langauge_id: u32, buffer: cstring, size: u32, va: rawptr) -> u32 ---
}

get_case_sensitive_path :: proc(
	path: string,
	allocator := context.temp_allocator,
	location := #caller_location,
) -> string {
	wide := win32.utf8_to_wstring(path, context.temp_allocator)
	file := win32.CreateFileW(
		wide,
		0,
		win32.FILE_SHARE_READ,
		nil,
		win32.OPEN_EXISTING,
		win32.FILE_FLAG_BACKUP_SEMANTICS,
		nil,
	)

	if file == win32.INVALID_HANDLE {
		when !ODIN_TEST {
			log.errorf("Failed on get_case_sensitive_path/CreateFileW(%v) at %v", path, location)
			log_last_error()
		}
		return path
	}
	defer win32.CloseHandle(file)

	required_length := win32.GetFinalPathNameByHandleW(file, nil, 0, 0)
	buffer := make([]u16, int(required_length), context.temp_allocator)
	ret := win32.GetFinalPathNameByHandleW(file, cast(win32.LPCWSTR)raw_data(buffer), required_length, 0)

	if ret == 0 {
		when !ODIN_TEST {
			log.errorf("Failed on get_case_sensitive_path/GetFinalPathNameByHandleW(%v) at %v", path, location)
			log_last_error()
		}
		return path
	}

	res, _ := win32.utf16_to_utf8(buffer[4:], allocator)

	return res
}

log_last_error :: proc() {
	err_text: [512]byte

	err := win32.GetLastError()

	error_string := cstring(&err_text[0])

	if (format_message_a(
			   FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
			   nil,
			   err,
			   (1 << 10) | 0,
			   error_string,
			   len(err_text) - 1,
			   nil,
		   ) !=
		   0) {
		log.error(error_string)
	}
}


run_executable :: proc(command: string, stdout: ^[]byte) -> (u32, bool, []byte) {
	stdout_read: win32.HANDLE
	stdout_write: win32.HANDLE

	attributes: win32.SECURITY_ATTRIBUTES
	attributes.nLength = size_of(win32.SECURITY_ATTRIBUTES)
	attributes.bInheritHandle = true
	attributes.lpSecurityDescriptor = nil

	if win32.CreatePipe(&stdout_read, &stdout_write, &attributes, 0) == false {
		return 0, false, stdout[0:]
	}

	if !win32.SetHandleInformation(stdout_read, win32.HANDLE_FLAG_INHERIT, 0) {
		return 0, false, stdout[0:]
	}

	startup_info: win32.STARTUPINFOW
	process_info: win32.PROCESS_INFORMATION

	startup_info.cb = size_of(win32.STARTUPINFOW)

	startup_info.hStdError = stdout_write
	startup_info.hStdOutput = stdout_write
	startup_info.dwFlags |= win32.STARTF_USESTDHANDLES

	if !win32.CreateProcessW(
		nil,
		win32.utf8_to_wstring(command),
		nil,
		nil,
		true,
		0,
		nil,
		nil,
		&startup_info,
		&process_info,
	) {
		return 0, false, stdout[0:]
	}

	win32.CloseHandle(stdout_write)

	index: int
	read: u32

	read_buffer: [50]byte

	success: win32.BOOL = true

	current_time := time.now()

	for success {
		success = win32.ReadFile(stdout_read, &read_buffer[0], len(read_buffer), &read, nil)

		if read > 0 && index + cast(int)read <= len(stdout) {
			mem.copy(&stdout[index], &read_buffer[0], cast(int)read)
		}

		index += cast(int)read

		elapsed_time := time.now()
		duration := time.diff(current_time, elapsed_time)

		if time.duration_seconds(duration) > 20 {
			log.error("odin check timed out")
			win32.TerminateProcess(process_info.hProcess, 1)
			return 0, false, stdout[0:]
		}

		current_time = elapsed_time
	}

	stdout[index + 1] = 0

	exit_code: u32

	win32.WaitForSingleObject(process_info.hProcess, win32.INFINITE)

	win32.GetExitCodeProcess(process_info.hProcess, &exit_code)

	win32.CloseHandle(stdout_read)

	return exit_code, true, stdout[0:index]
}
