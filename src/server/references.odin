package server 


import "shared:common"

import "core:strings"
import "core:odin/ast"
import "core:encoding/json"
import path "core:path/slashpath"

get_references :: proc(document: ^common.Document, position: common.Position) -> ([]common.Location, bool) {
	return {}, true
}