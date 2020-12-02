package server

import "core:odin/tokenizer"
import "core:odin/ast"
import "core:log"

import "shared:common"
import "shared:index"

SemanticTokenTypes :: enum {
    Namespace,
    Type,
    Enum,
    Struct,
    Parameter,
    Variable,
    EnumMember,
    Function,
    Member,
    Keyword,
    Modifier,
    Comment,
    String,
    Number,
    Operator,
};

SemanticTokenModifiers :: enum {
    None,
    Declaration,
    Definition,
    Deprecated,
};

SemanticTokensClientCapabilities :: struct {

    requests: struct {
        range: bool,
    },

    tokenTypes: [] string,
    tokenModifiers: [] string,
    formats: [] string,
    overlappingTokenSupport: bool,
    multilineTokenSupport: bool,
};

SemanticTokensLegend :: struct {
    tokenTypes: [] string,
    tokenModifiers: [] string,
};

SemanticTokensOptions :: struct {
    legend: SemanticTokensLegend,
    range: bool,
    full: bool,
};

SemanticTokensParams :: struct {
    textDocument: TextDocumentIdentifier,
};

SemanticTokensRangeParams :: struct {
    textDocument: TextDocumentIdentifier,
    range: common.Range,
};

SemanticTokens :: struct {
    data: [] u32,
};

SemanticTokenBuilder :: struct {
    current_function: ^ast.Node,
    current_start: int,
    tokens: [dynamic] u32,
};

make_token_builder :: proc(allocator := context.temp_allocator) -> SemanticTokenBuilder {

    return {
        tokens = make([dynamic]u32, context.temp_allocator),
    };

}

get_tokens :: proc(builder: SemanticTokenBuilder) -> SemanticTokens {
    return {
        data = builder.tokens[:],
    };
}

get_semantic_tokens :: proc(document: ^Document) -> SemanticTokens {

    ast_context := make_ast_context(document.ast, document.imports, document.package_name, context.temp_allocator);
    builder := make_token_builder();

    get_globals(document.ast, &ast_context);

    for decl in document.ast.decls {
        write_semantic_tokens(cast(^ast.Node)decl, &builder, &ast_context);
    }

    return get_tokens(builder);
}

write_semantic_node :: proc(builder: ^SemanticTokenBuilder, node: ^ast.Node, src: []byte, type: SemanticTokenTypes, modifier: SemanticTokenModifiers) {

    position := common.get_relative_token_position(node.pos.offset, src, builder.current_start);

    name := common.get_ast_node_string(node, src);

    append(&builder.tokens, cast(u32)position.line, cast(u32)position.character, cast(u32)len(name), cast(u32)type, 0);

    builder.current_start = node.pos.offset;
}

write_semantic_token :: proc(builder: ^SemanticTokenBuilder, token: tokenizer.Token, src: []byte, type: SemanticTokenTypes, modifier: SemanticTokenModifiers) {

    position := common.get_relative_token_position(token.pos.offset, src, builder.current_start);

    append(&builder.tokens, cast(u32)position.line, cast(u32)position.character, cast(u32)len(token.text), cast(u32)type, 0);

    builder.current_start = token.pos.offset;
}


write_semantic_token_pos :: proc(builder: ^SemanticTokenBuilder, pos: tokenizer.Pos, name: string, src: []byte, type: SemanticTokenTypes, modifier: SemanticTokenModifiers) {

    position := common.get_relative_token_position(pos.offset, src, builder.current_start);

    append(&builder.tokens, cast(u32)position.line, cast(u32)position.character, cast(u32)len(name), cast(u32)type, 0);

    builder.current_start = pos.offset;
}


resolve_and_write_ident :: proc(node: ^ast.Node, builder: ^SemanticTokenBuilder, ast_context: ^AstContext) {

    n := node.derived.(ast.Ident);

    ast_context.current_package = ast_context.document_package;

    if resolve_ident_is_variable(ast_context, n) {
        write_semantic_node(builder, node, ast_context.file.src, .Variable, .None);
    }

    else if symbol, ok := resolve_type_identifier(ast_context, n); ok {

        #partial switch v in symbol.value {
        case index.SymbolPackageValue:
            write_semantic_node(builder, node, ast_context.file.src, .Namespace, .None);
        case index.SymbolStructValue:
            write_semantic_node(builder, node, ast_context.file.src, .Struct, .None);
        case index.SymbolEnumValue:
            write_semantic_node(builder, node, ast_context.file.src, .Enum, .None);
        case index.SymbolUnionValue:
            write_semantic_node(builder, node, ast_context.file.src, .Enum, .None);
        case index.SymbolGenericValue:
            #partial switch symbol.type {
            case .Keyword:
                write_semantic_node(builder, node, ast_context.file.src, .Keyword, .None);
            }
        }

    }
}

resolve_and_write_expr :: proc(expr: ^ast.Expr, builder: ^SemanticTokenBuilder, ast_context: ^AstContext) {

    ast_context.current_package = ast_context.document_package;

    if symbol, ok := resolve_type_expression(ast_context, expr); ok {

        #partial switch v in symbol.value {
        case index.SymbolPackageValue:
            write_semantic_node(builder, expr, ast_context.file.src, .Namespace, .None);
        case index.SymbolStructValue:
            write_semantic_node(builder, expr, ast_context.file.src, .Struct, .None);
        case index.SymbolEnumValue:
            write_semantic_node(builder, expr, ast_context.file.src, .Enum, .None);
        case index.SymbolUnionValue:
            write_semantic_node(builder, expr, ast_context.file.src, .Enum, .None);
        case index.SymbolGenericValue:
            #partial switch symbol.type {
            case .Keyword:
                write_semantic_node(builder, expr, ast_context.file.src, .Keyword, .None);
            }
        }

    }

}

write_semantic_tokens :: proc {
    write_semantic_tokens_node,
    write_semantic_tokens_dynamic_array,
    write_semantic_tokens_array,
};

write_semantic_tokens_array :: proc(array: $A/[]^$T, builder: ^SemanticTokenBuilder, ast_context: ^AstContext) {

    for elem, i in array {
        write_semantic_tokens(elem, builder, ast_context);
    }

}

write_semantic_tokens_dynamic_array :: proc(array: $A/[dynamic]^$T, builder: ^SemanticTokenBuilder, ast_context: ^AstContext) {

    for elem, i in array {
        write_semantic_tokens(elem, builder, ast_context);
    }

}

write_semantic_tokens_node :: proc(node: ^ast.Node, builder: ^SemanticTokenBuilder, ast_context: ^AstContext) {

    using ast;

    if node == nil {
        return;
    }

    switch n in node.derived {
    case Ident:
        resolve_and_write_ident(node, builder, ast_context);
    case Selector_Expr:
        write_semantic_selector(cast(^Selector_Expr)node, builder, ast_context);
    case Pointer_Type:
        write_semantic_token_pos(builder, node.pos, "^", ast_context.file.src, .Operator, .None);
        write_semantic_tokens(n.elem, builder, ast_context);
    case Value_Decl:
        write_semantic_tokens_value_decl(n, builder, ast_context);
    case Block_Stmt:
        write_semantic_tokens(n.stmts, builder, ast_context);
    case Expr_Stmt:
        write_semantic_tokens(n.expr, builder, ast_context);
    case Range_Stmt:
        get_locals_at(builder.current_function, node, ast_context);
        write_semantic_token_pos(builder, n.for_pos, "for", ast_context.file.src, .Keyword, .None);
        if n.val0 != nil {
            if ident, ok := n.val0.derived.(Ident); ok {
                write_semantic_node(builder, n.val0, ast_context.file.src, .Variable, .None);
            }
        }

        if n.val1 != nil {
            if ident, ok := n.val1.derived.(Ident); ok {
                write_semantic_node(builder, n.val1, ast_context.file.src, .Variable, .None);
            }
        }

        write_semantic_token_pos(builder, n.in_pos, "in", ast_context.file.src, .Keyword, .None);

        write_semantic_tokens(n.expr, builder, ast_context);

        write_semantic_tokens(n.body, builder, ast_context);
    case:
        //log.infof("unhandled write node %v", n);
    }



}

write_semantic_tokens_value_decl :: proc(value_decl: ast.Value_Decl, builder: ^SemanticTokenBuilder, ast_context: ^AstContext) {

    using ast;

    for name, i in value_decl.names {
        if ident, ok := name.derived.(Ident); ok {

            if value_decl.type != nil {

            }

            else {

                if len(value_decl.values) == 1 {

                    switch v in value_decl.values[0].derived {
                    case ast.Struct_Type:
                        write_semantic_node(builder, name, ast_context.file.src, .Struct, .None);
                        write_semantic_token_pos(builder, v.pos, "struct", ast_context.file.src, .Keyword, .None);
                    case ast.Enum_Type:
                        write_semantic_node(builder, name, ast_context.file.src, .Enum, .None);
                        write_semantic_token_pos(builder, v.pos, "enum", ast_context.file.src, .Keyword, .None);
                        write_semantic_enum_fields(v, builder, ast_context);
                    case ast.Proc_Lit:
                        write_semantic_node(builder, name, ast_context.file.src, .Function, .None);
                        write_semantic_token_pos(builder, v.pos, "proc", ast_context.file.src, .Keyword, .None);
                        write_semantic_proc_type(v.type, builder, ast_context);

                        last_function := builder.current_function;
                        builder.current_function = value_decl.values[0];
                        get_locals_at(builder.current_function, builder.current_function, ast_context);
                        write_semantic_tokens(v.body, builder, ast_context);
                        builder.current_function = last_function;
                    }

                }

                else {

                }

            }

        }
    }

}

write_semantic_proc_type :: proc(node: ^ast.Proc_Type, builder: ^SemanticTokenBuilder, ast_context: ^AstContext) {

    using ast;

    if node == nil {
        return;
    }

    if node.params != nil {

        for param in node.params.list {

            for name in param.names {

                if ident, ok := name.derived.(Ident); ok {
                    write_semantic_node(builder, name, ast_context.file.src, .Parameter, .None);
                }

            }

            write_semantic_tokens(param.type, builder, ast_context);
        }

    }

    if node.results != nil {

        for result in node.results.list {


            for name in result.names {

                if ident, ok := name.derived.(Ident); ok {
                    //write_semantic_node(builder, name, ast_context.file.src, .Parameter, .None);
                }

            }

            write_semantic_tokens(result.type, builder, ast_context);

        }

    }

}

write_semantic_enum_fields :: proc(node: ast.Enum_Type, builder: ^SemanticTokenBuilder, ast_context: ^AstContext) {

    using ast;

    if node.fields == nil {
        return;
    }

    for field in node.fields {

        if ident, ok := field.derived.(Ident); ok {
            write_semantic_node(builder, field, ast_context.file.src, .EnumMember, .None);
        }

    }

}

write_semantic_selector :: proc(selector: ^ast.Selector_Expr, builder: ^SemanticTokenBuilder, ast_context: ^AstContext) {

    using ast;


    if ident, ok := selector.expr.derived.(Ident); ok {
        resolve_and_write_ident(selector.expr, builder, ast_context); //base
        resolve_and_write_expr(selector, builder, ast_context); //field
    }

    else {

    }



}

get_locals_at :: proc(function: ^ast.Node, position: ^ast.Node, ast_context: ^AstContext) {

    clear_locals(ast_context);

    if function == nil {
        return;
    }

    if position == nil {
        return;
    }

    document_position := DocumentPositionContext {
        position = position.end.offset,
    };

    get_locals(ast_context.file, function, ast_context, &document_position);
}