package index

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

    TODO(Daniel, Look into data structure for fuzzy searching)

 */


Indexer :: struct {
    static_index: MemoryIndex,
};

indexer: Indexer;


lookup :: proc(id: string) -> (Symbol, bool) {
    return memory_index_lookup(&indexer.static_index, id);
}


fuzzy_search :: proc(name: string, scope: [] string) -> ([] Symbol, bool) {
    return memory_index_fuzzy_search(&indexer.static_index, name, scope);
}

