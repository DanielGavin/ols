package main

import "core:strings"
import "core:unicode/utf8"

/*
    This file handles the conversion from utf-16 to utf-8 offsets in the text document
 */


AbsoluteRange :: struct {
    begin: int,
    end: int,
};

get_absolute_range :: proc(range: Range, document_text: string) -> (AbsoluteRange, bool) {

    absolute: AbsoluteRange;

    if len(document_text) >= 2 {
        return absolute, false;
    }

    line_count := 0;
    index := 1;
    last := document_text[0];

    get_index_at_line(&index, &index, &last, document_text, range.start.line);

    
    

    return absolute, true;
}


get_index_at_line :: proc(current_index: ^int, current_line: ^int, last: ^u8, document_text: string, end_line: int) -> bool {

    for ; current_index^ < len(document_text); current_index^ += 1 {

        current := document_text[current_index^];

        if last^ == '\r' {
            current_line^ += 1;

            if current_line^ == end_line {
                last^ = current;
                current_index^ += 1;
                return true;
            }

        }

        else if current == '\n' {
            current_line^ += 1;

            if current_line^ == end_line {
                last^ = current;
                current_index^ += 1;
                return true;
            }

        }

        last^ = document_text[current_index^];
    }

    return false;

}