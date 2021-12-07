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
	indentation_count:    int,
	disabled_lines:       map[int]string,
	last_disabled_line:   int,
	src:                  string,
}

Config :: struct {
	max_characters:       int,
	spaces:               int,  //Spaces per indentation
	newline_limit:        int,  //The limit of newlines between statements and declarations.
	tabs:                 bool, //Enable or disable tabs
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

Newline_Style :: enum {
	CRLF,
	LF,
}


when ODIN_OS == "windows" {
	default_style := Config {
		spaces               = 4,
		newline_limit        = 2,
		convert_do           = false,
		tabs                 = true,
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
				for line := disable_position.line; line <= comment.pos.line; line += 1 {
					p.disabled_lines[line] = p.src[begin:end]
				}
				
				found_disable = false
			}
		}
	}
}

print :: proc(p: ^Printer, file: ^ast.File) -> string {
	p.comments = file.comments
	p.string_builder = strings.make_builder(p.allocator)
	p.src = file.src
	context.allocator = p.allocator
	
	if p.config.tabs {
		p.indentation = "\t"
		p.indentation_count = 1
	} else {
		p.indentation_count = p.config.spaces
		p.indentation = " "
	}

	if p.config.newline_style == .CRLF {
		p.newline = "\r\n"
	} else {
		p.newline = "\n"
	}

	set_source_position(p, file.pkg_token.pos)

	p.last_source_position.line = 1

	build_disabled_lines_info(p)

	p.document = cons_with_nopl(text("package"), text(file.pkg_name))

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

