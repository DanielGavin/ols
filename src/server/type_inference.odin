// Type inference utilities for analyzing expressions and statements
// to determine their types without requiring full semantic analysis.
//
// This module provides lightweight type inference that can be used by
// code actions and other features that need to understand types from
// syntactic context alone.

package server

import "core:odin/ast"
import "core:odin/tokenizer"
import "core:strings"

// Inference_Context provides the necessary context for type inference.
// It can be created from various sources (ExtractProcContext, AstContext, etc.)
// Can be embedded in other contexts using `using` to share type inference state.
InferenceContext :: struct {
	document:       ^Document,
	ast_context:    ^AstContext,
	// Variable types that have been discovered during analysis
	variable_types: map[string]string, // variable name -> type string
}

// Create an inference context from a document and AST context
make_inference_context :: proc(
	document: ^Document,
	ast_context: ^AstContext,
	allocator := context.temp_allocator,
) -> InferenceContext {
	return InferenceContext {
		document = document,
		ast_context = ast_context,
		variable_types = make(map[string]string, allocator),
	}
}

// Destroy an inference context
destroy_inference_context :: proc(ctx: ^InferenceContext) {
	delete(ctx.variable_types)
}

// Register a known variable type for future inference
register_variable_type :: proc(ctx: ^InferenceContext, name: string, type_str: string) {
	ctx.variable_types[name] = type_str
}

// Get the type string of a variable if known
get_variable_type :: proc(ctx: ^InferenceContext, name: string) -> (string, bool) {
	if type_str, ok := ctx.variable_types[name]; ok {
		return type_str, true
	}
	return "", false
}

// Infer the type of an expression, returning a type string.
// Returns empty string if the type cannot be inferred.
infer_expr_type :: proc(ctx: ^InferenceContext, expr: ^ast.Expr) -> string {
	if expr == nil {
		return ""
	}

	#partial switch n in expr.derived {
	case ^ast.Basic_Lit:
		return infer_basic_literal_type(n)
	case ^ast.Ident:
		return infer_identifier_type(ctx, n)
	case ^ast.Binary_Expr:
		return infer_binary_expr_type(ctx, n)
	case ^ast.Unary_Expr:
		return infer_unary_expr_type(ctx, n)
	case ^ast.Paren_Expr:
		return infer_expr_type(ctx, n.expr)
	case ^ast.Call_Expr:
		return infer_call_type(ctx, n)
	case ^ast.Comp_Lit:
		return expr_to_string(n.type)
	case ^ast.Selector_Expr:
		return infer_selector_type(ctx, n)
	case ^ast.Index_Expr:
		return infer_index_type(ctx, n)
	case ^ast.Slice_Expr:
		return infer_slice_type(ctx, n)
	case ^ast.Ternary_If_Expr:
		return infer_expr_type(ctx, n.x)
	case ^ast.Or_Else_Expr:
		return infer_expr_type(ctx, n.y)
	case ^ast.Or_Return_Expr:
		return infer_expr_type(ctx, n.expr)
	case ^ast.Deref_Expr:
		return infer_deref_type(ctx, n)
	case ^ast.Auto_Cast:
		// auto_cast doesn't tell us the type, but we can try the inner expr
		return infer_expr_type(ctx, n.expr)
	case ^ast.Implicit_Selector_Expr:
		// .field syntax - type depends on context
		return ""
	case ^ast.Type_Assertion:
		// x.(T) returns T
		return expr_to_string(n.type)
	case ^ast.Ternary_When_Expr:
		return infer_expr_type(ctx, n.x)
	case ^ast.Matrix_Index_Expr:
		// Matrix indexing - would need matrix element type
		inner := infer_expr_type(ctx, n.expr)
		if inner != "" {
			return extract_matrix_element_type(inner)
		}
		return ""
	}

	return ""
}

// Infer type from a basic literal (integer, float, string, rune)
infer_basic_literal_type :: proc(lit: ^ast.Basic_Lit) -> string {
	#partial switch lit.tok.kind {
	case .Integer:
		return "int"
	case .Float:
		return "f64"
	case .String:
		return "string"
	case .Rune:
		return "rune"
	}
	return ""
}

// Infer type from an identifier by looking up known variables
infer_identifier_type :: proc(ctx: ^InferenceContext, ident: ^ast.Ident) -> string {
	if type_str, ok := ctx.variable_types[ident.name]; ok {
		return type_str
	}
	return ""
}

// Infer type from a binary expression
infer_binary_expr_type :: proc(ctx: ^InferenceContext, expr: ^ast.Binary_Expr) -> string {
	// Comparison operators always return bool
	#partial switch expr.op.kind {
	case .Cmp_Eq, .Not_Eq, .Lt, .Lt_Eq, .Gt, .Gt_Eq, .Cmp_And, .Cmp_Or:
		return "bool"
	}

	// Arithmetic/bitwise operators - infer from operands
	left_type := infer_expr_type(ctx, expr.left)
	if left_type != "" {
		return left_type
	}
	return infer_expr_type(ctx, expr.right)
}

// Infer type from a unary expression
infer_unary_expr_type :: proc(ctx: ^InferenceContext, expr: ^ast.Unary_Expr) -> string {
	#partial switch expr.op.kind {
	case .And:
		// Address-of operator - returns pointer to inner type
		inner := infer_expr_type(ctx, expr.expr)
		if inner != "" {
			return strings.concatenate({"^", inner}, context.temp_allocator)
		}
	case .Not:
		// Logical not always returns bool
		return "bool"
	case .Sub, .Add:
		// Negation/positive - same type as operand
		return infer_expr_type(ctx, expr.expr)
	case .Xor:
		// Bitwise not - same type as operand
		return infer_expr_type(ctx, expr.expr)
	}
	return infer_expr_type(ctx, expr.expr)
}

// Infer type from a call expression (handles builtins and type casts)
infer_call_type :: proc(ctx: ^InferenceContext, call: ^ast.Call_Expr) -> string {
	if call.expr == nil {
		return ""
	}

	// Check if it's an identifier (builtin or type cast)
	if ident, ok := call.expr.derived.(^ast.Ident); ok {
		name := ident.name

		// Handle builtins
		switch name {
		case "len", "cap", "size_of", "align_of", "offset_of":
			return "int"
		case "min", "max", "abs", "clamp":
			if len(call.args) > 0 {
				return infer_expr_type(ctx, call.args[0])
			}
			return ""
		case "make":
			if len(call.args) > 0 {
				return expr_to_string(call.args[0])
			}
			return ""
		case "new", "new_clone":
			if len(call.args) > 0 {
				inner := expr_to_string(call.args[0])
				if inner != "" {
					return strings.concatenate({"^", inner}, context.temp_allocator)
				}
			}
			return ""
		case "type_of":
			return "typeid"
		case "transmute", "cast", "auto_cast":
			return ""
		case "expand_values":
			// Returns multiple values, can't represent as single type
			return ""
		case "swizzle":
			if len(call.args) > 0 {
				return infer_expr_type(ctx, call.args[0])
			}
			return ""
		}

		// Check if it's a type cast
		if is_builtin_type_name(name) {
			return name
		}

		// Try to look up user-defined procedure return type
		return_type := lookup_proc_return_type(ctx, name)
		if return_type != "" {
			return return_type
		}
	}

	return ""
}

// Infer type from a selector expression (field access)
infer_selector_type :: proc(ctx: ^InferenceContext, expr: ^ast.Selector_Expr) -> string {
	// Would need full type analysis to determine field types
	// For now, we can't infer this without more context
	return ""
}

// Infer type from an index expression (array/slice/map access)
infer_index_type :: proc(ctx: ^InferenceContext, expr: ^ast.Index_Expr) -> string {
	container_type := infer_expr_type(ctx, expr.expr)
	if container_type != "" {
		return extract_element_type(container_type)
	}
	return ""
}

// Infer type from a slice expression
infer_slice_type :: proc(ctx: ^InferenceContext, expr: ^ast.Slice_Expr) -> string {
	inner_type := infer_expr_type(ctx, expr.expr)
	if inner_type != "" {
		// Slicing an array [N]T returns []T
		if strings.has_prefix(inner_type, "[") {
			if idx := strings.index(inner_type, "]"); idx >= 0 {
				return strings.concatenate({"[]", inner_type[idx + 1:]}, context.temp_allocator)
			}
		}
		// Slicing a slice or string returns the same type
		return inner_type
	}
	return ""
}

// Infer type from a dereference expression
infer_deref_type :: proc(ctx: ^InferenceContext, expr: ^ast.Deref_Expr) -> string {
	ptr_type := infer_expr_type(ctx, expr.expr)
	if ptr_type != "" {
		// Remove pointer prefix
		if strings.has_prefix(ptr_type, "^") {
			return ptr_type[1:]
		}
		if strings.has_prefix(ptr_type, "[^]") {
			// Multi-pointer dereference
			return ptr_type[3:]
		}
	}
	return ""
}

// Convert an AST expression to its string representation
expr_to_string :: proc(expr: ^ast.Expr) -> string {
	if expr == nil {
		return ""
	}
	return node_to_string(expr)
}

// Note: is_builtin_type_name is already defined in collector.odin
// and is accessible from this package

// Check if a type string represents a fixed-size array (e.g., "[3]int", "[10]f32")
// Dynamic arrays "[dynamic]int" and slices "[]int" return false
is_fixed_array_type :: proc(type_str: string) -> bool {
	if len(type_str) < 3 {
		return false
	}

	if type_str[0] != '[' {
		return false
	}

	close_idx := strings.index(type_str, "]")
	if close_idx < 0 {
		return false
	}

	inner := type_str[1:close_idx]
	if len(inner) == 0 {
		return false
	}

	// "[dynamic]" is a dynamic array, not a fixed array
	if inner == "dynamic" {
		return false
	}

	// "[^]" is a multi-pointer, not a fixed array
	if inner == "^" {
		return false
	}

	// Check if inner starts with a digit - that's a fixed array size
	if len(inner) > 0 && inner[0] >= '0' && inner[0] <= '9' {
		return true
	}

	// "?" is inferred size, still a fixed array
	if inner == "?" {
		return true
	}

	// Assume other identifiers could be compile-time constants
	return true
}

// Check if a type string represents a slice type
is_slice_type :: proc(type_str: string) -> bool {
	return strings.has_prefix(type_str, "[]")
}

// Check if a type string represents a dynamic array
is_dynamic_array_type :: proc(type_str: string) -> bool {
	return strings.has_prefix(type_str, "[dynamic]")
}

// Check if a type string represents a map type
is_map_type :: proc(type_str: string) -> bool {
	return strings.has_prefix(type_str, "map[")
}

// Check if a type string represents a pointer type
is_pointer_type_str :: proc(type_str: string) -> bool {
	return strings.has_prefix(type_str, "^")
}

// Check if a type string represents a multi-pointer type
is_multi_pointer_type :: proc(type_str: string) -> bool {
	return strings.has_prefix(type_str, "[^]")
}

// Check if a type string represents a matrix type
is_matrix_type :: proc(type_str: string) -> bool {
	return strings.has_prefix(type_str, "matrix[")
}

// Check if a type string represents an optional type (union with nil)
is_optional_type :: proc(type_str: string) -> bool {
	return strings.has_prefix(type_str, "Maybe(") || strings.contains(type_str, "| nil")
}

// Check if a type is numeric (integers or floats)
is_numeric_type :: proc(type_str: string) -> bool {
	switch type_str {
	case "int",
	     "uint",
	     "i8",
	     "i16",
	     "i32",
	     "i64",
	     "i128",
	     "u8",
	     "u16",
	     "u32",
	     "u64",
	     "u128",
	     "uintptr",
	     "f16",
	     "f32",
	     "f64",
	     "complex32",
	     "complex64",
	     "complex128":
		return true
	}
	return false
}

// Check if a type is an integer type
is_integer_type :: proc(type_str: string) -> bool {
	switch type_str {
	case "int", "uint", "i8", "i16", "i32", "i64", "i128", "u8", "u16", "u32", "u64", "u128", "uintptr":
		return true
	}
	return false
}

// Check if a type is a floating point type
is_float_type :: proc(type_str: string) -> bool {
	switch type_str {
	case "f16", "f32", "f64":
		return true
	}
	return false
}

// Check if a type is a complex number type
is_complex_type :: proc(type_str: string) -> bool {
	switch type_str {
	case "complex32", "complex64", "complex128":
		return true
	}
	return false
}

// Check if a type is a quaternion type
is_quaternion_type :: proc(type_str: string) -> bool {
	switch type_str {
	case "quaternion64", "quaternion128", "quaternion256":
		return true
	}
	return false
}

// Check if a type is a boolean type
is_boolean_type :: proc(type_str: string) -> bool {
	switch type_str {
	case "bool", "b8", "b16", "b32", "b64":
		return true
	}
	return false
}

// Check if a type is a string type
is_string_type :: proc(type_str: string) -> bool {
	return type_str == "string" || type_str == "cstring"
}

// Extract element type from array, slice, or map types
// e.g., "[3]int" -> "int", "[]string" -> "string", "map[string]int" -> "int"
extract_element_type :: proc(type_str: string) -> string {
	if type_str == "" {
		return ""
	}

	// Handle map type: map[key_type]value_type
	if strings.has_prefix(type_str, "map[") {
		bracket_count := 0
		for i := 4; i < len(type_str); i += 1 {
			if type_str[i] == '[' {
				bracket_count += 1
			} else if type_str[i] == ']' {
				if bracket_count == 0 {
					return type_str[i + 1:]
				}
				bracket_count -= 1
			}
		}
		return ""
	}

	// Handle array/slice type: [N]type or []type or [dynamic]type
	if strings.has_prefix(type_str, "[") {
		if idx := strings.index(type_str, "]"); idx >= 0 {
			return type_str[idx + 1:]
		}
	}

	return ""
}

// Extract key type from a map type string
// e.g., "map[string]int" -> "string"
extract_map_key_type :: proc(type_str: string) -> string {
	if type_str == "" || !strings.has_prefix(type_str, "map[") {
		return ""
	}

	bracket_count := 0
	for i := 4; i < len(type_str); i += 1 {
		if type_str[i] == '[' {
			bracket_count += 1
		} else if type_str[i] == ']' {
			if bracket_count == 0 {
				return type_str[4:i]
			}
			bracket_count -= 1
		}
	}
	return ""
}

// Extract the pointed-to type from a pointer type
// e.g., "^int" -> "int", "[^]f32" -> "f32"
extract_pointee_type :: proc(type_str: string) -> string {
	if strings.has_prefix(type_str, "^") {
		return type_str[1:]
	}
	if strings.has_prefix(type_str, "[^]") {
		return type_str[3:]
	}
	return ""
}

// Extract element type from a matrix type
// e.g., "matrix[4, 4]f32" -> "f32"
extract_matrix_element_type :: proc(type_str: string) -> string {
	if !strings.has_prefix(type_str, "matrix[") {
		return ""
	}
	if idx := strings.index(type_str, "]"); idx >= 0 {
		return type_str[idx + 1:]
	}
	return ""
}

// Extract array size from a fixed array type
// e.g., "[3]int" -> "3", "[]int" -> "", "[dynamic]int" -> ""
extract_array_size :: proc(type_str: string) -> string {
	if len(type_str) < 3 || type_str[0] != '[' {
		return ""
	}

	close_idx := strings.index(type_str, "]")
	if close_idx < 0 {
		return ""
	}

	inner := type_str[1:close_idx]
	if inner == "" || inner == "dynamic" || inner == "^" {
		return ""
	}

	return inner
}

// Wrap a type in a pointer
// e.g., "int" -> "^int"
make_pointer_type :: proc(type_str: string, allocator := context.temp_allocator) -> string {
	if type_str == "" {
		return ""
	}
	return strings.concatenate({"^", type_str}, allocator)
}

// Wrap a type in a slice
// e.g., "int" -> "[]int"
make_slice_type :: proc(type_str: string, allocator := context.temp_allocator) -> string {
	if type_str == "" {
		return ""
	}
	return strings.concatenate({"[]", type_str}, allocator)
}

// Wrap a type in a dynamic array
// e.g., "int" -> "[dynamic]int"
make_dynamic_array_type :: proc(type_str: string, allocator := context.temp_allocator) -> string {
	if type_str == "" {
		return ""
	}
	return strings.concatenate({"[dynamic]", type_str}, allocator)
}

// Check if an AST expression is a pointer type
is_pointer_type :: proc(type_expr: ^ast.Expr) -> bool {
	if type_expr == nil {
		return false
	}

	#partial switch n in type_expr.derived {
	case ^ast.Pointer_Type:
		return true
	case ^ast.Multi_Pointer_Type:
		return true
	}

	return false
}

// Get type string from a type expression
get_type_string :: proc(type_expr: ^ast.Expr) -> string {
	if type_expr == nil {
		return ""
	}
	return node_to_string(type_expr)
}

// Look up the return type of a procedure by name
lookup_proc_return_type :: proc(ctx: ^InferenceContext, proc_name: string) -> string {
	if ctx.ast_context == nil {
		return ""
	}

	// Try looking up in locals
	if return_type := try_lookup_proc_in_locals(ctx, proc_name); return_type != "" {
		return return_type
	}

	// Try looking up in globals
	if return_type := try_lookup_proc_in_globals(ctx, proc_name); return_type != "" {
		return return_type
	}

	// Try looking up in package index
	if return_type := try_lookup_proc_in_package_index(ctx, proc_name); return_type != "" {
		return return_type
	}

	// Try looking up in builtin package
	if return_type := try_lookup_proc_in_builtin(ctx, proc_name); return_type != "" {
		return return_type
	}

	return ""
}

// Try to find procedure in local variables
try_lookup_proc_in_locals :: proc(ctx: ^InferenceContext, proc_name: string) -> string {
	fake_ident := make_lookup_identifier(ctx, proc_name)

	if local, ok := get_local(ctx.ast_context^, fake_ident); ok {
		if local.rhs != nil {
			if proc_lit, ok := local.rhs.derived.(^ast.Proc_Lit); ok {
				return get_proc_literal_return_type(proc_lit)
			}
		}
		if local.value_expr != nil {
			if proc_lit, ok := local.value_expr.derived.(^ast.Proc_Lit); ok {
				return get_proc_literal_return_type(proc_lit)
			}
		}
	}

	return ""
}

// Try to find procedure in file-level globals
try_lookup_proc_in_globals :: proc(ctx: ^InferenceContext, proc_name: string) -> string {
	if global, ok := ctx.ast_context.globals[proc_name]; ok {
		if proc_lit, ok := global.expr.derived.(^ast.Proc_Lit); ok {
			return get_proc_literal_return_type(proc_lit)
		}
	}
	return ""
}

// Try to find procedure in the package index
try_lookup_proc_in_package_index :: proc(ctx: ^InferenceContext, proc_name: string) -> string {
	fake_ident := make_lookup_identifier(ctx, proc_name)
	pkg := get_package_from_node(fake_ident)

	if symbol, ok := lookup(proc_name, pkg, fake_ident.pos.file); ok {
		return extract_symbol_return_type(symbol)
	}

	return ""
}

// Try to find procedure in builtin package
try_lookup_proc_in_builtin :: proc(ctx: ^InferenceContext, proc_name: string) -> string {
	fake_ident := make_lookup_identifier(ctx, proc_name)

	if symbol, ok := lookup(proc_name, "$builtin", fake_ident.pos.file); ok {
		return extract_symbol_return_type(symbol)
	}

	return ""
}

// Create a temporary identifier for symbol lookup
make_lookup_identifier :: proc(ctx: ^InferenceContext, name: string) -> ast.Ident {
	default_pos: tokenizer.Pos
	if ctx.document != nil && len(ctx.document.ast.decls) > 0 {
		default_pos = ctx.document.ast.decls[0].pos
	}
	return ast.Ident{name = name, pos = default_pos}
}

// Extract return type string from a resolved symbol
extract_symbol_return_type :: proc(symbol: Symbol) -> string {
	proc_value, ok := symbol.value.(SymbolProcedureValue)
	if !ok {
		return ""
	}

	if len(proc_value.return_types) == 0 {
		return ""
	}

	if len(proc_value.return_types) == 1 {
		return get_type_string(proc_value.return_types[0].type)
	}

	// Multiple returns - format as tuple
	return format_tuple_type(proc_value.return_types)
}

// Format multiple return types as a tuple string
format_tuple_type :: proc(return_types: []^ast.Field) -> string {
	sb := strings.builder_make(context.temp_allocator)
	strings.write_string(&sb, "(")
	for ret, i in return_types {
		if i > 0 {
			strings.write_string(&sb, ", ")
		}
		strings.write_string(&sb, get_type_string(ret.type))
	}
	strings.write_string(&sb, ")")
	return strings.to_string(sb)
}

// Get the return type string from a procedure literal
get_proc_literal_return_type :: proc(proc_lit: ^ast.Proc_Lit) -> string {
	if proc_lit == nil || proc_lit.type == nil {
		return ""
	}

	if proc_type, ok := proc_lit.type.derived.(^ast.Proc_Type); ok {
		if proc_type.results == nil {
			return ""
		}

		if len(proc_type.results.list) == 1 {
			field := proc_type.results.list[0]
			return get_type_string(field.type)
		}

		if len(proc_type.results.list) > 1 {
			sb := strings.builder_make(context.temp_allocator)
			strings.write_string(&sb, "(")
			for field, i in proc_type.results.list {
				if i > 0 {
					strings.write_string(&sb, ", ")
				}
				strings.write_string(&sb, get_type_string(field.type))
			}
			strings.write_string(&sb, ")")
			return strings.to_string(sb)
		}
	}

	return ""
}

// Infer variable types from a value declaration
infer_value_decl_types :: proc(ctx: ^InferenceContext, decl: ^ast.Value_Decl) {
	for name, i in decl.names {
		if ident, ok := name.derived.(^ast.Ident); ok {
			type_str := get_type_string(decl.type)
			if type_str == "" && i < len(decl.values) {
				type_str = infer_expr_type(ctx, decl.values[i])
			}
			if type_str != "" {
				ctx.variable_types[ident.name] = type_str
			}
		}
	}
}

// Infer variable types from an assignment statement with :=
infer_assign_stmt_types :: proc(ctx: ^InferenceContext, stmt: ^ast.Assign_Stmt) {
	if stmt.op.text != ":=" {
		return // Only declaration assignments create new types
	}

	for lhs, i in stmt.lhs {
		if ident, ok := lhs.derived.(^ast.Ident); ok {
			type_str := ""
			if i < len(stmt.rhs) {
				type_str = infer_expr_type(ctx, stmt.rhs[i])
			}
			if type_str != "" {
				ctx.variable_types[ident.name] = type_str
			}
		}
	}
}

// Infer the iteration variable types from a range statement
// Returns (first_var_type, second_var_type)
infer_range_stmt_types :: proc(
	ctx: ^InferenceContext,
	stmt: ^ast.Range_Stmt,
) -> (
	first_type: string,
	second_type: string,
) {
	if stmt.expr == nil {
		return "", ""
	}

	container_type := infer_expr_type(ctx, stmt.expr)

	// Strings: for char in str -> (rune, int)
	if container_type == "string" || container_type == "cstring" {
		return "rune", "int"
	}

	// Maps: for key, value in map -> (key_type, value_type)
	if strings.has_prefix(container_type, "map[") {
		key_type := extract_map_key_type(container_type)
		value_type := extract_element_type(container_type)
		return key_type, value_type
	}

	// Arrays/Slices: for value, index in arr -> (element_type, int)
	element_type := extract_element_type(container_type)
	return element_type, "int"
}

// Infer variable types for a for-loop init statement
infer_for_stmt_types :: proc(ctx: ^InferenceContext, stmt: ^ast.For_Stmt) {
	if stmt.init != nil {
		#partial switch n in stmt.init.derived {
		case ^ast.Value_Decl:
			infer_value_decl_types(ctx, n)
		case ^ast.Assign_Stmt:
			infer_assign_stmt_types(ctx, n)
		}
	}
}

// Check if two types are compatible for assignment
// This is a simple check that doesn't handle all Odin type rules
types_are_compatible :: proc(from_type: string, to_type: string) -> bool {
	if from_type == to_type {
		return true
	}

	// Empty types are compatible with anything (unknown types)
	if from_type == "" || to_type == "" {
		return true
	}

	// Any can accept any type
	if to_type == "any" {
		return true
	}

	// rawptr can accept any pointer
	if to_type == "rawptr" && (strings.has_prefix(from_type, "^") || strings.has_prefix(from_type, "[^]")) {
		return true
	}

	return false
}

// Get the common type of two types (for binary expressions)
// Returns empty string if no common type can be determined
get_common_type :: proc(type1: string, type2: string) -> string {
	if type1 == type2 {
		return type1
	}

	if type1 == "" {
		return type2
	}
	if type2 == "" {
		return type1
	}

	// Numeric type promotion (simplified)
	if is_numeric_type(type1) && is_numeric_type(type2) {
		// Float wins over integer
		if is_float_type(type1) || is_float_type(type2) {
			if is_float_type(type1) {
				return type1
			}
			return type2
		}
	}

	return type1
}

// Infer type from an expression using a simple variable map
// This is a convenience function for callers that don't need full Inference_Context
infer_type_from_expr_simple :: proc(
	expr: ^ast.Expr,
	variables: map[string]string,
	document: ^Document = nil,
	ast_context: ^AstContext = nil,
) -> string {
	if expr == nil {
		return ""
	}

	ctx := InferenceContext {
		document       = document,
		ast_context    = ast_context,
		variable_types = variables,
	}

	return infer_expr_type(&ctx, expr)
}

// Infer types from multiple expressions, returning a slice of type strings
infer_types_from_exprs :: proc(
	ctx: ^InferenceContext,
	exprs: []^ast.Expr,
	allocator := context.temp_allocator,
) -> []string {
	result := make([]string, len(exprs), allocator)
	for expr, i in exprs {
		result[i] = infer_expr_type(ctx, expr)
	}
	return result
}

// Get the type that would be returned by iterating over a container
// Returns (element_type, index_type) for arrays/slices
// Returns (key_type, value_type) for maps
// Returns (rune, int) for strings
get_iteration_types :: proc(container_type: string) -> (first_type: string, second_type: string) {
	if container_type == "" {
		return "", ""
	}

	// Strings: for char, index in str
	if container_type == "string" || container_type == "cstring" {
		return "rune", "int"
	}

	// Maps: for key, value in map
	if strings.has_prefix(container_type, "map[") {
		key_type := extract_map_key_type(container_type)
		value_type := extract_element_type(container_type)
		return key_type, value_type
	}

	// Arrays/Slices/Dynamic Arrays: for element, index in arr
	element_type := extract_element_type(container_type)
	return element_type, "int"
}
