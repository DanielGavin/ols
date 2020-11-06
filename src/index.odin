package main

import "core:odin/ast"
import "core:fmt"
import "core:strings"


/*
    Concept ideas:

    static indexing:

    is responsible for implementing the indexing of symbols for static files.

    This is to solve the scaling problem of large projects with many files and symbols, as most of these files will be static.

    Possible scopes for static files:
    global scope (we don't have hiarachy of namespaces and therefore only need to look at the global scope)

    Scopes not part of the indexer:
    function scope, file scope, package scope(these are only relevant for dynamic active files in your project, that use the ast instead of indexing)

    Potential features:
        Allow for saving the indexer, instead of recreating it everytime the lsp starts(but you would have to account for stale data).


    dynamic indexing:

    When the user modifies files we need some smaller index to handle everything the user is using right now. This will allow
    us to rebuild parts of the index without too much of a performance hit.

    This index is first searched and if nothing is found look in the static index.

    interface ideas:

    index_search_fuzzy(symbol: string, scope: [] string) -> [] SymbolResult

    TODO(Daniel, Look into data structure for fuzzy searching)

 */
BaseSymbol :: struct {
    range: Range,
    uri: ^Uri,
};

ProcedureSymbol :: struct {
    using symbolbase: BaseSymbol,
};

Symbol :: union {
    ProcedureSymbol,
};

Indexer :: struct {
    symbol_table: map [string] Symbol,
};

indexer: Indexer;

index_document :: proc(document: ^Document) -> Error {

    for decl in document.ast.decls {

        if value_decl, ok := decl.derived.(ast.Value_Decl); ok {

            name := string(document.text[value_decl.names[0].pos.offset:value_decl.names[0].end.offset]);

            if len(value_decl.values) == 1 {

                if proc_lit, ok := value_decl.values[0].derived.(ast.Proc_Lit); ok {

                    symbol: ProcedureSymbol;

                    symbol.range = get_token_range(proc_lit, document.text);
                    symbol.uri = &document.uri;

                    indexer.symbol_table[strings.concatenate({document.package_name, name}, context.temp_allocator)] = symbol;

                    //fmt.println(proc_lit.type);

                }

            }

        }
    }

    //fmt.println(indexer.symbol_table);

    return .None;
}

indexer_get_symbol :: proc(id: string) -> (Symbol, bool) {
    return indexer.symbol_table[id];
}
