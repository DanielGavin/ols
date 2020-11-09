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
    position: common.AbsolutePosition,
    function: ^ast.Node, //used to help with type resolving in function scope
    selector: ^ast.Node, //used for completion
    identifier: ^ast.Node,
    field: ^ast.Node, //used for completion
    call: ^ast.Node, //used for signature help
    hint: DocumentPositionContextHint,
};


tokenizer_error_handler :: proc(pos: tokenizer.Pos, msg: string, args: ..any) {

}


get_definition_location :: proc(document: ^Document, position: common.Position) -> (common.Location, bool) {

    location: common.Location;

    position_context, ok := get_document_position_context(document, position, .Definition);

    if !ok {
        return location, false;
    }

    symbol: index.Symbol;

    if position_context.selector != nil && position_context.field != nil {

        selector: string;

        switch v in position_context.selector.derived {
        case ast.Ident:
            selector = v.name;
        case:
            return location, false;
        }

        field: string;

        switch v in position_context.field.derived {
        case ast.Ident:
            field = v.name;
        case:
            return location, false;
        }

        symbol, ok = index.lookup(strings.concatenate({selector, field}, context.temp_allocator));

        if !ok {
            return location, false;
        }

    }

    else if position_context.identifier != nil {

        field: string;

        switch v in position_context.field.derived {
        case ast.Ident:
            field = v.name;
        case:
            return location, false;
        }

        symbol, ok = index.lookup(strings.concatenate({document.ast.pkg_name, field}, context.temp_allocator));

        if !ok {
            return location, false;
        }


    }

    else {
        return location, false;
    }


    location.range = symbol.range;
    location.uri = symbol.uri;


    return location, true;
}

get_completion_list :: proc(document: ^Document, position: common.Position) -> (CompletionList, bool) {

    list: CompletionList;

    position_context, ok := get_document_position_context(document, position, .Completion);

    symbols: [] index.Symbol;

    //if we have format "selector.access" with plain identifiers
    if position_context.selector != nil && position_context.field != nil {

        selector: string;

        switch v in position_context.selector.derived {
        case ast.Ident:
            selector = v.name;
        case:
            return list, false;
        }

        field: string;

        switch v in position_context.field.derived {
        case ast.Ident:
            field = v.name;
        case:
            return list, false;
        }

        symbols, ok = index.fuzzy_search(field, {selector});

        if !ok {
            return list, false;
        }

    }

    else {
        return list, false;
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

    position_context, ok := get_document_position_context(document, position, .SignatureHelp);

    return signature_help, true;
}


/*
    Figure out what exactly is at the given position and whether it is in a function, struct, etc.
*/
get_document_position_context :: proc(document: ^Document, position: common.Position, hint: DocumentPositionContextHint) -> (DocumentPositionContext, bool) {

    position_context: DocumentPositionContext;

    position_context.hint = hint;

    absolute_position, ok := common.get_absolute_position(position, document.text);

    if !ok {
        log.error("failed to get absolute position");
        return position_context, false;
    }

    position_context.position = absolute_position;

    for decl in document.ast.decls {
        get_document_position(decl, &position_context);
    }


    //fmt.println(position_context);

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

    if !(node.pos.offset <= position_context.position && position_context.position <= node.end.offset) {
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
            return;
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
		get_document_position(n.expr, position_context);
		get_document_position(n.args, position_context);
	case Selector_Expr:
		get_document_position(n.expr, position_context);
        if position_in_node(n.field, position_context.position) {
            position_context.selector = n.expr;
            position_context.field = n.field;
		    get_document_position(n.field, position_context);
            return;
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