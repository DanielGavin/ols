package server

import "core:odin/parser"
import "core:odin/ast"
import "core:odin/tokenizer"
import "core:fmt"
import "core:log"
import "core:strings"
import path "core:path/slashpath"
import "core:mem"
import "core:strconv"
import "core:path/filepath"
import "core:sort"
import "core:slice"
import "core:os"


import "shared:common"
import "shared:index"
import "shared:analysis"

get_document_links :: proc(document: ^common.Document) -> ([]DocumentLink, bool) {
	using analysis;

	links := make([dynamic]DocumentLink, 0, context.temp_allocator);

	for imp in document.ast.imports {
		//Temporarly assuming non unicode
		node := ast.Node {
			pos = {
				offset = imp.relpath.pos.offset,
				column = imp.relpath.pos.column,
				line = imp.relpath.pos.line,
			},
			end = {
				offset = imp.relpath.pos.offset + len(imp.relpath.text) - 1, 
				column = imp.relpath.pos.column + len(imp.relpath.text) - 1,
				line = imp.relpath.pos.line,
			},
		}

		range := common.get_token_range(node, string(document.text));

		link := DocumentLink {
			range = range,
			target = "https://code.visualstudio.com/docs/extensions/overview#frag",
			tooltip = "Documentation",
		};

		append(&links, link);
	}

	return links[:], true;
}
