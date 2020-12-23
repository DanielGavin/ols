package index

import "core:odin/ast"
import "core:hash"
import "core:strings"
import "core:mem"
import "core:fmt"
import "core:path/filepath"
import "core:path"
import "core:log"

import "shared:common"


SymbolCollection :: struct {
    allocator: mem.Allocator,
    config: ^common.Config,
    symbols: map[uint] Symbol,
    unique_strings: map[string] string, //store all our strings as unique strings and reference them to save memory.
};

get_index_unique_string :: proc {
    get_index_unique_string_collection,
    get_index_unique_string_collection_raw,
};

get_index_unique_string_collection :: proc(collection: ^SymbolCollection, s: string) -> string {
    return get_index_unique_string_collection_raw(&collection.unique_strings, collection.allocator, s);
}

get_index_unique_string_collection_raw :: proc(unique_strings: ^map[string] string, allocator: mem.Allocator, s: string) -> string {
    //i'm hashing this string way to much
    if _, ok := unique_strings[s]; !ok {
        str := strings.clone(s, allocator);
        unique_strings[str] = str; //yeah maybe I have to use some integer and hash it, tried that before but got name collisions.
    }

    return unique_strings[s];
}

make_symbol_collection :: proc(allocator := context.allocator, config: ^common.Config) -> SymbolCollection {
    return SymbolCollection {
        allocator = allocator,
        config = config,
        symbols = make(map[uint] Symbol, 16, allocator),
        unique_strings = make(map[string] string, 16, allocator),
    };
}

delete_symbol_collection :: proc(collection: SymbolCollection) {

    for k, v in collection.symbols {
        free_symbol(v, collection.allocator);
    }

    for k, v in collection.unique_strings {
        delete(v, collection.allocator);
    }


    delete(collection.symbols);
    delete(collection.unique_strings);
}

collect_procedure_fields :: proc(collection: ^SymbolCollection, proc_type: ^ast.Proc_Type, arg_list: ^ast.Field_List, return_list: ^ast.Field_List, package_map: map [string] string) -> SymbolProcedureValue {

    returns := make([dynamic] ^ast.Field, 0, collection.allocator);
    args := make([dynamic] ^ast.Field, 0, collection.allocator);

    for ret in return_list.list {
        cloned := cast(^ast.Field)clone_type(ret, collection.allocator, &collection.unique_strings);
        replace_package_alias(cloned, package_map, collection);
        append(&returns, cloned);
    }

    for arg in arg_list.list {
        cloned := cast(^ast.Field)clone_type(arg, collection.allocator, &collection.unique_strings);
        replace_package_alias(cloned, package_map, collection);
        append(&args, cloned);
    }

    value := SymbolProcedureValue {
        return_types = returns[:],
        arg_types = args[:],
        generic = proc_type.generic,
    };

    return value;
}

collect_struct_fields :: proc(collection: ^SymbolCollection, struct_type: ast.Struct_Type, package_map: map [string] string) -> SymbolStructValue {

    names := make([dynamic] string, 0, collection.allocator);
    types := make([dynamic] ^ast.Expr, 0, collection.allocator);
    usings := make([dynamic] bool, 0, collection.allocator);

    for field in struct_type.fields.list {

        for n in field.names {
            ident := n.derived.(ast.Ident);
            append(&names, get_index_unique_string(collection, ident.name));

            cloned := clone_type(field.type, collection.allocator, &collection.unique_strings);
            replace_package_alias(cloned, package_map, collection);
            append(&types, cloned);

            if .Using in field.flags {
                append(&usings, true);
            }

            else {
                append(&usings, false);
            }

        }

    }

    value := SymbolStructValue {
        names = names[:],
        types = types[:],
        usings = usings[:],
    };

    return value;
}

collect_enum_fields :: proc(collection: ^SymbolCollection, fields: [] ^ast.Expr, package_map: map [string] string) -> SymbolEnumValue {

    names := make([dynamic] string, 0, collection.allocator);

    for n in fields {

        if ident, ok := n.derived.(ast.Ident); ok {
            append(&names, get_index_unique_string(collection, ident.name));
        }

    }

    value := SymbolEnumValue {
        names = names[:],
    };


    return value;
}

collect_union_fields :: proc(collection: ^SymbolCollection, union_type: ast.Union_Type, package_map: map [string] string) -> SymbolUnionValue {

    names := make([dynamic] string, 0, collection.allocator);


    for variant in union_type.variants {

        if ident, ok := variant.derived.(ast.Ident); ok {
            append(&names, get_index_unique_string(collection, ident.name));
        }

    }

    value := SymbolUnionValue {
        names = names[:],
    };

    return value;
}

collect_generic :: proc(collection: ^SymbolCollection, expr: ^ast.Expr, package_map: map [string] string) -> SymbolGenericValue {

    cloned := clone_type(expr, collection.allocator, &collection.unique_strings);
    replace_package_alias(cloned, package_map, collection);

    value := SymbolGenericValue {
        expr = cloned,
    };

    return value;
}


collect_symbols :: proc(collection: ^SymbolCollection, file: ast.File, uri: string) -> common.Error {

    forward, _ := filepath.to_slash(file.fullpath, context.temp_allocator);
    directory := strings.to_lower(path.dir(forward, context.temp_allocator), context.temp_allocator);
    package_map := get_package_mapping(file, collection.config, uri);

    for decl in file.decls {

        symbol: Symbol;

        if value_decl, ok := decl.derived.(ast.Value_Decl); ok {

            name := string(file.src[value_decl.names[0].pos.offset:value_decl.names[0].end.offset]);

            if len(value_decl.values) == 1 {

                token: ast.Node;
                token_type: SymbolType;

                switch v in value_decl.values[0].derived {
                case ast.Proc_Lit:
                    token = v;
                    token_type = .Function;

                    if v.type.params != nil {
                        symbol.signature = strings.concatenate( {"(", string(file.src[v.type.params.pos.offset:v.type.params.end.offset]), ")"},
                            collection.allocator);
                    }

                    if v.type.results != nil {
                        symbol.returns = strings.concatenate( {"(", string(file.src[v.type.results.pos.offset:v.type.results.end.offset]), ")"},
                            collection.allocator);
                    }

                    if v.type.params != nil && v.type.results != nil && v.type != nil {
                        symbol.value = collect_procedure_fields(collection, v.type, v.type.params, v.type.results, package_map);
                    }
                case ast.Proc_Group:
                    token = v;
                    token_type = .Function;
                    symbol.value = SymbolProcedureGroupValue {
                        group = clone_type(value_decl.values[0], collection.allocator, &collection.unique_strings),
                    };
                case ast.Struct_Type:
                    token = v;
                    token_type = .Struct;
                    symbol.value = collect_struct_fields(collection, v, package_map);
                    symbol.signature = "struct";
                case ast.Enum_Type:
                    token = v;
                    token_type = .Enum;
                    symbol.value = collect_enum_fields(collection, v.fields, package_map);
                    symbol.signature = "enum";
                case ast.Union_Type:
                    token = v;
                    token_type = .Enum;
                    symbol.value = collect_union_fields(collection, v, package_map);
                    symbol.signature = "union";
                case: // default
                    break;
                }

                symbol.range = common.get_token_range(token, file.src);
                symbol.name = get_index_unique_string(collection, name);
                symbol.pkg = get_index_unique_string(collection, directory);
                symbol.type = token_type;
                symbol.uri = get_index_unique_string(collection, uri);


                if value_decl.docs != nil {

                    tmp: string;

                    for doc in value_decl.docs.list {
                        tmp = strings.concatenate({tmp, "\n", doc.text}, context.temp_allocator);
                    }

                    if tmp != "" {
                        replaced, allocated := strings.replace_all(tmp, "//", "", context.temp_allocator);
                        symbol.doc = strings.clone(replaced, collection.allocator);
                    }

                }

                cat := strings.concatenate({symbol.pkg, name}, context.temp_allocator);

                id := get_symbol_id(cat);

                //right now i'm not checking comments whether is for windows, linux, etc, and some packages do not specify that(os)
                if v, ok := collection.symbols[id]; !ok {
                    collection.symbols[id] = symbol;
                }

                else {
                    free_symbol(symbol, collection.allocator);
                }

            }

            else {

                for name, i in value_decl.names {

                    str := common.get_ast_node_string(name, file.src);

                    symbol: Symbol;
                    symbol.range = common.get_token_range(name, file.src);
                    symbol.name = get_index_unique_string(collection, str);
                    symbol.pkg = get_index_unique_string(collection, directory);
                    symbol.uri = get_index_unique_string(collection, uri);
                    symbol.type = .Variable;

                    if value_decl.type != nil {
                        symbol.value = collect_generic(collection, value_decl.type, package_map);
                    }

                    else {
                        if len(value_decl.values) > i {
                            symbol.value = collect_generic(collection, value_decl.values[i], package_map);
                        }
                    }

                    cat := strings.concatenate({symbol.pkg, str}, context.temp_allocator);

                    id := get_symbol_id(cat);

                    if v, ok := collection.symbols[id]; !ok {
                        collection.symbols[id] = symbol;
                    }

                    else {
                        free_symbol(symbol, collection.allocator);
                    }
               }
            }
        }
    }

    return .None;
}


/*
    Gets the map from import alias to absolute package directory
*/
get_package_mapping :: proc(file: ast.File, config: ^common.Config, uri: string) -> map [string] string {

    package_map := make(map [string] string, 0, context.temp_allocator);

    for imp, index in file.imports {

        //collection specified
        if i := strings.index(imp.fullpath, ":"); i != -1 {

            collection := imp.fullpath[1:i];
            p := imp.fullpath[i+1:len(imp.fullpath)-1];

            dir, ok := config.collections[collection];

            if !ok {
                continue;
            }

            name: string;

            full := path.join(elems = {dir, p}, allocator = context.temp_allocator);

            if imp.name.text != "" {
                name = imp.name.text;
            }

            else {
                name = path.base(full, false, context.temp_allocator);
            }

            package_map[name] = strings.to_lower(full, context.temp_allocator);

        }

        else {

            name: string;

            base := path.base(uri, false, context.temp_allocator);

            full := path.join(elems = {base, imp.fullpath[1:len(imp.fullpath)-1]}, allocator = context.temp_allocator);

            full = path.clean(full, context.temp_allocator);

            if imp.name.text != "" {
                name = imp.name.text;
            }

            else {
                name = path.base(full, false, context.temp_allocator);
            }

            package_map[name] = strings.to_lower(full, context.temp_allocator);
        }

    }


    return package_map;
}


/*
    We can't have the alias names for packages with selector expression since that is specific to every files import, instead just replace it with the absolute
    package name(absolute directory path)
*/

replace_package_alias :: proc{
    replace_package_alias_node,
    replace_package_alias_expr,
    replace_package_alias_array,
    replace_package_alias_dynamic_array,
};

replace_package_alias_array :: proc(array: $A/[]^$T, package_map: map [string] string, collection: ^SymbolCollection) {

    for elem, i in array {
        replace_package_alias(elem, package_map, collection);
    }

}

replace_package_alias_dynamic_array :: proc(array: $A/[dynamic]^$T, package_map: map [string] string, collection: ^SymbolCollection) {

    for elem, i in array {
        replace_package_alias(elem, package_map, collection);
    }

}

replace_package_alias_expr :: proc(node: ^ast.Expr, package_map: map [string] string, collection: ^SymbolCollection) {
    replace_package_alias_node(node, package_map, collection);
}

replace_package_alias_node :: proc(node: ^ast.Node, package_map: map [string] string, collection: ^SymbolCollection) {

    using ast;

    if node == nil {
        return;
    }

    switch n in node.derived {
    case Bad_Expr:
    case Ident:
    case Implicit:
    case Undef:
    case Basic_Lit:
    case Basic_Directive:
    case Ellipsis:
        replace_package_alias(n.expr, package_map, collection);
    case Tag_Expr:
        replace_package_alias(n.expr, package_map, collection);
    case Unary_Expr:
        replace_package_alias(n.expr, package_map, collection);
    case Binary_Expr:
        replace_package_alias(n.left, package_map, collection);
        replace_package_alias(n.right, package_map, collection);
    case Paren_Expr:
        replace_package_alias(n.expr, package_map, collection);
    case Selector_Expr:

        if _, ok := n.expr.derived.(Ident); ok {

            ident := &n.expr.derived.(Ident);

            if package_name, ok := package_map[ident.name]; ok {
                ident.name = get_index_unique_string(collection, package_name);
            }

        }

        else {
            replace_package_alias(n.expr, package_map, collection);
            replace_package_alias(n.field, package_map, collection);
        }
    case Implicit_Selector_Expr:
        replace_package_alias(n.field, package_map, collection);
    case Slice_Expr:
        replace_package_alias(n.expr, package_map, collection);
        replace_package_alias(n.low, package_map, collection);
        replace_package_alias(n.high, package_map, collection);
    case Attribute:
        replace_package_alias(n.elems, package_map, collection);
    case Distinct_Type:
        replace_package_alias(n.type, package_map, collection);
    case Opaque_Type:
        replace_package_alias(n.type, package_map, collection);
    case Proc_Type:
        replace_package_alias(n.params, package_map, collection);
        replace_package_alias(n.results, package_map, collection);
    case Pointer_Type:
        replace_package_alias(n.elem, package_map, collection);
    case Array_Type:
        replace_package_alias(n.len, package_map, collection);
        replace_package_alias(n.elem, package_map, collection);
    case Dynamic_Array_Type:
        replace_package_alias(n.elem, package_map, collection);
    case Struct_Type:
        replace_package_alias(n.poly_params, package_map, collection);
        replace_package_alias(n.align, package_map, collection);
        replace_package_alias(n.fields, package_map, collection);
    case Field:
		replace_package_alias(n.names, package_map, collection);
		replace_package_alias(n.type, package_map, collection);
		replace_package_alias(n.default_value, package_map, collection);
	case Field_List:
        replace_package_alias(n.list, package_map, collection);
    case Field_Value:
	    replace_package_alias(n.field, package_map, collection);
	    replace_package_alias(n.value, package_map, collection);
    case Union_Type:
        replace_package_alias(n.poly_params, package_map, collection);
        replace_package_alias(n.align, package_map, collection);
        replace_package_alias(n.variants, package_map, collection);
    case Enum_Type:
        replace_package_alias(n.base_type, package_map, collection);
        replace_package_alias(n.fields, package_map, collection);
    case Bit_Field_Type:
        replace_package_alias(n.fields, package_map, collection);
    case Bit_Set_Type:
        replace_package_alias(n.elem, package_map, collection);
        replace_package_alias(n.underlying, package_map, collection);
    case Map_Type:
        replace_package_alias(n.key, package_map, collection);
        replace_package_alias(n.value, package_map, collection);
    case Call_Expr:
        replace_package_alias(n.expr, package_map, collection);
        replace_package_alias(n.args, package_map, collection);
    case Typeid_Type:
		replace_package_alias(n.specialization, package_map, collection);
    case Poly_Type:
        replace_package_alias(n.type, package_map, collection);
        replace_package_alias(n.specialization, package_map, collection);
    case Proc_Group:
        replace_package_alias(n.args, package_map, collection);
    case Comp_Lit:
        replace_package_alias(n.type, package_map, collection);
        replace_package_alias(n.elems, package_map, collection);
    case:
        log.error("Replace Unhandled node kind: %T", n);
    }

}