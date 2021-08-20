package common

import "core:strings"
import "core:mem"
import "core:fmt"
import "core:log"

import "core:sys/win32"

foreign import kernel32 "system:kernel32.lib"

@(default_calling_convention = "std")
foreign kernel32 {
	@(link_name = "CreatePipe")create_pipe      :: proc (hReadPipe, hWritePipe: ^win32.Handle, lpPipeAttributes: ^win32.Security_Attributes, nSize: i32) -> i32 ---;
}

run_executable :: proc(command: string, stdout: ^[]byte) -> (u32, bool, []byte) {

	stdout_read:  win32.Handle;
	stdout_write: win32.Handle;

	command := strings.clone_to_cstring(command, context.temp_allocator);

	attributes: win32.Security_Attributes;
	attributes.length              = size_of(win32.Security_Attributes);
	attributes.inherit_handle      = true;
	attributes.security_descriptor = nil;

	if create_pipe(&stdout_read, &stdout_write, &attributes, 0) == 0 {
		return 0, false, stdout[0:];
	}

	if !win32.set_handle_information(stdout_read, win32.HANDLE_FLAG_INHERIT, 0) {
		return 0, false, stdout[0:];
	}

	startup_info: win32.Startup_Info;
	process_info: win32.Process_Information;

	startup_info.cb = size_of(win32.Startup_Info);

	startup_info.stderr = stdout_write;
	startup_info.stdout = stdout_write;
	startup_info.flags |= win32.STARTF_USESTDHANDLES;

	if !win32.create_process_a(nil, command, nil, nil, true, 0, nil, nil, &startup_info, &process_info) {
		return 0, false, stdout[0:];
	}

	win32.close_handle(stdout_write);

	index: int;
	read:  i32;

	read_buffer: [50]byte;

	success: win32.Bool = true;

	for success {

		success = win32.read_file(stdout_read, &read_buffer[0], len(read_buffer), &read, nil);

		if read > 0 && index + cast(int)read <= len(stdout) {
			mem.copy(&stdout[index], &read_buffer[0], cast(int)read);
		}

		index += cast(int)read;
	}

	stdout[index + 1] = 0;

	exit_code: u32;

	win32.wait_for_single_object(process_info.process, win32.INFINITE);

	win32.get_exit_code_process(process_info.process, &exit_code);

	win32.close_handle(stdout_read);

	return exit_code, true, stdout[0:index];
}