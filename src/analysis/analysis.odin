package analysis

import "core:odin/parser"
import "core:odin/ast"
import "core:odin/tokenizer"
import "core:fmt"
import "core:log"
import "core:strings"
import "core:path"
import "core:mem"
import "core:strconv"
import "core:path/filepath"
import "core:sort"
import "core:slice"
import "core:unicode/utf8"
import "core:reflect"

import "shared:common"
import "shared:index"

/*
	TODO(replace all of the possible ast walking with the new odin visitor function)
	TODO(improve the current_package logic, kinda confusing switching between different packages with selectors)
	TODO(try to flatten some of the nested branches if possible)
*/

DocumentPositionContextHint :: enum {
	Completion,
	SignatureHelp,
	Definition,
	Hover,
}

DocumentPositionContext :: struct {
	file:             ast.File,
	position:         common.AbsolutePosition,
	line:             int,
	function:         ^ast.Proc_Lit, //used to help with type resolving in function scope
	selector:         ^ast.Expr,     //used for completion
	identifier:       ^ast.Node,
	tag:              ^ast.Node,
	field:            ^ast.Expr,        //used for completion
	call:             ^ast.Expr,        //used for signature help
	returns:          ^ast.Return_Stmt, //used for completion
	comp_lit:         ^ast.Comp_Lit,    //used for completion
	parent_comp_lit:  ^ast.Comp_Lit,    //used for completion
	field_value:      ^ast.Field_Value,
	implicit:         bool,             //used for completion
	arrow:            bool,
	binary:           ^ast.Binary_Expr,      //used for completion
	parent_binary:    ^ast.Binary_Expr,      //used for completion
	assign:           ^ast.Assign_Stmt,      //used for completion
	switch_stmt:      ^ast.Switch_Stmt,      //used for completion
	switch_type_stmt: ^ast.Type_Switch_Stmt, //used for completion
	case_clause:      ^ast.Case_Clause,      //used for completion
	value_decl:       ^ast.Value_Decl,       //used for completion
	abort_completion: bool,
	hint:             DocumentPositionContextHint,
	global_lhs_stmt:  bool,
	import_stmt:      ^ast.Import_Decl,
	call_commas:      []int,
}

DocumentLocal :: struct {
	expr:   ^ast.Expr,
	offset: int,
}

AstContext :: struct {
	locals:            map[string][dynamic]DocumentLocal, //locals all the way to the document position
	globals:           map[string]common.GlobalExpr,
	variables:         map[string]bool,
	parameters:        map[string]bool,
	in_package:        map[string]string, //sometimes you have to extract types from arrays/maps and you lose package information
	usings:            [dynamic]string,
	file:              ast.File,
	allocator:         mem.Allocator,
	imports:           []common.Package, //imports for the current document
	current_package:   string,
	document_package:  string,
	use_globals:       bool,
	use_locals:        bool,
	call:              ^ast.Call_Expr, //used to determene the types for generics and the correct function for overloaded functions
	position:          common.AbsolutePosition,
	value_decl:        ^ast.Value_Decl,
	field_name:        string,
	uri:               string,
}

make_ast_context :: proc(file: ast.File, imports: []common.Package, package_name: string, uri: string, allocator := context.temp_allocator) -> AstContext {

	ast_context := AstContext {
		locals = make(map[string][dynamic]DocumentLocal, 0, allocator),
		globals = make(map[string]common.GlobalExpr, 0, allocator),
		variables = make(map[string]bool, 0, allocator),
		usings = make([dynamic]string, allocator),
		parameters = make(map[string]bool, 0, allocator),
		in_package = make(map[string]string, 0, allocator),
		file = file,
		imports = imports,
		use_locals = true,
		use_globals = true,
		document_package = package_name,
		current_package = package_name,
		uri = uri,
	};

	when ODIN_OS == "windows" {
		ast_context.uri = strings.to_lower(ast_context.uri, allocator);
	}

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
		resolve_poly_spec(ast_context, elem, spec_array[i], poly_map);
	}
}

get_poly_node_to_expr :: proc(node: ^ast.Node) -> ^ast.Expr {

	using ast;

	switch v in node.derived {
	case Ident:
		return cast(^Expr)node;
	case:
		log.warnf("Unhandled poly to node kind %v", v);
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

resolve_type_comp_literal :: proc(ast_context: ^AstContext, position_context: ^DocumentPositionContext, current_symbol: index.Symbol, current_comp_lit: ^ast.Comp_Lit) -> (index.Symbol, ^ast.Comp_Lit, bool) {

	if position_context.comp_lit == current_comp_lit {
		return current_symbol, current_comp_lit, true;
	}

	element_index := 0;

	for elem, i in current_comp_lit.elems {
		if position_in_node(elem, position_context.position) {
			element_index = i;
		}
	}

	for elem in current_comp_lit.elems {

		if !position_in_node(elem, position_context.position) {
			continue;
		}
		
		if field_value, ok := elem.derived.(ast.Field_Value); ok { //named
			if comp_lit, ok := field_value.value.derived.(ast.Comp_Lit); ok {
				if s, ok := current_symbol.value.(index.SymbolStructValue); ok {
					for name, i in s.names {
						if name == field_value.field.derived.(ast.Ident).name {
							if symbol, ok := resolve_type_expression(ast_context, s.types[i]); ok {
								//Stop at bitset, because we don't want to enter a comp_lit of a bitset
								if _, ok := symbol.value.(index.SymbolBitSetValue); ok {
									return current_symbol, current_comp_lit, true;
								}
								return resolve_type_comp_literal(ast_context, position_context, symbol, cast(^ast.Comp_Lit)field_value.value);
							}
						}
					}
				}
			}
		} else { //indexed
			if s, ok := current_symbol.value.(index.SymbolStructValue); ok {

				if len(s.types) <= element_index {
					return {}, {}, false;
				}

				if symbol, ok := resolve_type_expression(ast_context, s.types[element_index]); ok {
					//Stop at bitset, because we don't want to enter a comp_lit of a bitset
					if _, ok := symbol.value.(index.SymbolBitSetValue); ok {
						return current_symbol, current_comp_lit, true;
					}
					return resolve_type_comp_literal(ast_context, position_context, symbol, cast(^ast.Comp_Lit)field_value.value);
				}
			}
		}
	}

	return current_symbol, current_comp_lit, true;
}

resolve_generic_function :: proc {
	resolve_generic_function_ast,
	resolve_generic_function_symbol,
};

resolve_generic_function_symbol :: proc(ast_context: ^AstContext, params: []^ast.Field, results: []^ast.Field) -> (index.Symbol, bool) {
	using ast;

	if params == nil {
		return {}, false;
	}

	if results == nil {
		return {}, false;
	}

	if ast_context.call == nil {
		return {}, false;
	}

	call_expr := ast_context.call;
	poly_map := make(map[string]^Expr, 0, context.temp_allocator);
	i := 0;
	count_required_params := 0;	

	for param in params {

		if param.default_value == nil {
			count_required_params += 1;
		}

		for name in param.names {

			if len(call_expr.args) <= i {
				break;
			}

			if poly, ok := name.derived.(Poly_Type); ok {
				poly_map[poly.type.name] = call_expr.args[i];
			}

			if param.type == nil {
				continue;
			}

			if type_id, ok := param.type.derived.(Typeid_Type); ok {
				if !common.node_equal(call_expr.args[i], type_id.specialization) {
					return {}, false;
				}
			}

			resolve_poly_spec_node(ast_context, call_expr.args[i], param.type, &poly_map);	

			i += 1;
		}
	}

	if count_required_params > len(call_expr.args) || count_required_params == 0 || len(call_expr.args) == 0 {
		return {}, false;
	}

	function_name := "";
	function_range: common.Range;

	if ident, ok := call_expr.expr.derived.(Ident); ok {
		function_name = ident.name;
		function_range = common.get_token_range(ident, ast_context.file.src);
	} else if selector, ok := call_expr.expr.derived.(Selector_Expr); ok {
		function_name = selector.field.name;
		function_range = common.get_token_range(selector, ast_context.file.src);
	} else {
		return {}, false;
	}

	symbol := index.Symbol {
		range = function_range,
		type = .Function,
		name = function_name,
	};

	return_types := make([dynamic]^ast.Field, context.temp_allocator);
	argument_types := make([dynamic]^ast.Field, context.temp_allocator);

	for result in results {
		if result.type == nil {
			continue;
		}

		if ident, ok := result.type.derived.(Ident); ok {
			if m, ok := poly_map[ident.name]; ok {
				field := cast(^Field)index.clone_node(result, context.temp_allocator, nil);
				field.type = m;
				append(&return_types, field);
			} else {
				append(&return_types, result);
			}
		} else {
			append(&return_types, result);
		}
	}

	for param in params {
		if len(param.names) == 0 {
			continue;
		}

		//check the name for poly
		if poly_type, ok := param.names[0].derived.(ast.Poly_Type); ok && param.type != nil {
			if m, ok := poly_map[poly_type.type.name]; ok {
				field := cast(^Field)index.clone_node(param, context.temp_allocator, nil);
				field.type = m;
				append(&argument_types, field);
			}
		} else {
			append(&argument_types, param);
		}

	}

	symbol.value = index.SymbolProcedureValue {
		return_types = return_types[:],
		arg_types = argument_types[:],
	};

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

is_symbol_same_typed :: proc(ast_context: ^AstContext, a, b: index.Symbol, flags: ast.Field_Flags = {}) -> bool {
	//relying on the fact that a is the call argument to avoid checking both sides for untyped.
	if untyped, ok := a.value.(index.SymbolUntypedValue); ok {
		if basic, ok := b.value.(index.SymbolBasicValue); ok {
			switch untyped.type {
			case .Integer:
				switch basic.ident.name {
				case "int", "uint", "u32", "i32", "u8", "i8", "u64", "u16", "i16": return true;
				case: return false;
				}
			case .Bool:
				switch basic.ident.name {
				case "bool", "b32", "b64": return true;
				case: return false;
				}
			case .String:
				switch basic.ident.name {
				case "string", "cstring": return true;
				case: return false;
				}
			case .Float:
				switch basic.ident.name {
				case "f32", "f64": return true;
				case: return false;
				}
			}
		}
	}

	a_id := reflect.union_variant_typeid(a.value);
	b_id := reflect.union_variant_typeid(b.value);

	if a_id != b_id {
		return false;
	}

	if a.pointers != b.pointers {
		return false;
	}

	if .Distinct in a.flags != .Distinct in b.flags {
		return false;
	}

	if .Distinct in a.flags == .Distinct in b.flags && 
	   .Distinct in a.flags &&
	   a.name == b.name &&
	   a.pkg == b.pkg {
		return true;
	} 

	#partial switch b_value in b.value {
	case index.SymbolBasicValue:
		if .Auto_Cast in flags {
			return true;
		} else if .Any_Int in flags {
			//Temporary - make a function that finds the base type of basic values 
			//This code only works with non distinct ints
			switch a.name {
				case "int", "uint", "u32", "i32", "u8", "i8", "u64", "u16", "i16": return true;
			}
		} 
	}

	#partial switch a_value in a.value {
	case index.SymbolBasicValue:
		return a.name == b.name && a.pkg == b.pkg
	case index.SymbolStructValue, index.SymbolEnumValue, index.SymbolUnionValue, index.SymbolBitSetValue:
			return a.name == b.name && a.pkg == b.pkg;
	case index.SymbolSliceValue:
		b_value := b.value.(index.SymbolSliceValue);

		a_symbol: index.Symbol;
		b_symbol: index.Symbol;
		ok: bool;

		a_symbol, ok = resolve_type_expression(ast_context, a_value.expr);

		if !ok {
			return false;
		}

		b_symbol, ok = resolve_type_expression(ast_context, b_value.expr);

		if !ok {
			return false;
		}

		return is_symbol_same_typed(ast_context, a_symbol, b_symbol);
	case index.SymbolFixedArrayValue:
		b_value := b.value.(index.SymbolFixedArrayValue);

		a_symbol: index.Symbol;
		b_symbol: index.Symbol;
		ok: bool;

		a_symbol, ok = resolve_type_expression(ast_context, a_value.expr);

		if !ok {
			return false;
		}

		b_symbol, ok = resolve_type_expression(ast_context, b_value.expr);

		if !ok {
			return false;
		}

		return is_symbol_same_typed(ast_context, a_symbol, b_symbol);
	case index.SymbolDynamicArrayValue:
		b_value := b.value.(index.SymbolDynamicArrayValue);

		a_symbol: index.Symbol;
		b_symbol: index.Symbol;
		ok: bool;

		a_symbol, ok = resolve_type_expression(ast_context, a_value.expr);

		if !ok {
			return false;
		}

		b_symbol, ok = resolve_type_expression(ast_context, b_value.expr);

		if !ok {
			return false;
		}

		return is_symbol_same_typed(ast_context, a_symbol, b_symbol);
	case index.SymbolMapValue:
		b_value := b.value.(index.SymbolMapValue);

		a_key_symbol: index.Symbol;
		b_key_symbol: index.Symbol;
		a_value_symbol: index.Symbol;
		b_value_symbol: index.Symbol;
		ok: bool;

		a_key_symbol, ok = resolve_type_expression(ast_context, a_value.key);

		if !ok {
			return false;
		}

		b_key_symbol, ok = resolve_type_expression(ast_context, b_value.key);

		if !ok {
			return false;
		}

		a_value_symbol, ok = resolve_type_expression(ast_context, a_value.value);

		if !ok {
			return false;
		}

		b_value_symbol, ok = resolve_type_expression(ast_context, b_value.value);

		if !ok {
			return false;
		}

		return is_symbol_same_typed(ast_context, a_key_symbol, b_key_symbol) && is_symbol_same_typed(ast_context, a_value_symbol, b_value_symbol); 
	}
	
	return false;
}

get_field_list_name_index :: proc(name: string, field_list: []^ast.Field) -> (int, bool) {

	for field, i in field_list {
		for field_name in field.names {
			if ident, ok := field_name.derived.(ast.Ident); ok {
				if name == ident.name {
					return i, true;
				}
			}		
		}
	}

	return 0, false;
}

/*
	Figure out which function the call expression is using out of the list from proc group
*/
resolve_function_overload :: proc(ast_context: ^AstContext, group: ast.Proc_Group) -> (index.Symbol, bool) {

	using ast;

	call_expr := ast_context.call;

	candidates := make([dynamic]index.Symbol, context.temp_allocator);

	for arg_expr in group.args {

		next_fn: if f, ok := resolve_type_expression(ast_context, arg_expr); ok {

			if ast_context.call == nil || len(ast_context.call.args) == 0 {
				append(&candidates, f);
				break next_fn;
			}

			if procedure, ok := f.value.(index.SymbolProcedureValue); ok {

				count_required_params := 0;

				for arg in procedure.arg_types {
					if arg.default_value == nil {
						count_required_params += 1;
					}
				}

				if len(procedure.arg_types) < len(call_expr.args) {
					continue;
				}

				for arg, i in call_expr.args {

					ast_context.use_locals = true;

					call_symbol: index.Symbol;
					arg_symbol:  index.Symbol;
					ok:          bool;
					i := i;

					if _, ok = arg.derived.(ast.Bad_Expr); ok {
						continue;
					}

					//named parameter
					if field, is_field := arg.derived.(ast.Field_Value); is_field {
						call_symbol, ok = resolve_type_expression(ast_context, field.value);
						if !ok {
							break next_fn;
						}

						if ident, is_ident := field.field.derived.(ast.Ident); is_ident {
							i, ok = get_field_list_name_index(field.field.derived.(ast.Ident).name, procedure.arg_types);
						} else {
							break next_fn;
						}
						
					} else {
						call_symbol, ok = resolve_type_expression(ast_context, arg);
					}

					if !ok {	
						break next_fn;
					}

					if procedure.arg_types[i].type != nil {
						arg_symbol, ok = resolve_type_expression(ast_context, procedure.arg_types[i].type);
					} else {					
						arg_symbol, ok = resolve_type_expression(ast_context, procedure.arg_types[i].default_value);
					}

					if !ok {			
						break next_fn;
					}

					if !is_symbol_same_typed(ast_context, call_symbol, arg_symbol, procedure.arg_types[i].flags) {	
						break next_fn;
					}

				}
	
				append(&candidates, f);
			}
		}
	}
	
	if len(candidates) > 1 {
		return index.Symbol {
			type = candidates[0].type,
			name = candidates[0].name,
			pkg = candidates[0].pkg,
			value = index.SymbolAggregateValue {
				symbols = candidates[:],
			},
		}, true;
	} else if len(candidates) == 1 {
		return candidates[0], true;
	}

	return index.Symbol {}, false;
}

resolve_basic_lit :: proc(ast_context: ^AstContext, basic_lit: ast.Basic_Lit) -> (index.Symbol, bool) {

	symbol := index.Symbol {
		type = .Constant,
	};

	value: index.SymbolUntypedValue;

	if v, ok := strconv.parse_int(basic_lit.tok.text); ok {
		value.type = .Integer;
	} else if v, ok := strconv.parse_bool(basic_lit.tok.text); ok {
		value.type = .Bool;
	} else {
		value.type = .String;
	}

	symbol.pkg = ast_context.current_package
	symbol.value = value;

	return symbol, true;
}

resolve_basic_directive :: proc(ast_context: ^AstContext, directive: ast.Basic_Directive, a := #caller_location) -> (index.Symbol, bool) {
	switch directive.name {
	case "caller_location":
		ident := index.new_type(ast.Ident, directive.pos, directive.end, context.temp_allocator);
		ident.name = "Source_Code_Location";
		ast_context.current_package = ast_context.document_package;
		return resolve_type_identifier(ast_context, ident^)
	}

	return {}, false;
}

resolve_type_expression :: proc(ast_context: ^AstContext, node: ^ast.Expr) -> (index.Symbol, bool) {

	if node == nil {
		return {}, false;
	}

	using ast;

	switch v in &node.derived {
	case Union_Type:
		return make_symbol_union_from_ast(ast_context, v, ast_context.field_name, true), true;
	case Enum_Type:
		return make_symbol_enum_from_ast(ast_context, v, ast_context.field_name, true), true;
	case Struct_Type:
		return make_symbol_struct_from_ast(ast_context, v, ast_context.field_name, true), true;
	case Bit_Set_Type:
		return make_symbol_bitset_from_ast(ast_context, v, ast_context.field_name, true), true;
	case Array_Type:
		return make_symbol_array_from_ast(ast_context, v), true;
	case Dynamic_Array_Type:
		return make_symbol_dynamic_array_from_ast(ast_context, v), true;
	case Map_Type:
		return make_symbol_map_from_ast(ast_context, v), true;
	case Proc_Type:
		return make_symbol_procedure_from_ast(ast_context, node, v, ast_context.field_name), true;
	case Basic_Directive:
		return resolve_basic_directive(ast_context, v);
	case Binary_Expr:
		return resolve_first_symbol_from_binary_expression(ast_context, &v); 
	case Ident:
		return resolve_type_identifier(ast_context, v);
	case Basic_Lit:
		return resolve_basic_lit(ast_context, v);
	case Type_Cast:
			return resolve_type_expression(ast_context, v.type);
	case Auto_Cast:
		return resolve_type_expression(ast_context, v.expr);
	case Comp_Lit:
		return resolve_type_expression(ast_context, v.type);
	case Unary_Expr:
		if v.op.kind == .And {
			symbol, ok := resolve_type_expression(ast_context, v.expr);
			symbol.pointers += 1;
			return symbol, ok;
		} else {
			return resolve_type_expression(ast_context, v.expr);
		}
	case Deref_Expr:
		symbol, ok := resolve_type_expression(ast_context, v.expr);
		symbol.pointers -= 1;
		return symbol, ok;
	case Paren_Expr:
		return resolve_type_expression(ast_context, v.expr);
	case Slice_Expr:
		return resolve_type_expression(ast_context, v.expr);
	case Tag_Expr:
		return resolve_type_expression(ast_context, v.expr);
	case Helper_Type:
		return resolve_type_expression(ast_context, v.type);
	case Ellipsis:
		return resolve_type_expression(ast_context, v.expr);
	case Implicit:
		ident := index.new_type(Ident, v.node.pos, v.node.end, context.temp_allocator);
		ident.name = v.tok.text;
		return resolve_type_identifier(ast_context, ident^);
	case Type_Assertion:
		if unary, ok := v.type.derived.(ast.Unary_Expr); ok {
			if unary.op.kind == .Question {
				if symbol, ok := resolve_type_expression(ast_context, v.expr); ok {
					if union_value, ok := symbol.value.(index.SymbolUnionValue); ok {
						if len(union_value.types) != 1 {
							return {}, false;
						}
						return resolve_type_expression(ast_context, union_value.types[0]);
					}
				}
			}
		} else {
			return resolve_type_expression(ast_context, v.type);
		}	
	case Proc_Lit:
		if v.type.results != nil {
			if len(v.type.results.list) == 1 {
				return resolve_type_expression(ast_context, v.type.results.list[0].type);
			}
		}
	case Pointer_Type:
		symbol, ok := resolve_type_expression(ast_context, v.elem);
		symbol.pointers += 1;
		return symbol, ok;
	case Multi_Pointer_Type:
		symbol, ok := resolve_type_expression(ast_context, v.elem);
		symbol.pointers += 1;
		return symbol, ok;
	case Index_Expr:
		indexed, ok := resolve_type_expression(ast_context, v.expr);

		#partial switch v2 in indexed.value {
		case index.SymbolDynamicArrayValue:
			return resolve_type_expression(ast_context, v2.expr);
		case index.SymbolSliceValue:
			return resolve_type_expression(ast_context, v2.expr);
		case index.SymbolFixedArrayValue:
			return resolve_type_expression(ast_context, v2.expr);
		case index.SymbolMapValue:
			return resolve_type_expression(ast_context, v2.value);
		}

		return index.Symbol {}, false;
	case Call_Expr:
		ast_context.call = cast(^Call_Expr)node;
		return resolve_type_expression(ast_context, v.expr);
	case Implicit_Selector_Expr:
		return index.Symbol {}, false;
	case Selector_Call_Expr:
		return resolve_type_expression(ast_context, v.expr);
	case Selector_Expr:
		if selector, ok := resolve_type_expression(ast_context, v.expr); ok {

			ast_context.use_locals = false;

			#partial switch s in selector.value {
			case index.SymbolFixedArrayValue:
				components_count := 0;
				for c in v.field.name {
					if c == 'x' || c == 'y' || c == 'z'  || c == 'w' ||
					   c == 'r' || c == 'g' || c == 'b'  || c == 'a' {
						components_count += 1;
					}
				}

				if components_count == 0 {
					return {}, false;
				}

				if components_count == 1 {
					if selector.pkg != "" {
						ast_context.current_package = selector.pkg;
					} else {
						ast_context.current_package = ast_context.document_package;
					}
					return resolve_type_expression(ast_context, s.expr);
				} else {
					value := index.SymbolFixedArrayValue {
						expr = s.expr,
						len = make_int_basic_value(components_count),
					};
					selector.value = value;
					return selector, true;
				}
			case index.SymbolProcedureValue:
				if len(s.return_types) == 1 {
					selector_expr := index.new_type(ast.Selector_Expr, s.return_types[0].node.pos, s.return_types[0].node.end, context.temp_allocator);
					selector_expr.expr = s.return_types[0].type;
					selector_expr.field = v.field;
					return resolve_type_expression(ast_context, selector_expr);
				}
			case index.SymbolStructValue:
				if selector.pkg != "" {
					ast_context.current_package = selector.pkg;
				} else {
					ast_context.current_package = ast_context.document_package;
				}

				for name, i in s.names {
					if v.field != nil && name == v.field.name {
						ast_context.field_name = v.field.name;
						return resolve_type_expression(ast_context, s.types[i]);
					}
				}
			case index.SymbolPackageValue:
				ast_context.current_package = selector.pkg;

				if v.field != nil {
					return resolve_symbol_return(ast_context, index.lookup(v.field.name, selector.pkg));
				} else {
					return index.Symbol {}, false;
				}
			}
		} else {
			return index.Symbol {}, false;
		}
	case:
		log.warnf("default node kind, resolve_type_expression: %T", v);
		if v == nil {
			return {}, false;
		}
	}

	return index.Symbol {}, false;
}

store_local :: proc(ast_context: ^AstContext, expr: ^ast.Expr, offset: int, name: string) {

	local_stack := &ast_context.locals[name];

	if local_stack == nil {
		ast_context.locals[name] = make([dynamic]DocumentLocal, context.temp_allocator);
		local_stack = &ast_context.locals[name];
	}

	append(local_stack, DocumentLocal {expr = expr, offset = offset});
}

get_local :: proc(ast_context: ^AstContext, offset: int, name: string) -> ^ast.Expr {

	previous := 0;

	//is the local we are getting being declared?
	if ast_context.value_decl != nil {
		for value_decl_name in ast_context.value_decl.names {
			if ident, ok := value_decl_name.derived.(ast.Ident); ok {

				if ident.name == name {
					previous = 1;
					break;
				}
			}
		}
	}

	if local_stack, ok := ast_context.locals[name]; ok {
		for i := len(local_stack) - 1; i >= 0; i -= 1 {
			if local_stack[i].offset <= offset {
				if i - previous < 0 {
					return nil;
				} else {
					return local_stack[i - previous].expr;
				}		
			}
		}
	}

	return nil;
}

resolve_type_identifier :: proc(ast_context: ^AstContext, node: ast.Ident) -> (index.Symbol, bool) {

	using ast;

	if pkg, ok := ast_context.in_package[node.name]; ok {
		ast_context.current_package = pkg;
	}

	if _, ok := ast_context.parameters[node.name]; ok {
		for imp in ast_context.imports {
			if strings.compare(imp.base, node.name) == 0 {
				symbol := index.Symbol {
					type = .Package,
					pkg = imp.name,
					value = index.SymbolPackageValue {},
				};

				return symbol, true;
			}
		}
	}

	//note(Daniel, if global and local ends up being 100% same just make a function that takes the map)
	if local := get_local(ast_context, node.pos.offset, node.name); local != nil && ast_context.use_locals {

		is_distinct := false;

		if dist, ok := local.derived.(ast.Distinct_Type); ok {
			if dist.type != nil {
				local = dist.type; 
				is_distinct = true;
			}
		}

		return_symbol: index.Symbol;
		ok: bool;

		switch v in local.derived {
		case Ident:
			return_symbol, ok = resolve_type_identifier(ast_context, v);
		case Union_Type:
			return_symbol, ok = make_symbol_union_from_ast(ast_context, v, node.name), true;
			return_symbol.name = node.name;
		case Enum_Type:
			return_symbol, ok = make_symbol_enum_from_ast(ast_context, v, node.name), true;
			return_symbol.name = node.name;
		case Struct_Type:
			return_symbol, ok = make_symbol_struct_from_ast(ast_context, v, node.name), true;
			return_symbol.name = node.name;
		case Bit_Set_Type:
			return_symbol, ok = make_symbol_bitset_from_ast(ast_context, v, node.name), true;
			return_symbol.name = node.name;
		case Proc_Lit:
			if !v.type.generic {
				return_symbol, ok = make_symbol_procedure_from_ast(ast_context, local, v.type^, node.name), true;
			} else {
				if return_symbol, ok = resolve_generic_function(ast_context, v); !ok {
					return_symbol, ok = make_symbol_procedure_from_ast(ast_context, local, v.type^, node.name), true;
				}
			}
		case Proc_Group:
			return_symbol, ok = resolve_function_overload(ast_context, v);
		case Array_Type:
			return_symbol, ok = make_symbol_array_from_ast(ast_context, v), true;
		case Dynamic_Array_Type:
			return_symbol, ok = make_symbol_dynamic_array_from_ast(ast_context, v), true;
		case Map_Type:
			return_symbol, ok = make_symbol_map_from_ast(ast_context, v), true;
		case Basic_Lit:
			return_symbol, ok = resolve_basic_lit(ast_context, v);
			return_symbol.name = node.name;
			return_symbol.type = ast_context.variables[node.name] ? .Variable : .Constant;
		case:
			return_symbol, ok = resolve_type_expression(ast_context, local);
		}

		if is_distinct {
			return_symbol.name = node.name;
			return_symbol.flags |= {.Distinct};
		}

		return return_symbol, ok;

	} else if global, ok := ast_context.globals[node.name]; ast_context.use_globals && ok {

		is_distinct := false;

		if dist, ok := global.expr.derived.(ast.Distinct_Type); ok {
			if dist.type != nil {
				global.expr = dist.type;
				is_distinct = true;
			}
		}

		return_symbol: index.Symbol;
		ok: bool;

		switch v in global.expr.derived {
		case Ident:
			return_symbol, ok = resolve_type_identifier(ast_context, v);
		case Struct_Type:
			return_symbol, ok = make_symbol_struct_from_ast(ast_context, v, node.name), true;
			return_symbol.name = node.name;
		case Bit_Set_Type:
			return_symbol, ok = make_symbol_bitset_from_ast(ast_context, v, node.name), true;
			return_symbol.name = node.name;
		case Union_Type:
			return_symbol, ok = make_symbol_union_from_ast(ast_context, v, node.name), true;
			return_symbol.name = node.name;
		case Enum_Type:
			return_symbol, ok = make_symbol_enum_from_ast(ast_context, v, node.name), true;
			return_symbol.name = node.name;
		case Proc_Lit:
			if !v.type.generic {
				return_symbol, ok = make_symbol_procedure_from_ast(ast_context, global.expr, v.type^, node.name), true;
			} else {
				if return_symbol, ok = resolve_generic_function(ast_context, v); !ok {
					return_symbol, ok = make_symbol_procedure_from_ast(ast_context, global.expr, v.type^, node.name), true;
				}
			}
		case Proc_Group:
			return_symbol, ok = resolve_function_overload(ast_context, v);
		case Array_Type:
			return_symbol, ok = make_symbol_array_from_ast(ast_context, v), true;
		case Dynamic_Array_Type:
			return_symbol, ok = make_symbol_dynamic_array_from_ast(ast_context, v), true;
		case Basic_Lit:
			return_symbol, ok = resolve_basic_lit(ast_context, v);
			return_symbol.name = node.name;
			return_symbol.type = global.mutable ? .Variable : .Constant;
		case:
			return_symbol, ok = resolve_type_expression(ast_context, global.expr);
		}

		if is_distinct {
			return_symbol.name = node.name;
			return_symbol.flags |= {.Distinct};
		}

		return_symbol.doc = common.get_doc(global.docs, context.temp_allocator);

		return return_symbol, ok;
	} else if node.name == "context" {
		for built in index.indexer.built_in_packages {
			if symbol, ok := index.lookup("Context", built); ok {
				return symbol, ok;
			}
		}
	} else if v, ok := common.keyword_map[node.name]; ok {
		//keywords
		ident := index.new_type(Ident, node.pos, node.end, context.temp_allocator);
		ident.name = node.name;

		symbol: index.Symbol;

		switch ident.name {
		case "true", "false":
			symbol = index.Symbol {
				type = .Keyword,
				signature = node.name,
				pkg = ast_context.current_package,
				value = index.SymbolUntypedValue {
					type = .Bool,	
				},
			};
		case:
			symbol = index.Symbol {
				type = .Keyword,
				signature = node.name,
				name = ident.name,
				pkg = ast_context.current_package,
				value = index.SymbolBasicValue {
					ident = ident,
				},
			};
		}

		return symbol, true;
	} else {
		//right now we replace the package ident with the absolute directory name, so it should have '/' which is not a valid ident character
		if strings.contains(node.name, "/") {

			symbol := index.Symbol {
				type = .Package,
				pkg = node.name,
				value = index.SymbolPackageValue {},
			};

			return symbol, true;
		} else {
			//part of the ast so we check the imports of the document
			for imp in ast_context.imports {

				if strings.compare(imp.base, node.name) == 0 {

					symbol := index.Symbol {
						type = .Package,
						pkg = imp.name,
						value = index.SymbolPackageValue {},
					};

					return symbol, true;
				}
			}
		}

		//last option is to check the index
		if symbol, ok := index.lookup(node.name, ast_context.current_package); ok {
			return resolve_symbol_return(ast_context, symbol);
		}

		//If we are resolving a symbol that is in the document package, then we'll check the builtin packages.
		if ast_context.current_package == ast_context.document_package {
			for built in index.indexer.built_in_packages {
				if symbol, ok := index.lookup(node.name, built); ok {
					return resolve_symbol_return(ast_context, symbol);
				}
			}
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

	}

	return index.Symbol {}, false;
}

resolve_ident_is_variable :: proc(ast_context: ^AstContext, node: ast.Ident) -> bool {

	if v, ok := ast_context.variables[node.name]; ok && v {
		return true;
	}

	if symbol, ok := index.lookup(node.name, ast_context.current_package); ok {
		return symbol.type == .Variable;
	}

	return false;
}

resolve_ident_is_package :: proc(ast_context: ^AstContext, node: ast.Ident) -> bool {

	if strings.contains(node.name, "/") {
		return true;
	} else {
		for imp in ast_context.imports {

			if imp.base == node.name {
				return true;
			}
		}
	}

	return false;
}

expand_struct_usings :: proc(ast_context: ^AstContext, symbol: index.Symbol, value: index.SymbolStructValue) -> index.SymbolStructValue {

	//ERROR no completion or over on names and types - generic resolve error
	names := slice.to_dynamic(value.names, context.temp_allocator);
	types := slice.to_dynamic(value.types, context.temp_allocator);
	
	//ERROR no hover on k and v(completion works)
	for k, v in value.usings {

		ast_context.current_package = symbol.pkg;

		field_expr: ^ast.Expr;

		for name, i in value.names {

			if name == k && v {
				field_expr = value.types[i];
			}
		}

		if field_expr == nil {
			continue;
		}

		if s, ok := resolve_type_expression(ast_context, field_expr); ok {

			if struct_value, ok := s.value.(index.SymbolStructValue); ok {

				for name in struct_value.names {
					append(&names, name);
				}

				for type in struct_value.types {
					append(&types, type);
				}
			}
		}
	}

	return {
		names = names[:],
		types = types[:],
	};
}

resolve_symbol_return :: proc(ast_context: ^AstContext, symbol: index.Symbol, ok := true) -> (index.Symbol, bool) {
	if !ok {
		return symbol, ok;
	}

	symbol := symbol;

	if symbol.type == .Unresolved {
		resolve_unresolved_symbol(ast_context, &symbol);
	}
	
	#partial switch v in &symbol.value {
	case index.SymbolProcedureGroupValue:
		if symbol, ok := resolve_function_overload(ast_context, v.group.derived.(ast.Proc_Group)); ok {
			return symbol, true;
		} else {
			return symbol, false;
		}
	case index.SymbolProcedureValue:
		if v.generic {
			if resolved_symbol, ok := resolve_generic_function(ast_context, v.arg_types, v.return_types); ok {
				return resolved_symbol, ok;
			} else {
				return symbol, true;
			}
		} else {
			return symbol, true;
		}
	case index.SymbolUnionValue:
		if v.poly != nil {
			//Todo(daniel): Maybe change the function to return a new symbol instead of referencing it.
			//resolving the poly union means changing the type, so we do a copy of it.
			types := make([dynamic]^ast.Expr, context.temp_allocator);
			append_elems(&types, ..v.types);
			v.types = types[:];
			resolve_poly_union(ast_context, v.poly, &symbol);
		}
		return symbol, ok;
	case index.SymbolStructValue:
		if v.poly != nil {
			//Todo(daniel): Maybe change the function to return a new symbol instead of referencing it.
			//resolving the struct union means changing the type, so we do a copy of it.
			types := make([dynamic]^ast.Expr, context.temp_allocator);
			append_elems(&types, ..v.types);
			v.types = types[:];
			resolve_poly_struct(ast_context, v.poly, &symbol);
		}

		//expand the types and names from the using - can't be done while indexing without complicating everything(this also saves memory)
		if len(v.usings) > 0 {
			expanded := symbol;
			expanded.value = expand_struct_usings(ast_context, symbol, v);
			return expanded, true;
		} else {
			return symbol, true; 
		}
	case index.SymbolGenericValue:
		ret, ok := resolve_type_expression(ast_context, v.expr);
		return ret, ok;
	}

	return symbol, true;
}

resolve_unresolved_symbol :: proc(ast_context: ^AstContext, symbol: ^index.Symbol) {
	using index;

	if symbol.type != .Unresolved {
		return;
	}

	#partial switch v in symbol.value {
	case SymbolStructValue:
		symbol.type = .Struct;
    case SymbolPackageValue:
		symbol.type = .Package;
    case SymbolProcedureValue, SymbolProcedureGroupValue:
		symbol.type = .Function;
    case SymbolUnionValue:
		symbol.type = .Enum;
    case SymbolEnumValue:
		symbol.type = .Enum;
    case SymbolBitSetValue:
		symbol.type = .Enum;
	case index.SymbolGenericValue:
		ast_context.current_package = symbol.pkg;
		if ret, ok := resolve_type_expression(ast_context, v.expr); ok {
			symbol.type = ret.type;
			symbol.signature = ret.signature;
		}
	}
}

resolve_location_identifier :: proc(ast_context: ^AstContext, node: ast.Ident) -> (index.Symbol, bool) {

	symbol: index.Symbol;

	if local := get_local(ast_context, node.pos.offset, node.name); local != nil {
		symbol.range = common.get_token_range(get_local(ast_context, node.pos.offset, node.name), ast_context.file.src);
		return symbol, true;
	} else if global, ok := ast_context.globals[node.name]; ok {
		symbol.range = common.get_token_range(global.expr, ast_context.file.src);
		return symbol, true;
	}

	if symbol, ok := index.lookup(node.name, ast_context.document_package); ok {
		return symbol, ok;
	}

	usings := get_using_packages(ast_context);

	for pkg in usings {
		if symbol, ok := index.lookup(node.name, pkg); ok {
			return symbol, ok;
		}
	}

	return {}, false;
}

resolve_first_symbol_from_binary_expression :: proc(ast_context: ^AstContext, binary: ^ast.Binary_Expr) -> (index.Symbol, bool) {

	//Fairly simple function to find the earliest identifier symbol in binary expression.

	if binary.left != nil {

		if ident, ok := binary.left.derived.(ast.Ident); ok {
			if s, ok := resolve_type_identifier(ast_context, ident); ok {
				return s, ok;
			}
		} else if _, ok := binary.left.derived.(ast.Binary_Expr); ok {
			if s, ok := resolve_first_symbol_from_binary_expression(ast_context, cast(^ast.Binary_Expr)binary.left); ok {
				return s, ok;
			}
		}
	}

	if binary.right != nil {
		if ident, ok := binary.right.derived.(ast.Ident); ok {
			if s, ok := resolve_type_identifier(ast_context, ident); ok {
				return s, ok;
			}
		} else if _, ok := binary.right.derived.(ast.Binary_Expr); ok {
			if s, ok := resolve_first_symbol_from_binary_expression(ast_context, cast(^ast.Binary_Expr)binary.right); ok {
				return s, ok;
			}
		}
	}

	return {}, false;
}

find_position_in_call_param :: proc(ast_context: ^AstContext, call: ast.Call_Expr) -> (int, bool) {

	if call.args == nil {
		return 0, false;
	}

	for arg, i in call.args {
		if position_in_node(arg, ast_context.position) {
			return i, true;
		}
	}

	return len(call.args) - 1, true;
}

make_pointer_ast :: proc(elem: ^ast.Expr) -> ^ast.Pointer_Type {
	pointer := index.new_type(ast.Pointer_Type, elem.pos, elem.end, context.temp_allocator);
	pointer.elem = elem;
	return pointer;
}

make_bool_ast :: proc() -> ^ast.Ident {
	ident := index.new_type(ast.Ident, {}, {}, context.temp_allocator);
	ident.name = "bool";
	return ident;
}

make_int_ast :: proc() -> ^ast.Ident {
	ident := index.new_type(ast.Ident, {}, {}, context.temp_allocator);
	ident.name = "int";
	return ident;
}

make_int_basic_value :: proc(n: int) -> ^ast.Basic_Lit {
	basic := index.new_type(ast.Basic_Lit, {}, {}, context.temp_allocator);
	basic.tok.text = fmt.tprintf("%v", n);
	return basic; 
}

get_package_from_node :: proc(node: ast.Node) -> string {
	slashed, _ := filepath.to_slash(node.pos.file, context.temp_allocator);

	when ODIN_OS == "windows" {
		ret := strings.to_lower(path.dir(slashed, context.temp_allocator), context.temp_allocator);
	} else {
		ret := path.dir(slashed, context.temp_allocator);
	}

	return ret;
}

get_using_packages :: proc(ast_context: ^AstContext) -> []string {

	usings := make([]string, len(ast_context.usings), context.temp_allocator);

	if len(ast_context.usings) == 0 {
		return usings;
	}

	//probably map instead
	for u, i in ast_context.usings {

		for imp in ast_context.imports {

			if strings.compare(imp.base, u) == 0 {
				usings[i] = imp.name;
			}
		}
	}

	return usings;
}

make_symbol_procedure_from_ast :: proc(ast_context: ^AstContext, n: ^ast.Node, v: ast.Proc_Type, name: string) -> index.Symbol {

	symbol := index.Symbol {
		range = common.get_token_range(n^, ast_context.file.src),
		type = .Function,
		pkg = get_package_from_node(n^),
		name = name,
	};

	return_types := make([dynamic]^ast.Field, context.temp_allocator);
	arg_types    := make([dynamic]^ast.Field, context.temp_allocator);

	if v.results != nil {
		for ret in v.results.list {
			append(&return_types, ret);
		}
	}

	if v.params != nil {
		for param in v.params.list {
			append(&arg_types, param);
		}
	}

	if expr, ok := ast_context.globals[name]; ok {
		if expr.deprecated {
			symbol.flags |= {.Distinct};
		}
	}

	symbol.value = index.SymbolProcedureValue {
		return_types = return_types[:],
		arg_types = arg_types[:],
	};

	return symbol;
}

make_symbol_array_from_ast :: proc(ast_context: ^AstContext, v: ast.Array_Type) -> index.Symbol {

	symbol := index.Symbol {
		range = common.get_token_range(v.node, ast_context.file.src),
		type = .Variable,
		pkg = get_package_from_node(v.node),
	};

	if v.len != nil {
		symbol.value = index.SymbolFixedArrayValue {
			expr = v.elem,
			len = v.len,
		};
	} else {
		symbol.value = index.SymbolSliceValue {
			expr = v.elem,
		};
	}

	return symbol;
}

make_symbol_dynamic_array_from_ast :: proc(ast_context: ^AstContext, v: ast.Dynamic_Array_Type) -> index.Symbol {

	symbol := index.Symbol {
		range = common.get_token_range(v.node, ast_context.file.src),
		type = .Variable,
		pkg = get_package_from_node(v.node),
	};

	symbol.value = index.SymbolDynamicArrayValue {
		expr = v.elem,
	};

	return symbol;
}

make_symbol_map_from_ast :: proc(ast_context: ^AstContext, v: ast.Map_Type) -> index.Symbol {

	symbol := index.Symbol {
		range = common.get_token_range(v.node, ast_context.file.src),
		type = .Variable,
		pkg = get_package_from_node(v.node),
	};

	symbol.value = index.SymbolMapValue {
		key = v.key,
		value = v.value,
	};

	return symbol;
}

make_symbol_basic_type_from_ast :: proc(ast_context: ^AstContext, n: ^ast.Node, v: ^ast.Ident) -> index.Symbol {

	symbol := index.Symbol {
		range = common.get_token_range(n^, ast_context.file.src),
		type = .Variable,
		pkg = get_package_from_node(n^),
	};

	symbol.value = index.SymbolBasicValue {
		ident = v,
	};

	return symbol;
}

make_symbol_union_from_ast :: proc(ast_context: ^AstContext, v: ast.Union_Type, ident: string, inlined := false) -> index.Symbol {

	symbol := index.Symbol {
		range = common.get_token_range(v, ast_context.file.src),
		type = .Union,
		pkg = get_package_from_node(v.node),
	};

	if inlined {
		symbol.flags |= {.Anonymous};
		symbol.name = "union";
	}

	names := make([dynamic]string, context.temp_allocator);

	for variant in v.variants {

		if ident, ok := variant.derived.(ast.Ident); ok {
			append(&names, ident.name);
		} else if selector, ok := variant.derived.(ast.Selector_Expr); ok {

			if ident, ok := selector.field.derived.(ast.Ident); ok {
				append(&names, ident.name);
			}
		}
	}

	symbol.value = index.SymbolUnionValue {
		types = v.variants,
		union_name = ident,
	};

	if v.poly_params != nil {
		resolve_poly_union(ast_context, v.poly_params, &symbol);
	}

	return symbol;
}

make_symbol_enum_from_ast :: proc(ast_context: ^AstContext, v: ast.Enum_Type, ident: string, inlined := false) -> index.Symbol {
	symbol := index.Symbol {
		range = common.get_token_range(v, ast_context.file.src),
		type = .Enum,
		pkg = get_package_from_node(v.node),
	};

	if inlined {
		symbol.flags |= {.Anonymous};
		symbol.name = "enum";
	}


	names := make([dynamic]string, context.temp_allocator);

	for n in v.fields {
		if ident, ok := n.derived.(ast.Ident); ok {
			append(&names, ident.name);
		} else if field, ok := n.derived.(ast.Field_Value); ok {
			if ident, ok := field.field.derived.(ast.Ident); ok {
				append(&names, ident.name);
			} else if binary, ok := field.field.derived.(ast.Binary_Expr); ok {
				append(&names, binary.left.derived.(ast.Ident).name);
			}	
		}
	}

	symbol.value = index.SymbolEnumValue {
		names = names[:],
		enum_name = ident,
	};

	return symbol;
}

make_symbol_bitset_from_ast :: proc(ast_context: ^AstContext, v: ast.Bit_Set_Type, ident: string, inlined := false) -> index.Symbol {

	symbol := index.Symbol {
		range = common.get_token_range(v, ast_context.file.src),
		type = .Enum,
		pkg = get_package_from_node(v.node),
	};

	if inlined {
		symbol.flags |= {.Anonymous};
		symbol.name = "bitset";
	}

	symbol.value = index.SymbolBitSetValue {
		expr = v.elem,
		bitset_name = ident,
	};

	return symbol;
}

make_symbol_struct_from_ast :: proc(ast_context: ^AstContext, v: ast.Struct_Type, ident: string, inlined := false) -> index.Symbol {

	symbol := index.Symbol {
		range = common.get_token_range(v, ast_context.file.src),
		type = .Struct,
		pkg = get_package_from_node(v.node),
	};

	if inlined {
		symbol.flags |= {.Anonymous};
		symbol.name = "struct";
	}

	names  := make([dynamic]string, context.temp_allocator);
	types  := make([dynamic]^ast.Expr, context.temp_allocator);
	usings := make(map[string]bool, 0, context.temp_allocator);

	for field in v.fields.list {
		for n in field.names {
			if identifier, ok := n.derived.(ast.Ident); ok {
				append(&names, identifier.name);
				append(&types, index.clone_type(field.type, context.temp_allocator, nil));

				if .Using in field.flags {
					usings[identifier.name] = true;
				}
			}
		}
	}

	symbol.value = index.SymbolStructValue {
		names = names[:],
		types = types[:],
		usings = usings,
		struct_name = ident,
	};

	if v.poly_params != nil {
		resolve_poly_struct(ast_context, v.poly_params, &symbol);
	}

	//TODO change the expand to not double copy the array, but just pass the dynamic arrays
	if len(usings) > 0 {
		symbol.value = expand_struct_usings(ast_context, symbol, symbol.value.(index.SymbolStructValue));
	}

	return symbol;
}

resolve_poly_union :: proc(ast_context: ^AstContext, poly_params: ^ast.Field_List, symbol: ^index.Symbol) {

	if ast_context.call == nil {
		return;
	}

	symbol_value := &symbol.value.(index.SymbolUnionValue);

	if symbol_value == nil {
		return;
	}

	i := 0;

	poly_map := make(map[string]^ast.Expr, 0, context.temp_allocator);

	for param in poly_params.list {
		for name in param.names {
			if len(ast_context.call.args) <= i {
				break;
			}

			if param.type == nil {
				continue;
			}
			
			if poly, ok := param.type.derived.(ast.Typeid_Type); ok {
				if ident, ok := name.derived.(ast.Ident); ok {
					poly_map[ident.name] = ast_context.call.args[i];
				} else if poly, ok := name.derived.(ast.Poly_Type); ok { 
					if poly.type != nil {
						poly_map[poly.type.name] = ast_context.call.args[i];
					}
				}
			}

			i += 1;
		}
	}
	
	for type, i in symbol_value.types {
		if ident, ok := type.derived.(ast.Ident); ok {
			if expr, ok := poly_map[ident.name]; ok {
				symbol_value.types[i] = expr;
			}
		} else if call_expr, ok := type.derived.(ast.Call_Expr); ok {
			if call_expr.args == nil {
				continue;
			}

			for arg, i in call_expr.args {
				if ident, ok := arg.derived.(ast.Ident); ok {
					if expr, ok := poly_map[ident.name]; ok {
						symbol_value.types[i] = expr;
					}
				}
			}
		}
	}
}

resolve_poly_struct :: proc(ast_context: ^AstContext, poly_params: ^ast.Field_List, symbol: ^index.Symbol) {

	if ast_context.call == nil {
		return;
	}

	symbol_value := &symbol.value.(index.SymbolStructValue);

	if symbol_value == nil {
		return;
	}

	i := 0;

	poly_map := make(map[string]^ast.Expr, 0, context.temp_allocator);

	for param in poly_params.list {
		for name in param.names {
			if len(ast_context.call.args) <= i {
				break;
			}

			if param.type == nil {
				continue;
			}
			
			if poly, ok := param.type.derived.(ast.Typeid_Type); ok {
				if ident, ok := name.derived.(ast.Ident); ok {
					poly_map[ident.name] = ast_context.call.args[i];
				} else if poly, ok := name.derived.(ast.Poly_Type); ok { 
					if poly.type != nil {
						poly_map[poly.type.name] = ast_context.call.args[i];
					}
				}
			}

			i += 1;
		}
	}
	
	for type, i in symbol_value.types {
		if ident, ok := type.derived.(ast.Ident); ok {
			if expr, ok := poly_map[ident.name]; ok {
				symbol_value.types[i] = expr;
			}
		} else if call_expr, ok := type.derived.(ast.Call_Expr); ok {
			if call_expr.args == nil {
				continue;
			}

			for arg, i in call_expr.args {
				if ident, ok := arg.derived.(ast.Ident); ok {
					if expr, ok := poly_map[ident.name]; ok {
						symbol_value.types[i] = expr;
					}
				}
			}
		}
	}
}

get_globals :: proc(file: ast.File, ast_context: ^AstContext) {

	ast_context.variables["context"] = true;

	exprs := common.collect_globals(file);

	for expr in exprs {
		ast_context.variables[expr.name] = expr.mutable;
		ast_context.globals[expr.name] = expr;
	}
}

get_generic_assignment :: proc(file: ast.File, value: ^ast.Expr, ast_context: ^AstContext, results: ^[dynamic]^ast.Expr) {

	using ast;

	ast_context.use_locals = true;
	ast_context.use_globals = true;

	switch v in &value.derived {
	case Call_Expr:

		ast_context.call = cast(^ast.Call_Expr)value;

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
			//This is the unique .? that can only be used with maybe
			if unary, ok := v.type.derived.(ast.Unary_Expr); ok && unary.op.kind == .Question {
				append(results, cast(^ast.Expr)&v.node);
			} else {
				append(results, v.type);
			}

			b := make_bool_ast();
			b.pos.file = v.type.pos.file;
			append(results, b);
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
		for name, i in value_decl.names {
			str := common.get_ast_node_string(value_decl.names[i], file.src);
			ast_context.variables[str] = value_decl.is_mutable;
			store_local(ast_context, value_decl.type, value_decl.end.offset, str);
		}
		return;
	}

	results := make([dynamic]^Expr, context.temp_allocator);

	for value in value_decl.values {
		get_generic_assignment(file, value, ast_context, &results);
	}

	if len(results) == 0 {
		return;
	}

	for name, i in value_decl.names {
		result_i := min(len(results)-1, i);
		str := common.get_ast_node_string(name, file.src);
		ast_context.in_package[str] = get_package_from_node(results[result_i]);
		store_local(ast_context, results[result_i], value_decl.end.offset, str);
		ast_context.variables[str] = value_decl.is_mutable;
	}
}

get_locals_stmt :: proc(file: ast.File, stmt: ^ast.Stmt, ast_context: ^AstContext, document_position: ^DocumentPositionContext, save_assign := false) {

	ast_context.use_locals = true;
	ast_context.use_globals = true;
	ast_context.current_package = ast_context.document_package;

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
	case Inline_Range_Stmt:
		get_locals_stmt(file, v.body, ast_context, document_position);
	case Range_Stmt:
		get_locals_for_range_stmt(file, v, ast_context, document_position);
	case If_Stmt:
		get_locals_if_stmt(file, v, ast_context, document_position);
	case Block_Stmt:
		get_locals_block_stmt(file, v, ast_context, document_position);
	case Proc_Lit:
		get_locals_stmt(file, v.body, ast_context, document_position);
	case Assign_Stmt:
		if save_assign {
			get_locals_assign_stmt(file, v, ast_context);
		}
	case Using_Stmt:
		get_locals_using_stmt(v, ast_context);
	case When_Stmt:
		get_locals_stmt(file, v.else_stmt, ast_context, document_position);
		get_locals_stmt(file, v.body, ast_context, document_position);
	case Case_Clause:
		for stmt in v.body {
			get_locals_stmt(file, stmt, ast_context, document_position);
		}
	case:
			//log.debugf("default node local stmt %v", v);
	}
}

get_locals_block_stmt :: proc(file: ast.File, block: ast.Block_Stmt, ast_context: ^AstContext, document_position: ^DocumentPositionContext) {

	if !(block.pos.offset <= document_position.position && document_position.position <= block.end.offset) {
		return;
	}

	for stmt in block.stmts {
		get_locals_stmt(file, stmt, ast_context, document_position);
	}
}

get_locals_using_stmt :: proc(stmt: ast.Using_Stmt, ast_context: ^AstContext) {

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
					store_local(ast_context, selector, 0, name);
					ast_context.variables[name] = true;
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
			store_local(ast_context, results[i], ident.pos.offset, ident.name);
			ast_context.variables[ident.name] = true;
		}
	}
}

get_locals_if_stmt :: proc(file: ast.File, stmt: ast.If_Stmt, ast_context: ^AstContext, document_position: ^DocumentPositionContext) {

	if !(stmt.pos.offset <= document_position.position && document_position.position <= stmt.end.offset) {
		return;
	}

	get_locals_stmt(file, stmt.init, ast_context, document_position, true);
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
		#partial switch v in symbol.value {
		case index.SymbolMapValue:
			if len(stmt.vals) >= 1 {
				if ident, ok := stmt.vals[0].derived.(Ident); ok {
					store_local(ast_context, v.key, ident.pos.offset, ident.name);
					ast_context.variables[ident.name] = true;
					ast_context.in_package[ident.name] = symbol.pkg;
				}
			}
			if len(stmt.vals) >= 2 {
				if ident, ok := stmt.vals[1].derived.(Ident); ok {
					store_local(ast_context, v.value, ident.pos.offset, ident.name);
					ast_context.variables[ident.name] = true;
					ast_context.in_package[ident.name] = symbol.pkg;
				}
			}
		case index.SymbolDynamicArrayValue:
			if len(stmt.vals) >= 1 {
				if ident, ok := stmt.vals[0].derived.(Ident); ok {
					store_local(ast_context, v.expr, ident.pos.offset, ident.name);
					ast_context.variables[ident.name] = true;
					ast_context.in_package[ident.name] = symbol.pkg;
				}
			}
			if len(stmt.vals) >= 2 {
				if ident, ok := stmt.vals[1].derived.(Ident); ok {
					store_local(ast_context, make_int_ast(), ident.pos.offset, ident.name);
					ast_context.variables[ident.name] = true;
					ast_context.in_package[ident.name] = symbol.pkg;
				}
			}
		case index.SymbolFixedArrayValue:
			if len(stmt.vals) >= 1 {
				if ident, ok := stmt.vals[0].derived.(Ident); ok {
					store_local(ast_context, v.expr, ident.pos.offset, ident.name);
					ast_context.variables[ident.name] = true;
					ast_context.in_package[ident.name] = symbol.pkg;
				}
			}

			if len(stmt.vals) >= 2 {
				if ident, ok := stmt.vals[1].derived.(Ident); ok {
					store_local(ast_context, make_int_ast(), ident.pos.offset, ident.name);
					ast_context.variables[ident.name] = true;
					ast_context.in_package[ident.name] = symbol.pkg;
				}
			}
		case index.SymbolSliceValue:
			if len(stmt.vals) >= 1 {
				if ident, ok := stmt.vals[0].derived.(Ident); ok {
					store_local(ast_context, v.expr, ident.pos.offset, ident.name);
					ast_context.variables[ident.name] = true;
					ast_context.in_package[ident.name] = symbol.pkg;
				}
			}
			if len(stmt.vals) >= 2 {
				if ident, ok := stmt.vals[1].derived.(Ident); ok {
					store_local(ast_context, make_int_ast(), ident.pos.offset, ident.name);
					ast_context.variables[ident.name] = true;
					ast_context.in_package[ident.name] = symbol.pkg;
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

	get_locals_stmt(file, stmt.init, ast_context, document_position, true);
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
					store_local(ast_context, cause.list[0], ident.pos.offset, ident.name);
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
					store_local(ast_context, arg.type, name.pos.offset, str);
					ast_context.variables[str] = true;
					ast_context.parameters[str] = true;

					if .Using in arg.flags {
						using_stmt: ast.Using_Stmt;
						using_stmt.list = make([]^ast.Expr, 1, context.temp_allocator);
						using_stmt.list[0] = arg.type;
						get_locals_using_stmt(using_stmt, ast_context);
					}
				} else {
					str := common.get_ast_node_string(name, file.src);
					store_local(ast_context, arg.default_value, name.pos.offset, str);
					ast_context.variables[str] = true;
					ast_context.parameters[str] = true;
				}
			}
		}
	}

	if proc_lit.type != nil && proc_lit.type.results != nil {

		for result in proc_lit.type.results.list {

			for name in result.names {
				if result.type != nil {
					str := common.get_ast_node_string(name, file.src);
					store_local(ast_context, result.type, name.pos.offset, str);
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

concatenate_symbols_information :: proc(ast_context: ^AstContext, symbol: index.Symbol, is_completion: bool) -> string {
	pkg := path.base(symbol.pkg, false, context.temp_allocator);

	if symbol.type == .Function {
		if symbol.returns != "" {
			return fmt.tprintf("%v.%v: proc%v -> %v", pkg, symbol.name, symbol.signature, symbol.returns);
		} else {
			return fmt.tprintf("%v.%v: proc%v", pkg, symbol.name, symbol.signature);
		}
	} else if symbol.type == .Package {
		return symbol.name;
	} else if symbol.type == .Keyword && is_completion {
		return symbol.name;
	} else {
		if symbol.signature != "" {
			return fmt.tprintf("%v.%v: %v", pkg, symbol.name, symbol.signature);
		} else {
			return fmt.tprintf("%v.%v", pkg, symbol.name);
		}
	}
}

unwrap_enum :: proc(ast_context: ^AstContext, node: ^ast.Expr) -> (index.SymbolEnumValue, bool) {

	if node == nil {
		return {}, false;
	}

	if enum_symbol, ok := resolve_type_expression(ast_context, node); ok {

		if enum_value, ok := enum_symbol.value.(index.SymbolEnumValue); ok {
			return enum_value, true;
		}
	}

	return {}, false;
}

unwrap_union :: proc(ast_context: ^AstContext, node: ^ast.Expr) -> (index.SymbolUnionValue, bool) {

	if union_symbol, ok := resolve_type_expression(ast_context, node); ok {

		if union_value, ok := union_symbol.value.(index.SymbolUnionValue); ok {
			return union_value, true;
		}
	}

	return {}, false;
}

unwrap_bitset :: proc(ast_context: ^AstContext, bitset_symbol: index.Symbol) -> (index.SymbolEnumValue, bool) {

	if bitset_value, ok := bitset_symbol.value.(index.SymbolBitSetValue); ok {
		if enum_symbol, ok := resolve_type_expression(ast_context, bitset_value.expr); ok {
			if enum_value, ok := enum_symbol.value.(index.SymbolEnumValue); ok {
				return enum_value, true;
			}
		}
	}

	return {}, false;
}

get_signature :: proc(ast_context: ^AstContext, ident: ast.Ident, symbol: index.Symbol, was_variable := false) -> string {

	using index;

	if symbol.type == .Function {
		return symbol.signature;
	}

	is_variable := resolve_ident_is_variable(ast_context, ident);

	#partial switch v in symbol.value {
	case SymbolBasicValue:
		return common.node_to_string(v.ident);
	case SymbolBitSetValue:
		return common.node_to_string(v.expr);
	case SymbolEnumValue:
		if is_variable {
			return v.enum_name;
		}
		else {
			return "enum";
		}
	case SymbolMapValue:
		return strings.concatenate(a = {"map[", common.node_to_string(v.key), "]", common.node_to_string(v.value)}, allocator = context.temp_allocator);
	case SymbolProcedureValue:
		return "proc";
	case SymbolStructValue:
		if is_variable {
			return v.struct_name;
		}
		else {
			return "struct";
		}
	case SymbolUnionValue:
		if is_variable {
			return v.union_name;
		}
		else {
			return "union";
		}
	case SymbolDynamicArrayValue:
		return strings.concatenate(a = {"[dynamic]", common.node_to_string(v.expr)}, allocator = context.temp_allocator);
	case SymbolSliceValue:
		return strings.concatenate(a = {"[]", common.node_to_string(v.expr)}, allocator = context.temp_allocator);
	case SymbolFixedArrayValue:
		return strings.concatenate(a = {"[", common.node_to_string(v.len), "]", common.node_to_string(v.expr)}, allocator = context.temp_allocator);
	case SymbolPackageValue:
		return "package";
	case SymbolUntypedValue:
		switch v.type {
		case .Float:   return "float"
		case .String:  return "string"
		case .Bool:    return "bool"
		case .Integer: return "int"
		}
	}
	
	return "";
}

position_in_proc_decl :: proc(position_context: ^DocumentPositionContext) -> bool {

	if position_context.value_decl == nil {
		return false;
	}

	if len(position_context.value_decl.values) != 1 {
		return false;
	}

	if _, ok := position_context.value_decl.values[0].derived.(ast.Proc_Type); ok {
		return true;
	}

	if proc_lit, ok := position_context.value_decl.values[0].derived.(ast.Proc_Lit); ok {
		if proc_lit.type != nil && position_in_node(proc_lit.type, position_context.position) {
			return true;
		}
	}

	return false;
}


is_lhs_comp_lit :: proc(position_context: ^DocumentPositionContext) -> bool {

	if len(position_context.comp_lit.elems) == 0 {
		return true;
	}

	for elem in position_context.comp_lit.elems {

		if position_in_node(elem, position_context.position) {

			if ident, ok := elem.derived.(ast.Ident); ok {
				return true;
			} else if field, ok := elem.derived.(ast.Field_Value); ok {

				if position_in_node(field.value, position_context.position) {
					return false;
				}
			}
		}
	}

	return true;
}

field_exists_in_comp_lit :: proc(comp_lit: ^ast.Comp_Lit, name: string) -> bool {

	for elem in comp_lit.elems {

		if field, ok := elem.derived.(ast.Field_Value); ok {

			if field.field != nil {

				if ident, ok := field.field.derived.(ast.Ident); ok {

					if ident.name == name {
						return true;
					}
				}
			}
		}
	}

	return false;
}

/*
	Parser gives ranges of expression, but not actually where the commas are placed.
*/
get_call_commas :: proc(position_context: ^DocumentPositionContext, document: ^common.Document) {

	if position_context.call == nil {
		return;
	}

	commas := make([dynamic]int, 0, 10, context.temp_allocator);

	paren_count := 0;
	bracket_count := 0;
	brace_count := 0;

	if call, ok := position_context.call.derived.(ast.Call_Expr); ok {
		if document.text[call.open.offset] == '(' {
			paren_count -= 1;
		}
		for i := call.open.offset; i < call.close.offset; i += 1 {
			switch document.text[i] {
			case '[': paren_count += 1;
			case ']': paren_count -= 1;
			case '{': brace_count += 1;
			case '}': brace_count -= 1;
			case '(': paren_count += 1;
			case ')': paren_count -= 1;
			case ',':
				if paren_count == 0 && brace_count == 0 && bracket_count == 0 {
					append(&commas, i);
				}
			}
		}
	}

	position_context.call_commas = commas[:];
}

type_to_string :: proc(ast_context: ^AstContext, expr: ^ast.Expr) -> string {
	
	if symbol, ok := resolve_type_expression(ast_context, expr); ok {
		if .Anonymous in symbol.flags {
			return symbol.name;
		}
	}

	return  common.node_to_string(expr);
}

/*
	Figure out what exactly is at the given position and whether it is in a function, struct, etc.
*/
get_document_position_context :: proc(document: ^common.Document, position: common.Position, hint: DocumentPositionContextHint) -> (DocumentPositionContext, bool) {

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

	exists_in_decl := false;

	for decl in document.ast.decls {
		if position_in_node(decl, position_context.position) {
			get_document_position(decl, &position_context);
			exists_in_decl = true;
			switch v in decl.derived {
			case ast.Expr_Stmt:
				position_context.global_lhs_stmt = true;
			}
			break;
		}
	}

	for import_stmt in document.ast.imports {
		if position_in_node(import_stmt, position_context.position) {
			position_context.import_stmt = import_stmt;
			break;
		}
	}

	if !exists_in_decl && position_context.import_stmt == nil {
		position_context.abort_completion = true;
	}

	if !position_in_node(position_context.comp_lit, position_context.position) {
		position_context.comp_lit = nil;
	}

	if !position_in_node(position_context.parent_comp_lit, position_context.position) {
		position_context.parent_comp_lit = nil;
	}

	if !position_in_node(position_context.assign, position_context.position) {
		position_context.assign = nil;
	}

	if !position_in_node(position_context.binary, position_context.position) {
		position_context.binary = nil;
	}

	if !position_in_node(position_context.parent_binary, position_context.position) {
		position_context.parent_binary = nil;
	}

	if hint == .Completion && position_context.selector == nil && position_context.field == nil {
		fallback_position_context_completion(document, position, &position_context);
	}

	if (hint == .SignatureHelp || hint == .Completion) && position_context.call == nil {
		fallback_position_context_signature(document, position, &position_context);
	}

	if hint == .SignatureHelp {
		get_call_commas(&position_context, document);
	}

	return position_context, true;
}

//terrible fallback code
fallback_position_context_completion :: proc(document: ^common.Document, position: common.Position, position_context: ^DocumentPositionContext) {

	paren_count:   int;
	bracket_count: int;
	end:           int;
	start:         int;
	empty_dot:     bool;
	empty_arrow:   bool;
	last_dot:      bool;
	last_arrow:    bool;
	dots_seen:     int;
	partial_arrow: bool;

	i := position_context.position - 1;

	end = i;

	for i > 0 {

		c := position_context.file.src[i];

		if c == '(' && paren_count == 0 {
			start = i + 1;
			break;
		} else if c == '[' && bracket_count == 0 {
			start = i + 1;
			break;
		} else if c == ']' && !last_dot {
			start = i + 1;
			break;
		} else if c == ')' && !last_dot {
			start = i + 1;
			break;
		} else if c == ')' {
			paren_count -= 1;
		} else if c == '(' {
			paren_count += 1;
		} else if c == '[' {
			bracket_count += 1;
		} else if c == ']' {
			bracket_count -= 1;
		} else if c == '.' {
			dots_seen += 1;
			last_dot = true;
			i -= 1;
			continue;
		} else if position_context.file.src[max(0, i - 1)] == '-' && c == '>' {
			last_arrow = true;
			i -= 2;
			continue;
		}

		//ignore everything in the bracket
		if bracket_count != 0 || paren_count != 0 {
			i -= 1;
			continue;
		}

		//yeah..
		if c == ' ' || c == '{' || c == ',' ||
		c == '}' || c == '^' || c == ':' ||
		c == '\n' || c == '\r' || c == '=' ||
		c == '<' || c == '-' || c == '!' ||
		c == '+' || c == '&'|| c == '|' {
			start = i + 1;
			break;
		} else if c == '>' {
			partial_arrow = true;
		}

		last_dot = false;
		last_arrow = false;

		i -= 1;
	}

	if i >= 0 && position_context.file.src[end] == '.' {
		empty_dot = true;
		end -= 1;
	} else if i >= 0 && position_context.file.src[max(0, end - 1)] == '-' && position_context.file.src[end] == '>' {
		empty_arrow = true;
		end -= 2;
		position_context.arrow = true;
	}

	begin_offset := max(0, start);
	end_offset   := max(start, end + 1);

	str := position_context.file.src[0:end_offset];

	if empty_dot && end_offset - begin_offset == 0 {
		position_context.implicit = true;
		return;
	}

	s := string(position_context.file.src[begin_offset:end_offset]);

	if !partial_arrow {

		only_whitespaces := true;

		for r in s {
			if !strings.is_space(r) {
				only_whitespaces = false;
			}
		}

		if only_whitespaces {
			return;
		}
	}

	p := parser.Parser {
		err = common.parser_warning_handler,  //empty
		warn = common.parser_warning_handler, //empty
		file = &position_context.file,
	};

	tokenizer.init(&p.tok, str, position_context.file.fullpath, common.parser_warning_handler);

	p.tok.ch = ' ';
	p.tok.line_count = position.line;
	p.tok.offset = begin_offset;
	p.tok.read_offset = begin_offset;

	tokenizer.advance_rune(&p.tok);

	if p.tok.ch == utf8.RUNE_BOM {
		tokenizer.advance_rune(&p.tok);
	}

	parser.advance_token(&p);

	context.allocator = context.temp_allocator;

	e := parser.parse_expr(&p, true);

	if empty_dot || empty_arrow {
		position_context.selector = e;
	} else if s, ok := e.derived.(ast.Selector_Expr); ok {
		position_context.selector = s.expr;
		position_context.field = s.field;
	} else if s, ok := e.derived.(ast.Implicit_Selector_Expr); ok {
		position_context.implicit = true;
	} else if s, ok := e.derived.(ast.Tag_Expr); ok {
		position_context.tag = s.expr;
	} else if bad_expr, ok := e.derived.(ast.Bad_Expr); ok {
		//this is most likely because of use of 'in', 'context', etc.
		//try to go back one dot.

		src_with_dot := string(position_context.file.src[0:min(len(position_context.file.src), end_offset + 1)]);
		last_dot     := strings.last_index(src_with_dot, ".");

		if last_dot == -1 {
			return;
		}

		tokenizer.init(&p.tok, position_context.file.src[0:last_dot], position_context.file.fullpath, common.parser_warning_handler);

		p.tok.ch = ' ';
		p.tok.line_count = position.line;
		p.tok.offset = begin_offset;
		p.tok.read_offset = begin_offset;

		tokenizer.advance_rune(&p.tok);

		if p.tok.ch == utf8.RUNE_BOM {
			tokenizer.advance_rune(&p.tok);
		}

		parser.advance_token(&p);

		e := parser.parse_expr(&p, true);

		if e == nil {
			position_context.abort_completion = true;
			return;
		} else if e, ok := e.derived.(ast.Bad_Expr); ok {
			position_context.abort_completion = true;
			return;
		}

		position_context.selector = e;

		ident := index.new_type(ast.Ident, e.pos, e.end, context.temp_allocator);
		ident.name = string(position_context.file.src[last_dot + 1:end_offset]);

		if ident.name != "" {
			position_context.field = ident;
		}
	} else {
		position_context.identifier = e;
	}
}

fallback_position_context_signature :: proc(document: ^common.Document, position: common.Position, position_context: ^DocumentPositionContext) {

	end:   int;
	start: int;
	i := position_context.position - 1;
	end = i;

	for i > 0 {

		c := position_context.file.src[i];

		if c == ' ' || c == '\n' || c == '\r' {
			start = i + 1;
			break;
		}

		i -= 1;
	}

	if end < 0 {
		return;
	}

	if position_context.file.src[end] != '(' {
		return;
	}

	end -= 1;

	begin_offset := max(0, start);
	end_offset   := max(start, end + 1);

	if end_offset - begin_offset <= 1 {
		return;
	}

	str := position_context.file.src[0:end_offset];

	p := parser.Parser {
		err = common.parser_warning_handler,  //empty
		warn = common.parser_warning_handler, //empty
		file = &position_context.file,
	};

	tokenizer.init(&p.tok, str, position_context.file.fullpath, common.parser_warning_handler);

	p.tok.ch = ' ';
	p.tok.line_count = position.line;
	p.tok.offset = begin_offset;
	p.tok.read_offset = begin_offset;

	tokenizer.advance_rune(&p.tok);

	if p.tok.ch == utf8.RUNE_BOM {
		tokenizer.advance_rune(&p.tok);
	}

	parser.advance_token(&p);

	context.allocator = context.temp_allocator;

	position_context.call = parser.parse_expr(&p, true);

	if _, ok := position_context.call.derived.(ast.Proc_Type); ok {
		position_context.call = nil;
	}
	
	//log.error(string(position_context.file.src[begin_offset:end_offset]));
}

/*
	All these fallback functions are not perfect and should be fixed. A lot of weird use of the odin tokenizer and parser.
*/

get_document_position ::proc {
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
	case Implicit:
	case Undef:
	case Basic_Lit:
	case Ellipsis:
		get_document_position(n.expr, position_context);
	case Proc_Lit:
		get_document_position(n.type, position_context);

		if position_in_node(n.body, position_context.position) {
			position_context.function = cast(^Proc_Lit)node;
			get_document_position(n.body, position_context);
		}  
	case Comp_Lit:
		//only set this for the parent comp literal, since we will need to walk through it to infer types.
		if position_context.parent_comp_lit == nil {
			position_context.parent_comp_lit = cast(^Comp_Lit)node;
		}

		position_context.comp_lit = cast(^Comp_Lit)node;

		get_document_position(n.type, position_context);
		get_document_position(n.elems, position_context);
	case Tag_Expr:
		get_document_position(n.expr, position_context);
	case Unary_Expr:
		get_document_position(n.expr, position_context);
	case Binary_Expr:
		if position_context.parent_binary == nil {
			position_context.parent_binary = cast(^Binary_Expr)node;
		}
		position_context.binary = cast(^Binary_Expr)node;
		get_document_position(n.left, position_context);
		get_document_position(n.right, position_context);
	case Paren_Expr:
		get_document_position(n.expr, position_context);
	case Call_Expr:
		if position_context.hint == .SignatureHelp || position_context.hint == .Completion {
			position_context.call = cast(^Expr)node;
		}
		get_document_position(n.expr, position_context);
		get_document_position(n.args, position_context);
	case Selector_Expr:
		if position_context.hint == .Completion {
			if n.field != nil && n.field.pos.line - 1 == position_context.line {
				//The parser is not fault tolerant enough, relying on the fallback as the main completion parsing for now
				//position_context.selector = n.expr;
				//position_context.field = n.field;
			}
		} else if (position_context.hint == .Definition || position_context.hint == .Hover) && n.field != nil {
			position_context.selector = n.expr;
			position_context.field = n.field;
			get_document_position(n.expr, position_context);
			get_document_position(n.field, position_context);
		} else {
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
		position_context.field_value = cast(^Field_Value)node;
		get_document_position(n.field, position_context);
		get_document_position(n.value, position_context);
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
		position_context.assign = cast(^Assign_Stmt)node;
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
		position_context.returns = cast(^Return_Stmt)node;
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
		get_document_position(n.vals, position_context);
		get_document_position(n.expr, position_context);
		get_document_position(n.body, position_context);
	case Case_Clause:

		for elem in n.list {
			if position_in_node(elem, position_context.position) {
				position_context.case_clause = cast(^Case_Clause)node;
				break;
			}
		}

		get_document_position(n.list, position_context);
		get_document_position(n.body, position_context);
	case Switch_Stmt:
		position_context.switch_stmt = cast(^Switch_Stmt)node;
		get_document_position(n.label, position_context);
		get_document_position(n.init, position_context);
		get_document_position(n.cond, position_context);
		get_document_position(n.body, position_context);
	case Type_Switch_Stmt:
		position_context.switch_type_stmt = cast(^Type_Switch_Stmt)node;
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
		position_context.value_decl = cast(^Value_Decl)node;
		get_document_position(n.attributes, position_context);

		for name in n.names {
			if position_in_node(name, position_context.position) && n.end.line - 1 == position_context.line {
				position_context.abort_completion = true;
				break;
			}
		}
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
	case Bit_Set_Type:
		get_document_position(n.elem, position_context);
		get_document_position(n.underlying, position_context);
	case Map_Type:
		get_document_position(n.key, position_context);
		get_document_position(n.value, position_context);
	case Implicit_Selector_Expr:
		position_context.implicit = true;
		get_document_position(n.field, position_context);
	case:
		log.errorf("Unhandled node kind: %T", n);
	}
}
