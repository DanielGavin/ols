package main


import "core:fmt"
import "core:encoding/json"

send_notification :: proc(notification: Notification, writer: ^Writer) -> bool {

    data, error := json.marshal(notification, context.temp_allocator);

    header := fmt.tprintf("Content-Length: {}\r\n\r\n", len(data));

    if error != json.Marshal_Error.None  {
        return false;
    }

    if(!write_sized(writer, transmute([]u8)header)) {
        return false;
    }

    if(!write_sized(writer, data)) {
        return false;
    }

    return true;
}

send_response :: proc(response: ResponseMessage, writer: ^Writer) -> bool {

    data, error := json.marshal(response, context.temp_allocator);

    header := fmt.tprintf("Content-Length: {}\r\n\r\n", len(data));

    if error != json.Marshal_Error.None  {
        return false;
    }

    if(!write_sized(writer, transmute([]u8)header)) {
        return false;
    }

    if(!write_sized(writer, data)) {
        return false;
    }

    return true;
}

send_error :: proc(response: ResponseMessageError, writer: ^Writer) -> bool {

    data, error := json.marshal(response, context.temp_allocator);

    header := fmt.tprintf("Content-Length: {}\r\n\r\n", len(data));

    if error != json.Marshal_Error.None  {
        return false;
    }

    if(!write_sized(writer, transmute([]u8)header)) {
        return false;
    }

    if(!write_sized(writer, data)) {
        return false;
    }

    return true;
}
