package odin_printer

import "core:strings"
import "core:fmt"

Document :: union {
	Document_Nil,
	Document_Newline,
	Document_Text,
	Document_Nest,
	Document_Break,
	Document_Group,
	Document_Cons,
	Document_If_Break,
	Document_Align,
}

Document_Nil :: struct {

}

Document_Newline :: struct {
	amount: int,
}

Document_Text :: struct {
	value: string,
}

Document_Nest :: struct {
	indentation: int,
	alignment: int,
	document: ^Document,
}

Document_Break :: struct {
	value: string,
	newline: bool,
}

Document_If_Break :: struct {
	value: string,
}

Document_Group :: struct {
	document: ^Document,
	fill: bool,
}

Document_Cons :: struct {
	lhs: ^Document,
	rhs: ^Document,
}

Document_Align :: struct {
	document: ^Document,
}

Document_Group_Mode :: enum {
	Flat,
	Break,
	Fill,
}

empty :: proc(allocator := context.allocator) -> ^Document {
	document := new(Document, allocator)
	document^ = Document_Nil {}
	return document
}

text :: proc(value: string, allocator := context.allocator) -> ^Document {
	document := new(Document, allocator)
	document^ = Document_Text {
		value = value,
	}
	return document
}

newline :: proc(amount: int, allocator := context.allocator) -> ^Document {
	document := new(Document, allocator)
	document^ = Document_Newline {
		amount = amount,
	}
	return document
}

nest :: proc(level: int, nested_document: ^Document, allocator := context.allocator) -> ^Document {
	document := new(Document, allocator)
	document^ = Document_Nest {
		indentation = level,
		document = nested_document,
	}
	return document
}

hang :: proc(align: int, hanged_document: ^Document, allocator := context.allocator) -> ^Document {
	document := new(Document, allocator)
	document^ = Document_Nest {
		alignment = align,
		document = hanged_document,
	}
	return document
}

align :: proc(aligned_document: ^Document, allocator := context.allocator) -> ^Document {
	document := new(Document, allocator)
	document^ = Document_Align {
		document = aligned_document,
	}
	return document
}

if_break :: proc(value: string, allocator := context.allocator) -> ^Document {
	document := new(Document, allocator)
	document^ = Document_If_Break {
		value = value,
	}
	return document
}

break_with :: proc(value: string, newline := true, allocator := context.allocator) -> ^Document {
	document := new(Document, allocator)
	document^ = Document_Break {
		value = value,
		newline = newline,
	}
	return document
}

break_with_space :: proc(allocator := context.allocator) -> ^Document {
	return break_with(" ", true, allocator)
}

break_with_no_newline :: proc(allocator := context.allocator) -> ^Document {
	return break_with(" ", false, allocator)
}

group :: proc(grouped_document: ^Document, allocator := context.allocator) -> ^Document {
	document := new(Document, allocator)
	document^ = Document_Group {
		document = grouped_document,
	}
	return document
}

fill_group :: proc(grouped_document: ^Document, allocator := context.allocator) -> ^Document {
	document := new(Document, allocator)
	document^ = Document_Group {
		document = grouped_document,
		fill = true,
	}
	return document
}

cons :: proc(lhs: ^Document, rhs: ^Document, allocator := context.allocator) -> ^Document {
	document := new(Document, allocator)
	document^ = Document_Cons {
		lhs = lhs,
		rhs = rhs,
	}
	return document
}

cons_with_opl :: proc(lhs: ^Document, rhs: ^Document, allocator := context.allocator) -> ^Document {
	if _, ok := lhs.(Document_Nil); ok {
		return rhs
	}

	if _, ok := rhs.(Document_Nil); ok {
		return lhs
	}

	return cons(lhs, cons(break_with_space(allocator), rhs), allocator)
}

cons_with_nopl:: proc(lhs: ^Document, rhs: ^Document, allocator := context.allocator) -> ^Document {
	if _, ok := lhs.(Document_Nil); ok {
		return rhs
	}

	if _, ok := rhs.(Document_Nil); ok {
		return lhs
	}

	return cons(lhs, cons(break_with_no_newline(allocator), rhs), allocator)
}

Tuple :: struct {
	indentation: int,
	alignment: int,
	mode: Document_Group_Mode,
	document: ^Document,
}

fits :: proc(width: int, list: ^[dynamic]Tuple, consumed: ^int) -> bool {
	assert(list != nil)

	start_width := width
	width := width

	if len(list) == 0 {
		return true
	} else if width < 0 {
		return false
	}

	for len(list) != 0 {
		data: Tuple = pop(list)

		if width < 0 {
			consumed^ = start_width
			return false
		}

		switch v in data.document {
		case Document_Nil:
		case Document_Newline:
			if v.amount > 0 {
				consumed^ = start_width - width
				return true
			}
		case Document_Cons:
			append(list, Tuple {indentation = data.indentation, mode = data.mode, document = v.rhs, alignment = data.alignment})
			append(list, Tuple {indentation = data.indentation, mode = data.mode, document = v.lhs, alignment = data.alignment})
		case Document_Align:
			append(list, Tuple {indentation = 0, mode = data.mode, document = v.document, alignment = start_width - width})
		case Document_Nest:
			append(list, Tuple {indentation = data.indentation + v.indentation, mode = data.mode, document = v.document, alignment = data.alignment + v.alignment})
		case Document_Text:
			width -= len(v.value)
		case Document_Break:
			if data.mode == .Break && v.newline {
				consumed^ = start_width - width
				return true
			} else if data.mode == .Fill && v.newline && width > 0 {
				return true
			} else {
				width -= len(v.value)
			}
		case Document_If_Break:
			if data.mode == .Break {
				width -= len(v.value)
			}
		case Document_Group:
			append(list, Tuple {indentation = data.indentation, mode = .Flat, document = v.document, alignment = data.alignment})		
		}
	}

	consumed^ = start_width - width
	return true
}

format_newline :: proc(indentation: int, alignment: int, consumed: ^int, builder: ^strings.Builder, p: ^Printer) {
	strings.write_string(builder, p.newline)
	for i := 0; i < indentation; i += 1 {
		strings.write_string(builder, p.indentation)
	}
	for i := 0; i < alignment; i += 1 {
		strings.write_string(builder, " ")
	}

	consumed^ = indentation + alignment
}

format :: proc(width: int, list: ^[dynamic]Tuple, builder: ^strings.Builder, p: ^Printer) {
	assert(list != nil)
	assert(builder != nil)

	consumed := 0

	for len(list) != 0 {
		data: Tuple = pop(list)

		switch v in data.document {
		case Document_Nil: 
		case Document_Newline:
			if v.amount > 0 {
				for i := 0; i < v.amount; i += 1 {
					strings.write_string(builder, p.newline)
				}
				for i := 0; i < data.indentation; i += 1 {
					strings.write_string(builder, p.indentation)
				}
				for i := 0; i < data.alignment; i += 1 {
					strings.write_string(builder, " ")
				}
				consumed = data.indentation + data.alignment
			}
		case Document_Cons:
			append(list, Tuple {indentation = data.indentation, mode = data.mode, document = v.rhs, alignment = data.alignment})
			append(list, Tuple {indentation = data.indentation, mode = data.mode, document = v.lhs, alignment = data.alignment})
		case Document_Nest:
			append(list, Tuple {indentation = data.indentation + v.indentation, mode = data.mode, document = v.document, alignment = data.alignment + v.alignment})
		case Document_Align:
			append(list, Tuple {indentation = 0, mode = data.mode, document = v.document, alignment = consumed})
		case Document_Text:
			strings.write_string(builder, v.value)
			consumed += len(v.value)
		case Document_Break:
			if data.mode == .Break && v.newline {
				format_newline(data.indentation, data.alignment, &consumed, builder, p)
			} else if data.mode == .Fill && consumed + len(v.value) < width {
				strings.write_string(builder, v.value)
				consumed += len(v.value)
			} else if data.mode == .Fill && v.newline {
				format_newline(data.indentation, data.alignment, &consumed, builder, p)
			} else {
				strings.write_string(builder, v.value)
				consumed += len(v.value)
			}		
	    case Document_If_Break:
			if data.mode == .Break {
				strings.write_string(builder, v.value)
				consumed += len(v.value)
			}
		case Document_Group:
			l := make([dynamic]Tuple, 0, len(list))

			for element in list {
				append(&l, element)
			}	
			
			append(&l, Tuple {indentation = data.indentation, mode = .Flat, document = v.document, alignment = data.alignment})

			fits_consumed := 0

			if fits(width-consumed, &l, &fits_consumed) {
				append(list, Tuple {indentation = data.indentation, mode = .Flat, document = v.document, alignment = data.alignment})
			} else {
				if v.fill {
					append(list, Tuple {indentation = data.indentation, mode = .Fill, document = v.document, alignment = data.alignment})
				} else {
					append(list, Tuple {indentation = data.indentation, mode = .Break, document = v.document, alignment = data.alignment})
				}
			}
		}
	}
}

