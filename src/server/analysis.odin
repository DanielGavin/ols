package server

import "core:odin/parser"
import "core:odin/ast"
import "core:odin/tokenizer"
import "core:fmt"
import "core:log"
import "core:strings"
import "core:path"
import "core:mem"
import "core:strconv"

import "shared:common"
import "shared:index"


bool_lit := "bool";
int_lit := "int";
string_lit := "string";

DocumentPositionContextHint :: enum {
    Completion,
    SignatureHelp,
    Definition,
};

DocumentPositionContext :: struct {
    file: ast.File,
    position: common.AbsolutePosition,
    line: int,
    function: ^ast.Node, //used to help with type resolving in function scope
    selector: ^ast.Expr, //used for completion
    identifier: ^ast.Node,
    field: ^ast.Expr, //used for completion
    call: ^ast.Expr, //used for signature help
    returns: ^ast.Expr, //used for completion
    hint: DocumentPositionContextHint,
};

AstContext :: struct {
    locals: map [string] ^ast.Expr, //locals all the way to the document position
    globals: map [string] ^ast.Expr,
    variables: map [string] bool,
    parameters: map [string] bool,
    usings: [dynamic] string,
    file: ast.File,
    allocator: mem.Allocator,
    imports: [] Package, //imports for the current document
    current_package: string,
    document_package: string,
    use_globals: bool,
    use_locals: bool,
    use_selection: bool,
    call: ^ast.Expr, //used to determene the types for generics and the correct function for overloaded functions
};

make_ast_context :: proc(file: ast.File, imports: [] Package, package_name: string, selection := false, allocator := context.temp_allocator) -> AstContext {

    ast_context := AstContext {
        locals = make(map [string] ^ast.Expr, 0, allocator),
        globals = make(map [string] ^ast.Expr, 0, allocator),
        variables = make(map [string] bool, 0, allocator),
        usings = make([dynamic] string, allocator),
        parameters = make(map [string] bool, 0, allocator),
        file = file,
        imports = imports,
        use_locals = true,
        use_globals = true,
        use_selection = selection,
        document_package = package_name,
        current_package = package_name,
    };
    return ast_context;
}

tokenizer_error_handler :: proc(pos: tokenizer.Pos, msg: string, args: ..any) {

}

/*
    Walk through the type expression while both the call expression and specialization type are the same
 */

resolve_poly_spec :: proc {
    resolve_poly_spec_node,
    resolve_poly_spec_array,
    resolve_poly_spec_dynamic_array,
};

resolve_poly_spec_array :: proc(ast_context: ^AstContext, call_array: $A/[]^$T, spec_array: $D/[]^$K, poly_map: ^map[string]^ast.Expr) {

    if len(call_array) != len(spec_array) {
        return;
    }

    for elem, i in call_array {
        resolve_poly_spec(ast_context, elem, spec_array[i], poly_map);
    }

}

resolve_poly_spec_dynamic_array :: proc(ast_context: ^AstContext, call_array: $A/[dynamic]^$T, spec_array: $D/[dynamic]^$K, poly_map: ^map[string]^ast.Expr) {

    if len(call_array) != len(spec_array) {
        return;
    }

    for elem, i in call_array {
        resolve_poly_spec(ast_context, elem, spec_array[i],  poly_map);
    }

}

get_poly_node_to_expr :: proc(node: ^ast.Node) -> ^ast.Expr {

    using ast;

    switch v in node.derived {
    case Ident:
        return cast(^Expr)node;
    case:
        log.errorf("Unhandled poly to node kind %v", v);
    }

    return nil;
}

resolve_poly_spec_node :: proc(ast_context: ^AstContext, call_node: ^ast.Node, spec_node: ^ast.Node, poly_map: ^map[string]^ast.Expr) {

    /*
        Note(Daniel, uncertain about the switch cases being enough or too little)
    */

    using ast;

    if call_node == nil || spec_node == nil {
        return;
    }

    switch m in spec_node.derived {
    case Bad_Expr:
    case Ident:
    case Implicit:
    case Undef:
    case Basic_Lit:
    case Poly_Type:
        if expr := get_poly_node_to_expr(call_node); expr != nil {
            poly_map[m.type.name] = expr;
        }
    case Ellipsis:
        if n, ok := call_node.derived.(Ellipsis); ok {
            resolve_poly_spec(ast_context, n.expr, m.expr, poly_map);
        }
    case Tag_Expr:
        if n, ok := call_node.derived.(Tag_Expr); ok {
            resolve_poly_spec(ast_context, n.expr, m.expr, poly_map);
        }
    case Unary_Expr:
        if n, ok := call_node.derived.(Unary_Expr); ok {
            resolve_poly_spec(ast_context, n.expr, m.expr, poly_map);
        }
    case Binary_Expr:
        if n, ok := call_node.derived.(Binary_Expr); ok {
            resolve_poly_spec(ast_context, n.left, m.left, poly_map);
            resolve_poly_spec(ast_context, n.right, m.right, poly_map);
        }
    case Paren_Expr:
        if n, ok := call_node.derived.(Paren_Expr); ok {
            resolve_poly_spec(ast_context, n.expr, m.expr, poly_map);
        }
    case Selector_Expr:
        if n, ok := call_node.derived.(Selector_Expr); ok {
            resolve_poly_spec(ast_context, n.expr, m.expr, poly_map);
            resolve_poly_spec(ast_context, n.field, m.field, poly_map);
        }
    case Slice_Expr:
        if n, ok := call_node.derived.(Slice_Expr); ok {
            resolve_poly_spec(ast_context, n.expr, m.expr, poly_map);
            resolve_poly_spec(ast_context, n.low, m.low, poly_map);
            resolve_poly_spec(ast_context, n.high, m.high, poly_map);
        }
    case Distinct_Type:
        if n, ok := call_node.derived.(Distinct_Type); ok {
            resolve_poly_spec(ast_context, n.type, m.type, poly_map);
        }
    case Opaque_Type:
        if n, ok := call_node.derived.(Opaque_Type); ok {
            resolve_poly_spec(ast_context, n.type, m.type, poly_map);
        }
    case Proc_Type:
        if n, ok := call_node.derived.(Proc_Type); ok {
            resolve_poly_spec(ast_context, n.params, m.params, poly_map);
            resolve_poly_spec(ast_context, n.results, m.results, poly_map);
        }
    case Pointer_Type:
        if n, ok := call_node.derived.(Pointer_Type); ok {
            resolve_poly_spec(ast_context, n.elem, m.elem, poly_map);
        }
    case Array_Type:
        if n, ok := call_node.derived.(Array_Type); ok {
            resolve_poly_spec(ast_context, n.len, m.len, poly_map);
            resolve_poly_spec(ast_context, n.elem, m.elem, poly_map);
        }
    case Dynamic_Array_Type:
        if n, ok := call_node.derived.(Dynamic_Array_Type); ok {
            resolve_poly_spec(ast_context, n.elem, m.elem, poly_map);
        }
    case Struct_Type:
        if n, ok := call_node.derived.(Struct_Type); ok {
            resolve_poly_spec(ast_context, n.poly_params, m.poly_params, poly_map);
            resolve_poly_spec(ast_context, n.align, m.align, poly_map);
            resolve_poly_spec(ast_context, n.fields, m.fields, poly_map);
        }
    case Field:
        if n, ok := call_node.derived.(Field); ok {
            resolve_poly_spec(ast_context, n.names, m.names, poly_map);
            resolve_poly_spec(ast_context, n.type, m.type, poly_map);
            resolve_poly_spec(ast_context, n.default_value, m.default_value, poly_map);
        }
	case Field_List:
        if n, ok := call_node.derived.(Field_List); ok {
            resolve_poly_spec(ast_context, n.list, m.list, poly_map);
        }
    case Field_Value:
        if n, ok := call_node.derived.(Field_Value); ok {
            resolve_poly_spec(ast_context, n.field, m.field, poly_map);
            resolve_poly_spec(ast_context, n.value, m.value, poly_map);
        }
    case Union_Type:
        if n, ok := call_node.derived.(Union_Type); ok {
            resolve_poly_spec(ast_context, n.poly_params, m.poly_params, poly_map);
            resolve_poly_spec(ast_context, n.align, m.align, poly_map);
            resolve_poly_spec(ast_context, n.variants, m.variants, poly_map);
        }
    case Enum_Type:
        if n, ok := call_node.derived.(Enum_Type); ok {
            resolve_poly_spec(ast_context, n.base_type, m.base_type, poly_map);
            resolve_poly_spec(ast_context, n.fields, m.fields, poly_map);
        }
    case Bit_Field_Type:
        if n, ok := call_node.derived.(Bit_Field_Type); ok {
            resolve_poly_spec(ast_context, n.fields, m.fields, poly_map);
        }
    case Bit_Set_Type:
        if n, ok := call_node.derived.(Bit_Set_Type); ok {
            resolve_poly_spec(ast_context, n.elem, m.elem, poly_map);
            resolve_poly_spec(ast_context, n.underlying, m.underlying, poly_map);
        }
    case Map_Type:
        if n, ok := call_node.derived.(Map_Type); ok {
            resolve_poly_spec(ast_context, n.key, m.key, poly_map);
            resolve_poly_spec(ast_context, n.value, m.value, poly_map);
        }
    case Call_Expr:
        if n, ok := call_node.derived.(Call_Expr); ok {
            resolve_poly_spec(ast_context, n.expr, m.expr, poly_map);
            resolve_poly_spec(ast_context, n.args, m.args, poly_map);
        }
    case Typeid_Type:
        if n, ok := call_node.derived.(Typeid_Type); ok {
            resolve_poly_spec(ast_context, n.specialization, m.specialization, poly_map);
        }
    case:
        log.error("Unhandled poly node kind: %T", m);
    }

}

resolve_generic_function :: proc {
    resolve_generic_function_ast,
    resolve_generic_function_symbol,
};

resolve_generic_function_symbol :: proc(ast_context: ^AstContext, params: []^ast.Field, results: []^ast.Field) -> (index.Symbol, bool) {
    using ast;

    if params == nil {
        return index.Symbol {}, false;
    }

    if results == nil {
        return index.Symbol {}, false;
    }

    if ast_context.call == nil {
        return index.Symbol {}, false;
    }

    call_expr := ast_context.call.derived.(Call_Expr);
    poly_map := make(map[string]^Expr, 0, context.temp_allocator);
    i := 0;


    for param in params {

        for name in param.names {

            if len(call_expr.args) >= i {
                break;
            }

            if poly, ok := name.derived.(Poly_Type); ok {
                poly_map[poly.type.name] = call_expr.args[i];
            }

            if param.type == nil {
                continue;
            }

            if poly, ok := param.type.derived.(Poly_Type); ok {

                if arg_eval, ok := resolve_type_expression(ast_context, call_expr.args[i]); ok {

                    if value, ok := arg_eval.value.(index.SymbolGenericValue); ok {
                        resolve_poly_spec_node(ast_context, value.expr, poly.specialization, &poly_map);
                    }

                }
            }

            i += 1;
        }

    }

    function_name := "";
    function_range: common.Range;

    if ident, ok := call_expr.expr.derived.(Ident); ok {
        function_name = ident.name;
        function_range = common.get_token_range(ident, ast_context.file.src);
    }

    else if selector, ok := call_expr.expr.derived.(Selector_Expr); ok {
        function_name = selector.field.name;
        function_range = common.get_token_range(selector, ast_context.file.src);
    }

    else {
        log.debug("call expr expr could not be derived correctly");
        return index.Symbol {}, false;
    }

    symbol := index.Symbol {
       range = function_range,
       type = .Function,
       name = function_name,
    };

    //symbol.signature = strings.concatenate( {"(", string(ast_context.file.src[params[0].pos.offset:params[len(params)-1].end.offset]), ")"}, context.temp_allocator);

    return_types := make([dynamic] ^ast.Field, context.temp_allocator);

    for result in results {

        if result.type == nil {
            continue;
        }

        if ident, ok := result.type.derived.(Ident); ok {
            field := cast(^Field)index.clone_node(result, context.temp_allocator, nil);

            if m := &poly_map[ident.name]; m != nil {
                field.type = poly_map[ident.name];
                append(&return_types, field);
            }

            else{
                return index.Symbol {}, false;
            }

        }

    }


    symbol.value = index.SymbolProcedureValue {
        return_types = return_types[:],
        arg_types = params,
    };


    //log.infof("return %v", poly_map);

    return symbol, true;
}

resolve_generic_function_ast :: proc(ast_context: ^AstContext, proc_lit: ast.Proc_Lit) -> (index.Symbol, bool) {

    using ast;

    if proc_lit.type.params == nil {
        return index.Symbol {}, false;
    }

    if proc_lit.type.results == nil {
        return index.Symbol {}, false;
    }

    if ast_context.call == nil {
        return index.Symbol {}, false;
    }

    return resolve_generic_function_symbol(ast_context, proc_lit.type.params.list, proc_lit.type.results.list);
}


/*
    Figure out which function the call expression is using out of the list from proc group
 */
resolve_function_overload :: proc(ast_context: ^AstContext, group: ast.Proc_Group) ->  (index.Symbol, bool) {

    using ast;

    //log.info("overload");

    if ast_context.call == nil {
        //log.info("no call");
        return index.Symbol {}, false;
    }

    call_expr := ast_context.call.derived.(Call_Expr);

    for arg_expr in group.args {

        next_fn: if f, ok := resolve_type_expression(ast_context, arg_expr); ok {

            if procedure, ok := f.value.(index.SymbolProcedureValue); ok {

                if len(procedure.arg_types) < len(call_expr.args) {
                    continue;
                }

                for arg, i in call_expr.args {

                    if eval_call_expr, ok := resolve_type_expression(ast_context, arg); ok {

                        #partial switch v in eval_call_expr.value {
                        case index.SymbolProcedureValue:
                        case index.SymbolGenericValue:
                            if !common.node_equal(v.expr, procedure.arg_types[i].type) {
                                break next_fn;
                            }
                        case index.SymbolStructValue:
                        }

                    }

                    else {
                        //log.debug("Failed to resolve call expr");
                        return index.Symbol {}, false;
                    }
                }

                //log.debugf("return overload %v", f);
                return f, true;
            }

        }

    }


    return index.Symbol {}, false;
}

resolve_basic_lit :: proc(ast_context: ^AstContext, basic_lit: ast.Basic_Lit) -> (index.Symbol, bool) {

    /*
        This is temporary, since basic lit is untyped, but either way it's going to be an ident representing a keyword.

        Could perhaps name them "$integer", "$float", etc.
     */

    ident := index.new_type(ast.Ident, basic_lit.pos, basic_lit.end, context.temp_allocator);

    symbol := index.Symbol {
        type = .Keyword,
    };

    if v, ok := strconv.parse_bool(basic_lit.tok.text); ok {
        ident.name = bool_lit;
    }

    else if v, ok := strconv.parse_int(basic_lit.tok.text); ok {
        ident.name = int_lit;
    }

    else {
        ident.name = string_lit;
    }

    symbol.value = index.SymbolGenericValue {
        expr = ident,
    };

    return symbol, true;
}

resolve_type_expression :: proc(ast_context: ^AstContext, node: ^ast.Expr) -> (index.Symbol, bool) {

    if node == nil {
        return {}, false;
    }

    using ast;

    switch v in node.derived {
    case Ident:
        return resolve_type_identifier(ast_context, v);
    case Basic_Lit:
        return resolve_basic_lit(ast_context, v);
    case Type_Assertion:
        resolve_type_expression(ast_context, v.type);
    case Pointer_Type:

        if v2, ok := v.elem.derived.(ast.Pointer_Type); !ok {
            return resolve_type_expression(ast_context, v.elem);
        }

        else {
            return make_symbol_generic_from_ast(ast_context, node), true;
        }

    case Index_Expr:
        indexed, ok := resolve_type_expression(ast_context, v.expr);

        if generic, ok := indexed.value.(index.SymbolGenericValue); ok {

            switch c in generic.expr.derived {
            case Array_Type:
                return resolve_type_expression(ast_context, c.elem);
            case Dynamic_Array_Type:
                return resolve_type_expression(ast_context, c.elem);

            }

        }

        return index.Symbol {}, false;
    case Call_Expr:
        ast_context.call = node;
        return resolve_type_expression(ast_context, v.expr);
    case Implicit_Selector_Expr:
        log.info(v);
        return index.Symbol {}, false;
    case Selector_Expr:

        if ident, ok := v.expr.derived.(Ident); ok {

            if !resolve_ident_is_variable(ast_context, ident) && !resolve_ident_is_package(ast_context, ident) {
                log.debugf("not a variable or package %v", ident.name);
                return {}, false;
            }

        }

        if selector, ok := resolve_type_expression(ast_context, v.expr); ok {

            ast_context.use_locals = false;

            #partial switch s in selector.value {
            case index.SymbolStructValue:
                if selector.uri != "" {
                    ast_context.current_package = selector.pkg;
                }

                else {
                    ast_context.current_package = ast_context.document_package;
                }

                for name, i in s.names {
                    if v.field != nil && strings.compare(name, v.field.name) == 0 {
                        return resolve_type_expression(ast_context, s.types[i]);
                    }
                }
            case index.SymbolPackageValue:

                ast_context.current_package = selector.pkg;

                if v.field != nil {
                    return resolve_symbol_return(ast_context, index.lookup(v.field.name, selector.pkg));
                }

                else {
                    log.error("No field");
                    return index.Symbol {}, false;
                }
            case index.SymbolGenericValue:

                /*
                    Slighty awkward, but you could have a pointer to struct, so have to check, i don't want to remove the pointer info by storing into the struct symbol value,
                    since it can be used for signature infering.
                */

                if ptr, ok := s.expr.derived.(Pointer_Type); ok {

                    if ident, ok := v.expr.derived.(Ident); ok {

                        if !resolve_ident_is_variable(ast_context, ident) && !resolve_ident_is_package(ast_context, ident) {
                            log.debugf("not a variable or package %v", ident.name);
                            return {}, false;
                        }

                    }

                    if symbol, ok := resolve_type_expression(ast_context, ptr.elem); ok {

                        #partial switch s2 in symbol.value {
                        case index.SymbolStructValue:

                            if selector.uri != "" {
                                ast_context.current_package = symbol.pkg;
                            }

                            else {
                                ast_context.current_package = ast_context.document_package;
                            }

                            for name, i in s2.names {
                                if v.field != nil && strings.compare(name, v.field.name) == 0 {
                                    return resolve_type_expression(ast_context, s2.types[i]);
                                }
                            }

                        }
                    }

                }

            }

        }

        else {
            return index.Symbol {}, false;
        }
    case:
        //log.debugf("default node kind, resolve_type_expression: %T", v);
        return make_symbol_generic_from_ast(ast_context, node), true;
    }

    return index.Symbol {}, false;

}


/*
    Function recusively goes through the identifier until it hits a struct, enum, procedure literals, since you can
    have chained variable declarations. ie. a := foo { test =  2}; b := a; c := b;
 */
resolve_type_identifier :: proc(ast_context: ^AstContext, node: ast.Ident) -> (index.Symbol, bool) {

    using ast;

    if _, ok := ast_context.parameters[node.name]; ok {
        for imp in ast_context.imports {

            if strings.compare(imp.base, node.name) == 0 {

                symbol := index.Symbol {
                    type = .Package,
                    pkg = imp.name,
                    value = index.SymbolPackageValue {
                    }
                };

                return symbol, true;
            }

        }
    }

    //note(Daniel, if global and local ends up being 100% same just make a function that takes the map)
    if local, ok := ast_context.locals[node.name]; ast_context.use_locals && ok {

        switch v in local.derived {
        case Ident:

            if node.name == v.name {
                break;
            }

            return resolve_type_identifier(ast_context, v);
        case Union_Type:
            return make_symbol_union_from_ast(ast_context, v), true;
        case Enum_Type:
            return make_symbol_enum_from_ast(ast_context, v), true;
        case Struct_Type:
            return make_symbol_struct_from_ast(ast_context, v), true;
        case Proc_Lit:
            if !v.type.generic {
                if ast_context.use_selection {
                    if v.type.results != nil {
                        if len(v.type.results.list) == 1 {
                            //ERROR v.type.results.list[0].
                            return resolve_type_expression(ast_context, v.type.results.list[0].type);
                        }
                    }
                }
                else {
                    return make_symbol_procedure_from_ast(ast_context, v, node.name), true;
                }
            }
            else {
                return resolve_generic_function(ast_context, v);
            }
        case Proc_Group:
            return resolve_function_overload(ast_context, v);
        case Selector_Expr:
            return resolve_type_expression(ast_context, local);
        case Array_Type:
            return make_symbol_generic_from_ast(ast_context, local), true;
        case Dynamic_Array_Type:
            return make_symbol_generic_from_ast(ast_context, local), true;
        case Index_Expr:
            return resolve_type_expression(ast_context, local);
        case Pointer_Type:
            return resolve_type_expression(ast_context, local);
        case:
            log.errorf("default type node kind: %T", v);
            return make_symbol_generic_from_ast(ast_context, local), true;
        }
    }

    else if global, ok := ast_context.globals[node.name]; ast_context.use_globals && ok {

        switch v in global.derived {
        case Ident:

            if node.name == v.name {
                break;
            }

            return resolve_type_identifier(ast_context, v);
        case Struct_Type:
            return make_symbol_struct_from_ast(ast_context, v), true;
        case Union_Type:
            return make_symbol_union_from_ast(ast_context, v), true;
        case Enum_Type:
            return make_symbol_enum_from_ast(ast_context, v), true;
        case Proc_Lit:
            if !v.type.generic {
                if ast_context.use_selection {
                    if v.type.results != nil {
                        if len(v.type.results.list) == 1 {
                            return resolve_type_expression(ast_context, v.type.results.list[0].type);
                        }
                    }
                }
                else {
                    return make_symbol_procedure_from_ast(ast_context, v, node.name), true;
                }
            }
            else {
                return resolve_generic_function(ast_context, v);
            }
        case Proc_Group:
            return resolve_function_overload(ast_context, v);
        case Selector_Expr:
            return resolve_type_expression(ast_context, local);
        case Array_Type:
            return make_symbol_generic_from_ast(ast_context, global), true;
        case Dynamic_Array_Type:
            return make_symbol_generic_from_ast(ast_context, global), true;
        case Index_Expr:
            return resolve_type_expression(ast_context, global);
        case Pointer_Type:
            return resolve_type_expression(ast_context, local);
        case:
            log.errorf("default type node kind: %T", v);
            return make_symbol_generic_from_ast(ast_context, global), true;
        }

    }

    //keywords
    else if v, ok := common.keyword_map[node.name]; ok {

        ident := index.new_type(Ident, node.pos, node.end, context.temp_allocator);
        ident.name = node.name;

        symbol := index.Symbol {
            type = .Keyword,
            signature = node.name,
            pkg = ast_context.current_package,
            value = index.SymbolGenericValue {
                expr = ident,
            },
        };

        return symbol, true;
    }

    else {

        //right now we replace the package ident with the absolute directory name, so it should have '/' which is not a valid ident character
        if strings.contains(node.name, "/") {

            symbol := index.Symbol {
                    type = .Package,
                    pkg = node.name,
                    value = index.SymbolPackageValue {
                    }
            };

            return symbol, true;

        }

        //part of the ast so we check the imports of the document
        else {

            for imp in ast_context.imports {

                if strings.compare(imp.base, node.name) == 0 {

                    symbol := index.Symbol {
                        type = .Package,
                        pkg = imp.name,
                        value = index.SymbolPackageValue {
                        }
                    };

                    return symbol, true;
                }

            }

        }

        //last option is to check the index

        if symbol, ok := index.lookup(node.name, ast_context.current_package); ok {
            return resolve_symbol_return(ast_context, symbol);
        }

        for u in ast_context.usings {

            //TODO(Daniel, make into a map, not really required for performance but looks nicer)
            for imp in ast_context.imports {

                if strings.compare(imp.base, u) == 0 {

                    if symbol, ok := index.lookup(node.name, imp.name); ok {
                        return resolve_symbol_return(ast_context, symbol);
                    }
                }

            }
        }

        //TODO(daniel, index can be used on identifiers if using is in the function scope)
    }

    return index.Symbol {}, false;
}

resolve_ident_is_variable ::  proc(ast_context: ^AstContext, node: ast.Ident) -> bool {

    if v, ok := ast_context.variables[node.name]; ok {
        return v;
    }

    return false;
}

resolve_ident_is_package ::  proc(ast_context: ^AstContext, node: ast.Ident) -> bool {

    if strings.contains(node.name, "/") {
        return true;
    }

    else {

        for imp in ast_context.imports {

            if strings.compare(imp.base, node.name) == 0 {
                return true;
            }

        }

    }

    return false;
}


resolve_symbol_return :: proc(ast_context: ^AstContext, symbol: index.Symbol, ok := true) -> (index.Symbol, bool) {

    if !ok {
        return symbol, ok;
    }

    #partial switch v in symbol.value {
    case index.SymbolProcedureGroupValue:
        if symbol, ok := resolve_function_overload(ast_context, v.group.derived.(ast.Proc_Group)); ok {
            return symbol, true;
        }
        else {
            return symbol, false;
        }
    case index.SymbolProcedureValue:
        if v.generic {
            return resolve_generic_function_symbol(ast_context, v.arg_types, v.return_types);
        }
        else {
            return symbol, true;
        }
    }

    return symbol, true;
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


    return index.lookup(node.name, ast_context.document_package);
}

make_bool_ast :: proc() -> ^ast.Ident {

    ident := index.new_type(ast.Ident, {}, {}, context.temp_allocator);

    ident.name = bool_lit;

    return ident;
}

make_int_ast :: proc() -> ^ast.Ident {

    ident := index.new_type(ast.Ident, {}, {}, context.temp_allocator);

    ident.name = int_lit;

    return ident;
}

make_symbol_procedure_from_ast :: proc(ast_context: ^AstContext, v: ast.Proc_Lit, name: string) -> index.Symbol {

    symbol := index.Symbol {
        range = common.get_token_range(v, ast_context.file.src),
        type = .Function,
        pkg = ast_context.current_package,
    };

    symbol.name = name;

    return_types := make([dynamic] ^ast.Field, context.temp_allocator);
    arg_types := make([dynamic] ^ast.Field, context.temp_allocator);

    if v.type.results != nil {

        for ret in v.type.results.list {
            append(&return_types, ret);
        }

        symbol.returns = strings.concatenate( {"(", string(ast_context.file.src[v.type.results.pos.offset:v.type.results.end.offset]), ")"}, context.temp_allocator);

    }

    if v.type.params != nil {

        for param in v.type.params.list {
            append(&arg_types, param);
        }

        symbol.signature = strings.concatenate( {"(", string(ast_context.file.src[v.type.params.pos.offset:v.type.params.end.offset]), ")"}, context.temp_allocator);
    }

    symbol.value = index.SymbolProcedureValue {
        return_types = return_types[:],
        arg_types = arg_types[:],
    };

    return symbol;
}

make_symbol_generic_from_ast :: proc(ast_context: ^AstContext, expr: ^ast.Expr) -> index.Symbol {

    symbol := index.Symbol {
        range = common.get_token_range(expr, ast_context.file.src),
        type = .Variable,
        pkg = ast_context.current_package,
        signature = common.get_ast_node_string(expr, ast_context.file.src),
    };

    symbol.value = index.SymbolGenericValue {
        expr = expr,
    };

    return symbol;
}

make_symbol_union_from_ast :: proc(ast_context: ^AstContext, v: ast.Union_Type) -> index.Symbol {

    symbol := index.Symbol {
        range = common.get_token_range(v, ast_context.file.src),
        type = .Enum,
        pkg = ast_context.current_package,
    };

    names := make([dynamic] string, context.temp_allocator);

    for variant in v.variants {

        if ident, ok := variant.derived.(ast.Ident); ok {
            append(&names, ident.name);
        }

    }

    symbol.value = index.SymbolUnionValue {
        names = names[:],
    };

    return symbol;
}

make_symbol_enum_from_ast :: proc(ast_context: ^AstContext, v: ast.Enum_Type) -> index.Symbol {

    symbol := index.Symbol {
        range = common.get_token_range(v, ast_context.file.src),
        type = .Enum,
        pkg = ast_context.current_package,
    };

    names := make([dynamic] string, context.temp_allocator);

    for field in v.fields {

        if ident, ok := field.derived.(ast.Ident); ok {
            append(&names, ident.name);
        }

    }

    symbol.value = index.SymbolEnumValue {
        names = names[:],
    };

    return symbol;
}

make_symbol_struct_from_ast :: proc(ast_context: ^AstContext, v: ast.Struct_Type) -> index.Symbol {

    symbol := index.Symbol {
        range = common.get_token_range(v, ast_context.file.src),
        type = .Struct,
        pkg = ast_context.current_package,
    };

    names := make([dynamic] string, context.temp_allocator);
    types := make([dynamic] ^ast.Expr, context.temp_allocator);

    for field in v.fields.list {

        for n in field.names {
            if identifier, ok := n.derived.(ast.Ident); ok {
                append(&names, identifier.name);

                if .Using in field.flags {

                }
                else {
                    append(&types, index.clone_type(field.type, context.temp_allocator, nil));
                }
            }
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
                    if len(value_decl.values) > i {
                        ast_context.globals[str] = value_decl.values[i];
                    }
                }

            }

        }
    }
}

get_generic_assignment :: proc(file: ast.File, value: ^ast.Expr, ast_context: ^AstContext, results: ^[dynamic]^ast.Expr) {

    using ast;

    ast_context.use_locals = true;
    ast_context.use_globals = true;

    switch v in value.derived {
    case Call_Expr:

        ast_context.call = value;

        if symbol, ok := resolve_type_expression(ast_context, v.expr); ok {

            if procedure, ok := symbol.value.(index.SymbolProcedureValue); ok {

                for ret in procedure.return_types {
                    append(results, ret.type);
                }

            }

        }

    case Comp_Lit:
        if v.type != nil {
            append(results, v.type);
        }
    case Array_Type:
        if v.elem != nil {
            append(results, v.elem);
        }
    case Dynamic_Array_Type:
        if v.elem != nil {
            append(results, v.elem);
        }
    case Selector_Expr:
        if v.expr != nil {
            append(results, value);
        }
    case Type_Assertion:
        if v.type != nil {
            append(results, v.type);
            append(results, make_bool_ast());
        }
    case:
        //log.debugf("default node get_generic_assignment %v", v);
        append(results, value);
    }

}

get_locals_value_decl :: proc(file: ast.File, value_decl: ast.Value_Decl, ast_context: ^AstContext) {

    using ast;

    if len(value_decl.names) <= 0 {
        return;
    }


    if value_decl.type != nil {
        str := common.get_ast_node_string(value_decl.names[0], file.src);
        ast_context.variables[str] = value_decl.is_mutable;
        ast_context.locals[str] = value_decl.type;
        return;
    }

    results := make([dynamic]^Expr, context.temp_allocator);

    for value in value_decl.values {
        get_generic_assignment(file, value, ast_context, &results);
    }


    for name, i in value_decl.names {
        if i < len(results) {
            str := common.get_ast_node_string(name, file.src);
            ast_context.locals[str] = results[i];
            ast_context.variables[str] = value_decl.is_mutable;
        }
    }



}

get_locals_stmt :: proc(file: ast.File, stmt: ^ast.Stmt, ast_context: ^AstContext, document_position: ^DocumentPositionContext) {

    ast_context.use_locals = true;
    ast_context.use_globals = true;

    using ast;

    if stmt == nil {
        return;
    }

    if stmt.pos.offset > document_position.position {
        return;
    }

    switch v in stmt.derived {
    case Value_Decl:
        get_locals_value_decl(file, v, ast_context);
    case Type_Switch_Stmt:
        get_locals_type_switch_stmt(file, v, ast_context, document_position);
    case Switch_Stmt:
        get_locals_switch_stmt(file, v, ast_context, document_position);
    case For_Stmt:
        get_locals_for_stmt(file, v, ast_context, document_position);
    case Range_Stmt:
        get_locals_for_range_stmt(file, v, ast_context, document_position);
    case If_Stmt:
        get_locals_if_stmt(file, v, ast_context, document_position);
    case Block_Stmt:
        for stmt in v.stmts {
            get_locals_stmt(file, stmt, ast_context, document_position);
        }
    case Assign_Stmt:
        get_locals_assign_stmt(file, v, ast_context);
    case Using_Stmt:
        get_locals_using_stmt(file, v, ast_context);
    case:
        //log.debugf("default node local stmt %v", v);
    }



}

get_locals_using_stmt :: proc(file: ast.File, stmt: ast.Using_Stmt, ast_context: ^AstContext) {

    for u in stmt.list {

        if symbol, ok := resolve_type_expression(ast_context, u); ok {

            #partial switch v in symbol.value {
            case index.SymbolPackageValue:
                if ident, ok := u.derived.(ast.Ident); ok {
                    append(&ast_context.usings, ident.name);
                }
            case index.SymbolStructValue:
                for name, i in v.names {
                    selector := index.new_type(ast.Selector_Expr, v.types[i].pos, v.types[i].end, context.temp_allocator);
                    selector.expr = u;
                    selector.field = index.new_type(ast.Ident, v.types[i].pos, v.types[i].end, context.temp_allocator);
                    selector.field.name = name;
                    ast_context.locals[name] = selector;
                }

            }


        }


    }

}

get_locals_assign_stmt :: proc(file: ast.File, stmt: ast.Assign_Stmt, ast_context: ^AstContext) {

    using ast;

    if stmt.lhs == nil || stmt.rhs == nil {
        return;
    }

    results := make([dynamic]^Expr, context.temp_allocator);

    for rhs in stmt.rhs {
        get_generic_assignment(file, rhs, ast_context, &results);
    }


    if len(stmt.lhs) != len(results) {
        return;
    }

    for lhs, i in stmt.lhs {
        if ident, ok := lhs.derived.(ast.Ident); ok {
            ast_context.locals[ident.name] = results[i];
            ast_context.variables[ident.name] = true;
        }
    }

}

get_locals_if_stmt :: proc(file: ast.File, stmt: ast.If_Stmt, ast_context: ^AstContext, document_position: ^DocumentPositionContext) {

    if !(stmt.pos.offset <= document_position.position && document_position.position <= stmt.end.offset) {
        return;
    }

    get_locals_stmt(file, stmt.init, ast_context, document_position);
    get_locals_stmt(file, stmt.body, ast_context, document_position);
    get_locals_stmt(file, stmt.else_stmt, ast_context, document_position);
}


get_locals_for_range_stmt :: proc(file: ast.File, stmt: ast.Range_Stmt, ast_context: ^AstContext, document_position: ^DocumentPositionContext) {

    using ast;

    if !(stmt.body.pos.offset <= document_position.position && document_position.position <= stmt.body.end.offset) {
        return;
    }

    results := make([dynamic]^Expr, context.temp_allocator);


    if stmt.expr == nil {
        return;
    }

    if symbol, ok := resolve_type_expression(ast_context, stmt.expr); ok {

        if generic, ok := symbol.value.(index.SymbolGenericValue); ok {

            switch v in generic.expr.derived {
            case Map_Type:
                if stmt.val0 != nil {

                    if ident, ok := stmt.val0.derived.(Ident); ok {
                        ast_context.locals[ident.name] = v.key;
                        ast_context.variables[ident.name] = true;
                    }

                }

                if stmt.val1 != nil {

                    if ident, ok := stmt.val1.derived.(Ident); ok {
                        ast_context.locals[ident.name] = v.value;
                        ast_context.variables[ident.name] = true;
                    }

                }
            case Dynamic_Array_Type:
                if stmt.val0 != nil {

                    if ident, ok := stmt.val0.derived.(Ident); ok {
                        ast_context.locals[ident.name] = v.elem;
                        ast_context.variables[ident.name] = true;
                    }

                }

                if stmt.val1 != nil {

                    if ident, ok := stmt.val1.derived.(Ident); ok {
                        ast_context.locals[ident.name] = make_int_ast();
                        ast_context.variables[ident.name] = true;
                    }

                }
            case Array_Type:
                if stmt.val0 != nil {

                    if ident, ok := stmt.val0.derived.(Ident); ok {
                        ast_context.locals[ident.name] = v.elem;
                        ast_context.variables[ident.name] = true;
                    }

                }

                if stmt.val1 != nil {

                    if ident, ok := stmt.val1.derived.(Ident); ok {
                        ast_context.locals[ident.name] = make_int_ast();
                        ast_context.variables[ident.name] = true;
                    }

                }
            }

        }

    }

    get_locals_stmt(file, stmt.body, ast_context, document_position);
}

get_locals_for_stmt :: proc(file: ast.File, stmt: ast.For_Stmt, ast_context: ^AstContext, document_position: ^DocumentPositionContext) {

    if !(stmt.pos.offset <= document_position.position && document_position.position <= stmt.end.offset) {
        return;
    }

    get_locals_stmt(file, stmt.init, ast_context, document_position);
    get_locals_stmt(file, stmt.body, ast_context, document_position);
}

get_locals_switch_stmt :: proc(file: ast.File, stmt: ast.Switch_Stmt, ast_context: ^AstContext, document_position: ^DocumentPositionContext) {

    if !(stmt.pos.offset <= document_position.position && document_position.position <= stmt.end.offset) {
        return;
    }

    get_locals_stmt(file, stmt.body, ast_context, document_position);
}

get_locals_type_switch_stmt :: proc(file: ast.File, stmt: ast.Type_Switch_Stmt, ast_context: ^AstContext, document_position: ^DocumentPositionContext) {

    using ast;

    if !(stmt.pos.offset <= document_position.position && document_position.position <= stmt.end.offset) {
        return;
    }

    if stmt.body == nil {
        return;
    }

    if block, ok := stmt.body.derived.(Block_Stmt); ok {

        for block_stmt in block.stmts {

            if cause, ok := block_stmt.derived.(Case_Clause); ok && cause.pos.offset <= document_position.position && document_position.position <= cause.end.offset {

                for b in cause.body {
                    get_locals_stmt(file, b, ast_context, document_position);
                }

                tag := stmt.tag.derived.(Assign_Stmt);

                if len(tag.lhs) == 1 && len(cause.list) == 1 {
                    ident := tag.lhs[0].derived.(Ident);
                    ast_context.locals[ident.name] = cause.list[0];
                    ast_context.variables[ident.name] = true;
                }

            }

        }

    }

}

get_locals :: proc(file: ast.File, function: ^ast.Node, ast_context: ^AstContext, document_position: ^DocumentPositionContext) {

    proc_lit, ok := function.derived.(ast.Proc_Lit);

    if !ok || proc_lit.body == nil {
        return;
    }

    if proc_lit.type != nil && proc_lit.type.params != nil {

        for arg in proc_lit.type.params.list {

            for name in arg.names {
                if arg.type != nil {
                    str := common.get_ast_node_string(name, file.src);
                    ast_context.locals[str] = arg.type;
                    ast_context.variables[str] = true;
                    ast_context.parameters[str] = true;
                }
            }

        }

    }

    block: ast.Block_Stmt;
    block, ok = proc_lit.body.derived.(ast.Block_Stmt);

    if !ok {
        log.error("Proc_List body not block");
        return;
    }

    for stmt in block.stmts {
        get_locals_stmt(file, stmt, ast_context, document_position);
    }

}

clear_locals :: proc(ast_context: ^AstContext) {
    clear(&ast_context.locals);
    clear(&ast_context.parameters);
    clear(&ast_context.variables);
    clear(&ast_context.usings);
}

concatenate_symbols_information :: proc(ast_context: ^AstContext, symbol: index.Symbol) -> string {

    pkg := path.base(symbol.pkg, false, context.temp_allocator);

    if symbol.type == .Function {

        if symbol.returns != "" {
            return strings.concatenate({pkg, "::", symbol.name, "::", symbol.signature, " -> ", symbol.returns}, context.temp_allocator);
        }

        else {
            return strings.concatenate({pkg, "::", symbol.name, "::", symbol.signature}, context.temp_allocator);
        }

    }

    else {
        if symbol.signature != "" {
            return strings.concatenate({pkg, "::", symbol.name, ": ", symbol.signature}, context.temp_allocator);
        }
        else {
            return strings.concatenate({pkg, "::", symbol.name}, context.temp_allocator);
        }
    }

    return ""; //weird bug requires this
}

get_definition_location :: proc(document: ^Document, position: common.Position) -> (common.Location, bool) {

    location: common.Location;

    ast_context := make_ast_context(document.ast, document.imports, document.package_name);

    uri: string;

    position_context, ok := get_document_position_context(document, position, .Definition);

    if !ok {
        log.error("Failed to get position context");
        return location, false;
    }

    get_globals(document.ast, &ast_context);

    if position_context.function != nil {
        get_locals(document.ast, position_context.function, &ast_context, &position_context);
    }

    if position_context.selector != nil {

        selector: index.Symbol;

        ast_context.use_locals = true;
        ast_context.use_globals = true;
        ast_context.current_package = ast_context.document_package;

        selector, ok = resolve_type_expression(&ast_context, position_context.selector);

        if !ok {
            return location, false;
        }

        field: string;

        if position_context.field != nil {

            switch v in position_context.field.derived {
            case ast.Ident:
                field = v.name;
            }

        }

        uri = selector.uri;

        #partial switch v in selector.value {
        case index.SymbolEnumValue:
             location.range = selector.range;
        case index.SymbolStructValue:
            for name, i in v.names {
                if strings.compare(name, field) == 0 {
                    location.range = common.get_token_range(v.types[i]^, document.ast.src);
                }
            }
        case index.SymbolPackageValue:
            if symbol, ok := index.lookup(field, selector.pkg); ok {
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

    else if position_context.identifier != nil {

        if resolved, ok := resolve_location_identifier(&ast_context, position_context.identifier.derived.(ast.Ident)); ok {
            location.range = resolved.range;
            uri = resolved.uri;
        }

        else {
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

//ERROR can't got to common.Position
get_completion_list :: proc(document: ^Document, position: common.Position) -> (CompletionList, bool) {

    list: CompletionList;

    ast_context := make_ast_context(document.ast, document.imports, document.package_name, true);

    position_context, ok := get_document_position_context(document, position, .Completion);

    get_globals(document.ast, &ast_context);

    if position_context.function != nil {
        get_locals(document.ast, position_context.function, &ast_context, &position_context);
    }

    items := make([dynamic] CompletionItem, context.temp_allocator);

    //log.infof("ident %v", position_context.identifier);
    if position_context.selector != nil {

        symbols := make([dynamic] index.Symbol, context.temp_allocator);

        selector: index.Symbol;

        ast_context.use_locals = true;
        ast_context.use_globals = true;
        ast_context.current_package = ast_context.document_package;

        selector, ok = resolve_type_expression(&ast_context, position_context.selector);

        if !ok {
            log.info(position_context.selector.derived);
            log.error("Failed to resolve type selector in completion list");
            return list, true;
        }

        if selector.uri != "" {
            ast_context.current_package = selector.pkg;
        }

        else {
            ast_context.current_package = ast_context.document_package;
        }

        field: string;

        if position_context.field != nil {

            switch v in position_context.field.derived {
            case ast.Ident:
                field = v.name;
            }

        }

        #partial switch v in selector.value {
        case index.SymbolEnumValue:
            list.isIncomplete = false;

            for name in v.names {
                symbol: index.Symbol;
                symbol.name = name;
                symbol.type = .EnumMember;
                append(&symbols, symbol);
            }

        case index.SymbolStructValue:
            list.isIncomplete = false;

            for name, i in v.names {

                if selector.uri != "" {
                    ast_context.current_package = selector.pkg;
                }

                else {
                    ast_context.current_package = ast_context.document_package;
                }

                if symbol, ok := resolve_type_expression(&ast_context, v.types[i]); ok {
                    symbol.name = name;
                    symbol.type = .Field;
                    symbol.signature = common.get_ast_node_string(v.types[i], ast_context.file.src);
                    append(&symbols, symbol);
                }

                else {
                    log.errorf("Failed to resolve field: %v", name);
                    return list, true;
                }

            }


        case index.SymbolPackageValue:

            list.isIncomplete = true;

            log.infof("search field %v, pkg %v", field, selector.pkg);

            if searched, ok := index.fuzzy_search(field, {selector.pkg}); ok {

                for search in searched {
                    append(&symbols, search);
                }

            }

            else {
                log.errorf("Failed to fuzzy search, field: %v, package: %v", field, selector.pkg);
                return list, true;
            }


        case index.SymbolGenericValue:

            list.isIncomplete = false;

            if ptr, ok := v.expr.derived.(ast.Pointer_Type); ok {

                if symbol, ok := resolve_type_expression(&ast_context, ptr.elem); ok {

                    #partial switch s in symbol.value {
                    case index.SymbolStructValue:
                        for name, i in s.names {

                            if selector.uri != "" {
                                ast_context.current_package = selector.pkg;
                            }

                            else {
                                ast_context.current_package = ast_context.document_package;
                            }

                            if symbol, ok := resolve_type_expression(&ast_context, s.types[i]); ok {
                                symbol.name = name;
                                symbol.type = .Field;
                                symbol.signature = common.get_ast_node_string(s.types[i], ast_context.file.src);
                                append(&symbols, symbol);
                            }

                            else {
                                log.errorf("Failed to resolve field: %v", name);
                                return list, true;
                            }
                        }
                    }
                }

            }

        }

        for symbol, i in symbols {

            item := CompletionItem {
                label = symbol.name,
                kind = cast(CompletionItemKind) symbol.type,
                detail = concatenate_symbols_information(&ast_context, symbol),
                documentation = symbol.doc,
            };

            append(&items, item);
        }

        list.items = items[:];
    }

    else {

        log.infof("label %v", position_context.identifier);

        /*
            Just show the local and global symbols of the document

            TODO(Add fuzzy matching)
        */

        for k, v in ast_context.locals {

            item := CompletionItem {
                label = k,
            };

            append(&items, item);
        }

        for k, v in ast_context.globals {

            item := CompletionItem {
                label = k,
            };

            append(&items, item);
        }

        ident := index.new_type(ast.Ident, tokenizer.Pos {}, tokenizer.Pos {}, context.temp_allocator);

        for item, i in items {

            ident.name = item.label;

            if symbol, ok := resolve_type_identifier(&ast_context, ident^); ok {

                symbol.name = ident.name;

                if ok := resolve_ident_is_variable(&ast_context, ident^); ok {
                    items[i].kind = .Variable;
                }

                else {
                    items[i].kind = cast(CompletionItemKind)symbol.type;
                }

                items[i].detail = concatenate_symbols_information(&ast_context, symbol);
            }

            //ERROR items[i].
        }

        list.items = items[:];
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
        get_locals(document.ast, position_context.function, &ast_context, &position_context);
    }

    call: index.Symbol;
    call, ok = resolve_type_expression(&ast_context, position_context.call);

    signature_information := make([] SignatureInformation, 1, context.temp_allocator);

    signature_information[0].label = concatenate_symbols_information(&ast_context, call);
    signature_information[0].documentation = call.doc;

    signature_help.signatures = signature_information;

    return signature_help, true;
}

get_document_symbols :: proc(document: ^Document) -> [] DocumentSymbol {

    ast_context := make_ast_context(document.ast, document.imports, document.package_name);

    get_globals(document.ast, &ast_context);

    symbols := make([dynamic] DocumentSymbol, context.temp_allocator);

    package_symbol: DocumentSymbol;

    if len(document.ast.decls) == 0 {
        return {};
    }

    package_symbol.kind = .Package;
    package_symbol.name = path.base(document.package_name, false, context.temp_allocator);
    package_symbol.range = {
        start = {
            line = document.ast.decls[0].pos.line,
        },
        end = {
            line = document.ast.decls[len(document.ast.decls)-1].end.line,
        },
    };
    package_symbol.selectionRange = package_symbol.range;

    children_symbols := make([dynamic] DocumentSymbol, context.temp_allocator);

    for k, expr in ast_context.globals {

        symbol: DocumentSymbol;

        symbol.range = common.get_token_range(expr, ast_context.file.src);
        symbol.selectionRange = symbol.range;
        symbol.name = k;

        switch v in expr.derived {
        case ast.Struct_Type:
            symbol.kind = .Struct;
        case ast.Proc_Lit, ast.Proc_Group:
            symbol.kind = .Function;
        case ast.Enum_Type, ast.Union_Type:
            symbol.kind = .Enum;
        case:
            symbol.kind = .Variable;
        }

        append(&children_symbols, symbol);
    }

    package_symbol.children = children_symbols[:];

    append(&symbols, package_symbol);

    return symbols[:];
}

/*
    Figure out what exactly is at the given position and whether it is in a function, struct, etc.
*/
get_document_position_context :: proc(document: ^Document, position: common.Position, hint: DocumentPositionContextHint) -> (DocumentPositionContext, bool) {

    position_context: DocumentPositionContext;

    position_context.hint = hint;
    position_context.file = document.ast;
    position_context.line = position.line;

    absolute_position, ok := common.get_absolute_position(position, document.text);

    if !ok {
        log.error("failed to get absolute position");
        return position_context, false;
    }

    position_context.position = absolute_position;

    for decl in document.ast.decls {
        get_document_position(decl, &position_context);
    }

    if hint == .Completion && position_context.selector == nil && position_context.field == nil {
        fallback_position_context_completion(document, position, &position_context);
    }

    else if hint == .SignatureHelp && position_context.call == nil {
        fallback_position_context_signature(document, position, &position_context);
    }

    return position_context, true;
}


fallback_position_context_completion :: proc(document: ^Document, position: common.Position, position_context: ^DocumentPositionContext) {

    //log.info("FALLBACK TIME");

    //log.infof("position character %c", position_context.file.src[position_context.position]);

    paren_count: int;
    end: int;
    start: int;
    empty_dot: bool;
    i := position_context.position;

    if position_context.file.src[max(0, position_context.position-1)] == '.' {
        i -= 1;
        empty_dot = true;
    }


    end = i;

    for i >= 0 {

        c := position_context.file.src[i];

        if c == '(' && paren_count == 0 {
            start = i+1;
            break;
        }

        else if c == ')' {
            paren_count -= 1;
        }

        else if c == '(' {
            paren_count += 1;
        }

        if c == ' ' || c == '[' || c == '{' || c == ',' || c == '}' {
            start = i+1;
            break;
        }

        i -= 1;
    }

    str := position_context.file.src[max(0, start):min(max(start, end), len(position_context.file.src))];

    log.infof("parser string %v", string(str));

    p := parser.Parser {
		err  = parser_warning_handler, //empty
		warn = parser_warning_handler, //empty
        file = &position_context.file,
	};

    tokenizer.init(&p.tok, str, position_context.file.fullpath);

    p.tok.line_count = position.line;

    parser.advance_token(&p);

    context.allocator = context.temp_allocator;

    e := parser.parse_expr(&p, true);

    if empty_dot {
        position_context.selector = e;
    }

    else if s, ok := e.derived.(ast.Selector_Expr); ok {
        position_context.selector = s.expr;
        position_context.field = s.field;
    }

    else {
        position_context.identifier = e;
    }

}

fallback_position_context_signature :: proc(document: ^Document, position: common.Position, position_context: ^DocumentPositionContext) {

    paren_count: int;
    end: int;
    start: int;
    first_paren: bool;
    i := position_context.position;

    for i >= 0 {

        c := position_context.file.src[i];

        if c == '(' && (paren_count == 0 || paren_count == -1)  {
            end = i;
            first_paren = true;
        }

        else if c == ')' {
            paren_count -= 1;
        }

        else if c == '(' {
            paren_count += 1;
        }

        else if c == ' ' && end != 0 {
            start = i+1;
            break;
        }
        //not good enough if you want multi function signature help
        else if c == '\n' || c == '\r' {
            start = i+1;
            break;
        }

        i -= 1;
    }

    if !first_paren {
        return;
    }

    str := position_context.file.src[max(0, start):min(max(start, end), len(position_context.file.src))];

    p := parser.Parser {
		err  = parser_warning_handler, //empty
		warn = parser_warning_handler, //empty
        file = &position_context.file,
	};

    tokenizer.init(&p.tok, str, position_context.file.fullpath);

    p.tok.line_count = position.line;

    parser.advance_token(&p);

    context.allocator = context.temp_allocator;

    e := parser.parse_expr(&p, true);

    position_context.call = e;
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
        if position_context.hint == .Completion || position_context.hint == .Definition  {
            if n.field != nil && n.field.pos.line == position_context.line {
                position_context.selector = n.expr;
                position_context.field = n.field;
            }
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
        r := cast(^Tag_Stmt)node;
        get_document_position(r.stmt, position_context);
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
        log.errorf("Unhandled node kind: %T", n);
    }

}