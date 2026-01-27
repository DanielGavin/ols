#+private file

package server

import "core:odin/ast"
import "core:strings"

import "src:common"

REDUNDANT_ELSE_ACTION_TITLE :: "Remove redundant else"

/*
This code action removes redundant else statements.
An else statement is redundant if the if block ends with a control flow
statement that always transfers control (return, break, continue, fallthrough).
 
For break and continue, we verify that the if statement is inside a loop or switch.
  
Example 1 (simple else):
```odin
  if x > 0 {
      foo()
      return
  } else {
      bar()
  }
```

Can be transformed to:
```odin
  if x > 0 {
      foo()
      return
  }
  bar()
```
 
Example 2 (else-if chain):
```odin
  if x > 0 {
      foo()
      return
  } else if x < 0 {
      bar()
  } else {
      baz()
  }
```
Can be transformed to:
```odin
  if x > 0 {
      foo()
      return
  }
  if x < 0 {
      bar()
  } else {
      baz()
  }
```
*/
@(private = "package")
add_redundant_else_action :: proc(
	document: ^Document,
	position: common.AbsolutePosition,
	uri: string,
	actions: ^[dynamic]CodeAction,
) {
	context_info := find_if_with_redundant_else(document.ast.decls[:], position)
	if context_info.if_stmt == nil {
		return
	}

	new_text, ok := generate_else_removed(document, context_info.if_stmt)
	if !ok {
		return
	}

	range := common.get_token_range(context_info.if_stmt^, document.ast.src)

	textEdits := make([dynamic]TextEdit, context.temp_allocator)
	append(&textEdits, TextEdit{range = range, newText = new_text})

	workspaceEdit: WorkspaceEdit
	workspaceEdit.changes = make(map[string][]TextEdit, 0, context.temp_allocator)
	workspaceEdit.changes[uri] = textEdits[:]

	append(
		actions,
		CodeAction {
			kind = "refactor.more",
			isPreferred = false,
			title = REDUNDANT_ELSE_ACTION_TITLE,
			edit = workspaceEdit,
		},
	)
}

// Context information about where the if statement is located
IfContextInfo :: struct {
	if_stmt:         ^ast.If_Stmt,
	in_loop:         bool,
	in_switch:       bool,
	in_proc:         bool,
}

// Find if statement with redundant else at the given position
find_if_with_redundant_else :: proc(stmts: []^ast.Stmt, position: common.AbsolutePosition) -> IfContextInfo {
	ctx := IfContextInfo{}
	for stmt in stmts {
		if stmt == nil {
			continue
		}
		if find_if_with_redundant_else_in_node(stmt, position, &ctx) {
			return ctx
		}
	}
	return {}
}

// Recursively search for if statement with redundant else
find_if_with_redundant_else_in_node :: proc(
	node: ^ast.Node, 
	position: common.AbsolutePosition, 
	ctx: ^IfContextInfo,
) -> bool {
	if node == nil {
		return false
	}

	if !(node.pos.offset <= position && position <= node.end.offset) {
		return false
	}

	#partial switch n in node.derived {
	case ^ast.If_Stmt:
		return handle_if_stmt(n, position, ctx)

	case ^ast.Block_Stmt:
		return search_in_block(n.stmts, position, ctx)

	case ^ast.Proc_Lit:
		ctx.in_proc = true
		if n.body != nil {
			return find_if_with_redundant_else_in_node(n.body, position, ctx)
		}

	case ^ast.Value_Decl:
		for value in n.values {
			if find_if_with_redundant_else_in_node(value, position, ctx) {
				return true
			}
		}

	case ^ast.For_Stmt:
		ctx.in_loop = true
		if n.body != nil {
			return find_if_with_redundant_else_in_node(n.body, position, ctx)
		}

	case ^ast.Range_Stmt:
		ctx.in_loop = true
		if n.body != nil {
			return find_if_with_redundant_else_in_node(n.body, position, ctx)
		}

	case ^ast.Switch_Stmt:
		ctx.in_switch = true
		if n.body != nil {
			return find_if_with_redundant_else_in_node(n.body, position, ctx)
		}

	case ^ast.Type_Switch_Stmt:
		ctx.in_switch = true
		if n.body != nil {
			return find_if_with_redundant_else_in_node(n.body, position, ctx)
		}

	case ^ast.Case_Clause:
		for stmt in n.body {
			if find_if_with_redundant_else_in_node(stmt, position, ctx) {
				return true
			}
		}

	case ^ast.When_Stmt:
		if n.body != nil {
			if find_if_with_redundant_else_in_node(n.body, position, ctx) {
				return true
			}
		}
		if n.else_stmt != nil {
			if find_if_with_redundant_else_in_node(n.else_stmt, position, ctx) {
				return true
			}
		}

	case ^ast.Defer_Stmt:
		if n.stmt != nil {
			return find_if_with_redundant_else_in_node(n.stmt, position, ctx)
		}
	}

	return false
}

// Handle if statement specifically
handle_if_stmt :: proc(n: ^ast.If_Stmt, position: common.AbsolutePosition, ctx: ^IfContextInfo) -> bool {
	// Check nested ifs in the body first
	if n.body != nil && position_in_node(n.body, position) {
		if find_if_with_redundant_else_in_node(n.body, position, ctx) {
			return true
		}
	}

	// Check if position is in the else clause (look for nested ifs there)
	if n.else_stmt != nil && position_in_node(n.else_stmt, position) {
		return find_if_with_redundant_else_in_node(n.else_stmt, position, ctx)
	}

	// Now check if this if statement has a redundant else
	if !has_redundant_else(n, ctx^) {
		return false
	}

	ctx.if_stmt = n
	return true
}

// Search for if statements in a block
search_in_block :: proc(stmts: []^ast.Stmt, position: common.AbsolutePosition, ctx: ^IfContextInfo) -> bool {
	for stmt in stmts {
		if find_if_with_redundant_else_in_node(stmt, position, ctx) {
			return true
		}
	}
	return false
}

// Check if an if statement has a redundant else clause
has_redundant_else :: proc(if_stmt: ^ast.If_Stmt, ctx: IfContextInfo) -> bool {
	// Must have an else clause (can be else-if or plain else)
	if if_stmt.else_stmt == nil {
		return false
	}

	// Check if the if body ends with a terminating statement
	body_block, ok := if_stmt.body.derived.(^ast.Block_Stmt)
	if !ok {
		return false
	}

	return ends_with_control_flow(body_block, ctx)
}

// Check if a block ends with a control flow statement
ends_with_control_flow :: proc(block: ^ast.Block_Stmt, ctx: IfContextInfo) -> bool {
	if block == nil || len(block.stmts) == 0 {
		return false
	}

	last_stmt := block.stmts[len(block.stmts) - 1]
	return is_terminating_stmt(last_stmt, ctx)
}

// Check if a statement is a terminating statement (return, break, continue, fallthrough)
is_terminating_stmt :: proc(stmt: ^ast.Stmt, ctx: IfContextInfo) -> bool {
	if stmt == nil {
		return false
	}

	#partial switch s in stmt.derived {
	case ^ast.Return_Stmt:
		return ctx.in_proc

	case ^ast.Branch_Stmt:
		return is_valid_branch_stmt(s, ctx)
	}

	return false
}

// Check if a branch statement (break, continue, fallthrough) is valid in context
is_valid_branch_stmt :: proc(branch: ^ast.Branch_Stmt, ctx: IfContextInfo) -> bool {
	#partial switch branch.tok.kind {
	case .Break:
		// Break is valid in loops and switches
		return ctx.in_loop || ctx.in_switch

	case .Continue:
		// Continue is only valid in loops
		return ctx.in_loop

	case .Fallthrough:
		// Fallthrough is only valid in switches
		return ctx.in_switch
	}

	return false
}

// Generate the transformed code with else removed
generate_else_removed :: proc(document: ^Document, if_stmt: ^ast.If_Stmt) -> (string, bool) {
	src := document.ast.src
	indent := get_line_indentation(src, if_stmt.pos.offset)

	sb := strings.builder_make(context.temp_allocator)

	// Write the if part with label
	if if_stmt.label != nil {
		label_text := src[if_stmt.label.pos.offset:if_stmt.label.end.offset]
		strings.write_string(&sb, label_text)
		strings.write_string(&sb, ": ")
	}

	strings.write_string(&sb, "if ")

	// Write init statement if present
	if if_stmt.init != nil {
		init_text := src[if_stmt.init.pos.offset:if_stmt.init.end.offset]
		strings.write_string(&sb, init_text)
		strings.write_string(&sb, "; ")
	}

	// Write condition
	if if_stmt.cond != nil {
		cond_text := src[if_stmt.cond.pos.offset:if_stmt.cond.end.offset]
		strings.write_string(&sb, cond_text)
	}

	strings.write_string(&sb, " ")

	// Write the if body
	if_body_text := src[if_stmt.body.pos.offset:if_stmt.body.end.offset]
	strings.write_string(&sb, if_body_text)

	// Handle else clause
	if else_if, is_else_if := if_stmt.else_stmt.derived.(^ast.If_Stmt); is_else_if {
		// Else-if chain: write the else-if as a new if statement
		strings.write_string(&sb, "\n")
		strings.write_string(&sb, indent)
		else_if_text := src[else_if.pos.offset:else_if.end.offset]
		strings.write_string(&sb, else_if_text)
	} else {
		// Simple else: extract statements from the else block
		else_stmts := get_else_statements(if_stmt.else_stmt)
		for stmt in else_stmts {
			if stmt == nil {
				continue
			}
			stmt_text := src[stmt.pos.offset:stmt.end.offset]
			strings.write_string(&sb, "\n")
			strings.write_string(&sb, indent)
			strings.write_string(&sb, stmt_text)
		}
	}

	return strings.to_string(sb), true
}

// Extract statements from the else clause
get_else_statements :: proc(else_stmt: ^ast.Stmt) -> []^ast.Stmt {
	if else_stmt == nil {
		return {}
	}

	#partial switch block in else_stmt.derived {
	case ^ast.Block_Stmt:
		return block.stmts
	}

	return {}
}
