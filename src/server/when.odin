package server

import "core:odin/ast"

resolve_when_stmt :: proc(ast_context: ^AstContext, when_stmt: ^ast.When_Stmt) -> bool {
    return false
}
