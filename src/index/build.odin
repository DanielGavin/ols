package index

import "core:path/filepath"
import "core:os"
import "core:fmt"
import "core:odin/parser"
import "core:odin/ast"
import "core:odin/tokenizer"

import "shared:common"

/*
    Not fully sure how to handle rebuilding, but one thing is for sure, dynamic indexing has to have a background thread
    rebuilding every minute or less to fight against stale information
 */


//test version for static indexing

symbol_collection: SymbolCollection;

build_static_index :: proc(allocator := context.allocator, config: ^common.Config) {

    //right now just collect the symbols from core

    core_path := config.collections["core"];


    symbol_collection = make_symbol_collection(allocator);

    walk_static_index_build := proc(info: os.File_Info, in_err: os.Errno) -> (err: os.Errno, skip_dir: bool) {

        if info.is_dir {
            return 0, false;
        }

        //fmt.println(info.fullpath);

        //bit worried about using temp allocator here since we might overwrite all our temp allocator budget
        data, ok := os.read_entire_file(info.fullpath, context.allocator);

        if !ok {
            return 1, false;
        }

        p := parser.Parser {
            err  = no_error_handler,
            warn = no_warning_handler,
        };

        file := ast.File {
            fullpath = info.fullpath,
            src = data,
        };

        parser.parse_file(&p, &file);

        uri := common.create_uri(info.fullpath, context.temp_allocator);

        collect_symbols(&symbol_collection, file, uri.uri);

        delete(data);


        return 0, false;
    };

    filepath.walk(core_path, walk_static_index_build);

    indexer.static_index = make_memory_index(symbol_collection);
}


no_error_handler :: proc(pos: tokenizer.Pos, msg: string, args: ..any) {

}

no_warning_handler :: proc(pos: tokenizer.Pos, msg: string, args: ..any) {

}





