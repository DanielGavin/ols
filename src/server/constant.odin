package server

import "core:odin/ast"
import "core:odin/tokenizer"
import "core:strconv"

resolve_integer_constant :: proc(
	evaluation: ^Layout_Evaluation_Context,
	expr: ^ast.Expr,
	local_integer_values: map[string]int = nil,
) -> (
	int,
	bool,
) {
	return resolve_integer_constant_internal(evaluation, expr, local_integer_values, 0)
}

@(private = "file")
extract_config_key :: proc(expr: ^ast.Expr) -> (string, bool) {
	if expr == nil {
		return "", false
	}

	if ident, ok := expr.derived.(^ast.Ident); ok {
		return ident.name, true
	}

	return "", false
}

@(private = "file")
resolve_integer_config_directive :: proc(
	evaluation: ^Layout_Evaluation_Context,
	call: ^ast.Call_Expr,
	local_integer_values: map[string]int,
	depth: int,
) -> (
	result: int,
	ok: bool,
) {
	if len(call.args) != 2 {
		return 0, false
	}

	key := extract_config_key(call.args[0]) or_return
	if evaluation.config != nil {
		if configured, found := evaluation.config.profile.defines[key]; found {
			return strconv.parse_int(configured)
		}
	}

	return resolve_integer_constant_internal(evaluation, call.args[1], local_integer_values, depth + 1)
}

@(private = "file")
resolve_boolean_config_directive :: proc(
	evaluation: ^Layout_Evaluation_Context,
	call: ^ast.Call_Expr,
	local_integer_values: map[string]int,
	depth: int,
) -> (
	result: bool,
	ok: bool,
) {
	if len(call.args) != 2 {
		return false, false
	}

	key := extract_config_key(call.args[0]) or_return
	if evaluation.config != nil {
		if configured, found := evaluation.config.profile.defines[key]; found {
			return strconv.parse_bool(configured)
		}
	}

	return resolve_boolean_constant_internal(evaluation, call.args[1], local_integer_values, depth + 1)
}

@(private = "file")
get_simple_callee_name :: proc(call: ^ast.Call_Expr) -> (string, bool) {
	if call == nil || call.expr == nil {
		return "", false
	}

	#partial switch callee in call.expr.derived {
	case ^ast.Ident:
		return callee.name, true
	case ^ast.Basic_Directive:
		return callee.name, true
	}

	return "", false
}

@(private = "file")
get_integer_type_properties :: proc(name: string) -> (bits: int, signed: bool, ok: bool) {
	switch name {
	case "i8":
		return 8, true, true
	case "i16", "i16le", "i16be":
		return 16, true, true
	case "i32", "i32le", "i32be", "rune":
		return 32, true, true
	case "i64", "i64le", "i64be":
		return 64, true, true
	case "i128", "i128le", "i128be":
		return 128, true, true
	case "int":
		return size_of(int) * 8, true, true
	case "u8", "byte":
		return 8, false, true
	case "u16", "u16le", "u16be":
		return 16, false, true
	case "u32", "u32le", "u32be":
		return 32, false, true
	case "u64", "u64le", "u64be":
		return 64, false, true
	case "u128", "u128le", "u128be":
		return 128, false, true
	case "uint":
		return size_of(uint) * 8, false, true
	case "uintptr":
		return size_of(uintptr) * 8, false, true
	}

	return 0, false, false
}

@(private = "file")
Integer_Type_Kind :: enum {
	Unknown,
	Untyped,
	Signed,
	Unsigned,
	Context_Dependent,
}

@(private = "file")
classify_resolved_integer_type :: proc(evaluation: ^Layout_Evaluation_Context, expr: ^ast.Expr) -> Integer_Type_Kind {
	symbol, ok := resolve_type_expression(evaluation.ast_context, expr)
	if !ok {
		return .Unknown
	}
	if symbol.pointers > 0 {
		return .Unknown
	}

	if basic, ok := symbol.value.(SymbolBasicValue); ok {
		_, signed, integer_type := get_integer_type_properties(basic.ident.name)
		if !integer_type {
			return .Unknown
		}
		return signed ? .Signed : .Unsigned
	}

	if untyped, ok := symbol.value.(SymbolUntypedValue); ok {
		#partial switch untyped.type {
		case .Integer, .Rune:
			return .Untyped
		}
	}

	return .Unknown
}

@(private = "file")
merge_integer_type_kinds :: proc(
	evaluation: ^Layout_Evaluation_Context,
	expr: ^ast.Expr,
	left, right: Integer_Type_Kind,
) -> Integer_Type_Kind {
	if left == .Context_Dependent || right == .Context_Dependent {
		return .Context_Dependent
	}

	if left == .Unknown || right == .Unknown {
		return classify_resolved_integer_type(evaluation, expr)
	}

	if left == right {
		return left
	}

	if left == .Untyped {
		return right
	}

	if right == .Untyped {
		return left
	}

	return classify_resolved_integer_type(evaluation, expr)
}

@(private = "file")
classify_integer_expression_type :: proc(
	evaluation: ^Layout_Evaluation_Context,
	expr: ^ast.Expr,
	local_integer_values: map[string]int,
	depth: int = 0,
) -> Integer_Type_Kind {
	if expr == nil || depth > 64 {
		return .Unknown
	}

	#partial switch value in expr.derived {
	case ^ast.Paren_Expr:
		return classify_integer_expression_type(evaluation, value.expr, local_integer_values, depth + 1)
	case ^ast.Auto_Cast:
		return .Context_Dependent
	case ^ast.Type_Cast:
		return classify_resolved_integer_type(evaluation, value.type)
	case ^ast.Basic_Lit:
		#partial switch value.tok.kind {
		case .Integer, .Rune:
			return .Untyped
		}

		return .Unknown
	case ^ast.Ident:
		if _, found := local_integer_values[value.name]; found {
			// Enum-local values have a contextual enum type which is not retained in
			// local_integer_values. Do not guess its signedness.
			return .Unknown
		}

		return classify_resolved_integer_type(evaluation, expr)
	case ^ast.Implicit_Selector_Expr:
		return .Unknown
	case ^ast.Selector_Expr:
		return classify_resolved_integer_type(evaluation, expr)
	case ^ast.Unary_Expr:
		return classify_integer_expression_type(evaluation, value.expr, local_integer_values, depth + 1)
	case ^ast.Binary_Expr:
		left := classify_integer_expression_type(evaluation, value.left, local_integer_values, depth + 1)
		right := classify_integer_expression_type(evaluation, value.right, local_integer_values, depth + 1)

		return merge_integer_type_kinds(evaluation, expr, left, right)
	case ^ast.Call_Expr:
		name, ok := get_simple_callee_name(value)
		if !ok {
			return .Unknown
		}

		switch name {
		case "size_of", "align_of":
			return .Signed
		case "config":
			if len(value.args) != 2 {
				return .Unknown
			}

			return classify_integer_expression_type(evaluation, value.args[1], local_integer_values, depth + 1)
		}

		return classify_resolved_integer_type(evaluation, value.expr)
	case ^ast.Ternary_If_Expr:
		x := classify_integer_expression_type(evaluation, value.x, local_integer_values, depth + 1)
		y := classify_integer_expression_type(evaluation, value.y, local_integer_values, depth + 1)

		return merge_integer_type_kinds(evaluation, expr, x, y)
	case ^ast.Ternary_When_Expr:
		x := classify_integer_expression_type(evaluation, value.x, local_integer_values, depth + 1)
		y := classify_integer_expression_type(evaluation, value.y, local_integer_values, depth + 1)

		return merge_integer_type_kinds(evaluation, expr, x, y)
	}

	return classify_resolved_integer_type(evaluation, expr)
}

@(private = "file")
resolve_integer_conversion :: proc(
	evaluation: ^Layout_Evaluation_Context,
	type_expr: ^ast.Expr,
	value: int,
) -> (
	result: int,
	ok: bool,
) {
	if type_expr == nil {
		return 0, false
	}

	symbol := resolve_type_expression(evaluation.ast_context, type_expr) or_return
	if symbol.pointers > 0 {
		return 0, false
	}

	basic := symbol.value.(SymbolBasicValue) or_return
	bits, signed, integer_type := get_integer_type_properties(basic.ident.name)
	if !integer_type {
		return 0, false
	}

	wide := i128(value)
	if signed {
		if bits >= size_of(int) * 8 {
			return value, true
		}

		limit := i128(1) << uint(bits - 1)
		return value, -limit <= wide && wide < limit
	}

	if value < 0 {
		return 0, false
	}

	if bits >= size_of(int) * 8 {
		return value, true
	}

	limit := i128(1) << uint(bits)
	return value, wide < limit
}

@(private = "file")
resolve_rune_constant :: proc(tok: tokenizer.Token) -> (int, bool) {
	text := tok.text
	if len(text) < 2 || text[0] != '\'' || text[len(text) - 1] != '\'' {
		return 0, false
	}

	r, _, tail, ok := strconv.unquote_char(text[1:len(text) - 1], '\'')
	return int(r), ok && len(tail) == 0
}

@(private = "file")
get_indexed_constant_expression :: proc(symbol: Symbol) -> (^ast.Expr, bool) {
	if .Mutable in symbol.flags {
		return nil, false
	}

	if symbol.value_expr != nil {
		return symbol.value_expr, true
	}

	if value, ok := symbol.value.(SymbolGenericValue); ok && value.expr != nil {
		return value.expr, true
	}

	return nil, false
}

@(private = "file")
resolve_identifier_constant_expression :: proc(
	evaluation: ^Layout_Evaluation_Context,
	ident: ^ast.Ident,
) -> (
	^ast.Expr,
	bool,
) {
	ast_context := evaluation.ast_context
	package_name := get_package_from_node(ident.node)

	if package_name == "" || package_name == ast_context.document_package {
		if local, ok := get_local(ast_context^, ident^); ok && .Mutable not_in local.flags {
			if local.value_expr != nil {
				return local.value_expr, true
			}
			if local.rhs != nil {
				return local.rhs, true
			}
		}

		if global, ok := ast_context.globals[ident.name]; ok && .Mutable not_in global.flags {
			if global.value_expr != nil {
				return global.value_expr, true
			}

			if global.expr != nil {
				return global.expr, true
			}
		}
	}

	if package_name == "" {
		package_name = ast_context.current_package
	}

	if symbol, ok := lookup(ident.name, package_name, ident.pos.file); ok {
		return get_indexed_constant_expression(symbol)
	}

	return nil, false
}

@(private = "file")
resolve_selector_constant_expression :: proc(
	evaluation: ^Layout_Evaluation_Context,
	selector: ^ast.Selector_Expr,
) -> (
	^ast.Expr,
	bool,
) {
	package_symbol, ok := resolve_type_expression(evaluation.ast_context, selector.expr)
	if !ok {
		return nil, false
	}

	_, is_package := package_symbol.value.(SymbolPackageValue)
	if !is_package || selector.field == nil {
		return nil, false
	}

	symbol, found := lookup(selector.field.name, package_symbol.pkg, selector.pos.file)
	if !found {
		return nil, false
	}

	return get_indexed_constant_expression(symbol)
}

@(private = "file")
resolve_boolean_constant_internal :: proc(
	evaluation: ^Layout_Evaluation_Context,
	expr: ^ast.Expr,
	local_integer_values: map[string]int,
	depth: int,
) -> (
	result: bool,
	ok: bool,
) {
	if expr == nil || depth > 64 {
		return false, false
	}

	if expr in evaluation.active_constant_expressions {
		return false, false
	}

	evaluation.active_constant_expressions[expr] = {}
	defer delete_key(&evaluation.active_constant_expressions, expr)

	#partial switch value in expr.derived {
	case ^ast.Paren_Expr:
		return resolve_boolean_constant_internal(evaluation, value.expr, local_integer_values, depth + 1)
	case ^ast.Ident:
		switch value.name {
		case "true":
			return true, true
		case "false":
			return false, true
		}

		constant_expr := resolve_identifier_constant_expression(evaluation, value) or_return

		return resolve_boolean_constant_internal(evaluation, constant_expr, local_integer_values, depth + 1)
	case ^ast.Selector_Expr:
		constant_expr := resolve_selector_constant_expression(evaluation, value) or_return

		return resolve_boolean_constant_internal(evaluation, constant_expr, local_integer_values, depth + 1)
	case ^ast.Unary_Expr:
		if value.op.kind == .Not {
			operand := resolve_boolean_constant_internal(
				evaluation,
				value.expr,
				local_integer_values,
				depth + 1,
			) or_return

			return !operand, true
		}
	case ^ast.Binary_Expr:
		#partial switch value.op.kind {
		case .Cmp_And:
			left := resolve_boolean_constant_internal(
				evaluation,
				value.left,
				local_integer_values,
				depth + 1,
			) or_return

			if !left {
				return false, true
			}

			return resolve_boolean_constant_internal(evaluation, value.right, local_integer_values, depth + 1)
		case .Cmp_Or:
			left := resolve_boolean_constant_internal(
				evaluation,
				value.left,
				local_integer_values,
				depth + 1,
			) or_return

			if left {
				return true, true
			}

			return resolve_boolean_constant_internal(evaluation, value.right, local_integer_values, depth + 1)
		case .Cmp_Eq, .Not_Eq, .Lt, .Lt_Eq, .Gt, .Gt_Eq:
			left := resolve_integer_constant_internal(
				evaluation,
				value.left,
				local_integer_values,
				depth + 1,
			) or_return

			right := resolve_integer_constant_internal(
				evaluation,
				value.right,
				local_integer_values,
				depth + 1,
			) or_return

			#partial switch value.op.kind {
			case .Cmp_Eq:
				return left == right, true
			case .Not_Eq:
				return left != right, true
			case .Lt:
				return left < right, true
			case .Lt_Eq:
				return left <= right, true
			case .Gt:
				return left > right, true
			case .Gt_Eq:
				return left >= right, true
			}
		}
	case ^ast.Call_Expr:
		name := get_simple_callee_name(value) or_return

		if name == "config" {
			return resolve_boolean_config_directive(evaluation, value, local_integer_values, depth)
		}
	case ^ast.Ternary_If_Expr:
		condition := resolve_boolean_constant_internal(
			evaluation,
			value.cond,
			local_integer_values,
			depth + 1,
		) or_return

		if condition {
			return resolve_boolean_constant_internal(evaluation, value.x, local_integer_values, depth + 1)
		}

		return resolve_boolean_constant_internal(evaluation, value.y, local_integer_values, depth + 1)
	case ^ast.Ternary_When_Expr:
		condition := resolve_boolean_constant_internal(
			evaluation,
			value.cond,
			local_integer_values,
			depth + 1,
		) or_return

		if condition {
			return resolve_boolean_constant_internal(evaluation, value.x, local_integer_values, depth + 1)
		}

		return resolve_boolean_constant_internal(evaluation, value.y, local_integer_values, depth + 1)
	}

	return false, false
}

@(private = "file")
resolve_integer_constant_internal :: proc(
	evaluation: ^Layout_Evaluation_Context,
	expr: ^ast.Expr,
	local_integer_values: map[string]int,
	depth: int,
) -> (
	result: int,
	ok: bool,
) {
	if expr == nil || depth > 64 {
		return 0, false
	}

	if expr in evaluation.active_constant_expressions {
		return 0, false
	}

	evaluation.active_constant_expressions[expr] = {}
	defer delete_key(&evaluation.active_constant_expressions, expr)

	#partial switch value in expr.derived {
	case ^ast.Paren_Expr:
		return resolve_integer_constant_internal(evaluation, value.expr, local_integer_values, depth + 1)
	case ^ast.Auto_Cast:
		return resolve_integer_constant_internal(evaluation, value.expr, local_integer_values, depth + 1)
	case ^ast.Type_Cast:
		operand := resolve_integer_constant_internal(evaluation, value.expr, local_integer_values, depth + 1) or_return

		return resolve_integer_conversion(evaluation, value.type, operand)
	case ^ast.Basic_Lit:
		if value.tok.kind == .Rune {
			return resolve_rune_constant(value.tok)
		}

		return strconv.parse_int(value.tok.text)
	case ^ast.Ident:
		if local_value, found := local_integer_values[value.name]; found {
			return local_value, true
		}

		constant_expr := resolve_identifier_constant_expression(evaluation, value) or_return

		return resolve_integer_constant_internal(evaluation, constant_expr, local_integer_values, depth + 1)
	case ^ast.Implicit_Selector_Expr:
		if local_value, found := local_integer_values[value.field.name]; found {
			return local_value, true
		}

		return 0, false
	case ^ast.Selector_Expr:
		constant_expr := resolve_selector_constant_expression(evaluation, value) or_return

		return resolve_integer_constant_internal(evaluation, constant_expr, local_integer_values, depth + 1)
	case ^ast.Unary_Expr:
		operand := resolve_integer_constant_internal(evaluation, value.expr, local_integer_values, depth + 1) or_return

		#partial switch value.op.kind {
		case .Add:
			return operand, true
		case .Sub:
			if operand == min(int) {
				return 0, false
			}

			return -operand, true
		case .Xor:
			kind := classify_integer_expression_type(evaluation, value.expr, local_integer_values)
			if kind == .Unsigned || kind == .Context_Dependent || kind == .Unknown {
				return 0, false
			}

			return ~operand, true
		}

		return 0, false
	case ^ast.Binary_Expr:
		left := resolve_integer_constant_internal(evaluation, value.left, local_integer_values, depth + 1) or_return
		right := resolve_integer_constant_internal(evaluation, value.right, local_integer_values, depth + 1) or_return

		wide: i128
		#partial switch value.op.kind {
		case .Add:
			wide = i128(left) + i128(right)
		case .Sub:
			wide = i128(left) - i128(right)
		case .Mul:
			wide = i128(left) * i128(right)
		case .Quo:
			if right == 0 || left == min(int) && right == -1 {
				return 0, false
			}

			return left / right, true
		case .Mod:
			if right == 0 || left == min(int) && right == -1 {
				return 0, false
			}

			return left % right, true
		case .And:
			return left & right, true
		case .Or:
			return left | right, true
		case .Xor:
			return left ~ right, true
		case .And_Not:
			return left &~ right, true
		case .Shl:
			if right < 0 || right >= size_of(int) * 8 {
				return 0, left == 0
			}

			wide = i128(left) << uint(right)
		case .Shr:
			if right < 0 || right >= size_of(int) * 8 {
				return 0, false
			}

			return left >> uint(right), true
		case:
			return 0, false
		}

		if wide < i128(min(int)) || wide > i128(max(int)) {
			return 0, false
		}

		return int(wide), true
	case ^ast.Call_Expr:
		name := get_simple_callee_name(value) or_return
		switch name {
		case "config":
			return resolve_integer_config_directive(evaluation, value, local_integer_values, depth)
		case "size_of", "align_of":
			if len(value.args) != 1 {
				return 0, false
			}

			layout := resolve_type_layout(evaluation, value.args[0]) or_return
			if name == "size_of" {
				return layout.size, true
			}

			return layout.alignment, true
		}

		if len(value.args) != 1 {
			return 0, false
		}

		operand := resolve_integer_constant_internal(
			evaluation,
			value.args[0],
			local_integer_values,
			depth + 1,
		) or_return

		return resolve_integer_conversion(evaluation, value.expr, operand)
	case ^ast.Ternary_If_Expr:
		condition := resolve_boolean_constant_internal(
			evaluation,
			value.cond,
			local_integer_values,
			depth + 1,
		) or_return

		if condition {
			return resolve_integer_constant_internal(evaluation, value.x, local_integer_values, depth + 1)
		}

		return resolve_integer_constant_internal(evaluation, value.y, local_integer_values, depth + 1)
	case ^ast.Ternary_When_Expr:
		condition := resolve_boolean_constant_internal(
			evaluation,
			value.cond,
			local_integer_values,
			depth + 1,
		) or_return

		if condition {
			return resolve_integer_constant_internal(evaluation, value.x, local_integer_values, depth + 1)
		}

		return resolve_integer_constant_internal(evaluation, value.y, local_integer_values, depth + 1)
	}

	return 0, false
}
