package server

import "core:odin/ast"
import "core:strings"

// InferenceContext provides the necessary context for type inference.
InferenceContext :: struct {
	document:       ^Document,
	ast_context:    ^AstContext,
	// Variable types that have been discovered during analysis
	variable_types: map[string]string, // variable name -> type string
}

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

destroy_inference_context :: proc(ctx: ^InferenceContext) {
	delete(ctx.variable_types)
}

// Infer the type of an expression, returning a type string.
// Returns empty string if the type cannot be inferred.
infer_expr_type :: proc(ctx: ^InferenceContext, expression: ^ast.Expr) -> string {
	if expression == nil {
		return ""
	}

	#partial switch expr in expression.derived {
	case ^ast.Basic_Lit:
		return infer_basic_literal_type(expr)
	case ^ast.Ident:
		return infer_identifier_type(ctx, expr)
	case ^ast.Binary_Expr:
		return infer_binary_expr_type(ctx, expr)
	case ^ast.Unary_Expr:
		return infer_unary_expr_type(ctx, expr)
	case ^ast.Paren_Expr:
		return infer_expr_type(ctx, expr.expr)
	case ^ast.Call_Expr:
		return infer_call_type(ctx, expr)
	case ^ast.Comp_Lit:
		return expr_to_string(expr.type)
	case ^ast.Selector_Expr:
		return infer_selector_type(ctx, expr)
	case ^ast.Index_Expr:
		return infer_index_type(ctx, expr)
	case ^ast.Slice_Expr:
		return infer_slice_type(ctx, expr)
	case ^ast.Ternary_If_Expr:
		return infer_expr_type(ctx, expr.x)
	case ^ast.Or_Else_Expr:
		return infer_expr_type(ctx, expr.y)
	case ^ast.Or_Return_Expr:
		return infer_expr_type(ctx, expr.expr)
	case ^ast.Deref_Expr:
		return infer_deref_type(ctx, expr)
	case ^ast.Auto_Cast:
		return infer_expr_type(ctx, expr.expr)
	case ^ast.Type_Cast:
		// cast(Type)expr and transmute(Type)expr - return the target type
		return expr_to_string(expr.type)
	case ^ast.Implicit_Selector_Expr:
		symbol, ok := resolve_type_expression(ctx.ast_context, expr)
		if ok && symbol.type_expr != nil {
			return expr_to_string(symbol.type_expr)
		}
		return ""
	case ^ast.Type_Assertion:
		return expr_to_string(expr.type)
	case ^ast.Ternary_When_Expr:
		return infer_expr_type(ctx, expr.x)
	case ^ast.Matrix_Index_Expr:
		inner := infer_expr_type(ctx, expr.expr)
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

		// Handle special builtins that need custom logic
		switch name {
		case "make":
			// make returns the type of the first argument
			if len(call.args) > 0 {
				return expr_to_string(call.args[0])
			}
			return ""
		case "new", "new_clone":
			// new returns a pointer to the type argument
			if len(call.args) > 0 {
				inner := expr_to_string(call.args[0])
				if inner != "" {
					return strings.concatenate({"^", inner}, context.temp_allocator)
				}
			}
			return ""
		}

		// Check if it's a basic type cast (e.g., f32(x), int(y))
		if is_builtin_type_name(name) {
			return name
		}

		// Try to look up procedure in globals directly (for file-scope procedures)
		if ctx.ast_context != nil {
			if global, ok := ctx.ast_context.globals[name]; ok {
				if proc_lit, ok := global.expr.derived.(^ast.Proc_Lit); ok {
					return get_proc_literal_return_type(proc_lit)
				}
			}
		}
	}

	// For all other calls, use resolve_call_expr from analysis.odin
	if ctx.ast_context == nil {
		return ""
	}

	symbol, ok := resolve_call_expr(ctx.ast_context, call)
	if !ok {
		return ""
	}

	// Handle type casts for non-builtin types (e.g., MyInt(x))
	if _, is_basic := symbol.value.(SymbolBasicValue); is_basic {
		return symbol.name
	}

	// Get the return types using get_proc_return_types which handles builtin procs
	// Pass true for is_mutable to get type names instead of literal values
	return_types := get_proc_return_types(ctx.ast_context, symbol, call, true)

	if len(return_types) == 0 {
		return ""
	}

	// Return the first return type as a string
	if len(return_types) == 1 {
		return get_type_string(return_types[0])
	}

	// Multiple returns - format as tuple
	sb := strings.builder_make(context.temp_allocator)
	strings.write_string(&sb, "(")
	for ret, i in return_types {
		if i > 0 {
			strings.write_string(&sb, ", ")
		}
		strings.write_string(&sb, get_type_string(ret))
	}
	strings.write_string(&sb, ")")
	return strings.to_string(sb)
}

// Helper to get return type from a procedure literal
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
