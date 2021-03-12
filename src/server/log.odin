package server

import "core:fmt"
import "core:strings"
import "core:os"
import "core:time"
import "core:log"

Default_Console_Logger_Opts :: log.Options {
	.Level,
	.Terminal_Color,
	.Short_File_Path,
	.Line,
	.Procedure,
} | log.Full_Timestamp_Opts;

Lsp_Logger_Data :: struct {
	writer: ^Writer,
}

create_lsp_logger :: proc (writer: ^Writer, lowest := log.Level.Debug, opt := Default_Console_Logger_Opts) -> log.Logger {
	data := new(Lsp_Logger_Data);
	data.writer = writer;
	return log.Logger {lsp_logger_proc, data, lowest, opt};
}

destroy_lsp_logger :: proc (log: ^log.Logger) {
	free(log.data);
}

lsp_logger_proc :: proc (logger_data: rawptr, level: log.Level, text: string, options: log.Options, location := #caller_location) {

	data := cast(^Lsp_Logger_Data)logger_data;

	message := fmt.tprintf("%s", text);

	notification := Notification {
		jsonrpc = "2.0",
		method = "window/logMessage",
		params = NotificationLoggingParams {
			type = 1,
			message = message,
		},
	};

	send_notification(notification, data.writer);
}
