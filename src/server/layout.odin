package server

import "core:fmt"
import "core:odin/ast"
import "core:strconv"
import "core:strings"

import "src:common"

Type_Layout :: struct {
	size:  i64,
	align: i64,
}

Field_Layout :: struct {
	name:   string,
	offset: i64,
	layout: Type_Layout,
}

LAYOUT_MAX_DEPTH :: 32
LAYOUT_MAX_SIMD_ALIGN :: 16

@(private = "file")
align_forward :: proc(x, align: i64) -> i64 {
	if align <= 1 {
		return x
	}
	return (x + align - 1) / align * align
}

@(private = "file")
target_pointer_size :: proc() -> i64 {
	switch common.config.profile.arch {
	case "i386", "arm32", "wasm32", "wasm64p32", "riscv32":
		return 4
	}
	return 8
}

@(private = "file")
target_int_size :: proc() -> i64 {
	switch common.config.profile.arch {
	case "i386", "arm32", "wasm32", "riscv32":
		return 4
	}
	return 8
}

@(private = "file")
target_max_align :: proc() -> i64 {
	return 2 * target_int_size()
}

@(private = "file")
allocator_layout :: proc() -> Type_Layout {
	ptr := target_pointer_size()
	return {2 * ptr, ptr}
}

@(private = "file")
basic_type_layout :: proc(name: string) -> (Type_Layout, bool) {
	ptr := target_pointer_size()
	word := target_int_size()
	switch name {
	case "bool", "b8", "i8", "u8", "byte":
		return {1, 1}, true
	case "b16", "i16", "u16", "i16le", "i16be", "u16le", "u16be", "f16", "f16le", "f16be":
		return {2, 2}, true
	case "b32", "i32", "u32", "i32le", "i32be", "u32le", "u32be", "f32", "f32le", "f32be", "rune":
		return {4, 4}, true
	case "b64", "i64", "u64", "i64le", "i64be", "u64le", "u64be", "f64", "f64le", "f64be", "typeid":
		return {8, 8}, true
	case "i128", "u128", "i128le", "i128be", "u128le", "u128be":
		return {16, min(16, target_max_align())}, true
	case "int", "uint":
		return {word, word}, true
	case "uintptr", "rawptr", "cstring", "cstring16":
		return {ptr, ptr}, true
	case "string", "string16":
		return {align_forward(ptr + word, max(ptr, word)), max(ptr, word)}, true
	case "any":
		return {align_forward(ptr, 8) + 8, max(ptr, 8)}, true
	case "complex32":
		return {4, 2}, true
	case "complex64":
		return {8, 4}, true
	case "complex128":
		return {16, 8}, true
	case "quaternion64":
		return {8, 2}, true
	case "quaternion128":
		return {16, 4}, true
	case "quaternion256":
		return {32, 8}, true
	}
	return {}, false
}

eval_const_int :: proc(
	ast_context: ^AstContext,
	expr: ^ast.Expr,
	depth := 0,
	locals: ^map[string]i64 = nil,
) -> (
	value: i64,
	ok: bool,
) {
	if expr == nil || depth > LAYOUT_MAX_DEPTH {
		return 0, false
	}

	#partial switch v in expr.derived {
	case ^ast.Basic_Lit:
		#partial switch v.tok.kind {
		case .Integer:
			text, _ := strings.remove_all(v.tok.text, "_", context.temp_allocator)
			return strconv.parse_i64(text)
		case .Rune:
			text := v.tok.text
			if len(text) < 3 {
				return 0, false
			}
			r, _, _, success := strconv.unquote_char(text[1:len(text) - 1], '\'')
			return i64(r), success
		}
	case ^ast.Paren_Expr:
		return eval_const_int(ast_context, v.expr, depth + 1, locals)
	case ^ast.Unary_Expr:
		x := eval_const_int(ast_context, v.expr, depth + 1, locals) or_return
		#partial switch v.op.kind {
		case .Sub:
			return -x, true
		case .Add:
			return x, true
		case .Xor:
			return ~x, true
		}
	case ^ast.Binary_Expr:
		x := eval_const_int(ast_context, v.left, depth + 1, locals) or_return
		y := eval_const_int(ast_context, v.right, depth + 1, locals) or_return
		#partial switch v.op.kind {
		case .Add:
			return x + y, true
		case .Sub:
			return x - y, true
		case .Mul:
			return x * y, true
		case .Quo:
			return y == 0 ? 0 : x / y, y != 0
		case .Mod:
			return y == 0 ? 0 : x % y, y != 0
		case .Shl:
			return x << u64(y), y >= 0
		case .Shr:
			return x >> u64(y), y >= 0
		case .And:
			return x & y, true
		case .Or:
			return x | y, true
		case .Xor:
			return x ~ y, true
		case .And_Not:
			return x &~ y, true
		}
	case ^ast.Ident:
		if locals != nil {
			if value, found := locals[v.name]; found {
				return value, true
			}
		}
		symbol := resolve_type_identifier(ast_context, v^) or_return
		return eval_const_symbol(ast_context, symbol, expr, depth)
	case ^ast.Selector_Expr:
		symbol := resolve_type_expression(ast_context, expr) or_return
		return eval_const_symbol(ast_context, symbol, expr, depth)
	case ^ast.Call_Expr:
		if ident, is_ident := v.expr.derived.(^ast.Ident); is_ident && len(v.args) == 1 {
			switch ident.name {
			case "size_of":
				layout := type_expr_layout(ast_context, v.args[0], depth + 1) or_return
				return layout.size, true
			case "align_of":
				layout := type_expr_layout(ast_context, v.args[0], depth + 1) or_return
				return layout.align, true
			}
		}
	}
	return 0, false
}

@(private = "file")
eval_const_symbol :: proc(
	ast_context: ^AstContext,
	symbol: Symbol,
	from: ^ast.Expr,
	depth: int,
) -> (
	value: i64,
	ok: bool,
) {
	if symbol.value_expr != nil && symbol.value_expr != from {
		return eval_const_int(ast_context, symbol.value_expr, depth + 1)
	}
	if v, is_untyped := symbol.value.(SymbolUntypedValue); is_untyped && v.type == .Integer {
		text, _ := strings.remove_all(v.tok.text, "_", context.temp_allocator)
		return strconv.parse_i64(text)
	}
	return 0, false
}

@(private = "file")
enum_value_range :: proc(ast_context: ^AstContext, v: SymbolEnumValue, depth: int) -> (lo, hi: i64, ok: bool) {
	if len(v.names) == 0 {
		return 0, 0, false
	}
	values := make(map[string]i64, context.temp_allocator)
	current: i64 = -1
	for name, i in v.names {
		if i < len(v.values) && v.values[i] != nil {
			current = eval_const_int(ast_context, v.values[i], depth + 1, &values) or_return
		} else {
			current += 1
		}
		values[name] = current
		if i == 0 {
			lo, hi = current, current
		} else {
			lo, hi = min(lo, current), max(hi, current)
		}
	}
	return lo, hi, true
}

@(private = "file")
array_count :: proc(ast_context: ^AstContext, len_expr: ^ast.Expr, depth: int) -> (count: i64, ok: bool) {
	if n, is_const := eval_const_int(ast_context, len_expr, depth + 1); is_const {
		return n, true
	}
	symbol := resolve_type_expression(ast_context, len_expr) or_return
	if e, is_enum := symbol.value.(SymbolEnumValue); is_enum {
		lo, hi := enum_value_range(ast_context, e, depth + 1) or_return
		return hi - lo + 1, true
	}
	return 0, false
}

@(private = "file")
bit_set_layout :: proc(ast_context: ^AstContext, v: SymbolBitSetValue, depth: int) -> (result: Type_Layout, ok: bool) {
	if v.underlying != nil {
		return type_expr_layout(ast_context, v.underlying, depth + 1)
	}

	lo, hi: i64
	if range, is_range := v.expr.derived.(^ast.Binary_Expr);
	   is_range && (range.op.kind == .Range_Half || range.op.kind == .Range_Full || range.op.kind == .Ellipsis) {
		lo = eval_const_int(ast_context, range.left, depth + 1) or_return
		hi = eval_const_int(ast_context, range.right, depth + 1) or_return
		if range.op.kind == .Range_Half {
			hi -= 1
		}
	} else {
		symbol := resolve_type_expression(ast_context, v.expr) or_return
		e := symbol.value.(SymbolEnumValue) or_return
		lo, hi = enum_value_range(ast_context, e, depth + 1) or_return
	}

	bits := hi - lo + 1
	switch {
	case bits <= 8:
		return {1, 1}, true
	case bits <= 16:
		return {2, 2}, true
	case bits <= 32:
		return {4, 4}, true
	case bits <= 64:
		return {8, 8}, true
	case bits <= 128:
		return {16, 16}, true
	}
	return {}, false
}

@(private = "file")
is_pointer_like_symbol :: proc(symbol: Symbol) -> bool {
	if symbol.pointers > 0 {
		return true
	}
	#partial switch v in symbol.value {
	case SymbolMultiPointerValue, SymbolProcedureValue:
		return true
	case SymbolBasicValue:
		if v.ident != nil {
			switch v.ident.name {
			case "rawptr", "cstring", "cstring16":
				return true
			}
		}
	}
	return false
}

@(private = "file")
union_layout :: proc(ast_context: ^AstContext, v: SymbolUnionValue, depth: int) -> (result: Type_Layout, ok: bool) {
	if len(v.types) == 0 {
		return {0, 1}, true
	}

	custom_align: i64 = 0
	if v.align != nil {
		custom_align = eval_const_int(ast_context, v.align, depth + 1) or_return
	}

	max_size, max_align: i64 = 0, 1
	for t in v.types {
		l := type_expr_layout(ast_context, t, depth + 1) or_return
		max_size = max(max_size, l.size)
		max_align = max(max_align, l.align)
	}

	align := custom_align > 0 ? custom_align : max_align

	if len(v.types) == 1 {
		if symbol, resolved := resolve_type_expression(ast_context, v.types[0]);
		   resolved && is_pointer_like_symbol(symbol) {
			return {align_forward(max_size, align), align}, true
		}
	}

	// Mirrors `union_tag_size` in the compiler.
	tag_size: i64 = 1
	if len(v.types) >= 1 << 16 {
		tag_size = 4
	} else if len(v.types) >= 1 << 8 {
		tag_size = 2
	}
	tag_size = max(tag_size, align)
	tag_size = min(tag_size, target_max_align(), 8)

	size := align_forward(max_size, tag_size) + tag_size
	return {align_forward(size, align), align}, true
}

struct_layout :: proc(
	ast_context: ^AstContext,
	v: SymbolStructValue,
	depth := 0,
	fields: ^[dynamic]Field_Layout = nil,
) -> (
	result: Type_Layout,
	ok: bool,
) {
	if depth > LAYOUT_MAX_DEPTH {
		return {}, false
	}

	is_packed := .Is_Packed in v.tags
	is_raw_union := .Is_Raw_Union in v.tags

	min_field_align, max_field_align: i64 = 0, 0
	if v.min_field_align != nil {
		min_field_align = eval_const_int(ast_context, v.min_field_align, depth + 1) or_return
	}
	if v.max_field_align != nil {
		max_field_align = eval_const_int(ast_context, v.max_field_align, depth + 1) or_return
	}

	offset, size, align: i64 = 0, 0, 1
	for name, i in v.names {
		if i < len(v.from_usings) && v.from_usings[i] != -1 {
			continue
		}

		field := type_expr_layout(ast_context, v.types[i], depth + 1) or_return
		field_align := field.align
		if is_packed {
			field_align = 1
		} else {
			if min_field_align > 0 {
				field_align = max(field_align, min_field_align)
			}
			if max_field_align > 0 {
				field_align = min(field_align, max_field_align)
			}
		}

		field_offset: i64 = 0
		if is_raw_union {
			size = max(size, field.size)
		} else {
			offset = align_forward(offset, field_align)
			field_offset = offset
			offset += field.size
			size = offset
		}
		align = max(align, field_align)

		if fields != nil {
			append(fields, Field_Layout{name = name, offset = field_offset, layout = field})
		}
	}

	if v.align != nil {
		align = eval_const_int(ast_context, v.align, depth + 1) or_return
	}
	return {align_forward(size, align), align}, true
}

@(private = "file")
soa_element_fields :: proc(
	ast_context: ^AstContext,
	elem: ^ast.Expr,
	depth: int,
) -> (
	layouts: [dynamic]Type_Layout,
	ok: bool,
) {
	layouts = make([dynamic]Type_Layout, context.temp_allocator)
	symbol := resolve_type_expression(ast_context, elem) or_return
	#partial switch v in symbol.value {
	case SymbolStructValue:
		for _, i in v.names {
			if i < len(v.from_usings) && v.from_usings[i] != -1 {
				continue
			}
			append(&layouts, type_expr_layout(ast_context, v.types[i], depth + 1) or_return)
		}
		return layouts, true
	case SymbolFixedArrayValue:
		n := array_count(ast_context, v.len, depth + 1) or_return
		l := type_expr_layout(ast_context, v.expr, depth + 1) or_return
		for _ in 0 ..< n {
			append(&layouts, l)
		}
		return layouts, true
	}
	return layouts, false
}

type_expr_layout :: proc(ast_context: ^AstContext, expr: ^ast.Expr, depth := 0) -> (result: Type_Layout, ok: bool) {
	if expr == nil || depth > LAYOUT_MAX_DEPTH {
		return {}, false
	}
	symbol := resolve_type_expression(ast_context, expr) or_return
	return symbol_layout(ast_context, symbol, depth + 1)
}

symbol_layout :: proc(ast_context: ^AstContext, symbol: Symbol, depth := 0) -> (result: Type_Layout, ok: bool) {
	if depth > LAYOUT_MAX_DEPTH {
		return {}, false
	}

	ptr := target_pointer_size()
	word := target_int_size()

	if symbol.pointers > 0 {
		if .SoaPointer in symbol.flags {
			return {align_forward(ptr + word, max(ptr, word)), max(ptr, word)}, true
		}
		return {ptr, ptr}, true
	}

	switch v in symbol.value {
	case SymbolBasicValue:
		if v.ident == nil {
			return {}, false
		}
		return basic_type_layout(v.ident.name)
	case SymbolStructValue:
		return struct_layout(ast_context, v, depth + 1)
	case SymbolUnionValue:
		return union_layout(ast_context, v, depth + 1)
	case SymbolEnumValue:
		if v.base_type != nil {
			return type_expr_layout(ast_context, v.base_type, depth + 1)
		}
		return {word, word}, true
	case SymbolBitSetValue:
		return bit_set_layout(ast_context, v, depth + 1)
	case SymbolBitFieldValue:
		return type_expr_layout(ast_context, v.backing_type, depth + 1)
	case SymbolFixedArrayValue:
		n := array_count(ast_context, v.len, depth + 1) or_return
		if .Soa in symbol.flags {
			fields := soa_element_fields(ast_context, v.expr, depth + 1) or_return
			size, align: i64 = 0, 1
			for f in fields {
				size = align_forward(size, f.align) + f.size * n
				align = max(align, f.align)
			}
			return {align_forward(size, align), align}, true
		}
		elem := type_expr_layout(ast_context, v.expr, depth + 1) or_return
		if .Simd in symbol.flags {
			size := elem.size * n
			return {size, min(size, LAYOUT_MAX_SIMD_ALIGN)}, true
		}
		return {elem.size * n, elem.align}, true
	case SymbolDynamicArrayValue:
		if .Soa in symbol.flags {
			fields := soa_element_fields(ast_context, v.expr, depth + 1) or_return
			return {i64(len(fields)) * ptr + 2 * word + allocator_layout().size, max(ptr, word)}, true
		}
		if v.cap != nil {
			n := eval_const_int(ast_context, v.cap, depth + 1) or_return
			elem := type_expr_layout(ast_context, v.expr, depth + 1) or_return
			align := max(elem.align, word)
			return {align_forward(align_forward(elem.size * n, word) + word, align), align}, true
		}
		return {ptr + 2 * word + allocator_layout().size, max(ptr, word)}, true
	case SymbolSliceValue:
		if .Soa in symbol.flags {
			fields := soa_element_fields(ast_context, v.expr, depth + 1) or_return
			return {i64(len(fields)) * ptr + word, max(ptr, word)}, true
		}
		return {align_forward(ptr + word, max(ptr, word)), max(ptr, word)}, true
	case SymbolMultiPointerValue:
		return {ptr, ptr}, true
	case SymbolMapValue:
		return {2 * ptr + allocator_layout().size, ptr}, true
	case SymbolMatrixValue:
		rows := eval_const_int(ast_context, v.x, depth + 1) or_return
		cols := eval_const_int(ast_context, v.y, depth + 1) or_return
		elem := type_expr_layout(ast_context, v.expr, depth + 1) or_return
		return {rows * cols * elem.size, elem.align}, true
	case SymbolProcedureValue:
		return {ptr, ptr}, true
	case SymbolPackageValue,
	     SymbolGenericValue,
	     SymbolProcedureGroupValue,
	     SymbolAggregateValue,
	     SymbolUntypedValue,
	     SymbolPolyTypeValue:
		return {}, false
	}
	return {}, false
}

construct_symbol_layout :: proc(
	ast_context: ^AstContext,
	symbol: Symbol,
	allocator := context.temp_allocator,
) -> string {
	#partial switch symbol.type {
	case .Function, .Package, .Keyword, .EnumMember, .Unresolved, .Type_Function:
		return ""
	}
	#partial switch v in symbol.value {
	case SymbolProcedureValue:
		if symbol.type != .Variable && symbol.type != .Field {
			return ""
		}
	case SymbolUntypedValue, SymbolProcedureGroupValue, SymbolAggregateValue, SymbolPackageValue:
		return ""
	}

	is_type := symbol.type != .Variable && symbol.type != .Field && symbol.type != .Constant

	if v, is_struct := symbol.value.(SymbolStructValue); is_struct && is_type && symbol.pointers == 0 {
		fields := make([dynamic]Field_Layout, context.temp_allocator)
		layout, ok := struct_layout(ast_context, v, 0, &fields)
		if !ok {
			return ""
		}
		padding := struct_padding(layout, fields[:], .Is_Raw_Union in v.tags)
		if padding > 0 {
			return fmt.aprintf(
				"size=%v, align=%v, padding=%v",
				layout.size,
				layout.align,
				padding,
				allocator = allocator,
			)
		}
		return fmt.aprintf("size=%v, align=%v", layout.size, layout.align, allocator = allocator)
	}

	layout, ok := symbol_layout(ast_context, symbol)
	if !ok {
		return ""
	}
	return fmt.aprintf("size=%v, align=%v", layout.size, layout.align, allocator = allocator)
}

construct_field_layout :: proc(
	ast_context: ^AstContext,
	parent: SymbolStructValue,
	field_index: int,
	allocator := context.temp_allocator,
) -> string {
	if field_index < 0 || field_index >= len(parent.names) {
		return ""
	}

	if field_index < len(parent.from_usings) && parent.from_usings[field_index] != -1 {
		layout, ok := type_expr_layout(ast_context, parent.types[field_index])
		if !ok {
			return ""
		}
		return fmt.aprintf("size=%v, align=%v", layout.size, layout.align, allocator = allocator)
	}

	comments, ok := struct_field_layout_comments(ast_context, parent, allocator)
	if !ok {
		return ""
	}
	return comments[field_index] or_else ""
}

struct_field_layout_comments :: proc(
	ast_context: ^AstContext,
	v: SymbolStructValue,
	allocator := context.temp_allocator,
) -> (
	comments: map[int]string,
	ok: bool,
) {
	fields := make([dynamic]Field_Layout, context.temp_allocator)
	layout := struct_layout(ast_context, v, 0, &fields) or_return
	is_raw_union := .Is_Raw_Union in v.tags

	comments = make(map[int]string, allocator)
	field := 0
	for name, i in v.names {
		if i < len(v.from_usings) && v.from_usings[i] != -1 {
			continue
		}
		if field >= len(fields) || fields[field].name != name {
			return comments, false
		}
		f := fields[field]
		field += 1

		padding: i64 = 0
		if !is_raw_union {
			next := layout.size
			if field < len(fields) {
				next = fields[field].offset
			}
			padding = next - (f.offset + f.layout.size)
		}

		if padding > 0 {
			comments[i] = fmt.aprintf(
				"size=%v, offset=%v (+%v padding)",
				f.layout.size,
				f.offset,
				padding,
				allocator = allocator,
			)
		} else {
			comments[i] = fmt.aprintf("size=%v, offset=%v", f.layout.size, f.offset, allocator = allocator)
		}
	}
	return comments, true
}

@(private = "file")
struct_padding :: proc(layout: Type_Layout, fields: []Field_Layout, is_raw_union: bool) -> i64 {
	padding: i64 = 0
	end: i64 = 0
	for f in fields {
		if !is_raw_union && f.offset > end {
			padding += f.offset - end
		}
		end = max(end, f.offset + f.layout.size)
	}
	if layout.size > end {
		padding += layout.size - end
	}
	return padding
}

append_first_line_comment :: proc(text, comment: string, allocator := context.temp_allocator) -> string {
	if newline := strings.index_byte(text, '\n'); newline >= 0 {
		return strings.concatenate({text[:newline], " // ", comment, text[newline:]}, allocator)
	}
	return strings.concatenate({text, " // ", comment}, allocator)
}

LAYOUT_COMMENT_MARKER :: '\x01'

align_layout_comments :: proc(text: string, allocator := context.temp_allocator) -> string {
	column := 0
	for line in strings.split_lines(text, context.temp_allocator) {
		if i := strings.index_byte(line, u8(LAYOUT_COMMENT_MARKER)); i >= 0 {
			column = max(column, i)
		}
	}

	sb := strings.builder_make(allocator)
	lines := strings.split_lines(text, context.temp_allocator)
	for line, n in lines {
		if i := strings.index_byte(line, u8(LAYOUT_COMMENT_MARKER)); i >= 0 {
			strings.write_string(&sb, line[:i])
			for _ in i ..= column {
				strings.write_byte(&sb, ' ')
			}
			strings.write_string(&sb, "// ")
			strings.write_string(&sb, line[i + 1:])
		} else {
			strings.write_string(&sb, line)
		}
		if n < len(lines) - 1 {
			strings.write_byte(&sb, '\n')
		}
	}
	return strings.to_string(sb)
}
