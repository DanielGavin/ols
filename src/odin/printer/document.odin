package odin_printer

import "core:fmt"
import "core:strings"

Document :: union {
	Document_Nil,
	Document_Newline,
	Document_Text,
	Document_Nest,
	Document_Break,
	Document_Group,
	Document_Cons,
	Document_If_Break_Or,
	Document_Align,
	Document_Break_Parent,
	Document_Line_Suffix,
}

Document_Nil :: struct {}

Document_Newline :: struct {
	amount: int,
}

Document_Text :: struct {
	value: string,
}

Document_Line_Suffix :: struct {
	value: string,
}

Document_Nest :: struct {
	alignment: int, //Is only used when hanging a document
	negate:    bool,
	document:  ^Document,
}

Document_Break :: struct {
	value:   string,
	newline: bool,
}

Document_If_Break_Or :: struct {
	break_document: ^Document,
	fit_document:   ^Document,
	group_id:       string,
}

Document_Group :: struct {
	document: ^Document,
	mode:     Document_Group_Mode,
	options:  Document_Group_Options,
}

Document_Cons :: struct {
	elements: []^Document,
}

Document_Align :: struct {
	document: ^Document,
}

Document_Group_Mode :: enum {
	Flat,
	Break,
	Fit,
	Fill,
}

Document_Group_Options :: struct {
	id: string,
}

Document_Break_Parent :: struct {}

empty :: proc(allocator := context.allocator) -> ^Document {
	document := new(Document, allocator)
	document^ = Document_Nil{}
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

nest :: proc(nested_document: ^Document, allocator := context.allocator) -> ^Document {
	document := new(Document, allocator)
	document^ = Document_Nest {
		document = nested_document,
	}
	return document
}

escape_nest :: proc(nested_document: ^Document, allocator := context.allocator) -> ^Document {
	document := new(Document, allocator)
	document^ = Document_Nest {
		document = nested_document,
		negate   = true,
	}
	return document
}

nest_if_break :: proc(nested_document: ^Document, group_id := "", allocator := context.allocator) -> ^Document {
	return if_break_or_document(nest(nested_document, allocator), nested_document, group_id, allocator)
}

hang :: proc(align: int, hanged_document: ^Document, allocator := context.allocator) -> ^Document {
	document := new(Document, allocator)
	document^ = Document_Nest {
		alignment = align,
		document  = hanged_document,
	}
	return document
}

enforce_fit :: proc(fitted_document: ^Document, allocator := context.allocator) -> ^Document {
	document := new(Document, allocator)
	document^ = Document_Group {
		document = fitted_document,
		mode     = .Fit,
	}
	return document
}

fill :: proc(filled_document: ^Document, allocator := context.allocator) -> ^Document {
	document := new(Document, allocator)
	document^ = Document_Group {
		document = filled_document,
		mode     = .Fill,
	}
	return document
}

enforce_break :: proc(
	fitted_document: ^Document,
	options := Document_Group_Options{},
	allocator := context.allocator,
) -> ^Document {
	document := new(Document, allocator)
	document^ = Document_Group {
		document = fitted_document,
		mode     = .Break,
		options  = options,
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
	return if_break_or_document(text(value, allocator), nil, "", allocator)
}

if_break_or :: proc {
	if_break_or_string,
	if_break_or_document,
}

if_break_or_string :: proc(
	break_value: string,
	fit_value: string,
	group_id := "",
	allocator := context.allocator,
) -> ^Document {
	return if_break_or_document(text(break_value, allocator), text(fit_value, allocator), group_id, allocator)
}

if_break_or_document :: proc(
	break_document: ^Document,
	fit_document: ^Document,
	group_id := "",
	allocator := context.allocator,
) -> ^Document {
	document := new(Document, allocator)
	document^ = Document_If_Break_Or {
		break_document = break_document,
		fit_document   = fit_document,
		group_id       = group_id,
	}
	return document
}

break_with :: proc(value: string, newline := true, allocator := context.allocator) -> ^Document {
	document := new(Document, allocator)
	document^ = Document_Break {
		value   = value,
		newline = newline,
	}
	return document
}

break_parent :: proc(allocator := context.allocator) -> ^Document {
	document := new(Document, allocator)
	document^ = Document_Break_Parent{}
	return document
}

line_suffix :: proc(value: string, allocator := context.allocator) -> ^Document {
	document := new(Document, allocator)
	document^ = Document_Line_Suffix {
		value = value,
	}
	return document
}

break_with_space :: proc(allocator := context.allocator) -> ^Document {
	return break_with(" ", true, allocator)
}

break_with_no_newline :: proc(allocator := context.allocator) -> ^Document {
	return break_with(" ", false, allocator)
}

group :: proc(
	grouped_document: ^Document,
	options := Document_Group_Options{},
	allocator := context.allocator,
) -> ^Document {
	document := new(Document, allocator)
	document^ = Document_Group {
		document = grouped_document,
		options  = options,
	}
	return document
}

cons :: proc(elems: ..^Document, allocator := context.allocator) -> ^Document {
	document := new(Document, allocator)
	elements := make([dynamic]^Document, 0, len(elems), allocator)

	for elem in elems {
		append(&elements, elem)
	}

	c := Document_Cons {
		elements = elements[:],
	}
	document^ = c
	return document
}

cons_with_opl :: proc(lhs: ^Document, rhs: ^Document, allocator := context.allocator) -> ^Document {
	if _, ok := lhs.(Document_Nil); ok {
		return rhs
	}

	if _, ok := rhs.(Document_Nil); ok {
		return lhs
	}

	return cons(elems = {lhs, break_with_space(allocator), rhs}, allocator = allocator)
}

cons_with_nopl :: proc(lhs: ^Document, rhs: ^Document, allocator := context.allocator) -> ^Document {
	if _, ok := lhs.(Document_Nil); ok {
		return rhs
	}

	if _, ok := rhs.(Document_Nil); ok {
		return lhs
	}

	return cons(elems = {lhs, break_with_no_newline(allocator), rhs}, allocator = allocator)
}

Tuple :: struct {
	indentation: int,
	alignment:   int,
	mode:        Document_Group_Mode,
	document:    ^Document,
}

list_fits: [dynamic]Tuple

fits :: proc(width: int, list: ^[dynamic]Tuple) -> bool {
	assert(list != nil)

	start_width := width
	width := width

	if len(list) == 0 {
		return true
	} else if width <= 0 {
		return false
	}

	for len(list) != 0 {
		data: Tuple = pop(list)

		if width <= 0 {
			return false
		}

		switch v in data.document {
		case Document_Nil:
		case Document_Line_Suffix:
		case Document_Break_Parent:
			return false
		case Document_Newline:
			if v.amount > 0 {
				return true
			}
		case Document_Cons:
			for i := len(v.elements) - 1; i >= 0; i -= 1 {
				append(
					list,
					Tuple {
						indentation = data.indentation,
						mode = data.mode,
						document = v.elements[i],
						alignment = data.alignment,
					},
				)
			}
		case Document_Align:
			append(
				list,
				Tuple{indentation = 0, mode = data.mode, document = v.document, alignment = start_width - width},
			)

		case Document_Nest:
			if v.alignment != 0 {
				append(
					list,
					Tuple {
						indentation = data.indentation,
						mode = data.mode,
						document = v.document,
						alignment = data.alignment + v.alignment,
					},
				)

			} else {
				append(
					list,
					Tuple {
						indentation = data.indentation + (v.negate ? -1 : 1),
						mode = data.mode,
						document = v.document,
						alignment = data.alignment + v.alignment,
					},
				)
			}
		case Document_Text:
			width -= len(v.value)
		case Document_Break:
			if data.mode == .Break && v.newline {
				return true
			} else {
				width -= len(v.value)
			}
		case Document_If_Break_Or:
			if data.mode == .Break {
				append(
					list,
					Tuple {
						indentation = data.indentation,
						mode = data.mode,
						document = v.break_document,
						alignment = data.alignment,
					},
				)
			} else if v.fit_document != nil {
				append(
					list,
					Tuple {
						indentation = data.indentation,
						mode = data.mode,
						document = v.fit_document,
						alignment = data.alignment,
					},
				)
			}
		case Document_Group:
			append(
				list,
				Tuple {
					indentation = data.indentation,
					mode = (v.mode == .Break ? .Break : data.mode),
					document = v.document,
					alignment = data.alignment,
				},
			)
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

flush_line_suffix :: proc(builder: ^strings.Builder, suffix_builder: ^strings.Builder) {
	strings.write_string(builder, strings.to_string(suffix_builder^))
	strings.builder_reset(suffix_builder)
}

format :: proc(width: int, list: ^[dynamic]Tuple, builder: ^strings.Builder, p: ^Printer) {
	assert(list != nil)
	assert(builder != nil)

	consumed := 0
	recalculate := false

	suffix_builder := strings.builder_make()

	list_fits = make([dynamic]Tuple, 0, 100, p.allocator)

	for len(list) != 0 {
		data: Tuple = pop(list)

		switch v in data.document {
		case Document_Nil:
		case Document_Line_Suffix:
			strings.write_string(&suffix_builder, v.value)
		case Document_Break_Parent:
		case Document_Newline:
			if v.amount > 0 {
				flush_line_suffix(builder, &suffix_builder)
				// ensure we strip any misplaced trailing whitespace
				for builder.buf[len(builder.buf)-1] == ' ' {
					pop(&builder.buf)
				}
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

				if data.mode == .Flat {
					recalculate = true
				}
			}
		case Document_Cons:
			for i := len(v.elements) - 1; i >= 0; i -= 1 {
				append(
					list,
					Tuple {
						indentation = data.indentation,
						mode = data.mode,
						document = v.elements[i],
						alignment = data.alignment,
					},
				)
			}
		case Document_Nest:
			if v.alignment != 0 {
				append(
					list,
					Tuple {
						indentation = data.indentation,
						mode = data.mode,
						document = v.document,
						alignment = data.alignment + v.alignment,
					},
				)

			} else {
				append(
					list,
					Tuple {
						indentation = data.indentation + (v.negate ? -1 : 1),
						mode = data.mode,
						document = v.document,
						alignment = data.alignment + v.alignment,
					},
				)
			}
		case Document_Align:
			align := consumed - data.indentation * p.indentation_width
			append(
				list,
				Tuple{indentation = data.indentation, mode = data.mode, document = v.document, alignment = align},
			)
		case Document_Text:
			strings.write_string(builder, v.value)
			consumed += len(v.value)
		case Document_Break:
			if data.mode == .Break && v.newline {
				flush_line_suffix(builder, &suffix_builder)
				format_newline(data.indentation, data.alignment, &consumed, builder, p)
			} else if data.mode == .Fill && consumed < width {
				strings.write_string(builder, v.value)
				consumed += len(v.value)
			} else if data.mode == .Fill && v.newline {
				flush_line_suffix(builder, &suffix_builder)
				format_newline(data.indentation, data.alignment, &consumed, builder, p)
			} else {
				strings.write_string(builder, v.value)
				consumed += len(v.value)
			}
		case Document_If_Break_Or:
			mode := v.group_id != "" ? p.group_modes[v.group_id] : data.mode
			if mode == .Break {
				append(
					list,
					Tuple {
						indentation = data.indentation,
						mode = data.mode,
						document = v.break_document,
						alignment = data.alignment,
					},
				)
			} else if v.fit_document != nil {
				append(
					list,
					Tuple {
						indentation = data.indentation,
						mode = data.mode,
						document = v.fit_document,
						alignment = data.alignment,
					},
				)
			}
		case Document_Group:
			if data.mode == .Flat && !recalculate {
				append(
					list,
					Tuple {
						indentation = data.indentation,
						mode = v.mode,
						document = v.document,
						alignment = data.alignment,
					},
				)
				break
			}

			clear(&list_fits)

			for element in list {
				append(&list_fits, element)
			}

			append(
				&list_fits,
				Tuple{indentation = data.indentation, mode = .Flat, document = v.document, alignment = data.alignment},
			)

			recalculate = false

			if data.mode == .Fit {
				append(
					list,
					Tuple {
						indentation = data.indentation,
						mode = .Fit,
						document = v.document,
						alignment = data.alignment,
					},
				)
			} else if fits(width - consumed, &list_fits) && v.mode != .Break && v.mode != .Fit {
				append(
					list,
					Tuple {
						indentation = data.indentation,
						mode = .Flat,
						document = v.document,
						alignment = data.alignment,
					},
				)
			} else {
				if data.mode == .Fill || v.mode == .Fill {
					append(
						list,
						Tuple {
							indentation = data.indentation,
							mode = .Fill,
							document = v.document,
							alignment = data.alignment,
						},
					)
				} else if v.mode == .Fit {
					append(
						list,
						Tuple {
							indentation = data.indentation,
							mode = .Fit,
							document = v.document,
							alignment = data.alignment,
						},
					)
				} else {
					append(
						list,
						Tuple {
							indentation = data.indentation,
							mode = .Break,
							document = v.document,
							alignment = data.alignment,
						},
					)
				}
			}

			p.group_modes[v.options.id] = list[len(list) - 1].mode
		}
	}
}
