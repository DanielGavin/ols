#+private file
#+feature dynamic-literals

package server

import "core:odin/ast"
import "core:odin/tokenizer"
import "core:slice"
import "core:strings"

import "src:common"

EXTRACT_PROC_ACTION_TITLE :: "Extract Proc"
EXTRACT_PROC_ACTION_KIND :: "refactor.extract"
DEFAULT_PROC_NAME :: "extracted_proc"

VariableUsage :: struct {
	name:           string,
	is_modified:    bool,
	is_read:        bool,
	is_declared:    bool,
	is_used_after:  bool,
	is_pointer:     bool,
	addr_of_source: string, // If this variable is assigned from &x, stores "x"
	type_expr:      ^ast.Expr,
}

ControlFlowType :: enum {
	None,
	Return,
	Break,
	Continue,
	BreakAndContinue,
}

ExtractProcContext :: struct {
	using inference_context: InferenceContext,
	selection_start:         common.AbsolutePosition,
	selection_end:           common.AbsolutePosition,
	containing_proc:         ^ast.Proc_Lit,
	selected_stmts:          [dynamic]^ast.Stmt,
	selected_expr:           ^ast.Expr, // For expression extraction
	expr_type_str:           string, // Type of the selected expression
	variables:               map[string]VariableUsage,
	has_control_flow:        bool,
	control_flow_type:       ControlFlowType,
	has_defer:               bool,
	has_loop:                bool,
}

ParamInfo :: struct {
	name:        string,
	pass_addr:   bool, // Add & at call site, need deref in extracted code
	needs_deref: bool, // Already a pointer, need deref in extracted code but no & at call site
	type_str:    string,
}

ReturnInfo :: struct {
	name:     string,
	type_str: string,
}

@(private = "package")
add_extract_proc_action :: proc(
	document: ^Document,
	ast_context: ^AstContext,
	range: common.Range,
	uri: string,
	actions: ^[dynamic]CodeAction,
) {
	if !is_valid_selection(range) {
		return
	}

	ctx, ok := create_extract_context(document, ast_context, range)
	if !ok {
		return
	}
	defer destroy_extract_context(&ctx)

	if ctx.containing_proc == nil {
		return
	}

	// Must have either selected statements or a selected expression
	if len(ctx.selected_stmts) == 0 && ctx.selected_expr == nil {
		return
	}

	if ctx.has_defer {
		return
	}

	analyze_variables(&ctx)

	edit, edit_ok := generate_extract_edit(&ctx, uri, range)
	if !edit_ok {
		return
	}

	append(
		actions,
		CodeAction {
			kind = EXTRACT_PROC_ACTION_KIND,
			isPreferred = false,
			title = EXTRACT_PROC_ACTION_TITLE,
			edit = edit,
		},
	)
}

is_valid_selection :: proc(range: common.Range) -> bool {
	if range.start.line == range.end.line && range.start.character == range.end.character {
		return false
	}
	return true
}

create_extract_context :: proc(
	document: ^Document,
	ast_context: ^AstContext,
	range: common.Range,
) -> (
	ExtractProcContext,
	bool,
) {
	ctx := ExtractProcContext {
		variables         = make(map[string]VariableUsage, context.temp_allocator),
		selected_stmts    = make([dynamic]^ast.Stmt, context.temp_allocator),
		inference_context = make_inference_context(document, ast_context, context.temp_allocator),
	}

	start_pos, start_ok := common.get_absolute_position(range.start, document.text)
	end_pos, end_ok := common.get_absolute_position(range.end, document.text)
	if !start_ok || !end_ok {
		return ctx, false
	}

	ctx.selection_start = start_pos
	ctx.selection_end = end_pos

	ctx.containing_proc = find_containing_proc(document.ast.decls[:], ctx.selection_start)
	if ctx.containing_proc == nil {
		return ctx, false
	}

	collect_selected_statements(&ctx)

	// If no statements selected, try to find a selected expression
	if len(ctx.selected_stmts) == 0 {
		find_selected_expression(&ctx)
	}

	return ctx, len(ctx.selected_stmts) > 0 || ctx.selected_expr != nil
}

destroy_extract_context :: proc(ctx: ^ExtractProcContext) {
	delete(ctx.variables)
	delete(ctx.selected_stmts)
}

// Finds the top-level declaration (at package scope) that contains the given procedure.
// This is used to determine where to insert extracted procedures - they should be placed
// after the top-level declaration, not inside nested scopes.
find_top_level_decl :: proc(decls: []^ast.Stmt, target_proc: ^ast.Proc_Lit) -> ^ast.Stmt {
	if target_proc == nil {
		return nil
	}

	for decl in decls {
		if decl == nil {
			continue
		}
		if decl_contains_proc(decl, target_proc) {
			return decl
		}
	}
	return nil
}

// Checks if a declaration statement contains the given procedure literal.
decl_contains_proc :: proc(stmt: ^ast.Stmt, target_proc: ^ast.Proc_Lit) -> bool {
	if stmt == nil || target_proc == nil {
		return false
	}

	#partial switch n in stmt.derived {
	case ^ast.Value_Decl:
		for value in n.values {
			if value == target_proc {
				return true
			}
			if expr_contains_proc(value, target_proc) {
				return true
			}
		}
	}

	return false
}

// Recursively checks if an expression contains the target procedure.
// This handles nested procedure definitions (procedures defined inside other procedures).
expr_contains_proc :: proc(expr: ^ast.Expr, target_proc: ^ast.Proc_Lit) -> bool {
	if expr == nil || target_proc == nil {
		return false
	}

	if expr == target_proc {
		return true
	}

	#partial switch n in expr.derived {
	case ^ast.Proc_Lit:
		if n == target_proc {
			return true
		}
		// Check inside proc body for nested procedures
		if n.body != nil {
			if block, ok := n.body.derived.(^ast.Block_Stmt); ok {
				for stmt in block.stmts {
					if decl_contains_proc(stmt, target_proc) {
						return true
					}
				}
			}
		}
	}

	return false
}

find_containing_proc :: proc(stmts: []^ast.Stmt, position: common.AbsolutePosition) -> ^ast.Proc_Lit {
	for stmt in stmts {
		if stmt == nil {
			continue
		}
		if result := find_proc_in_node(stmt, position); result != nil {
			return result
		}
	}
	return nil
}

find_proc_in_node :: proc(node: ^ast.Node, position: common.AbsolutePosition) -> ^ast.Proc_Lit {
	if node == nil {
		return nil
	}

	if !position_in_node(node, position) {
		return nil
	}

	#partial switch n in node.derived {
	case ^ast.Value_Decl:
		for value in n.values {
			if result := find_proc_in_node(value, position); result != nil {
				return result
			}
		}

	case ^ast.Proc_Lit:
		if n.body != nil {
			if block, ok := n.body.derived.(^ast.Block_Stmt); ok {
				if nested := find_proc_in_block(block, position); nested != nil {
					return nested
				}
			}
		}
		return n

	case ^ast.Block_Stmt:
		return find_proc_in_block(n, position)
	}

	return nil
}

find_proc_in_block :: proc(block: ^ast.Block_Stmt, position: common.AbsolutePosition) -> ^ast.Proc_Lit {
	if block == nil {
		return nil
	}

	for stmt in block.stmts {
		if result := find_proc_in_node(stmt, position); result != nil {
			return result
		}
	}
	return nil
}

collect_selected_statements :: proc(ctx: ^ExtractProcContext) {
	if ctx.containing_proc == nil || ctx.containing_proc.body == nil {
		return
	}

	body, ok := ctx.containing_proc.body.derived.(^ast.Block_Stmt)
	if !ok {
		return
	}

	collect_stmts_in_range(body.stmts, ctx)
}

collect_stmts_in_range :: proc(stmts: []^ast.Stmt, ctx: ^ExtractProcContext) {
	for stmt in stmts {
		if stmt == nil {
			continue
		}

		if is_statement_in_selection(stmt, ctx) {
			append(&ctx.selected_stmts, stmt)
			check_statement_properties(stmt, ctx)
		} else if stmt.pos.offset < ctx.selection_end && stmt.end.offset > ctx.selection_start {
			collect_stmts_in_nested_blocks(stmt, ctx)
		}
	}
}

is_statement_in_selection :: proc(stmt: ^ast.Stmt, ctx: ^ExtractProcContext) -> bool {
	return stmt.pos.offset >= ctx.selection_start && stmt.end.offset <= ctx.selection_end
}

collect_stmts_in_nested_blocks :: proc(stmt: ^ast.Stmt, ctx: ^ExtractProcContext) {
	#partial switch n in stmt.derived {
	case ^ast.Block_Stmt:
		collect_stmts_in_range(n.stmts, ctx)
	case ^ast.If_Stmt:
		if n.body != nil {
			if block, ok := n.body.derived.(^ast.Block_Stmt); ok {
				collect_stmts_in_range(block.stmts, ctx)
			}
		}
		if n.else_stmt != nil {
			collect_stmts_in_nested_blocks(n.else_stmt, ctx)
		}
	case ^ast.For_Stmt:
		if n.body != nil {
			if block, ok := n.body.derived.(^ast.Block_Stmt); ok {
				collect_stmts_in_range(block.stmts, ctx)
			}
		}
	case ^ast.Range_Stmt:
		if n.body != nil {
			if block, ok := n.body.derived.(^ast.Block_Stmt); ok {
				collect_stmts_in_range(block.stmts, ctx)
			}
		}
	}
}

// Find an expression that matches the selection exactly
// This enables extracting expressions (not just statements) into procedures
find_selected_expression :: proc(ctx: ^ExtractProcContext) {
	if ctx.containing_proc == nil || ctx.containing_proc.body == nil {
		return
	}

	body, ok := ctx.containing_proc.body.derived.(^ast.Block_Stmt)
	if !ok {
		return
	}

	// Search for an expression that matches the selection
	ctx.selected_expr = find_expr_in_stmts(body.stmts[:], ctx)
	if ctx.selected_expr != nil {
		ctx.expr_type_str = infer_expr_type(&ctx.inference_context, ctx.selected_expr)
	}
}

// Recursively search for an expression matching the selection in statements
find_expr_in_stmts :: proc(stmts: []^ast.Stmt, ctx: ^ExtractProcContext) -> ^ast.Expr {
	for stmt in stmts {
		if stmt == nil {
			continue
		}
		// Only search in statements that overlap with the selection
		if stmt.end.offset < ctx.selection_start || stmt.pos.offset > ctx.selection_end {
			continue
		}
		if expr := find_expr_in_stmt(stmt, ctx); expr != nil {
			return expr
		}
	}
	return nil
}

// Search for matching expression within a statement
find_expr_in_stmt :: proc(stmt: ^ast.Stmt, ctx: ^ExtractProcContext) -> ^ast.Expr {
	if stmt == nil {
		return nil
	}

	#partial switch n in stmt.derived {
	case ^ast.If_Stmt:
		// Check the condition expression
		if expr := find_matching_expr(n.cond, ctx); expr != nil {
			return expr
		}
		// Check body and else
		if n.body != nil {
			if block, ok := n.body.derived.(^ast.Block_Stmt); ok {
				if expr := find_expr_in_stmts(block.stmts[:], ctx); expr != nil {
					return expr
				}
			}
		}
		if n.else_stmt != nil {
			if expr := find_expr_in_stmt(n.else_stmt, ctx); expr != nil {
				return expr
			}
		}
	case ^ast.For_Stmt:
		if expr := find_matching_expr(n.cond, ctx); expr != nil {
			return expr
		}
		if n.body != nil {
			if block, ok := n.body.derived.(^ast.Block_Stmt); ok {
				if expr := find_expr_in_stmts(block.stmts[:], ctx); expr != nil {
					return expr
				}
			}
		}
	case ^ast.Range_Stmt:
		if expr := find_matching_expr(n.expr, ctx); expr != nil {
			return expr
		}
		if n.body != nil {
			if block, ok := n.body.derived.(^ast.Block_Stmt); ok {
				if expr := find_expr_in_stmts(block.stmts[:], ctx); expr != nil {
					return expr
				}
			}
		}
	case ^ast.Value_Decl:
		for value in n.values {
			if expr := find_matching_expr(value, ctx); expr != nil {
				return expr
			}
		}
	case ^ast.Assign_Stmt:
		for rhs in n.rhs {
			if expr := find_matching_expr(rhs, ctx); expr != nil {
				return expr
			}
		}
		for lhs in n.lhs {
			if expr := find_matching_expr(lhs, ctx); expr != nil {
				return expr
			}
		}
	case ^ast.Expr_Stmt:
		if expr := find_matching_expr(n.expr, ctx); expr != nil {
			return expr
		}
	case ^ast.Return_Stmt:
		for result in n.results {
			if expr := find_matching_expr(result, ctx); expr != nil {
				return expr
			}
		}
	case ^ast.Switch_Stmt:
		if expr := find_matching_expr(n.cond, ctx); expr != nil {
			return expr
		}
		if n.body != nil {
			if block, ok := n.body.derived.(^ast.Block_Stmt); ok {
				if expr := find_expr_in_stmts(block.stmts[:], ctx); expr != nil {
					return expr
				}
			}
		}
	case ^ast.Block_Stmt:
		if expr := find_expr_in_stmts(n.stmts[:], ctx); expr != nil {
			return expr
		}
	case ^ast.Case_Clause:
		if expr := find_expr_in_stmts(n.body[:], ctx); expr != nil {
			return expr
		}
	}

	return nil
}

// Check if an expression matches the selection, or search inside it
find_matching_expr :: proc(expr: ^ast.Expr, ctx: ^ExtractProcContext) -> ^ast.Expr {
	if expr == nil {
		return nil
	}

	// Check if this expression exactly matches the selection
	if expr.pos.offset == ctx.selection_start && expr.end.offset == ctx.selection_end {
		return expr
	}

	// If selection is not within this expression, skip
	if expr.end.offset < ctx.selection_start || expr.pos.offset > ctx.selection_end {
		return nil
	}

	// Search inside compound expressions
	#partial switch n in expr.derived {
	case ^ast.Binary_Expr:
		if result := find_matching_expr(n.left, ctx); result != nil {
			return result
		}
		if result := find_matching_expr(n.right, ctx); result != nil {
			return result
		}
	case ^ast.Unary_Expr:
		if result := find_matching_expr(n.expr, ctx); result != nil {
			return result
		}
	case ^ast.Paren_Expr:
		if result := find_matching_expr(n.expr, ctx); result != nil {
			return result
		}
	case ^ast.Call_Expr:
		if result := find_matching_expr(n.expr, ctx); result != nil {
			return result
		}
		for arg in n.args {
			if result := find_matching_expr(arg, ctx); result != nil {
				return result
			}
		}
	case ^ast.Index_Expr:
		if result := find_matching_expr(n.expr, ctx); result != nil {
			return result
		}
		if result := find_matching_expr(n.index, ctx); result != nil {
			return result
		}
	case ^ast.Selector_Expr:
		if result := find_matching_expr(n.expr, ctx); result != nil {
			return result
		}
	case ^ast.Ternary_If_Expr:
		if result := find_matching_expr(n.cond, ctx); result != nil {
			return result
		}
		if result := find_matching_expr(n.x, ctx); result != nil {
			return result
		}
		if result := find_matching_expr(n.y, ctx); result != nil {
			return result
		}
	case ^ast.Comp_Lit:
		for elem in n.elems {
			if result := find_matching_expr(elem, ctx); result != nil {
				return result
			}
		}
	}

	return nil
}

check_statement_properties :: proc(stmt: ^ast.Stmt, ctx: ^ExtractProcContext) {
	#partial switch n in stmt.derived {
	case ^ast.Return_Stmt:
		ctx.has_control_flow = true
		ctx.control_flow_type = .Return
	case ^ast.Branch_Stmt:
		ctx.has_control_flow = true
		// Only track break/continue if not inside a loop in the selection
		// (if break/continue is inside a loop that's entirely in the selection, it's fine)
		if !ctx.has_loop {
			if n.tok.kind == .Break {
				if ctx.control_flow_type == .Continue {
					ctx.control_flow_type = .BreakAndContinue
				} else if ctx.control_flow_type != .BreakAndContinue {
					ctx.control_flow_type = .Break
				}
			} else if n.tok.kind == .Continue {
				if ctx.control_flow_type == .Break {
					ctx.control_flow_type = .BreakAndContinue
				} else if ctx.control_flow_type != .BreakAndContinue {
					ctx.control_flow_type = .Continue
				}
			}
		}
	case ^ast.Defer_Stmt:
		ctx.has_defer = true
	case ^ast.For_Stmt, ^ast.Range_Stmt:
		// Mark that we have a loop - break/continue inside will be scoped to it
		old_has_loop := ctx.has_loop
		ctx.has_loop = true
		check_nested_control_flow(stmt, ctx)
		ctx.has_loop = old_has_loop
		return
	}

	check_nested_control_flow(stmt, ctx)
}

check_nested_control_flow :: proc(stmt: ^ast.Stmt, ctx: ^ExtractProcContext) {
	if stmt == nil {
		return
	}

	#partial switch n in stmt.derived {
	case ^ast.Block_Stmt:
		for s in n.stmts {
			check_statement_properties(s, ctx)
		}
	case ^ast.If_Stmt:
		if n.body != nil {
			check_statement_properties(n.body, ctx)
		}
		if n.else_stmt != nil {
			check_statement_properties(n.else_stmt, ctx)
		}
	case ^ast.For_Stmt:
		if n.body != nil {
			check_statement_properties(n.body, ctx)
		}
	case ^ast.Range_Stmt:
		if n.body != nil {
			check_statement_properties(n.body, ctx)
		}
	case ^ast.Switch_Stmt:
		// Switch body contains Case_Clauses - recurse into them
		if n.body != nil {
			check_statement_properties(n.body, ctx)
		}
	case ^ast.Type_Switch_Stmt:
		if n.body != nil {
			check_statement_properties(n.body, ctx)
		}
	case ^ast.Case_Clause:
		// Case clauses contain statements
		for s in n.body {
			check_statement_properties(s, ctx)
		}
	}
}

analyze_variables :: proc(ctx: ^ExtractProcContext) {
	find_variables_before_selection(ctx)

	// Handle expression extraction
	if ctx.selected_expr != nil {
		analyze_expression_variables(ctx.selected_expr, ctx)
	} else {
		for stmt in ctx.selected_stmts {
			analyze_statement_variables(stmt, ctx)
		}
	}

	check_variables_used_after(ctx)
}

find_variables_before_selection :: proc(ctx: ^ExtractProcContext) {
	if ctx.containing_proc == nil || ctx.containing_proc.body == nil {
		return
	}

	if ctx.containing_proc.type != nil {
		if proc_type, ok := ctx.containing_proc.type.derived.(^ast.Proc_Type); ok {
			if proc_type.params != nil {
				for field in proc_type.params.list {
					for name in field.names {
						if ident, ok := name.derived.(^ast.Ident); ok {
							usage := VariableUsage {
								name       = ident.name,
								type_expr  = field.type,
								is_pointer = is_pointer_type(field.type),
							}
							ctx.variables[ident.name] = usage
							// Store type in InferenceContext
							type_str := get_type_string(field.type)
							if type_str != "" {
								ctx.variable_types[ident.name] = type_str
							}
						}
					}
				}
			}
		}
	}

	body, ok := ctx.containing_proc.body.derived.(^ast.Block_Stmt)
	if !ok {
		return
	}

	collect_variables_in_scope(body.stmts[:], ctx)
}

// Recursively collect variables that are in scope at the selection
// This handles variables declared before the selection and in containing structures
collect_variables_in_scope :: proc(stmts: []^ast.Stmt, ctx: ^ExtractProcContext) {
	for stmt in stmts {
		if stmt == nil {
			continue
		}

		// If the statement ends before selection starts, collect its declarations
		if stmt.end.offset <= ctx.selection_start {
			collect_declared_variables(stmt, ctx)
			continue
		}

		// If the statement starts after selection, we're done
		if stmt.pos.offset >= ctx.selection_start {
			break
		}

		// The statement contains the selection - look inside for variable declarations
		// that would be in scope (e.g., for loop init)
		collect_containing_scope_variables(stmt, ctx)
	}
}

// Collect variables from containing structures (for loops, etc.) that are in scope
collect_containing_scope_variables :: proc(stmt: ^ast.Stmt, ctx: ^ExtractProcContext) {
	#partial switch n in stmt.derived {
	case ^ast.For_Stmt:
		// Collect for-loop init variables (e.g., for i := 0; ...)
		if n.init != nil {
			collect_declared_variables(n.init, ctx)
		}
		// Recurse into body to find more containing structures
		if n.body != nil {
			if block, ok := n.body.derived.(^ast.Block_Stmt); ok {
				collect_variables_in_scope(block.stmts[:], ctx)
			}
		}
	case ^ast.Range_Stmt:
		// Collect range loop variables
		// Semantics depend on container type:
		// - Arrays/slices: for value, index in arr (first=value, second=index:int)
		// - Maps: for key, value in map (first=key, second=value)
		// - Strings: for char in str (char is rune)
		container_type := ""
		if n.expr != nil {
			container_type = infer_expr_type(&ctx.inference_context, n.expr)
		}

		is_map := strings.has_prefix(container_type, "map[")
		is_string := container_type == "string"

		for val, idx in n.vals {
			if val != nil {
				// Check for &val (address-of for by-reference iteration)
				is_by_ref := false
				var_name := ""

				if ident, ok := val.derived.(^ast.Ident); ok {
					var_name = ident.name
				} else if unary, ok := val.derived.(^ast.Unary_Expr); ok {
					if unary.op.kind == .And {
						if ident, ident_ok := unary.expr.derived.(^ast.Ident); ident_ok {
							var_name = ident.name
							is_by_ref = true
						}
					}
				}

				if var_name != "" {
					type_str := ""

					if is_map {
						// Map: first var is key, second is value
						if idx == 0 {
							type_str = extract_map_key_type(container_type)
						} else {
							type_str = extract_element_type(container_type)
						}
					} else if is_string {
						// String: loop variable is rune
						if idx == 0 {
							type_str = "rune"
						} else {
							// Second variable is byte index (int)
							type_str = "int"
						}
					} else {
						// Array/slice: first var is value, second is index (int)
						if len(n.vals) == 1 {
							// Single variable - it's the value
							type_str = extract_element_type(container_type)
						} else if idx == 0 {
							// First of two variables - it's the value
							type_str = extract_element_type(container_type)
						} else {
							// Second variable - it's the index
							type_str = "int"
						}
					}

					// If it's a by-reference variable, it's already a pointer
					if is_by_ref && type_str != "" {
						type_str = strings.concatenate({"^", type_str}, context.temp_allocator)
					}

					usage := VariableUsage {
						name       = var_name,
						is_pointer = is_by_ref,
					}
					ctx.variables[var_name] = usage
					// Store type in InferenceContext
					if type_str != "" {
						ctx.variable_types[var_name] = type_str
					}
				}
			}
		}
		// Recurse into body
		if n.body != nil {
			if block, ok := n.body.derived.(^ast.Block_Stmt); ok {
				collect_variables_in_scope(block.stmts[:], ctx)
			}
		}
	case ^ast.If_Stmt:
		// If statements can have init (if x := foo(); x != nil)
		if n.init != nil {
			collect_declared_variables(n.init, ctx)
		}
		// Check which branch contains the selection
		if n.body != nil && n.body.pos.offset <= ctx.selection_start && ctx.selection_start < n.body.end.offset {
			if block, ok := n.body.derived.(^ast.Block_Stmt); ok {
				collect_variables_in_scope(block.stmts[:], ctx)
			}
		}
		if n.else_stmt != nil &&
		   n.else_stmt.pos.offset <= ctx.selection_start &&
		   ctx.selection_start < n.else_stmt.end.offset {
			collect_containing_scope_variables(n.else_stmt, ctx)
		}
	case ^ast.Block_Stmt:
		collect_variables_in_scope(n.stmts[:], ctx)
	case ^ast.Switch_Stmt:
		if n.init != nil {
			collect_declared_variables(n.init, ctx)
		}
		if n.body != nil {
			if block, ok := n.body.derived.(^ast.Block_Stmt); ok {
				collect_variables_in_scope(block.stmts[:], ctx)
			}
		}
	case ^ast.Type_Switch_Stmt:
		if n.tag != nil {
			collect_declared_variables(n.tag, ctx)
		}
		if n.body != nil {
			if block, ok := n.body.derived.(^ast.Block_Stmt); ok {
				collect_variables_in_scope(block.stmts[:], ctx)
			}
		}
	case ^ast.Case_Clause:
		// Case clauses themselves don't declare variables, but their body might contain the selection
		for s in n.body {
			if s != nil && s.pos.offset <= ctx.selection_start && ctx.selection_start < s.end.offset {
				collect_containing_scope_variables(s, ctx)
			}
		}
	}
}

collect_declared_variables :: proc(stmt: ^ast.Stmt, ctx: ^ExtractProcContext) {
	#partial switch n in stmt.derived {
	case ^ast.Value_Decl:
		for name, i in n.names {
			if ident, ok := name.derived.(^ast.Ident); ok {
				type_expr := n.type
				type_str := get_type_string(type_expr)
				// If no explicit type, try to infer from value
				if type_str == "" && i < len(n.values) {
					type_str = infer_expr_type(&ctx.inference_context, n.values[i])
				}
				usage := VariableUsage {
					name       = ident.name,
					type_expr  = type_expr,
					is_pointer = is_pointer_type(type_expr),
				}
				ctx.variables[ident.name] = usage
				// Store type in InferenceContext
				if type_str != "" {
					ctx.variable_types[ident.name] = type_str
				}
			}
		}
	case ^ast.Assign_Stmt:
		if n.op.text == ":=" {
			for lhs, i in n.lhs {
				if ident, ok := lhs.derived.(^ast.Ident); ok {
					type_str := ""
					if i < len(n.rhs) {
						type_str = infer_expr_type(&ctx.inference_context, n.rhs[i])
					}
					usage := VariableUsage {
						name = ident.name,
					}
					ctx.variables[ident.name] = usage
					// Store type in InferenceContext
					if type_str != "" {
						ctx.variable_types[ident.name] = type_str
					}
				}
			}
		}
	}
}

// Analyze variables used in a selected expression
// For expression extraction, all variables are reads (no declarations or modifications)
analyze_expression_variables :: proc(expr: ^ast.Expr, ctx: ^ExtractProcContext) {
	analyze_expr_reads(expr, ctx)
}

analyze_statement_variables :: proc(stmt: ^ast.Stmt, ctx: ^ExtractProcContext) {
	if stmt == nil {
		return
	}

	#partial switch n in stmt.derived {
	case ^ast.Value_Decl:
		analyze_value_decl(n, ctx)
	case ^ast.Assign_Stmt:
		analyze_assign_stmt(n, ctx)
	case ^ast.Expr_Stmt:
		if n.expr != nil {
			analyze_expr_reads(n.expr, ctx)
		}
	case ^ast.Return_Stmt:
		for result in n.results {
			analyze_expr_reads(result, ctx)
		}
	case ^ast.If_Stmt:
		if n.cond != nil {
			analyze_expr_reads(n.cond, ctx)
		}
		if n.body != nil {
			analyze_statement_variables(n.body, ctx)
		}
		if n.else_stmt != nil {
			analyze_statement_variables(n.else_stmt, ctx)
		}
	case ^ast.For_Stmt:
		// Mark loop init variables as declared (they are loop-scoped)
		if n.init != nil {
			mark_loop_variables_declared(n.init, ctx)
		}
		if n.cond != nil {
			analyze_expr_reads(n.cond, ctx)
		}
		if n.body != nil {
			analyze_statement_variables(n.body, ctx)
		}
	case ^ast.Range_Stmt:
		// Mark range loop variables as declared (they are loop-scoped)
		for val in n.vals {
			if val != nil {
				if ident, ok := val.derived.(^ast.Ident); ok {
					usage := ctx.variables[ident.name]
					usage.name = ident.name
					usage.is_declared = true
					ctx.variables[ident.name] = usage
				}
			}
		}
		// Iterating over a fixed array creates references, so mark it as modified
		// to ensure it's passed by pointer
		if n.expr != nil {
			if ident, ok := n.expr.derived.(^ast.Ident); ok {
				if !is_builtin_identifier(ident.name) {
					usage := ctx.variables[ident.name]
					usage.name = ident.name
					usage.is_modified = true // Mark as modified so it's passed by pointer
					usage.is_read = true
					ctx.variables[ident.name] = usage
				}
			} else {
				analyze_expr_reads(n.expr, ctx)
			}
		}
		if n.body != nil {
			analyze_statement_variables(n.body, ctx)
		}
	case ^ast.Block_Stmt:
		for s in n.stmts {
			analyze_statement_variables(s, ctx)
		}
	case ^ast.Switch_Stmt:
		if n.init != nil {
			analyze_statement_variables(n.init, ctx)
		}
		if n.cond != nil {
			analyze_expr_reads(n.cond, ctx)
		}
		if n.body != nil {
			analyze_statement_variables(n.body, ctx)
		}
	case ^ast.Type_Switch_Stmt:
		if n.tag != nil {
			analyze_statement_variables(n.tag, ctx)
		}
		if n.body != nil {
			analyze_statement_variables(n.body, ctx)
		}
	case ^ast.Case_Clause:
		for expr in n.list {
			analyze_expr_reads(expr, ctx)
		}
		for s in n.body {
			analyze_statement_variables(s, ctx)
		}
	case ^ast.Defer_Stmt:
		if n.stmt != nil {
			analyze_statement_variables(n.stmt, ctx)
		}
	}
}

analyze_value_decl :: proc(decl: ^ast.Value_Decl, ctx: ^ExtractProcContext) {
	for name, i in decl.names {
		if ident, ok := name.derived.(^ast.Ident); ok {
			usage := ctx.variables[ident.name]
			usage.name = ident.name
			usage.is_declared = true
			usage.type_expr = decl.type
			usage.is_pointer = is_pointer_type(decl.type)
			// Set type string if not already set
			if ident.name not_in ctx.variable_types {
				type_str := get_type_string(decl.type)
				if type_str == "" && i < len(decl.values) {
					type_str = infer_expr_type(&ctx.inference_context, decl.values[i])
				}
				if type_str != "" {
					ctx.variable_types[ident.name] = type_str
				}
			}
			// Track if this is assigned from &x
			if i < len(decl.values) {
				if unary, unary_ok := decl.values[i].derived.(^ast.Unary_Expr); unary_ok {
					if unary.op.kind == .And {
						if src_ident, src_ok := unary.expr.derived.(^ast.Ident); src_ok {
							usage.addr_of_source = src_ident.name
						}
					}
				}
			}
			ctx.variables[ident.name] = usage
		}
	}

	for value in decl.values {
		analyze_expr_reads(value, ctx)
	}
}

analyze_assign_stmt :: proc(stmt: ^ast.Assign_Stmt, ctx: ^ExtractProcContext) {
	is_declaration := stmt.op.text == ":="

	for lhs, i in stmt.lhs {
		if ident, ok := lhs.derived.(^ast.Ident); ok {
			usage := ctx.variables[ident.name]
			usage.name = ident.name
			if is_declaration {
				usage.is_declared = true
				// Set type string from RHS if declaring and not already known
				if ident.name not_in ctx.variable_types && i < len(stmt.rhs) {
					type_str := infer_expr_type(&ctx.inference_context, stmt.rhs[i])
					if type_str != "" {
						ctx.variable_types[ident.name] = type_str
					}
				}
				// Track if this is assigned from &x
				if i < len(stmt.rhs) {
					if unary, unary_ok := stmt.rhs[i].derived.(^ast.Unary_Expr); unary_ok {
						if unary.op.kind == .And {
							if src_ident, src_ok := unary.expr.derived.(^ast.Ident); src_ok {
								usage.addr_of_source = src_ident.name
							}
						}
					}
				}
			} else {
				usage.is_modified = true
			}
			ctx.variables[ident.name] = usage
		} else {
			analyze_lhs_modification(lhs, ctx)
		}
	}

	for rhs in stmt.rhs {
		analyze_expr_reads(rhs, ctx)
	}
}

analyze_lhs_modification :: proc(expr: ^ast.Expr, ctx: ^ExtractProcContext) {
	if expr == nil {
		return
	}

	#partial switch n in expr.derived {
	case ^ast.Selector_Expr:
		if ident, ok := get_root_ident(n.expr); ok {
			usage := ctx.variables[ident.name]
			usage.name = ident.name
			usage.is_modified = true
			ctx.variables[ident.name] = usage
		}
	case ^ast.Index_Expr:
		if ident, ok := get_root_ident(n.expr); ok {
			usage := ctx.variables[ident.name]
			usage.name = ident.name
			usage.is_modified = true
			ctx.variables[ident.name] = usage
		}
	case ^ast.Deref_Expr:
		if ident, ok := get_root_ident(n.expr); ok {
			usage := ctx.variables[ident.name]
			usage.name = ident.name
			usage.is_read = true
			ctx.variables[ident.name] = usage
		}
	case ^ast.Unary_Expr:
		if ident, ok := get_root_ident(n.expr); ok {
			usage := ctx.variables[ident.name]
			usage.name = ident.name
			ctx.variables[ident.name] = usage
		}
	}
}

get_root_ident :: proc(expr: ^ast.Expr) -> (^ast.Ident, bool) {
	if expr == nil {
		return nil, false
	}

	#partial switch n in expr.derived {
	case ^ast.Ident:
		return n, true
	case ^ast.Selector_Expr:
		return get_root_ident(n.expr)
	case ^ast.Index_Expr:
		return get_root_ident(n.expr)
	case ^ast.Unary_Expr:
		return get_root_ident(n.expr)
	case ^ast.Deref_Expr:
		return get_root_ident(n.expr)
	}

	return nil, false
}

// Mark variables declared in for-loop init statements as loop-scoped
mark_loop_variables_declared :: proc(init_stmt: ^ast.Stmt, ctx: ^ExtractProcContext) {
	if init_stmt == nil {
		return
	}

	#partial switch n in init_stmt.derived {
	case ^ast.Assign_Stmt:
		if n.op.text == ":=" {
			for lhs in n.lhs {
				if ident, ok := lhs.derived.(^ast.Ident); ok {
					usage := ctx.variables[ident.name]
					usage.name = ident.name
					usage.is_declared = true
					ctx.variables[ident.name] = usage
				}
			}
		}
	case ^ast.Value_Decl:
		for name in n.names {
			if ident, ok := name.derived.(^ast.Ident); ok {
				usage := ctx.variables[ident.name]
				usage.name = ident.name
				usage.is_declared = true
				ctx.variables[ident.name] = usage
			}
		}
	}
}

analyze_expr_reads :: proc(expr: ^ast.Expr, ctx: ^ExtractProcContext) {
	if expr == nil {
		return
	}

	#partial switch n in expr.derived {
	case ^ast.Ident:
		if is_builtin_identifier(n.name) {
			return
		}
		usage := ctx.variables[n.name]
		usage.name = n.name
		usage.is_read = true
		ctx.variables[n.name] = usage

	case ^ast.Binary_Expr:
		analyze_expr_reads(n.left, ctx)
		analyze_expr_reads(n.right, ctx)

	case ^ast.Unary_Expr:
		// For address-of operator, just mark as read (we're reading the value to get its address)
		analyze_expr_reads(n.expr, ctx)

	case ^ast.Deref_Expr:
		analyze_expr_reads(n.expr, ctx)

	case ^ast.Call_Expr:
		for arg in n.args {
			analyze_expr_reads(arg, ctx)
		}

	case ^ast.Selector_Expr:
		analyze_expr_reads(n.expr, ctx)

	case ^ast.Index_Expr:
		analyze_expr_reads(n.expr, ctx)
		analyze_expr_reads(n.index, ctx)

	case ^ast.Slice_Expr:
		// Slicing reads the underlying array/slice - and for arrays, creates a slice
		// which means the variable should be passed by pointer
		if ident, ok := get_root_ident(n.expr); ok {
			usage := ctx.variables[ident.name]
			usage.name = ident.name
			usage.is_modified = true // Mark as modified since slicing an array creates a reference
			ctx.variables[ident.name] = usage
		}
		analyze_expr_reads(n.expr, ctx)
		if n.low != nil {
			analyze_expr_reads(n.low, ctx)
		}
		if n.high != nil {
			analyze_expr_reads(n.high, ctx)
		}

	case ^ast.Comp_Lit:
		for elem in n.elems {
			analyze_expr_reads(elem, ctx)
		}

	case ^ast.Field_Value:
		analyze_expr_reads(n.value, ctx)

	case ^ast.Paren_Expr:
		analyze_expr_reads(n.expr, ctx)

	case ^ast.Ternary_If_Expr:
		analyze_expr_reads(n.cond, ctx)
		analyze_expr_reads(n.x, ctx)
		analyze_expr_reads(n.y, ctx)
	}
}

check_variables_used_after :: proc(ctx: ^ExtractProcContext) {
	if ctx.containing_proc == nil || ctx.containing_proc.body == nil {
		return
	}

	body, ok := ctx.containing_proc.body.derived.(^ast.Block_Stmt)
	if !ok {
		return
	}

	for stmt in body.stmts {
		if stmt == nil || stmt.pos.offset <= ctx.selection_end {
			continue
		}
		check_stmt_uses_variables(stmt, ctx)
	}
}

check_stmt_uses_variables :: proc(stmt: ^ast.Stmt, ctx: ^ExtractProcContext) {
	if stmt == nil {
		return
	}

	#partial switch n in stmt.derived {
	case ^ast.Expr_Stmt:
		if n.expr != nil {
			check_expr_uses_variables(n.expr, ctx)
		}
	case ^ast.Value_Decl:
		for value in n.values {
			check_expr_uses_variables(value, ctx)
		}
	case ^ast.Assign_Stmt:
		for rhs in n.rhs {
			check_expr_uses_variables(rhs, ctx)
		}
	case ^ast.Return_Stmt:
		for result in n.results {
			check_expr_uses_variables(result, ctx)
		}
	case ^ast.If_Stmt:
		if n.cond != nil {
			check_expr_uses_variables(n.cond, ctx)
		}
		if n.body != nil {
			check_stmt_uses_variables(n.body, ctx)
		}
		if n.else_stmt != nil {
			check_stmt_uses_variables(n.else_stmt, ctx)
		}
	case ^ast.For_Stmt:
		if n.cond != nil {
			check_expr_uses_variables(n.cond, ctx)
		}
		if n.body != nil {
			check_stmt_uses_variables(n.body, ctx)
		}
	case ^ast.Range_Stmt:
		if n.expr != nil {
			check_expr_uses_variables(n.expr, ctx)
		}
		if n.body != nil {
			check_stmt_uses_variables(n.body, ctx)
		}
	case ^ast.Block_Stmt:
		for s in n.stmts {
			check_stmt_uses_variables(s, ctx)
		}
	}
}

check_expr_uses_variables :: proc(expr: ^ast.Expr, ctx: ^ExtractProcContext) {
	if expr == nil {
		return
	}

	#partial switch n in expr.derived {
	case ^ast.Ident:
		if usage, ok := &ctx.variables[n.name]; ok {
			if usage.is_declared {
				usage.is_used_after = true
			}
		}

	case ^ast.Binary_Expr:
		check_expr_uses_variables(n.left, ctx)
		check_expr_uses_variables(n.right, ctx)

	case ^ast.Unary_Expr:
		check_expr_uses_variables(n.expr, ctx)

	case ^ast.Call_Expr:
		check_expr_uses_variables(n.expr, ctx)
		for arg in n.args {
			check_expr_uses_variables(arg, ctx)
		}

	case ^ast.Selector_Expr:
		check_expr_uses_variables(n.expr, ctx)

	case ^ast.Index_Expr:
		check_expr_uses_variables(n.expr, ctx)
		check_expr_uses_variables(n.index, ctx)

	case ^ast.Paren_Expr:
		check_expr_uses_variables(n.expr, ctx)

	case ^ast.Deref_Expr:
		check_expr_uses_variables(n.expr, ctx)
	}
}


is_builtin_identifier :: proc(name: string) -> bool {
	if name in keyword_map {
		return true
	}

	switch name {
	case "len",
	     "cap",
	     "size_of",
	     "align_of",
	     "offset_of",
	     "type_of",
	     "type_info_of",
	     "typeid_of",
	     "swizzle",
	     "complex",
	     "quaternion",
	     "real",
	     "imag",
	     "jmag",
	     "kmag",
	     "conj",
	     "expand_values",
	     "min",
	     "max",
	     "abs",
	     "clamp",
	     "soa_zip",
	     "soa_unzip":
		return true
	case "new",
	     "new_clone",
	     "free",
	     "free_all",
	     "delete",
	     "make",
	     "clear",
	     "reserve",
	     "resize",
	     "append",
	     "append_elems",
	     "pop",
	     "inject_at",
	     "assign_at",
	     "pop_front",
	     "unordered_remove",
	     "ordered_remove":
		return true
	case "transmute", "auto_cast", "cast":
		return true
	case "context", "raw_data", "card", "assert", "panic", "unreachable":
		return true
	}

	return false
}

generate_extract_edit :: proc(
	ctx: ^ExtractProcContext,
	uri: string,
	selection_range: common.Range,
) -> (
	WorkspaceEdit,
	bool,
) {
	src := ctx.document.ast.src

	params := build_parameter_list(ctx)
	returns := build_return_list(ctx)

	// If a returned variable was assigned from &x where x is a parameter,
	// mark x as needing pass-by-pointer so the returned pointer is valid
	for ret in returns {
		if usage, ok := ctx.variables[ret.name]; ok {
			if usage.addr_of_source != "" {
				// Find the source parameter and mark it as pass_addr
				for &param in params {
					if param.name == usage.addr_of_source {
						param.pass_addr = true
						break
					}
				}
			}
		}
	}

	// Get the indentation of the selection
	indent := get_line_indentation(src, int(ctx.selection_start))

	call_text := build_call_text(ctx, params, returns, indent)
	proc_text := build_proc_definition(ctx, params, returns)

	// Find the top-level declaration containing the procedure and insert after it
	// This ensures extracted procedures are placed at package scope, not inside nested procedures
	insert_range: common.Range
	top_level_decl := find_top_level_decl(ctx.document.ast.decls[:], ctx.containing_proc)
	if top_level_decl != nil {
		insert_pos := common.token_pos_to_position(top_level_decl.end, src)
		// Move to the start of the next line (after the closing brace)
		insert_pos.line += 1
		insert_pos.character = 0
		insert_range = common.Range {
			start = insert_pos,
			end   = insert_pos,
		}
	} else {
		// Fallback: insert after the containing procedure
		proc_end_pos := common.token_pos_to_position(ctx.containing_proc.end, src)
		proc_end_pos.line += 1
		proc_end_pos.character = 0
		insert_range = common.Range {
			start = proc_end_pos,
			end   = proc_end_pos,
		}
	}

	textEdits := make([dynamic]TextEdit, context.temp_allocator)
	append(&textEdits, TextEdit{range = selection_range, newText = call_text})
	append(&textEdits, TextEdit{range = insert_range, newText = proc_text})

	workspaceEdit: WorkspaceEdit
	workspaceEdit.changes = make(map[string][]TextEdit, 0, context.temp_allocator)
	workspaceEdit.changes[uri] = textEdits[:]

	return workspaceEdit, true
}

build_parameter_list :: proc(ctx: ^ExtractProcContext) -> [dynamic]ParamInfo {
	params := make([dynamic]ParamInfo, context.temp_allocator)

	for name, usage in ctx.variables {
		if usage.is_declared {
			continue
		}

		if !usage.is_read && !usage.is_modified {
			continue
		}

		type_str := ctx.variable_types[name] or_else "untyped"
		param := ParamInfo {
			name     = name,
			type_str = type_str,
		}

		if usage.is_modified && !usage.is_pointer {
			param.pass_addr = true
		}

		// If variable is already a pointer (e.g., from &val in range loop)
		// and it's modified, we need to dereference in the extracted code
		// but not add & at the call site
		if usage.is_modified && usage.is_pointer {
			param.needs_deref = true
		}

		// Pass fixed-size arrays by pointer to avoid copying
		if is_fixed_array_type(param.type_str) && !usage.is_pointer {
			param.pass_addr = true
		}

		append(&params, param)
	}

	slice.sort_by(params[:], proc(a, b: ParamInfo) -> bool {
		return a.name < b.name
	})

	return params
}

build_return_list :: proc(ctx: ^ExtractProcContext) -> [dynamic]ReturnInfo {
	returns := make([dynamic]ReturnInfo, context.temp_allocator)

	for name, usage in ctx.variables {
		if usage.is_declared && usage.is_used_after {
			type_str := ctx.variable_types[name] or_else "untyped"
			ret := ReturnInfo {
				name     = name,
				type_str = type_str,
			}
			append(&returns, ret)
		}
	}

	slice.sort_by(returns[:], proc(a, b: ReturnInfo) -> bool {
		return a.name < b.name
	})

	return returns
}

build_proc_definition :: proc(
	ctx: ^ExtractProcContext,
	params: [dynamic]ParamInfo,
	returns: [dynamic]ReturnInfo,
) -> string {
	sb := strings.builder_make(context.temp_allocator)

	// Add newlines before the new procedure
	strings.write_string(&sb, "\n\n")

	// Procedure signature
	strings.write_string(&sb, DEFAULT_PROC_NAME)
	strings.write_string(&sb, " :: proc(")

	// Parameters
	for param, i in params {
		if i > 0 {
			strings.write_string(&sb, ", ")
		}
		strings.write_string(&sb, param.name)
		strings.write_string(&sb, ": ")
		if param.pass_addr {
			strings.write_string(&sb, "^")
		}
		strings.write_string(&sb, param.type_str)
	}

	strings.write_string(&sb, ")")

	// Handle expression extraction - simple return with expression type
	if ctx.selected_expr != nil {
		// Add return type from expression
		if ctx.expr_type_str != "" {
			strings.write_string(&sb, " -> ")
			strings.write_string(&sb, ctx.expr_type_str)
		}
		strings.write_string(&sb, " {\n")
		strings.write_string(&sb, "\treturn ")
		strings.write_string(&sb, string(ctx.document.text[ctx.selection_start:ctx.selection_end]))
		strings.write_string(&sb, "\n}")
		return strings.to_string(sb)
	}

	// Return types - handle control flow types
	has_control_flow_return := ctx.control_flow_type != .None

	// Build return type based on control flow and normal returns
	#partial switch ctx.control_flow_type {
	case .Return, .Break, .Continue:
		// Single bool for control flow + any normal returns
		strings.write_string(&sb, " -> ")
		if len(returns) > 0 {
			strings.write_string(&sb, "(bool")
			for ret in returns {
				strings.write_string(&sb, ", ")
				strings.write_string(&sb, ret.type_str)
			}
			strings.write_string(&sb, ")")
		} else {
			strings.write_string(&sb, "bool")
		}
	case .BreakAndContinue:
		// Two bools for break and continue + any normal returns
		strings.write_string(&sb, " -> ")
		if len(returns) > 0 {
			strings.write_string(&sb, "(bool, bool")
			for ret in returns {
				strings.write_string(&sb, ", ")
				strings.write_string(&sb, ret.type_str)
			}
			strings.write_string(&sb, ")")
		} else {
			strings.write_string(&sb, "(bool, bool)")
		}
	case:
		// No control flow - normal returns only
		if len(returns) > 0 {
			strings.write_string(&sb, " -> ")
			if len(returns) > 1 {
				strings.write_string(&sb, "(")
			}
			for ret, i in returns {
				if i > 0 {
					strings.write_string(&sb, ", ")
				}
				strings.write_string(&sb, ret.type_str)
			}
			if len(returns) > 1 {
				strings.write_string(&sb, ")")
			}
		}
	}

	strings.write_string(&sb, " {\n")

	// Extract the selected code and transform variable references for pointer params
	// Also transform control flow statements
	selected_code := transform_extracted_code(ctx, params, returns)

	// Split into lines and find common indentation
	lines := strings.split(selected_code, "\n", context.temp_allocator)
	common_indent := find_common_indentation(lines)

	// Add each line with normalized indentation
	for line, i in lines {
		if i > 0 {
			strings.write_byte(&sb, '\n')
		}
		// First line: don't strip (selection starts at content, no leading whitespace)
		// Other lines: strip the common indentation from the source
		strings.write_byte(&sb, '\t')
		if i == 0 {
			strings.write_string(&sb, line)
		} else {
			stripped := line
			if len(line) >= common_indent {
				stripped = line[common_indent:]
			}
			strings.write_string(&sb, stripped)
		}
	}

	// Add return statement based on control flow type
	#partial switch ctx.control_flow_type {
	case .Return, .Break, .Continue:
		// Add "return false" at the end (control flow didn't happen)
		if len(returns) > 0 {
			strings.write_string(&sb, "\n\treturn false")
			for ret in returns {
				strings.write_string(&sb, ", ")
				strings.write_string(&sb, ret.name)
			}
		} else {
			strings.write_string(&sb, "\n\treturn false")
		}
	case .BreakAndContinue:
		// Add "return false, false" at the end
		if len(returns) > 0 {
			strings.write_string(&sb, "\n\treturn false, false")
			for ret in returns {
				strings.write_string(&sb, ", ")
				strings.write_string(&sb, ret.name)
			}
		} else {
			strings.write_string(&sb, "\n\treturn false, false")
		}
	case:
		// Normal returns only
		if len(returns) > 0 {
			strings.write_string(&sb, "\n\treturn ")
			for ret, i in returns {
				if i > 0 {
					strings.write_string(&sb, ", ")
				}
				strings.write_string(&sb, ret.name)
			}
		}
	}

	strings.write_string(&sb, "\n}\n")

	return strings.to_string(sb)
}

// Transform the extracted code to handle pointer parameters and control flow
// Variables passed by address need to be dereferenced in the extracted code
// Control flow statements (return, break, continue) are transformed to return true
transform_extracted_code :: proc(
	ctx: ^ExtractProcContext,
	params: [dynamic]ParamInfo,
	returns: [dynamic]ReturnInfo,
) -> string {
	// Build a set of variables that need to be dereferenced
	deref_vars := make(map[string]bool, context.temp_allocator)
	for param in params {
		if param.pass_addr || param.needs_deref {
			deref_vars[param.name] = true
		}
	}

	if len(deref_vars) == 0 && ctx.control_flow_type == .None {
		// No transformations needed, return original code
		return string(ctx.document.text[ctx.selection_start:ctx.selection_end])
	}

	// Transform the code by walking through and replacing variable references
	sb := strings.builder_make(context.temp_allocator)

	// Process each selected statement and transform it
	last_offset := ctx.selection_start

	for stmt in ctx.selected_stmts {
		// Write any text between statements
		if stmt.pos.offset > last_offset {
			strings.write_string(&sb, string(ctx.document.text[last_offset:stmt.pos.offset]))
		}

		// Transform this statement
		transformed := transform_statement(stmt, ctx.document.text, deref_vars, ctx.control_flow_type, returns)
		strings.write_string(&sb, transformed)

		last_offset = stmt.end.offset
	}

	// Write any remaining text after the last statement
	if last_offset < ctx.selection_end {
		strings.write_string(&sb, string(ctx.document.text[last_offset:ctx.selection_end]))
	}

	return strings.to_string(sb)
}

// Transform a statement, adding dereferences for pointer parameters
// and transforming control flow statements
transform_statement :: proc(
	stmt: ^ast.Stmt,
	source: []u8,
	deref_vars: map[string]bool,
	control_flow_type: ControlFlowType,
	returns: [dynamic]ReturnInfo,
) -> string {
	if stmt == nil {
		return ""
	}

	sb := strings.builder_make(context.temp_allocator)
	transform_node(stmt, source, deref_vars, &sb, int(stmt.pos.offset), false, control_flow_type, false, returns)
	return strings.to_string(sb)
}

// Recursively transform a node, tracking position to copy whitespace/text between nodes
// auto_deref_context is true when we're in a context where pointers auto-dereference (field/index access)
// control_flow_type indicates what kind of control flow statements need to be transformed
// in_loop is true when we're inside a loop in the extracted code (break/continue should not be transformed)
// returns contains the list of variables that need to be returned
transform_node :: proc(
	node: ^ast.Node,
	source: []u8,
	deref_vars: map[string]bool,
	sb: ^strings.Builder,
	start_offset: int,
	auto_deref_context: bool,
	control_flow_type: ControlFlowType,
	in_loop: bool,
	returns: [dynamic]ReturnInfo,
) -> int {
	if node == nil {
		return start_offset
	}

	// Write any text before this node
	if int(node.pos.offset) > start_offset {
		strings.write_string(sb, string(source[start_offset:node.pos.offset]))
	}

	current_offset := int(node.pos.offset)

	#partial switch n in node.derived {
	case ^ast.Return_Stmt:
		// Transform return statement based on control flow type
		if control_flow_type == .Return {
			strings.write_string(sb, "return true")
			// Also return the declared variables
			for ret in returns {
				strings.write_string(sb, ", ")
				strings.write_string(sb, ret.name)
			}
			return int(node.end.offset)
		}
		// Default: copy as-is
		strings.write_string(sb, string(source[node.pos.offset:node.end.offset]))
		return int(node.end.offset)

	case ^ast.Branch_Stmt:
		// Get the actual token position - Branch_Stmt.tok contains the keyword
		tok_start := n.tok.pos.offset
		tok_end := tok_start + len(n.tok.text)
		// Transform break/continue if not inside a loop in extracted code
		if !in_loop && control_flow_type != .None {
			if n.tok.kind == tokenizer.Token_Kind.Break {
				#partial switch control_flow_type {
				case .Break:
					strings.write_string(sb, "return true")
					// Also return the declared variables
					for ret in returns {
						strings.write_string(sb, ", ")
						strings.write_string(sb, ret.name)
					}
					return int(tok_end)
				case .BreakAndContinue:
					strings.write_string(sb, "return true, false")
					for ret in returns {
						strings.write_string(sb, ", ")
						strings.write_string(sb, ret.name)
					}
					return int(tok_end)
				}
			} else if n.tok.kind == tokenizer.Token_Kind.Continue {
				#partial switch control_flow_type {
				case .Continue:
					strings.write_string(sb, "return true")
					for ret in returns {
						strings.write_string(sb, ", ")
						strings.write_string(sb, ret.name)
					}
					return int(tok_end)
				case .BreakAndContinue:
					strings.write_string(sb, "return false, true")
					for ret in returns {
						strings.write_string(sb, ", ")
						strings.write_string(sb, ret.name)
					}
					return int(tok_end)
				}
			}
		}
		// Default: copy as-is using token position
		strings.write_string(sb, string(source[tok_start:tok_end]))
		return int(tok_end)

	case ^ast.Ident:
		// Only add ^ if we're NOT in an auto-deref context (field/index access)
		if n.name in deref_vars && !auto_deref_context {
			strings.write_string(sb, n.name)
			strings.write_string(sb, "^")
		} else {
			strings.write_string(sb, n.name)
		}
		return int(node.end.offset)

	case ^ast.Unary_Expr:
		// Handle &x -> x when x is passed by pointer
		if n.op.kind == .And {
			if ident, ok := n.expr.derived.(^ast.Ident); ok {
				if ident.name in deref_vars {
					// &x becomes just x (since x is already a pointer)
					strings.write_string(sb, ident.name)
					return int(node.end.offset)
				}
			}
		}
		// Write the operator
		strings.write_string(sb, string(source[current_offset:n.expr.pos.offset]))
		current_offset = transform_node(
			n.expr,
			source,
			deref_vars,
			sb,
			int(n.expr.pos.offset),
			auto_deref_context,
			control_flow_type,
			in_loop,
			returns,
		)
		return max(current_offset, int(node.end.offset))

	case ^ast.Binary_Expr:
		current_offset = transform_node(
			n.left,
			source,
			deref_vars,
			sb,
			current_offset,
			auto_deref_context,
			control_flow_type,
			in_loop,
			returns,
		)
		current_offset = transform_node(
			n.right,
			source,
			deref_vars,
			sb,
			current_offset,
			auto_deref_context,
			control_flow_type,
			in_loop,
			returns,
		)
		return max(current_offset, int(node.end.offset))

	case ^ast.Paren_Expr:
		// Write opening paren
		strings.write_byte(sb, '(')
		current_offset = int(n.expr.pos.offset)
		current_offset = transform_node(
			n.expr,
			source,
			deref_vars,
			sb,
			current_offset,
			auto_deref_context,
			control_flow_type,
			in_loop,
			returns,
		)
		strings.write_byte(sb, ')')
		return int(node.end.offset)

	case ^ast.Call_Expr:
		// Check if this is a builtin that accepts pointers to arrays (len, cap, etc.)
		is_pointer_accepting_builtin := false
		if ident, ok := n.expr.derived.(^ast.Ident); ok {
			switch ident.name {
			case "len", "cap", "size_of", "align_of":
				is_pointer_accepting_builtin = true
			}
		}

		current_offset = transform_node(
			n.expr,
			source,
			deref_vars,
			sb,
			current_offset,
			auto_deref_context,
			control_flow_type,
			in_loop,
			returns,
		)
		// Write the opening paren
		strings.write_string(sb, string(source[current_offset:n.open.offset + 1]))
		current_offset = int(n.open.offset) + 1
		for arg, i in n.args {
			if i > 0 {
				strings.write_string(sb, string(source[current_offset:arg.pos.offset]))
			}
			// For builtins that accept pointers, pass args in auto-deref context
			current_offset = transform_node(
				arg,
				source,
				deref_vars,
				sb,
				int(arg.pos.offset),
				is_pointer_accepting_builtin,
				control_flow_type,
				in_loop,
				returns,
			)
		}
		// Write closing paren
		strings.write_string(sb, string(source[current_offset:node.end.offset]))
		return int(node.end.offset)

	case ^ast.Index_Expr:
		// Base expression is in auto-deref context (arr[i] auto-dereferences)
		current_offset = transform_node(
			n.expr,
			source,
			deref_vars,
			sb,
			current_offset,
			true,
			control_flow_type,
			in_loop,
			returns,
		)
		strings.write_string(sb, string(source[current_offset:n.index.pos.offset]))
		current_offset = transform_node(
			n.index,
			source,
			deref_vars,
			sb,
			int(n.index.pos.offset),
			false,
			control_flow_type,
			in_loop,
			returns,
		)
		strings.write_string(sb, string(source[current_offset:node.end.offset]))
		return int(node.end.offset)

	case ^ast.Slice_Expr:
		// Base expression is in auto-deref context
		current_offset = transform_node(
			n.expr,
			source,
			deref_vars,
			sb,
			current_offset,
			true,
			control_flow_type,
			in_loop,
			returns,
		)
		// Write the rest including brackets and indices
		strings.write_string(sb, string(source[current_offset:node.end.offset]))
		return int(node.end.offset)

	case ^ast.Selector_Expr:
		// Base expression is in auto-deref context (x.field auto-dereferences)
		current_offset = transform_node(
			n.expr,
			source,
			deref_vars,
			sb,
			current_offset,
			true,
			control_flow_type,
			in_loop,
			returns,
		)
		// Write the dot and field name
		strings.write_string(sb, string(source[current_offset:node.end.offset]))
		return int(node.end.offset)

	case ^ast.Deref_Expr:
		current_offset = transform_node(
			n.expr,
			source,
			deref_vars,
			sb,
			current_offset,
			false,
			control_flow_type,
			in_loop,
			returns,
		)
		strings.write_string(sb, "^")
		return int(node.end.offset)

	case ^ast.Assign_Stmt:
		for lhs, i in n.lhs {
			if i > 0 {
				strings.write_string(sb, string(source[current_offset:lhs.pos.offset]))
			}
			current_offset = transform_node(
				lhs,
				source,
				deref_vars,
				sb,
				int(lhs.pos.offset),
				false,
				control_flow_type,
				in_loop,
				returns,
			)
		}
		// Write the operator and spacing
		strings.write_string(sb, string(source[current_offset:n.rhs[0].pos.offset]))
		current_offset = int(n.rhs[0].pos.offset)
		for rhs, i in n.rhs {
			if i > 0 {
				strings.write_string(sb, string(source[current_offset:rhs.pos.offset]))
			}
			current_offset = transform_node(
				rhs,
				source,
				deref_vars,
				sb,
				int(rhs.pos.offset),
				false,
				control_flow_type,
				in_loop,
				returns,
			)
		}
		return max(current_offset, int(node.end.offset))

	case ^ast.Value_Decl:
		// Variable declarations - copy as-is but transform the value expressions
		for name in n.names {
			strings.write_string(sb, string(source[current_offset:name.end.offset]))
			current_offset = int(name.end.offset)
		}
		if n.type != nil {
			strings.write_string(sb, string(source[current_offset:n.type.end.offset]))
			current_offset = int(n.type.end.offset)
		}
		if len(n.values) > 0 {
			// Write up to the first value (includes the = or :=)
			strings.write_string(sb, string(source[current_offset:n.values[0].pos.offset]))
			current_offset = int(n.values[0].pos.offset)
			for value, i in n.values {
				if i > 0 {
					strings.write_string(sb, string(source[current_offset:value.pos.offset]))
				}
				current_offset = transform_node(
					value,
					source,
					deref_vars,
					sb,
					int(value.pos.offset),
					false,
					control_flow_type,
					in_loop,
					returns,
				)
			}
		}
		return max(current_offset, int(node.end.offset))

	case ^ast.Expr_Stmt:
		return transform_node(
			n.expr,
			source,
			deref_vars,
			sb,
			current_offset,
			false,
			control_flow_type,
			in_loop,
			returns,
		)

	case ^ast.If_Stmt:
		// "if" keyword
		strings.write_string(sb, "if")
		current_offset = int(node.pos.offset) + 2
		if n.cond != nil {
			strings.write_string(sb, string(source[current_offset:n.cond.pos.offset]))
			current_offset = transform_node(
				n.cond,
				source,
				deref_vars,
				sb,
				int(n.cond.pos.offset),
				false,
				control_flow_type,
				in_loop,
				returns,
			)
		}
		if n.body != nil {
			strings.write_string(sb, string(source[current_offset:n.body.pos.offset]))
			current_offset = transform_node(
				n.body,
				source,
				deref_vars,
				sb,
				int(n.body.pos.offset),
				false,
				control_flow_type,
				in_loop,
				returns,
			)
		}
		if n.else_stmt != nil {
			strings.write_string(sb, string(source[current_offset:n.else_stmt.pos.offset]))
			current_offset = transform_node(
				n.else_stmt,
				source,
				deref_vars,
				sb,
				int(n.else_stmt.pos.offset),
				false,
				control_flow_type,
				in_loop,
				returns,
			)
		}
		return max(current_offset, int(node.end.offset))

	case ^ast.For_Stmt:
		// "for" keyword - inside loops, break/continue should not be transformed
		strings.write_string(sb, "for")
		current_offset = int(node.pos.offset) + 3
		if n.init != nil {
			strings.write_string(sb, string(source[current_offset:n.init.pos.offset]))
			current_offset = transform_node(
				n.init,
				source,
				deref_vars,
				sb,
				int(n.init.pos.offset),
				false,
				control_flow_type,
				in_loop,
				returns,
			)
		}
		if n.cond != nil {
			strings.write_string(sb, string(source[current_offset:n.cond.pos.offset]))
			current_offset = transform_node(
				n.cond,
				source,
				deref_vars,
				sb,
				int(n.cond.pos.offset),
				false,
				control_flow_type,
				in_loop,
				returns,
			)
		}
		if n.post != nil {
			strings.write_string(sb, string(source[current_offset:n.post.pos.offset]))
			current_offset = transform_node(
				n.post,
				source,
				deref_vars,
				sb,
				int(n.post.pos.offset),
				false,
				control_flow_type,
				in_loop,
				returns,
			)
		}
		if n.body != nil {
			strings.write_string(sb, string(source[current_offset:n.body.pos.offset]))
			// Inside the loop body, break/continue are scoped to this loop
			current_offset = transform_node(
				n.body,
				source,
				deref_vars,
				sb,
				int(n.body.pos.offset),
				false,
				control_flow_type,
				true,
				returns,
			)
		}
		return max(current_offset, int(node.end.offset))

	case ^ast.Range_Stmt:
		// Copy the for and loop variables as-is, transform body
		if n.body != nil {
			strings.write_string(sb, string(source[current_offset:n.body.pos.offset]))
			// Inside the loop body, break/continue are scoped to this loop
			current_offset = transform_node(
				n.body,
				source,
				deref_vars,
				sb,
				int(n.body.pos.offset),
				false,
				control_flow_type,
				true,
				returns,
			)
		} else {
			strings.write_string(sb, string(source[current_offset:node.end.offset]))
		}
		return max(current_offset, int(node.end.offset))

	case ^ast.Block_Stmt:
		strings.write_byte(sb, '{')
		current_offset = int(node.pos.offset) + 1
		for stmt in n.stmts {
			strings.write_string(sb, string(source[current_offset:stmt.pos.offset]))
			current_offset = transform_node(
				stmt,
				source,
				deref_vars,
				sb,
				int(stmt.pos.offset),
				false,
				control_flow_type,
				in_loop,
				returns,
			)
		}
		strings.write_string(sb, string(source[current_offset:node.end.offset]))
		return int(node.end.offset)

	case ^ast.Switch_Stmt:
		// switch keyword
		strings.write_string(sb, "switch")
		current_offset = int(node.pos.offset) + 6
		if n.init != nil {
			strings.write_string(sb, string(source[current_offset:n.init.pos.offset]))
			current_offset = transform_node(
				n.init,
				source,
				deref_vars,
				sb,
				int(n.init.pos.offset),
				false,
				control_flow_type,
				in_loop,
				returns,
			)
		}
		if n.cond != nil {
			strings.write_string(sb, string(source[current_offset:n.cond.pos.offset]))
			current_offset = transform_node(
				n.cond,
				source,
				deref_vars,
				sb,
				int(n.cond.pos.offset),
				false,
				control_flow_type,
				in_loop,
				returns,
			)
		}
		if n.body != nil {
			strings.write_string(sb, string(source[current_offset:n.body.pos.offset]))
			current_offset = transform_node(
				n.body,
				source,
				deref_vars,
				sb,
				int(n.body.pos.offset),
				false,
				control_flow_type,
				in_loop,
				returns,
			)
		}
		return max(current_offset, int(node.end.offset))

	case ^ast.Type_Switch_Stmt:
		// switch keyword
		strings.write_string(sb, "switch")
		current_offset = int(node.pos.offset) + 6
		if n.tag != nil {
			strings.write_string(sb, string(source[current_offset:n.tag.pos.offset]))
			current_offset = transform_node(
				n.tag,
				source,
				deref_vars,
				sb,
				int(n.tag.pos.offset),
				false,
				control_flow_type,
				in_loop,
				returns,
			)
		}
		if n.body != nil {
			strings.write_string(sb, string(source[current_offset:n.body.pos.offset]))
			current_offset = transform_node(
				n.body,
				source,
				deref_vars,
				sb,
				int(n.body.pos.offset),
				false,
				control_flow_type,
				in_loop,
				returns,
			)
		}
		return max(current_offset, int(node.end.offset))

	case ^ast.Case_Clause:
		// Write the case keyword and expressions
		if n.body != nil && len(n.body) > 0 {
			strings.write_string(sb, string(source[current_offset:n.body[0].pos.offset]))
			current_offset = int(n.body[0].pos.offset)
			for stmt in n.body {
				strings.write_string(sb, string(source[current_offset:stmt.pos.offset]))
				current_offset = transform_node(
					stmt,
					source,
					deref_vars,
					sb,
					int(stmt.pos.offset),
					false,
					control_flow_type,
					in_loop,
					returns,
				)
			}
			// Write any remaining text (usually just whitespace to the end of the case)
			if current_offset < int(node.end.offset) {
				strings.write_string(sb, string(source[current_offset:node.end.offset]))
			}
		} else {
			strings.write_string(sb, string(source[current_offset:node.end.offset]))
		}
		return int(node.end.offset)

	case ^ast.Ternary_If_Expr:
		current_offset = transform_node(
			n.cond,
			source,
			deref_vars,
			sb,
			current_offset,
			false,
			control_flow_type,
			in_loop,
			returns,
		)
		if n.x != nil {
			strings.write_string(sb, string(source[current_offset:n.x.pos.offset]))
			current_offset = transform_node(
				n.x,
				source,
				deref_vars,
				sb,
				int(n.x.pos.offset),
				false,
				control_flow_type,
				in_loop,
				returns,
			)
		}
		if n.y != nil {
			strings.write_string(sb, string(source[current_offset:n.y.pos.offset]))
			current_offset = transform_node(
				n.y,
				source,
				deref_vars,
				sb,
				int(n.y.pos.offset),
				false,
				control_flow_type,
				in_loop,
				returns,
			)
		}
		return max(current_offset, int(node.end.offset))

	case ^ast.Comp_Lit:
		if n.type != nil {
			strings.write_string(sb, string(source[current_offset:n.type.end.offset]))
			current_offset = int(n.type.end.offset)
		}
		strings.write_byte(sb, '{')
		current_offset = int(n.open.offset) + 1
		for elem in n.elems {
			strings.write_string(sb, string(source[current_offset:elem.pos.offset]))
			current_offset = transform_node(
				elem,
				source,
				deref_vars,
				sb,
				int(elem.pos.offset),
				false,
				control_flow_type,
				in_loop,
				returns,
			)
		}
		strings.write_string(sb, string(source[current_offset:node.end.offset]))
		return int(node.end.offset)

	case ^ast.Field_Value:
		// field = value
		strings.write_string(sb, string(source[current_offset:n.value.pos.offset]))
		current_offset = transform_node(
			n.value,
			source,
			deref_vars,
			sb,
			int(n.value.pos.offset),
			false,
			control_flow_type,
			in_loop,
			returns,
		)
		return max(current_offset, int(node.end.offset))

	case:
		// Default: copy as-is
		strings.write_string(sb, string(source[node.pos.offset:node.end.offset]))
		return int(node.end.offset)
	}

	return current_offset
}

find_common_indentation :: proc(lines: []string) -> int {
	// The first line has no indentation because selection starts at content
	// So we find the minimum indentation from lines 2 onwards only

	if len(lines) < 2 {
		return 0
	}

	common_indent := max(int)

	for line in lines[1:] {
		// Skip empty lines
		trimmed := strings.trim_space(line)
		if len(trimmed) == 0 {
			continue
		}

		// Count leading tabs/spaces
		indent := 0
		for ch in line {
			if ch == '\t' || ch == ' ' {
				indent += 1
			} else {
				break
			}
		}

		if indent < common_indent {
			common_indent = indent
		}
	}

	if common_indent == max(int) {
		return 0
	}
	return common_indent
}

build_call_text :: proc(
	ctx: ^ExtractProcContext,
	params: [dynamic]ParamInfo,
	returns: [dynamic]ReturnInfo,
	indent: string,
) -> string {
	sb := strings.builder_make(context.temp_allocator)

	// Handle expression extraction - just output the call (no assignment needed)
	if ctx.selected_expr != nil {
		strings.write_string(&sb, DEFAULT_PROC_NAME)
		strings.write_string(&sb, "(")
		for param, i in params {
			if i > 0 {
				strings.write_string(&sb, ", ")
			}
			if param.pass_addr {
				strings.write_string(&sb, "&")
			}
			strings.write_string(&sb, param.name)
		}
		strings.write_string(&sb, ")")
		return strings.to_string(sb)
	}

	// Handle control flow - wrap call in appropriate control structure
	#partial switch ctx.control_flow_type {
	case .Return:
		// For return: if extracted_proc(...) { return }
		// With returns: if should_return, result := extracted_proc(...); should_return { return }
		if len(returns) > 0 {
			strings.write_string(&sb, "if __should_return")
			for ret in returns {
				strings.write_string(&sb, ", ")
				strings.write_string(&sb, ret.name)
			}
			strings.write_string(&sb, " := ")
			strings.write_string(&sb, DEFAULT_PROC_NAME)
			strings.write_string(&sb, "(")
			for param, i in params {
				if i > 0 {
					strings.write_string(&sb, ", ")
				}
				if param.pass_addr {
					strings.write_string(&sb, "&")
				}
				strings.write_string(&sb, param.name)
			}
			strings.write_string(&sb, "); __should_return {\n")
			strings.write_string(&sb, indent)
			strings.write_string(&sb, "\treturn\n")
			strings.write_string(&sb, indent)
			strings.write_string(&sb, "}")
		} else {
			strings.write_string(&sb, "if ")
			strings.write_string(&sb, DEFAULT_PROC_NAME)
			strings.write_string(&sb, "(")
			for param, i in params {
				if i > 0 {
					strings.write_string(&sb, ", ")
				}
				if param.pass_addr {
					strings.write_string(&sb, "&")
				}
				strings.write_string(&sb, param.name)
			}
			strings.write_string(&sb, ") {\n")
			strings.write_string(&sb, indent)
			strings.write_string(&sb, "\treturn\n")
			strings.write_string(&sb, indent)
			strings.write_string(&sb, "}")
		}
		return strings.to_string(sb)

	case .Break:
		// For break: if extracted_proc(...) { break }
		if len(returns) > 0 {
			strings.write_string(&sb, "if __should_break")
			for ret in returns {
				strings.write_string(&sb, ", ")
				strings.write_string(&sb, ret.name)
			}
			strings.write_string(&sb, " := ")
			strings.write_string(&sb, DEFAULT_PROC_NAME)
			strings.write_string(&sb, "(")
			for param, i in params {
				if i > 0 {
					strings.write_string(&sb, ", ")
				}
				if param.pass_addr {
					strings.write_string(&sb, "&")
				}
				strings.write_string(&sb, param.name)
			}
			strings.write_string(&sb, "); __should_break {\n")
			strings.write_string(&sb, indent)
			strings.write_string(&sb, "\tbreak\n")
			strings.write_string(&sb, indent)
			strings.write_string(&sb, "}")
		} else {
			strings.write_string(&sb, "if ")
			strings.write_string(&sb, DEFAULT_PROC_NAME)
			strings.write_string(&sb, "(")
			for param, i in params {
				if i > 0 {
					strings.write_string(&sb, ", ")
				}
				if param.pass_addr {
					strings.write_string(&sb, "&")
				}
				strings.write_string(&sb, param.name)
			}
			strings.write_string(&sb, ") {\n")
			strings.write_string(&sb, indent)
			strings.write_string(&sb, "\tbreak\n")
			strings.write_string(&sb, indent)
			strings.write_string(&sb, "}")
		}
		return strings.to_string(sb)

	case .Continue:
		// For continue: if extracted_proc(...) { continue }
		if len(returns) > 0 {
			strings.write_string(&sb, "if __should_continue")
			for ret in returns {
				strings.write_string(&sb, ", ")
				strings.write_string(&sb, ret.name)
			}
			strings.write_string(&sb, " := ")
			strings.write_string(&sb, DEFAULT_PROC_NAME)
			strings.write_string(&sb, "(")
			for param, i in params {
				if i > 0 {
					strings.write_string(&sb, ", ")
				}
				if param.pass_addr {
					strings.write_string(&sb, "&")
				}
				strings.write_string(&sb, param.name)
			}
			strings.write_string(&sb, "); __should_continue {\n")
			strings.write_string(&sb, indent)
			strings.write_string(&sb, "\tcontinue\n")
			strings.write_string(&sb, indent)
			strings.write_string(&sb, "}")
		} else {
			strings.write_string(&sb, "if ")
			strings.write_string(&sb, DEFAULT_PROC_NAME)
			strings.write_string(&sb, "(")
			for param, i in params {
				if i > 0 {
					strings.write_string(&sb, ", ")
				}
				if param.pass_addr {
					strings.write_string(&sb, "&")
				}
				strings.write_string(&sb, param.name)
			}
			strings.write_string(&sb, ") {\n")
			strings.write_string(&sb, indent)
			strings.write_string(&sb, "\tcontinue\n")
			strings.write_string(&sb, indent)
			strings.write_string(&sb, "}")
		}
		return strings.to_string(sb)

	case .BreakAndContinue:
		// For both: use an enum or multi-return. Let's use a simple approach with two bools
		if len(returns) > 0 {
			strings.write_string(&sb, "__should_break, __should_continue")
			for ret in returns {
				strings.write_string(&sb, ", ")
				strings.write_string(&sb, ret.name)
			}
			strings.write_string(&sb, " := ")
			strings.write_string(&sb, DEFAULT_PROC_NAME)
			strings.write_string(&sb, "(")
			for param, i in params {
				if i > 0 {
					strings.write_string(&sb, ", ")
				}
				if param.pass_addr {
					strings.write_string(&sb, "&")
				}
				strings.write_string(&sb, param.name)
			}
			strings.write_string(&sb, ")\n")
			strings.write_string(&sb, indent)
			strings.write_string(&sb, "if __should_break {\n")
			strings.write_string(&sb, indent)
			strings.write_string(&sb, "\tbreak\n")
			strings.write_string(&sb, indent)
			strings.write_string(&sb, "}\n")
			strings.write_string(&sb, indent)
			strings.write_string(&sb, "if __should_continue {\n")
			strings.write_string(&sb, indent)
			strings.write_string(&sb, "\tcontinue\n")
			strings.write_string(&sb, indent)
			strings.write_string(&sb, "}")
		} else {
			strings.write_string(&sb, "__should_break, __should_continue := ")
			strings.write_string(&sb, DEFAULT_PROC_NAME)
			strings.write_string(&sb, "(")
			for param, i in params {
				if i > 0 {
					strings.write_string(&sb, ", ")
				}
				if param.pass_addr {
					strings.write_string(&sb, "&")
				}
				strings.write_string(&sb, param.name)
			}
			strings.write_string(&sb, ")\n")
			strings.write_string(&sb, indent)
			strings.write_string(&sb, "if __should_break {\n")
			strings.write_string(&sb, indent)
			strings.write_string(&sb, "\tbreak\n")
			strings.write_string(&sb, indent)
			strings.write_string(&sb, "}\n")
			strings.write_string(&sb, indent)
			strings.write_string(&sb, "if __should_continue {\n")
			strings.write_string(&sb, indent)
			strings.write_string(&sb, "\tcontinue\n")
			strings.write_string(&sb, indent)
			strings.write_string(&sb, "}")
		}
		return strings.to_string(sb)
	}

	// No control flow - normal call
	if len(returns) > 0 {
		for ret, i in returns {
			if i > 0 {
				strings.write_string(&sb, ", ")
			}
			strings.write_string(&sb, ret.name)
		}
		strings.write_string(&sb, " := ")
	}

	strings.write_string(&sb, DEFAULT_PROC_NAME)
	strings.write_string(&sb, "(")

	for param, i in params {
		if i > 0 {
			strings.write_string(&sb, ", ")
		}
		if param.pass_addr {
			strings.write_string(&sb, "&")
		}
		strings.write_string(&sb, param.name)
	}

	strings.write_string(&sb, ")")

	return strings.to_string(sb)
}
