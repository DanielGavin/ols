package odin_printer

import "core:odin/ast"
import "core:odin/tokenizer"
import "core:strings"
import "core:fmt"
import "core:mem"

Printer :: struct {
	string_builder:       strings.Builder,
	config:               Config,
	comments:             [dynamic]^ast.Comment_Group,
	comments_option:      map[int]Line_Suffix_Option,
	latest_comment_index: int,
	allocator:            mem.Allocator,
	file:                 ^ast.File,
	source_position:      tokenizer.Pos,
	last_source_position: tokenizer.Pos,
	skip_semicolon:       bool,
	current_line_index:   int,
	last_line_index:      int,
	document:             ^Document,
	indentation:          string,
	newline:              string,
	indentation_width:    int,
	disabled_lines:       map[int]Disabled_Info,
	disabled_until_line:  int,
	group_modes:          map[string]Document_Group_Mode,
	src:                  string,
}

Disabled_Info :: struct {
	text: string,
	end_line: int,
}

Config :: struct {
	max_characters:       int,
	spaces:               int,  //Spaces per indentation
	newline_limit:        int,  //The limit of newlines between statements and declarations.
	tabs:                 bool, //Enable or disable tabs
	tabs_width:           int,
	convert_do:           bool, //Convert all do statements to brace blocks
	brace_style:          Brace_Style,
	indent_cases:         bool,
	newline_style:        Newline_Style,
}

Brace_Style :: enum {
	_1TBS,
	Allman,
	Stroustrup,
	K_And_R,
}

Block_Type :: enum {
	None,
	If_Stmt,
	Proc,
	Generic,
	Comp_Lit,
	Switch_Stmt,
}

Expr_Called_Type :: enum {
	Generic,
	Value_Decl,
	Assignment_Stmt,
	Call_Expr,
	Binary_Expr,
}

Newline_Style :: enum {
	CRLF,
	LF,
}

Line_Suffix_Option :: enum {
	Default,
	Indent,
}


when ODIN_OS ==  .Windows {
	default_style := Config {
		spaces               = 4,
		newline_limit        = 2,
		convert_do           = false,
		tabs                 = true,
		tabs_width           = 4,
		brace_style          = ._1TBS,
		indent_cases         = false,
		newline_style        = .CRLF,
		max_characters       = 100,
	}
} else {
	default_style := Config {
		spaces               = 4,
		newline_limit        = 2,
		convert_do           = false,
		tabs                 = true,
		tabs_width           = 4,
		brace_style          = ._1TBS,
		indent_cases         = false,
		newline_style        = .LF,
		max_characters       = 100,
	}
}

make_printer :: proc(config: Config, allocator := context.allocator) -> Printer {
	return {
		config = config,
		allocator = allocator,
	}
}


@private
build_disabled_lines_info :: proc(p: ^Printer) {
	found_disable := false
	disable_position: tokenizer.Pos

	for group in p.comments {
		for comment in group.list {
			if strings.contains(comment.text[:], "//odinfmt: disable") {
				found_disable = true
				disable_position = comment.pos
			} else if strings.contains(comment.text[:], "//odinfmt: enable") && found_disable {
				begin := disable_position.offset - (comment.pos.column - 1)
				end := comment.pos.offset+len(comment.text)

				disabled_info := Disabled_Info {
					end_line = comment.pos.line,
					text = p.src[begin:end],
				}

				for line := disable_position.line; line <= comment.pos.line; line += 1 {
					p.disabled_lines[line] = disabled_info
				}
				
				found_disable = false
			}
		}
	}
}

@private
set_comment_option :: proc(p: ^Printer, line: int, option: Line_Suffix_Option) {
	p.comments_option[line] = option
}

print :: proc {
	print_file,
	print_expr,
}

print_expr :: proc(p: ^Printer, expr: ^ast.Expr) -> string {
	p.document = empty();
	p.document = cons(p.document, visit_expr(p, expr))
	p.string_builder = strings.builder_make(p.allocator)
	context.allocator = p.allocator

	list := make([dynamic]Tuple, p.allocator)

	append(&list, Tuple {
		document = p.document,
		indentation = 0,
	})

	format(p.config.max_characters, &list, &p.string_builder, p)

	return strings.to_string(p.string_builder)
}

print_file :: proc(p: ^Printer, file: ^ast.File) -> string {
	p.comments = file.comments
	p.string_builder = strings.builder_make(0, len(file.src)*2, p.allocator)
	p.src = file.src
	context.allocator = p.allocator
	
	if p.config.tabs {
		p.indentation = "\t"
		p.indentation_width = p.config.tabs_width
	} else {
		p.indentation = strings.repeat(" ", p.config.spaces)
		p.indentation_width = p.config.spaces
	}

	if p.config.newline_style == .CRLF {
		p.newline = "\r\n"
	} else {
		p.newline = "\n"
	}

	build_disabled_lines_info(p)
	
	p.source_position.line = 1
	p.source_position.column = 1

	p.document = move_line(p, file.pkg_token.pos)
	p.document = cons(p.document, cons_with_nopl(text(file.pkg_token.text), text(file.pkg_name)))

	for decl in file.decls {
		p.document = cons(p.document, visit_decl(p, cast(^ast.Decl)decl))
	}

	if len(p.comments) > 0 {
		infinite := p.comments[len(p.comments) - 1].end
		infinite.offset = 9999999
		document, _ := visit_comments(p, infinite)
		p.document = cons(p.document, document)
	}

	p.document = cons(p.document, newline(1))

	list := make([dynamic]Tuple, p.allocator)

	append(&list, Tuple {
		document = p.document,
		indentation = 0,
	})

	format(p.config.max_characters, &list, &p.string_builder, p)

	return strings.to_string(p.string_builder)
}

