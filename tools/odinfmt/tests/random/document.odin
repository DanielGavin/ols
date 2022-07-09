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
	Document_Nest_If_Break,
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

Document_Nest_If_Break :: struct {
	indentation: int,
	alignment: int,
	document: ^Document,
	group_id: string,
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
	mode: Document_Group_Mode,
	options: Document_Group_Options,
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
	Fit,
}

Document_Group_Options :: struct {
	id: string,
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

nest_if_break :: proc(level: int, nested_document: ^Document, group_id := "", allocator := context.allocator) -> ^Document {
	document := new(Document, allocator)
	document^ = Document_Nest_If_Break {
		indentation = level,
		document = nested_document,
		group_id = group_id,
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

enforce_fit :: proc(fitted_document: ^Document, allocator := context.allocator) -> ^Document {
	document := new(Document, allocator)
	document^ = Document_Group { 
		document = fitted_document,
		mode = .Fit,
	}
	return document
}

enforce_break :: proc(fitted_document: ^Document, allocator := context.allocator) -> ^Document {
	document := new(Document, allocator)
	document^ = Document_Group { 
		document = fitted_document,
		mode = .Break,
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

group :: proc(grouped_document: ^Document, options := Document_Group_Options{}, allocator := context.allocator) -> ^Document {
	document := new(Document, allocator)
	document^ = Document_Group {
		document = grouped_document,
		options = options,
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

fits :: proc(width: int, list: ^[dynamic]Tuple) -> bool {
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

		if width <= 0 {
			return false
		}

		switch v in data.document {
		case Document_Nil:
		case Document_Newline:
			if v.amount > 0 {
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
				return true
			} else {
				width -= len(v.value)
			}
		case Document_If_Break:
			if data.mode == .Break {
				width -= len(v.value)
			}
		case Document_Nest_If_Break:
			if data.mode == .Break {
				append(list, Tuple {indentation = data.indentation + v.indentation, mode = data.mode, document = v.document, alignment = data.alignment + v.alignment})
			} else {
				append(list, Tuple {indentation = data.indentation, mode = data.mode, document = v.document, alignment = data.alignment})
			}
		case Document_Group:
			append(list, Tuple {indentation = data.indentation, mode = data.mode, document = v.document, alignment = data.alignment})		
		}
	}

	return width > 0
}

format_newline :: proc(indentation: int, alignment: int, consumed: ^int, builder: ^strings.Builder, p: ^Printer) {
	strings.write_string(builder, p.newline)
	for i := 0; i < indentation; i += 1 {
		strings.write_string(builder, p.indentation)
	}
	for i := 0; i < alignment; i += 1 {
		strings.write_string(builder, " ")
	}

	consumed^ = indentation * p.indentation_width + alignment
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
				consumed = data.indentation * p.indentation_width + data.alignment
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
			} else {
				strings.write_string(builder, v.value)
				consumed += len(v.value)
			}		
	    case Document_If_Break:
			if data.mode == .Break {
				strings.write_string(builder, v.value)
				consumed += len(v.value)
			}
		case Document_Nest_If_Break:
			mode := v.group_id != "" ? p.group_modes[v.group_id] : data.mode
			if mode == .Break {
				append(list, Tuple {indentation = data.indentation + v.indentation, mode = data.mode, document = v.document, alignment = data.alignment + v.alignment})
			} else {
				append(list, Tuple {indentation = data.indentation, mode = data.mode, document = v.document, alignment = data.alignment})
			}
		case Document_Group:
			l := make([dynamic]Tuple, 0, len(list))

			for element in list {
				append(&l, element)
			}	

			append(&l, Tuple {indentation = data.indentation, mode = .Flat, document = v.document, alignment = data.alignment})
		
			if data.mode == .Fit {
				append(list, Tuple {indentation = data.indentation, mode = .Fit, document = v.document, alignment = data.alignment})
			}
			else if fits(width-consumed, &l) && v.mode != .Break {			
				append(list, Tuple {indentation = data.indentation, mode = .Flat, document = v.document, alignment = data.alignment})
			} else {
				if v.mode == .Fit {
					append(list, Tuple {indentation = data.indentation, mode = .Fit, document = v.document, alignment = data.alignment})
				} else {
					append(list, Tuple {indentation = data.indentation, mode = .Break, document = v.document, alignment = data.alignment})
				}
			}

			p.group_modes[v.options.id] = list[len(list)-1].mode
		}
	}
}

