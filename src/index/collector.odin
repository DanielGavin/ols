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
    symbols: map[string] Symbol,
    unique_strings: map[string] string, //store all our strings as unique strings and reference them to save memory.
};


get_index_unique_string :: proc(collection: ^SymbolCollection, s: string) -> string {

    //i'm hashing this string way to much
    if _, ok := collection.unique_strings[s]; !ok {
        str := strings.clone(s, collection.allocator);
        collection.unique_strings[str] = str; //yeah maybe I have to use some integer and hash it, tried that before but got name collisions.
    }

    return collection.unique_strings[s];
}


make_symbol_collection :: proc(allocator := context.allocator, config: ^common.Config) -> SymbolCollection {
    return SymbolCollection {
        allocator = allocator,
        config = config,
        symbols = make(map[string] Symbol, 16, allocator),
        unique_strings = make(map[string] string, 16, allocator),
    };
}

free_symbol_collection :: proc(collection: SymbolCollection) {

    for k, v in collection.unique_strings {
        delete(v);
    }

    for k, v in collection.symbols {
        free_symbol(v);
    }

    delete(collection.symbols);
    delete(collection.unique_strings);
}

collect_struct_fields :: proc(collection: ^SymbolCollection, fields: ^ast.Field_List, package_map: map [string] string) -> SymbolStructValue {

    names := make([dynamic] string, 0, collection.allocator);
    types := make([dynamic] ^ast.Expr, 0, collection.allocator);

    for field in fields.list {

        for n in field.names {
            identifier := n.derived.(ast.Ident);
            append(&names, get_index_unique_string(collection, identifier.name));
            append(&types, clone_type(field.type, collection.allocator));
        }

    }

    for t in types {
        replace_package_alias(t, package_map, collection);
    }

    value := SymbolStructValue {
        names = names[:],
        types = types[:],
    };

    return value;
}



collect_symbols :: proc(collection: ^SymbolCollection, file: ast.File, uri: string) -> common.Error {

    forward, _ := filepath.to_slash(file.fullpath, context.temp_allocator);
    directory := path.dir(forward, context.temp_allocator);
    package_map := get_package_mapping(file, collection.config);

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
                        symbol.signature = get_index_unique_string(collection,
                            strings.concatenate( {"(", string(file.src[v.type.params.pos.offset:v.type.params.end.offset]), ")"},
                            context.temp_allocator));
                    }
                case ast.Struct_Type:
                    token = v;
                    token_type = .Struct;
                    symbol.value = collect_struct_fields(collection, v.fields, package_map);
                case: // default
                    break;
                }

                symbol.range = common.get_token_range(token, file.src);
                symbol.name = get_index_unique_string(collection, name);
                symbol.scope = get_index_unique_string(collection, directory);
                symbol.type = token_type;
                symbol.uri = get_index_unique_string(collection, uri);

                //id := hash.murmur64(transmute([]u8)strings.concatenate({symbol.scope, name}, context.temp_allocator));

                if name == "Time" {
                    fmt.println(name);
                    fmt.println(symbol.scope);
                }

                collection.symbols[strings.concatenate({symbol.scope, name}, context.temp_allocator)] = symbol;
            }

        }
    }

    return .None;
}


/*
    Gets the map from import alias to absolute package directory
*/
get_package_mapping :: proc(file: ast.File, config: ^common.Config) -> map [string] string {

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

            package_map[name] = full;

        }

        else {

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

        if ident := &n.expr.derived.(Ident); ident != nil {

            if package_name, ok := package_map[ident.name]; ok {
                ident.name = get_index_unique_string(collection, package_name);
            }

        }

        else {
            replace_package_alias(n.expr, package_map, collection);
            replace_package_alias(n.field, package_map, collection);
        }
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
    case:
        log.error("Unhandled node kind: %T", n);
    }

}