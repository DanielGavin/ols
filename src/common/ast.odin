package common

import "core:odin/ast"


get_ast_node_string :: proc(node: ^ast.Node, src: [] byte) -> string {
    return string(src[node.pos.offset:node.end.offset]);
}


free_ast_node :: proc(file: ^ast.Node) {

}