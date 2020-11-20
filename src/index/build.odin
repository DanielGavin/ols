package index

import "core:path/filepath"
import "core:os"
import "core:fmt"
import "core:odin/parser"
import "core:odin/ast"
import "core:log"
import "core:odin/tokenizer"
import "core:strings"

import "shared:common"

/*
    Not fully sure how to handle rebuilding, but one thing is for sure, dynamic indexing has to have a background thread
    rebuilding every minute or less to fight against stale information
 */


//test version for static indexing

symbol_collection: SymbolCollection;

files: [dynamic] string;

walk_static_index_build :: proc(info: os.File_Info, in_err: os.Errno) -> (err: os.Errno, skip_dir: bool) {

    if info.is_dir {
        return 0, false;
    }

    append(&files, strings.clone(info.fullpath, context.allocator));

    return 0, false;
};

build_static_index :: proc(allocator := context.allocator, config: ^common.Config) {

    symbol_collection = make_symbol_collection(allocator, config);

    files = make([dynamic] string, context.allocator);

    for k, v in config.collections {
        filepath.walk(v, walk_static_index_build);
    }

    context.allocator = context.temp_allocator;

    for fullpath in files {

        data, ok := os.read_entire_file(fullpath, context.temp_allocator);

        if !ok {
            continue;
        }

        p := parser.Parser {
            err  = no_error_handler,
            warn = no_warning_handler,
        };

        file := ast.File {
            fullpath = fullpath,
            src = data,
        };

        ok = parser.parse_file(&p, &file);

        uri := common.create_uri(fullpath, context.temp_allocator);

        collect_symbols(&symbol_collection, file, uri.uri);

        free_all(context.temp_allocator);

        delete(fullpath, allocator);
    }

    delete(files);

    indexer.static_index = make_memory_index(symbol_collection);
}

free_static_index :: proc() {
    delete_symbol_collection(symbol_collection);
}


no_error_handler :: proc(pos: tokenizer.Pos, msg: string, args: ..any) {

}

no_warning_handler :: proc(pos: tokenizer.Pos, msg: string, args: ..any) {

}





