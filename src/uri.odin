package main

import "core:mem"
import "core:strings"
import "core:strconv"
import "core:fmt"

Uri :: struct {
    full: string,
    path: string,
};

//Note(Daniel, This is an extremely incomplete uri parser and for now ignores fragment and query and only handles file schema)

parse_uri :: proc(value: string, allocator := context.allocator) -> (Uri, bool) {

    uri: Uri;

    decoded, ok := decode_percent(value, allocator);

    if !ok {
        return uri, false;
    }

    starts := "file:///";

    if !starts_with(decoded, starts) {
        return uri, false;
    }

    uri.full = decoded;
    uri.path = decoded[len(starts):];

    return uri, true;
}

@(private)
starts_with :: proc(value: string, starts_with: string) -> bool {

    if len(value) < len(starts_with) {
        return false;
    }

    for i := 0; i < len(starts_with); i += 1 {

        if value[i] != starts_with[i] {
            return false;
        }

    }

    return true;
}


@(private)
decode_percent :: proc(value: string, allocator: mem.Allocator) -> (string, bool) {

    builder := strings.make_builder(allocator);    

    for i := 0; i < len(value); i += 1 {

        if value[i] == '%' {

            if i+2 < len(value) {

                v, ok := strconv.parse_i64_of_base(value[i+1:i+3], 16);

                if !ok {
                    strings.destroy_builder(&builder);
                    return "", false;
                }

                strings.write_byte(&builder, cast(byte)v);

                i+= 2;
            }

            else {
                strings.destroy_builder(&builder);
                return "", false;
            }

        }

        else {
            strings.write_byte(&builder, value[i]);
        }

    }

    return strings.to_string(builder), true;
}

