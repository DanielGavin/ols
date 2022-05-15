package common

import "core:strings"
import "core:mem"
import "core:fmt"
import "core:log"

import win32 "core:sys/windows"

foreign import kernel32 "system:kernel32.lib"


run_executable :: proc(command: string, stdout: ^[]byte) -> (u32, bool, []byte) {
	stdout_read:  win32.HANDLE
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

	startup_info: win32.STARTUPINFO
	process_info: win32.PROCESS_INFORMATION

	startup_info.cb = size_of(win32.STARTUPINFO)

	startup_info.hStdError = stdout_write
	startup_info.hStdOutput = stdout_write
	startup_info.dwFlags |= win32.STARTF_USESTDHANDLES

	if !win32.CreateProcessW(nil, &win32.utf8_to_utf16(command)[0], nil, nil, true, 0, nil, nil, &startup_info, &process_info) {
		return 0, false, stdout[0:]
	}

	win32.CloseHandle(stdout_write)

	index: int
	read:  u32

	read_buffer: [50]byte

	success: win32.BOOL = true

	for success {
		success = win32.ReadFile(stdout_read, &read_buffer[0], len(read_buffer), &read, nil)

		if read > 0 && index + cast(int)read <= len(stdout) {
			mem.copy(&stdout[index], &read_buffer[0], cast(int)read)
		}

		index += cast(int)read
	}

	stdout[index + 1] = 0

	exit_code: u32

	win32.WaitForSingleObject(process_info.hProcess, win32.INFINITE)

	win32.GetExitCodeProcess(process_info.hProcess, &exit_code)

	win32.CloseHandle(stdout_read)

	return exit_code, true, stdout[0:index]
}