package server

import "core:fmt";
import "core:strings";
import "core:os";
import "core:time";
import "core:log";
import "core:sync"


Default_Console_Logger_Opts :: log.Options{
    .Level,
    .Terminal_Color,
    .Short_File_Path,
    .Line,
    .Procedure,
} | log.Full_Timestamp_Opts;


Lsp_Logger_Data :: struct {
    writer:  ^Writer,
    mutex: sync.Mutex,
}

create_lsp_logger :: proc(writer: ^Writer, lowest := log.Level.Debug, opt := Default_Console_Logger_Opts) -> log.Logger {
    data := new(Lsp_Logger_Data);
    data.writer = writer;
    sync.mutex_init(&data.mutex);
    return log.Logger{lsp_logger_proc, data, lowest, opt};
}

destroy_lsp_logger :: proc(log: ^log.Logger) {
    free(log.data);
}

lsp_logger_proc :: proc(logger_data: rawptr, level: log.Level, text: string, options: log.Options, location := #caller_location) {

    data := cast(^Lsp_Logger_Data)logger_data;
    sync.mutex_lock(&data.mutex);
    defer sync.mutex_unlock(&data.mutex);

    backing: [1024]byte; //NOTE(Hoej): 1024 might be too much for a header backing, unless somebody has really long paths.
    buf := strings.builder_from_slice(backing[:]);

    when time.IS_SUPPORTED {
        if log.Full_Timestamp_Opts & options != nil {
            fmt.sbprint(&buf, "[");
            t := time.now();
            y, m, d := time.date(t);
            h, min, s := time.clock(t);
            if .Date in options { fmt.sbprintf(&buf, "%d-%02d-%02d ", y, m, d);    }
            if .Time in options { fmt.sbprintf(&buf, "%02d:%02d:%02d", h, min, s); }
            fmt.sbprint(&buf, "] ");
        }
    }

    message := fmt.tprintf("%s", text);

    notification := Notification {
        jsonrpc = "2.0",
        method = "window/logMessage",
        params = NotificationLoggingParams {
            type = 1,
            message = message,
        }
    };

    send_notification(notification, data.writer);
}

