package server

import "core:odin/parser"
import "core:odin/ast"
import "core:odin/tokenizer"
import "core:fmt"
import "core:log"
import "core:strings"
import "core:path"
import "core:mem"

import "shared:common"
import "shared:index"


DocumentPositionContextHint :: enum {
    Completion,
    SignatureHelp,
    Definition,
};

DocumentPositionContext :: struct {
    file: ast.File,
    position: common.AbsolutePosition,
    function: ^ast.Node, //used to help with type resolving in function scope
    selector: ^ast.Expr, //used for completion
    identifier: ^ast.Node,
    field: ^ast.Expr, //used for completion
    call: ^ast.Expr, //used for signature help
    hint: DocumentPositionContextHint,
};

AstContext :: struct {
    locals: map [string] ^ast.Expr, //locals all the way to the document position
    globals: map [string] ^ast.Expr,
    file: ast.File,
    allocator: mem.Allocator,
    imports: [] Package, //imports for the current document
    current_package: string,
    document_package: string,
    use_globals: bool,
    use_locals: bool,
};

make_ast_context :: proc(file: ast.File, imports: [] Package, package_name: string, allocator := context.temp_allocator) -> AstContext {

    ast_context := AstContext {
        locals = make(map [string] ^ast.Expr, 0, allocator),
        globals = make(map [string] ^ast.Expr, 0, allocator),
        file = file,
        imports = imports,
        use_locals = true,
        use_globals = true,
        document_package = package_name,
        current_package = package_name,
    };

    return ast_context;
}

tokenizer_error_handler :: proc(pos: tokenizer.Pos, msg: string, args: ..any) {

}

resolve_type_expression :: proc(ast_context: ^AstContext, node: ^ast.Expr, expect_identifier := true) -> (index.Symbol, bool) {

    using ast;

    switch v in node.derived {
    case Ident:
        return resolve_type_identifier(ast_context, v, expect_identifier);
    case Call_Expr:
        return resolve_type_expression(ast_context, v.expr);
    case Selector_Expr:

        if selector, ok := resolve_type_expression(ast_context, v.expr); ok {

            ast_context.use_locals = false;

            switch s in selector.value {
            case index.SymbolStructValue:

                if selector.uri != "" {
                    ast_context.current_package = selector.scope;
                }

                for name, i in s.names {
                    if v.field != nil && strings.compare(name, v.field.name) == 0 {
                        return resolve_type_expression(ast_context, s.types[i], false);
                    }
                }
            case index.SymbolPackageValue:

                ast_context.current_package = selector.scope;

                if v.field != nil {
                    return index.lookup(v.field.name, selector.scope);
                }

                else {
                    log.error("No field");
                    return index.Symbol {}, false;
                }

            }

        }

        else {
            return index.Symbol {}, false;
        }
    }

    return index.Symbol {}, false;

}

/*
    Function recusively goes through the identifier until it hits a struct, enum, procedure literals, since you can
    have chained variable declarations. ie. a := foo { test =  2}; b := a; c := b;
 */
resolve_type_identifier :: proc(ast_context: ^AstContext, node: ast.Ident, expect_identifier := false) -> (index.Symbol, bool) {

    using ast;

    if local, ok := ast_context.locals[node.name]; ast_context.use_locals && ok {

        switch v in local.derived {
        case Ident:
            return resolve_type_identifier(ast_context, v);
        case Struct_Type:
            return make_symbol_struct_from_ast(ast_context, v), !expect_identifier;
        case Proc_Lit:
            return make_symbol_procedure_from_ast(ast_context, v, node.name), !expect_identifier;
        case Selector_Expr:

            if ident, ok := v.expr.derived.(Ident); ok {

                if selector, ok := resolve_type_identifier(ast_context, ident); ok {

                    if value, ok := selector.value.(index.SymbolPackageValue); ok {
                        return index.lookup(v.field.name, selector.scope);
                    }

                }

            }

            return index.Symbol {}, false;
        }
    }

    else if global, ok := ast_context.globals[node.name]; ast_context.use_globals && ok {

        switch v in global.derived {
        case Ident:
            return resolve_type_identifier(ast_context, v);
        case Struct_Type:
            return make_symbol_struct_from_ast(ast_context, v), !expect_identifier;
        case Proc_Lit:
            return make_symbol_procedure_from_ast(ast_context, v, node.name), !expect_identifier;
        case Selector_Expr:
            if ident, ok := v.expr.derived.(Ident); ok {

                if selector, ok := resolve_type_identifier(ast_context, ident); ok {

                    if value, ok := selector.value.(index.SymbolPackageValue); ok {
                        return index.lookup(v.field.name, selector.scope);
                    }

                }

            }

            return index.Symbol {}, false;
        }

    }

    //keywords
    else if node.name == "int" || node.name == "string"
        || node.name == "u64" || node.name == "f32"
        || node.name == "i64" || node.name == "i32" {

        symbol := index.Symbol {
            type = .Keyword,
        };

        return symbol, true;
    }

    //imports - probably have this higher to check imports befure everything else
    else {

        //right now we replace the package ident with the absolute directory name, so it should have '/' which is not a valid ident character
        if strings.contains(node.name, "/") {

            symbol := index.Symbol {
                    type = .Package,
                    scope = node.name,
                    value = index.SymbolPackageValue {
                    }
                };

            return symbol, true;

        }

        else {

            for imp in ast_context.imports {

                if strings.compare(imp.base, node.name) == 0 {

                    symbol := index.Symbol {
                        type = .Package,
                        scope = imp.name,
                        value = index.SymbolPackageValue {
                        }
                    };

                    return symbol, true;
                }

            }

        }

        //last option is to check the index

        return index.lookup(node.name, ast_context.current_package);


        //TODO(daniel, index can be used on identifiers if using is in the function scope)
    }

    return index.Symbol {}, false;
}

resolve_location_identifier :: proc(ast_context: ^AstContext, node: ast.Ident) -> (index.Symbol, bool) {

    symbol: index.Symbol;

    if local, ok := ast_context.locals[node.name]; ok {
        symbol.range = common.get_token_range(local, ast_context.file.src);
        return symbol, true;
    }

    else if global, ok := ast_context.globals[node.name]; ok {
        symbol.range = common.get_token_range(global, ast_context.file.src);
        return symbol, true;
    }

    return symbol, false;
}

make_symbol_procedure_from_ast :: proc(ast_context: ^AstContext, v: ast.Proc_Lit, name: string) -> index.Symbol {

    symbol := index.Symbol {
        range = common.get_token_range(v, ast_context.file.src),
        type = .Function,
    };

    symbol.name = name;
    symbol.signature = strings.concatenate( {"(", string(ast_context.file.src[v.type.params.pos.offset:v.type.params.end.offset]), ")"}, context.temp_allocator);

    return symbol;
}

make_symbol_struct_from_ast :: proc(ast_context: ^AstContext, v: ast.Struct_Type) -> index.Symbol {

    symbol := index.Symbol {
        range = common.get_token_range(v, ast_context.file.src),
        type = .Struct,
    };

    names := make([dynamic] string, 0, context.temp_allocator);
    types := make([dynamic] ^ast.Expr, 0, context.temp_allocator);

    for field in v.fields.list {

        for n in field.names {
            identifier := n.derived.(ast.Ident);
            append(&names, identifier.name);
            append(&types, ast.clone_expr(field.type));
        }

    }

    symbol.value = index.SymbolStructValue {
        names = names[:],
        types = types[:],
    };

    return symbol;
}

get_globals :: proc(file: ast.File, ast_context: ^AstContext) {

    for decl in file.decls {

        if value_decl, ok := decl.derived.(ast.Value_Decl); ok {

            for name, i in value_decl.names {

                str := common.get_ast_node_string(name, file.src);

                if value_decl.type != nil {
                    ast_context.globals[str] = value_decl.type;
                }

                else {
                    ast_context.globals[str] = value_decl.values[i];
                }

            }

        }
    }
}

get_locals :: proc(file: ast.File, function: ^ast.Node, ast_context: ^AstContext) {

    proc_lit, ok := function.derived.(ast.Proc_Lit);

    if !ok || proc_lit.body == nil {
        return;
    }

    block: ast.Block_Stmt;
    block, ok = proc_lit.body.derived.(ast.Block_Stmt);

    if !ok {
        return;
    }

    for stmt in block.stmts {

        if value_decl, ok := stmt.derived.(ast.Value_Decl); ok {

            for name, i in value_decl.names {

                str := common.get_ast_node_string(name, file.src);

                if value_decl.type != nil {
                    ast_context.locals[str] = value_decl.type;
                }

                else {
                    ast_context.locals[str] = value_decl.values[i];
                }

            }

        }

    }

}

get_definition_location :: proc(document: ^Document, position: common.Position) -> (common.Location, bool) {

    location: common.Location;


    ast_context := make_ast_context(document.ast, document.imports, document.package_name);

    uri: string;

    position_context, ok := get_document_position_context(document, position, .Definition);

    if !ok {
        log.info("Failed to get position context");
        return location, false;
    }

    get_globals(document.ast, &ast_context);

    if position_context.function != nil {
        get_locals(document.ast, position_context.function, &ast_context);
    }

    if position_context.identifier != nil {

        if resolved, ok := resolve_location_identifier(&ast_context, position_context.identifier.derived.(ast.Ident)); ok {
            location.range = resolved.range;
            location.uri = resolved.uri;
        }

        else {
            return location, false;
        }

    }

    else if position_context.selector != nil && position_context.field != nil {

        selector: index.Symbol;

        selector, ok = resolve_type_expression(&ast_context, position_context.selector);

        if !ok {
            return location, false;
        }

        field: string;

        switch v in position_context.field.derived {
        case ast.Ident:
            field = v.name;
        case:
            return location, false;
        }

        switch v in selector.value {
        case index.SymbolStructValue:
            for name, i in v.names {
                if strings.compare(name, field) == 0 {
                    location.range = common.get_token_range(v.types[i]^, document.ast.src);
                }
            }
        case index.SymbolPackageValue:
            if symbol, ok := index.lookup(field, selector.scope); ok {
                location.range = symbol.range;
                uri = symbol.uri;
            }
            else {
                return location, false;
            }
        }

        if !ok {
            return location, false;
        }

    }

    else {
        return location, false;
    }

    //if the symbol is generated by the ast we don't set the uri.
    if uri == "" {
        location.uri = document.uri.uri;
    }

    else {
        location.uri = uri;
    }

    return location, true;
}

get_completion_list :: proc(document: ^Document, position: common.Position) -> (CompletionList, bool) {

    symbols := make([dynamic] index.Symbol, 0, context.temp_allocator);

    list: CompletionList;

    ast_context := make_ast_context(document.ast, document.imports, document.package_name);

    position_context, ok := get_document_position_context(document, position, .Completion);

    get_globals(document.ast, &ast_context);

    if position_context.function != nil {
        get_locals(document.ast, position_context.function, &ast_context);
    }

    items := make([dynamic] CompletionItem, 0, context.temp_allocator);


    if position_context.selector != nil {

        selector: index.Symbol;

        selector, ok = resolve_type_expression(&ast_context, position_context.selector);

        if !ok {
            log.error("Failed to resolve type selector");
            return list, true;
        }


        if selector.uri != "" {
            ast_context.current_package = selector.scope;
        }

        field: string;

        if position_context.field != nil {

            switch v in position_context.field.derived {
            case ast.Ident:
                field = v.name;
            }

        }

        switch v in selector.value {
        case index.SymbolStructValue:
            for name, i in v.names {

                if symbol, ok := resolve_type_expression(&ast_context, v.types[i], false); ok {
                    symbol.name = name;
                    symbol.type = .Field;
                    append(&symbols, symbol);
                }

                else {
                    log.errorf("Failed to resolve field: %v", name);
                    return list, true;
                }

            }

            list.isIncomplete = false;
        case index.SymbolPackageValue:

            list.isIncomplete = true;

            if field != "" {

                if searched, ok := index.fuzzy_search(selector.name, {selector.scope}); ok {

                    for search in searched {
                        append(&symbols, search);
                    }

                }

                else {
                    log.errorf("Failed to fuzzy search, field: %v, package: %v", field, selector.scope);
                    return list, true;
                }

            }
        }

    }

    else {
        return list, true;
    }

    list.items = make([] CompletionItem, len(symbols), context.temp_allocator);

    for symbol, i in symbols {
        list.items[i].label = symbol.name;
        list.items[i].kind = cast(CompletionItemKind) symbol.type;
    }

    return list, true;
}

get_signature_information :: proc(document: ^Document, position: common.Position) -> (SignatureHelp, bool) {

    signature_help: SignatureHelp;

    ast_context := make_ast_context(document.ast, document.imports, document.package_name);

    position_context, ok := get_document_position_context(document, position, .SignatureHelp);

    if !ok {
        return signature_help, false;
    }

    if position_context.call == nil {
        return signature_help, false;
    }

    get_globals(document.ast, &ast_context);

    if position_context.function != nil {
        get_locals(document.ast, position_context.function, &ast_context);
    }

    call: index.Symbol;
    call, ok = resolve_type_expression(&ast_context, position_context.call);

    signature_information := make([] SignatureInformation, 1, context.temp_allocator);

    signature_information[0].label = strings.concatenate({call.name, call.signature}, context.temp_allocator);

    signature_help.signatures = signature_information;

    return signature_help, true;
}


/*
    Figure out what exactly is at the given position and whether it is in a function, struct, etc.
*/
get_document_position_context :: proc(document: ^Document, position: common.Position, hint: DocumentPositionContextHint) -> (DocumentPositionContext, bool) {

    position_context: DocumentPositionContext;

    position_context.hint = hint;
    position_context.file = document.ast;

    absolute_position, ok := common.get_absolute_position(position, document.text);

    if !ok {
        log.error("failed to get absolute position");
        return position_context, false;
    }

    position_context.position = absolute_position;

    for decl in document.ast.decls {
        get_document_position(decl, &position_context);
    }

    return position_context, true;
}

get_document_position :: proc{
    get_document_position_array,
    get_document_position_dynamic_array,
    get_document_position_node,
};

get_document_position_array :: proc(array: $A/[]^$T, position_context: ^DocumentPositionContext) {

    for elem, i in array {
        get_document_position(elem, position_context);
    }

}

get_document_position_dynamic_array :: proc(array: $A/[dynamic]^$T, position_context: ^DocumentPositionContext) {

    for elem, i in array {
        get_document_position(elem, position_context);
    }

}

position_in_node :: proc(node: ^ast.Node, position: common.AbsolutePosition) -> bool {
    return node != nil && node.pos.offset <= position && position <= node.end.offset;
}

get_document_position_node :: proc(node: ^ast.Node, position_context: ^DocumentPositionContext) {

    using ast;

    if node == nil {
        return;
    }

    if !position_in_node(node, position_context.position) {
        return;
    }

    switch n in node.derived {
    case Bad_Expr:
        if position_context.hint == .Completion && position_context.file.src[max(0, node.end.offset-1)] == '.' {

            str := position_context.file.src[node.pos.offset:max(0, node.end.offset-1)];

            p := parser.default_parser();

            tokenizer.init(&p.tok, str, position_context.file.fullpath);

            parser.advance_token(&p);

            //do we still have recursive dots?
            if strings.contains(string(str), ".") {
                e := parser.parse_expr(&p, true); //MEMORY LEAK - need to modify parser to allow for temp allocator
                position_context.selector = e;
            }

            else {
                //this might not hold be enough in the future
                e := parser.parse_ident(&p); //MEMORY LEAK - need to modify parser to allow for temp allocator
                position_context.selector = e;
            }


        }

    case Ident:
        position_context.identifier = node;
        return;
    case Implicit:
    case Undef:
    case Basic_Lit:
    case Ellipsis:
        get_document_position(n.expr, position_context);
    case Proc_Lit:
        get_document_position(n.type, position_context);

        if position_in_node(n.body, position_context.position) {
            position_context.function = node;
            get_document_position(n.body, position_context);
        }
    case Comp_Lit:
        get_document_position(n.type, position_context);
        get_document_position(n.elems, position_context);
    case Tag_Expr:
        get_document_position(n.expr, position_context);
    case Unary_Expr:
        get_document_position(n.expr, position_context);
    case Binary_Expr:
        get_document_position(n.left, position_context);
        get_document_position(n.right, position_context);
    case Paren_Expr:
        get_document_position(n.expr, position_context);
    case Call_Expr:
        if position_context.hint == .SignatureHelp  {
            position_context.call = cast(^Expr)node;
        }
        get_document_position(n.expr, position_context);
        get_document_position(n.args, position_context);
    case Selector_Expr:
        if position_context.hint == .Completion || position_context.hint == .Definition {
            position_context.selector = n.expr;
            position_context.field = n.field;
        }
        else {
            get_document_position(n.expr, position_context);
            get_document_position(n.field, position_context);
        }
    case Index_Expr:
        get_document_position(n.expr, position_context);
        get_document_position(n.index, position_context);
    case Deref_Expr:
        get_document_position(n.expr, position_context);
    case Slice_Expr:
        get_document_position(n.expr, position_context);
        get_document_position(n.low, position_context);
        get_document_position(n.high, position_context);
    case Field_Value:
        get_document_position(n.field, position_context);
        get_document_position(n.value, position_context);
    case Ternary_Expr:
        get_document_position(n.cond, position_context);
        get_document_position(n.x, position_context);
        get_document_position(n.y, position_context);
    case Ternary_If_Expr:
        get_document_position(n.x, position_context);
        get_document_position(n.cond, position_context);
        get_document_position(n.y, position_context);
    case Ternary_When_Expr:
        get_document_position(n.x, position_context);
        get_document_position(n.cond, position_context);
        get_document_position(n.y, position_context);
    case Type_Assertion:
        get_document_position(n.expr, position_context);
        get_document_position(n.type, position_context);
    case Type_Cast:
        get_document_position(n.type, position_context);
        get_document_position(n.expr, position_context);
    case Auto_Cast:
        get_document_position(n.expr, position_context);
    case Bad_Stmt:
    case Empty_Stmt:
    case Expr_Stmt:
        get_document_position(n.expr, position_context);
    case Tag_Stmt:
        r := cast(^Expr_Stmt)node;
        get_document_position(r.expr, position_context);
    case Assign_Stmt:
        get_document_position(n.lhs, position_context);
        get_document_position(n.rhs, position_context);
    case Block_Stmt:
        get_document_position(n.label, position_context);
        get_document_position(n.stmts, position_context);
    case If_Stmt:
        get_document_position(n.label, position_context);
        get_document_position(n.init, position_context);
        get_document_position(n.cond, position_context);
        get_document_position(n.body, position_context);
        get_document_position(n.else_stmt, position_context);
    case When_Stmt:
        get_document_position(n.cond, position_context);
        get_document_position(n.body, position_context);
        get_document_position(n.else_stmt, position_context);
    case Return_Stmt:
        get_document_position(n.results, position_context);
    case Defer_Stmt:
        get_document_position(n.stmt, position_context);
    case For_Stmt:
        get_document_position(n.label, position_context);
        get_document_position(n.init, position_context);
        get_document_position(n.cond, position_context);
        get_document_position(n.post, position_context);
        get_document_position(n.body, position_context);
    case Range_Stmt:
        get_document_position(n.label, position_context);
        get_document_position(n.val0, position_context);
        get_document_position(n.val1, position_context);
        get_document_position(n.expr, position_context);
        get_document_position(n.body, position_context);
    case Case_Clause:
        get_document_position(n.list, position_context);
        get_document_position(n.body, position_context);
    case Switch_Stmt:
        get_document_position(n.label, position_context);
        get_document_position(n.init, position_context);
        get_document_position(n.cond, position_context);
        get_document_position(n.body, position_context);
    case Type_Switch_Stmt:
        get_document_position(n.label, position_context);
        get_document_position(n.tag, position_context);
        get_document_position(n.expr, position_context);
        get_document_position(n.body, position_context);
    case Branch_Stmt:
        get_document_position(n.label, position_context);
    case Using_Stmt:
        get_document_position(n.list, position_context);
    case Bad_Decl:
    case Value_Decl:
        get_document_position(n.attributes, position_context);
        get_document_position(n.names, position_context);
        get_document_position(n.type, position_context);
        get_document_position(n.values, position_context);
    case Package_Decl:
    case Import_Decl:
    case Foreign_Block_Decl:
        get_document_position(n.attributes, position_context);
        get_document_position(n.foreign_library, position_context);
        get_document_position(n.body, position_context);
    case Foreign_Import_Decl:
        get_document_position(n.name, position_context);
    case Proc_Group:
        get_document_position(n.args, position_context);
    case Attribute:
        get_document_position(n.elems, position_context);
    case Field:
        get_document_position(n.names, position_context);
        get_document_position(n.type, position_context);
        get_document_position(n.default_value, position_context);
    case Field_List:
        get_document_position(n.list, position_context);
    case Typeid_Type:
        get_document_position(n.specialization, position_context);
    case Helper_Type:
        get_document_position(n.type, position_context);
    case Distinct_Type:
        get_document_position(n.type, position_context);
    case Opaque_Type:
        get_document_position(n.type, position_context);
    case Poly_Type:
        get_document_position(n.type, position_context);
        get_document_position(n.specialization, position_context);
    case Proc_Type:
        get_document_position(n.params, position_context);
        get_document_position(n.results, position_context);
    case Pointer_Type:
        get_document_position(n.elem, position_context);
    case Array_Type:
        get_document_position(n.len, position_context);
        get_document_position(n.elem, position_context);
    case Dynamic_Array_Type:
        get_document_position(n.elem, position_context);
    case Struct_Type:
        get_document_position(n.poly_params, position_context);
        get_document_position(n.align, position_context);
        get_document_position(n.fields, position_context);
    case Union_Type:
        get_document_position(n.poly_params, position_context);
        get_document_position(n.align, position_context);
        get_document_position(n.variants, position_context);
    case Enum_Type:
        get_document_position(n.base_type, position_context);
        get_document_position(n.fields, position_context);
    case Bit_Field_Type:
        get_document_position(n.fields, position_context);
    case Bit_Set_Type:
        get_document_position(n.elem, position_context);
        get_document_position(n.underlying, position_context);
    case Map_Type:
        get_document_position(n.key, position_context);
        get_document_position(n.value, position_context);
    case:
        fmt.panicf("Unhandled node kind: %T", n);
    }

}