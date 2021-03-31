package server

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

import "shared:common"
import "shared:index"

/*
	TODO(replace all of the possible ast walking with the new odin visitor function)
	TODO(improve the current_package logic, kinda confusing switching between different packages with selectors)
	TODO(try to flatten some of the nested branches if possible)
*/

bool_lit   := "bool";
int_lit    := "int";
string_lit := "string";

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
	selector:         ^ast.Expr, //used for completion
	identifier:       ^ast.Node,
	tag:              ^ast.Node,
	field:            ^ast.Expr, //used for completion
	call:             ^ast.Expr, //used for signature help
	returns:          ^ast.Return_Stmt, //used for completion
	comp_lit:         ^ast.Comp_Lit, //used for completion
	parent_comp_lit:  ^ast.Comp_Lit, //used for completion
	implicit:         bool, //used for completion
	arrow:            bool,
	binary:           ^ast.Binary_Expr, //used for completion
	parent_binary:    ^ast.Binary_Expr, //used for completion
	assign:           ^ast.Assign_Stmt, //used for completion
	switch_stmt:      ^ast.Switch_Stmt, //used for completion
	switch_type_stmt: ^ast.Type_Switch_Stmt, //used for completion
	case_clause:      ^ast.Case_Clause, //used for completion
	value_decl:       ^ast.Value_Decl, //used for completion
	abort_completion: bool,
	hint:             DocumentPositionContextHint,
	global_lhs_stmt:  bool,
	import_stmt:      ^ast.Import_Decl,
}

DocumentLocal :: struct {
	expr:   ^ast.Expr,
	offset: int,
}

AstContext :: struct {
	locals:           map[string][dynamic]DocumentLocal, //locals all the way to the document position
	globals:          map[string]^ast.Expr,
	variables:        map[string]bool,
	parameters:       map[string]bool,
	in_package:       map[string]string, //sometimes you have to extract types from arrays/maps and you lose package information
	usings:           [dynamic]string,
	file:             ast.File,
	allocator:        mem.Allocator,
	imports:          []Package, //imports for the current document
	current_package:  string,
	document_package: string,
	use_globals:      bool,
	use_locals:       bool,
	call:             ^ast.Call_Expr, //used to determene the types for generics and the correct function for overloaded functions
	position:         common.AbsolutePosition,
	value_decl:       ^ast.Value_Decl,
	field_name:       string,
}

make_ast_context :: proc(file: ast.File, imports: []Package, package_name: string, allocator := context.temp_allocator) -> AstContext {

	ast_context := AstContext {
		locals = make(map[string][dynamic]DocumentLocal, 0, allocator),
		globals = make(map[string]^ast.Expr, 0, allocator),
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
	};
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

resolve_type_comp_literal :: proc(ast_context: ^AstContext, position_context: ^DocumentPositionContext, current_symbol: index.Symbol, current_comp_lit: ^ast.Comp_Lit) -> (index.Symbol, bool) {

	if position_context.comp_lit == current_comp_lit {
		return current_symbol, true;
	}

	for elem in current_comp_lit.elems {

		if !position_in_node(elem, position_context.position) {
			continue;
		}

		if field_value, ok := elem.derived.(ast.Field_Value); ok {

			if comp_lit, ok := field_value.value.derived.(ast.Comp_Lit); ok {

				if s, ok := current_symbol.value.(index.SymbolStructValue); ok {

					for name, i in s.names {

						if name == field_value.field.derived.(ast.Ident).name {

							if symbol, ok := resolve_type_expression(ast_context, s.types[i]); ok {
								return resolve_type_comp_literal(ast_context, position_context, symbol, cast(^ast.Comp_Lit)field_value.value);
							}
						}
					}
				}
			}
		}
	}

	return current_symbol, true;
}

resolve_generic_function :: proc {
	resolve_generic_function_ast,
	resolve_generic_function_symbol,
};

resolve_generic_function_symbol :: proc(ast_context: ^AstContext, params: []^ast.Field, results: []^ast.Field) -> (index.Symbol, bool) {
	using ast;

	if params == nil {
		return index.Symbol {}, false;
	}

	if results == nil {
		return index.Symbol {}, false;
	}

	if ast_context.call == nil {
		return index.Symbol {}, false;
	}

	call_expr := ast_context.call;
	poly_map  := make(map[string]^Expr, 0, context.temp_allocator);
	i         := 0;

	for param in params {

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

			if poly, ok := param.type.derived.(Poly_Type); ok {

				if arg_eval, ok := resolve_type_expression(ast_context, call_expr.args[i]); ok {

					if value, ok := arg_eval.value.(index.SymbolGenericValue); ok {
						resolve_poly_spec_node(ast_context, value.expr, poly.specialization, &poly_map);
					}
				}
			}

			i += 1;
		}
	}

	function_name := "";
	function_range: common.Range;

	if ident, ok := call_expr.expr.derived.(Ident); ok {
		function_name  = ident.name;
		function_range = common.get_token_range(ident, ast_context.file.src);
	} else if selector, ok := call_expr.expr.derived.(Selector_Expr); ok {
		function_name  = selector.field.name;
		function_range = common.get_token_range(selector, ast_context.file.src);
	} else {
		log.debug("call expr expr could not be derived correctly");
		return index.Symbol {}, false;
	}

	symbol := index.Symbol {
		range = function_range,
		type = .Function,
		name = function_name,
	};

	return_types := make([dynamic]^ast.Field, context.temp_allocator);

	for result in results {

		if result.type == nil {
			continue;
		}

		if ident, ok := result.type.derived.(Ident); ok {
			field := cast(^Field)index.clone_node(result, context.temp_allocator, nil);

			if m := &poly_map[ident.name]; m != nil {
				field.type = poly_map[ident.name];
				append(&return_types, field);
			} else {
				return index.Symbol {}, false;
			}
		}
	}

	symbol.value = index.SymbolProcedureValue {
		return_types = return_types[:],
		arg_types = params,
	};

	//log.infof("return %v", poly_map);

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

/*
	Figure out which function the call expression is using out of the list from proc group
*/
resolve_function_overload :: proc(ast_context: ^AstContext, group: ast.Proc_Group) -> (index.Symbol, bool) {

	using ast;

	//log.info("overload");

	if ast_context.call == nil {
		//log.info("no call");
		return index.Symbol {}, false;
	}

	call_expr := ast_context.call;

	for arg_expr in group.args {

		next_fn: if f, ok := resolve_type_expression(ast_context, arg_expr); ok {

			if procedure, ok := f.value.(index.SymbolProcedureValue); ok {

				if len(procedure.arg_types) < len(call_expr.args) {
					continue;
				}

				for arg, i in call_expr.args {

					if eval_call_expr, ok := resolve_type_expression(ast_context, arg); ok {

						#partial switch v in eval_call_expr.value {
						case index.SymbolProcedureValue:
						case index.SymbolGenericValue:
							if !common.node_equal(v.expr, procedure.arg_types[i].type) {
								break next_fn;
							}
						case index.SymbolStructValue:
						}
					} else {
						//log.debug("Failed to resolve call expr");
						return index.Symbol {}, false;
					}
				}

				//log.debugf("return overload %v", f);
				return f, true;
			}
		}
	}

	return index.Symbol {}, false;
}

resolve_basic_lit :: proc(ast_context: ^AstContext, basic_lit: ast.Basic_Lit) -> (index.Symbol, bool) {

	/*
		This is temporary, since basic lit is untyped, but either way it's going to be an ident representing a keyword.

		Could perhaps name them "$integer", "$float", etc.
	*/

	ident := index.new_type(ast.Ident, basic_lit.pos, basic_lit.end, context.temp_allocator);

	symbol := index.Symbol {
		type = .Keyword,
	};

	if v, ok := strconv.parse_bool(basic_lit.tok.text); ok {
		ident.name = bool_lit;
	} else if v, ok := strconv.parse_int(basic_lit.tok.text); ok {
		ident.name = int_lit;
	} else {
		ident.name = string_lit;
	}

	symbol.value = index.SymbolGenericValue {
		expr = ident,
	};

	return symbol, true;
}

resolve_type_expression :: proc(ast_context: ^AstContext, node: ^ast.Expr) -> (index.Symbol, bool) {

	if node == nil {
		return {}, false;
	}

	using ast;

	switch v in node.derived {
	case Proc_Type:
		return make_symbol_procedure_from_ast(ast_context, node, v, ast_context.field_name), true;
	case Ident:
		return resolve_type_identifier(ast_context, v);
	case Basic_Lit:
		return resolve_basic_lit(ast_context, v);
	case Type_Cast:
		return resolve_type_expression(ast_context, v.type);
	case Auto_Cast:
		return resolve_type_expression(ast_context, v.expr);
	case Unary_Expr:
		if v.op.kind == .And {
			return resolve_type_expression(ast_context, make_pointer_ast(v.expr));
		} else {
			return resolve_type_expression(ast_context, v.expr);
		}
	case Deref_Expr:
		return resolve_type_expression(ast_context, v.expr);
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
		return resolve_type_expression(ast_context, v.type);
	case Proc_Lit:
		if v.type.results != nil {
			if len(v.type.results.list) == 1 {
				return resolve_type_expression(ast_context, v.type.results.list[0].type);
			}
		}
	case Pointer_Type:

		/*
			Add flag to not pull out a type from a pointer for function overloading.
		*/

		if v2, ok := v.elem.derived.(ast.Pointer_Type); !ok {
			return resolve_type_expression(ast_context, v.elem);
		} else if v2, ok := v.elem.derived.(ast.Type_Assertion); !ok {
			return resolve_type_expression(ast_context, v.elem);
		} else {
			return make_symbol_generic_from_ast(ast_context, node), true;
		}

	case Index_Expr:
		indexed, ok := resolve_type_expression(ast_context, v.expr);

		if generic, ok := indexed.value.(index.SymbolGenericValue); ok {

			switch c in generic.expr.derived {
			case Array_Type:
				return resolve_type_expression(ast_context, c.elem);
			case Dynamic_Array_Type:
				return resolve_type_expression(ast_context, c.elem);
			case Map_Type:
				return resolve_type_expression(ast_context, c.value);
			}
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
			case index.SymbolProcedureValue:

				if len(s.return_types) == 1 {
					selector_expr := index.new_type(ast.Selector_Expr, s.return_types[0].node.pos, s.return_types[0].node.end, context.temp_allocator);
					selector_expr.expr  = s.return_types[0].type;
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

		return make_symbol_generic_from_ast(ast_context, node), true;
	}

	return index.Symbol {}, false;
}

store_local :: proc(ast_context: ^AstContext, expr: ^ast.Expr, offset: int, name: string) {

	local_stack := &ast_context.locals[name];

	if local_stack == nil {
		ast_context.locals[name] = make([dynamic]DocumentLocal, context.temp_allocator);
		local_stack              = &ast_context.locals[name];
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
				return local_stack[max(0, i - previous)].expr;
			}
		}
	}

	return nil;
}

/*
	Function recusively goes through the identifier until it hits a struct, enum, procedure literals, since you can
	have chained variable declarations. ie. a := foo { test =  2}; b := a; c := b;
*/
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

		switch v in local.derived {
		case Ident:

			if node.name == v.name {
				break;
			}

			return resolve_type_identifier(ast_context, v);
		case Union_Type:
			return make_symbol_union_from_ast(ast_context, v, node), true;
		case Enum_Type:
			return make_symbol_enum_from_ast(ast_context, v, node), true;
		case Struct_Type:
			return make_symbol_struct_from_ast(ast_context, v, node), true;
		case Bit_Set_Type:
			return make_symbol_bitset_from_ast(ast_context, v, node), true;
		case Proc_Lit:
			if !v.type.generic {
				return make_symbol_procedure_from_ast(ast_context, local, v.type^, node.name), true;
			} else {
				return resolve_generic_function(ast_context, v);
			}
		case Proc_Group:
			return resolve_function_overload(ast_context, v);
		case Array_Type:
			return make_symbol_generic_from_ast(ast_context, local), true;
		case Dynamic_Array_Type:
			return make_symbol_generic_from_ast(ast_context, local), true;
		case Call_Expr:
			return resolve_type_expression(ast_context, local);
		case:
			log.warnf("default type node kind: %T", v);
			return resolve_type_expression(ast_context, local);
				//return make_symbol_generic_from_ast(ast_context, local), true;
		}
	} else if global, ok := ast_context.globals[node.name]; ast_context.use_globals && ok {

		switch v in global.derived {
		case Ident:

			if node.name == v.name {
				break;
			}

			return resolve_type_identifier(ast_context, v);
		case Struct_Type:
			return make_symbol_struct_from_ast(ast_context, v, node), true;
		case Bit_Set_Type:
			return make_symbol_bitset_from_ast(ast_context, v, node), true;
		case Union_Type:
			return make_symbol_union_from_ast(ast_context, v, node), true;
		case Enum_Type:
			return make_symbol_enum_from_ast(ast_context, v, node), true;
		case Proc_Lit:
			if !v.type.generic {
				return make_symbol_procedure_from_ast(ast_context, global, v.type^, node.name), true;
			} else {
				return resolve_generic_function(ast_context, v);
			}
		case Proc_Group:
			return resolve_function_overload(ast_context, v);
		case Array_Type:
			return make_symbol_generic_from_ast(ast_context, global), true;
		case Dynamic_Array_Type:
			return make_symbol_generic_from_ast(ast_context, global), true;
		case Call_Expr:
			return resolve_type_expression(ast_context, global);
		case:
			log.warnf("default type node kind: %T", v);
			return resolve_type_expression(ast_context, global);
		}
	} else if node.name == "context" {
		//if there are more of these variables that hard builtin, move them to the indexer
		return index.lookup("Context", ast_context.current_package);
	} else if v, ok := common.keyword_map[node.name]; ok {
		//keywords
		ident := index.new_type(Ident, node.pos, node.end, context.temp_allocator);
		ident.name = node.name;

		symbol := index.Symbol {
			type = .Keyword,
			signature = node.name,
			pkg = ast_context.current_package,
			value = index.SymbolGenericValue {
				expr = ident,
			},
		};
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

		//TODO(daniel, index can be used on identifiers if using is in the function scope)
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

	#partial switch v in symbol.value {
	case index.SymbolProcedureGroupValue:
		if symbol, ok := resolve_function_overload(ast_context, v.group.derived.(ast.Proc_Group)); ok {
			return symbol, true;
		} else {
			return symbol, false;
		}
	case index.SymbolProcedureValue:
		if v.generic {
			return resolve_generic_function_symbol(ast_context, v.arg_types, v.return_types);
		} else {
			return symbol, true;
		}
	case index.SymbolStructValue:

		//expand the types and names from the using - can't be done while indexing without complicating everything(this also saves memory)
		if len(v.usings) > 0 {
			expanded := symbol;
			expanded.value = expand_struct_usings(ast_context, symbol, v);
			return expanded, true;
		} else {
			return symbol, true;
		}

	case index.SymbolGenericValue:
		return resolve_type_expression(ast_context, v.expr);
	}

	return symbol, true;
}

resolve_location_identifier :: proc(ast_context: ^AstContext, node: ast.Ident) -> (index.Symbol, bool) {

	symbol: index.Symbol;

	if local := get_local(ast_context, node.pos.offset, node.name); local != nil {
		symbol.range = common.get_token_range(get_local(ast_context, node.pos.offset, node.name), ast_context.file.src);
		return symbol, true;
	} else if global, ok := ast_context.globals[node.name]; ok {
		symbol.range = common.get_token_range(global, ast_context.file.src);
		return symbol, true;
	}

	return index.lookup(node.name, ast_context.document_package);
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
	ident.name = bool_lit;
	return ident;
}

make_int_ast :: proc() -> ^ast.Ident {
	ident := index.new_type(ast.Ident, {}, {}, context.temp_allocator);
	ident.name = int_lit;
	return ident;
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
	};

	symbol.name = name;

	return_types := make([dynamic]^ast.Field, context.temp_allocator);
	arg_types    := make([dynamic]^ast.Field, context.temp_allocator);

	if v.results != nil {

		for ret in v.results.list {
			append(&return_types, ret);
		}

		symbol.returns = strings.concatenate({"(", string(ast_context.file.src[v.results.pos.offset:v.results.end.offset]), ")"}, context.temp_allocator);
	}

	if v.params != nil {

		for param in v.params.list {
			append(&arg_types, param);
		}

		symbol.signature = strings.concatenate({"(", string(ast_context.file.src[v.params.pos.offset:v.params.end.offset]), ")"}, context.temp_allocator);
	}

	symbol.value = index.SymbolProcedureValue {
		return_types = return_types[:],
		arg_types = arg_types[:],
	};

	return symbol;
}

make_symbol_generic_from_ast :: proc(ast_context: ^AstContext, expr: ^ast.Expr) -> index.Symbol {

	symbol := index.Symbol {
		range = common.get_token_range(expr, ast_context.file.src),
		type = .Variable,
		signature = index.node_to_string(expr),
		pkg = get_package_from_node(expr^),
	};

	symbol.value = index.SymbolGenericValue {
		expr = expr,
	};

	return symbol;
}

make_symbol_union_from_ast :: proc(ast_context: ^AstContext, v: ast.Union_Type, ident: ast.Ident) -> index.Symbol {

	symbol := index.Symbol {
		range = common.get_token_range(v, ast_context.file.src),
		type = .Enum,
		name = ident.name,
		pkg = get_package_from_node(v.node),
	};

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
		names = names[:],
		types = v.variants,
	};

	return symbol;
}

make_symbol_enum_from_ast :: proc(ast_context: ^AstContext, v: ast.Enum_Type, ident: ast.Ident) -> index.Symbol {

	symbol := index.Symbol {
		range = common.get_token_range(v, ast_context.file.src),
		type = .Enum,
		name = ident.name,
		pkg = get_package_from_node(v.node),
	};

	names := make([dynamic]string, context.temp_allocator);

	for n in v.fields {

		if ident, ok := n.derived.(ast.Ident); ok {
			append(&names, ident.name);
		} else if field, ok := n.derived.(ast.Field_Value); ok {
			append(&names, field.field.derived.(ast.Ident).name);
		}
	}

	symbol.value = index.SymbolEnumValue {
		names = names[:],
	};

	return symbol;
}

make_symbol_bitset_from_ast :: proc(ast_context: ^AstContext, v: ast.Bit_Set_Type, ident: ast.Ident) -> index.Symbol {

	symbol := index.Symbol {
		range = common.get_token_range(v, ast_context.file.src),
		type = .Enum,
		name = ident.name,
		pkg = get_package_from_node(v.node),
	};

	symbol.value = index.SymbolBitSetValue {
		expr = v.elem,
	};

	return symbol;
}

make_symbol_struct_from_ast :: proc(ast_context: ^AstContext, v: ast.Struct_Type, ident: ast.Ident) -> index.Symbol {

	symbol := index.Symbol {
		range = common.get_token_range(v, ast_context.file.src),
		type = .Struct,
		name = ident.name,
		pkg = get_package_from_node(v.node),
	};

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
	};

	if v.poly_params != nil {
		resolve_poly_struct(ast_context, v, &symbol);
	}

	//TODO change the expand to not double copy the array, but just pass the dynamic arrays
	if len(usings) > 0 {
		symbol.value = expand_struct_usings(ast_context, symbol, symbol.value.(index.SymbolStructValue));
	}

	return symbol;
}

resolve_poly_struct :: proc(ast_context: ^AstContext, v: ast.Struct_Type, symbol: ^index.Symbol) {

	if ast_context.call == nil {
		log.infof("no call");
		return;
	}

	symbol_value := &symbol.value.(index.SymbolStructValue);

	if symbol_value == nil {
		log.infof("no value");
		return;
	}

	i := 0;

	poly_map := make(map[string]^ast.Expr, 0, context.temp_allocator);

	for param in v.poly_params.list {

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
						call_expr.args[i] = expr;
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
		ast_context.globals[expr.name]   = expr.expr;
		ast_context.variables[expr.name] = expr.mutable;
	}
}

get_generic_assignment :: proc(file: ast.File, value: ^ast.Expr, ast_context: ^AstContext, results: ^[dynamic]^ast.Expr) {

	using ast;

	ast_context.use_locals  = true;
	ast_context.use_globals = true;

	switch v in value.derived {
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
			append(results, v.type);
			append(results, make_bool_ast());
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
		str := common.get_ast_node_string(value_decl.names[0], file.src);
		ast_context.variables[str] = value_decl.is_mutable;
		store_local(ast_context, value_decl.type, value_decl.pos.offset, str);
		return;
	}

	results := make([dynamic]^Expr, context.temp_allocator);

	for value in value_decl.values {
		get_generic_assignment(file, value, ast_context, &results);
	}

	for name, i in value_decl.names {
		if i < len(results) {
			str := common.get_ast_node_string(name, file.src);
			ast_context.in_package[str] = get_package_from_node(results[i]);
			store_local(ast_context, results[i], name.pos.offset, str);
			ast_context.variables[str] = value_decl.is_mutable;
		}
	}
}

get_locals_stmt :: proc(file: ast.File, stmt: ^ast.Stmt, ast_context: ^AstContext, document_position: ^DocumentPositionContext, save_assign := false) {

	ast_context.use_locals      = true;
	ast_context.use_globals     = true;
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
		for stmt in v.stmts {
			get_locals_stmt(file, stmt, ast_context, document_position);
		}
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
	case:
			//log.debugf("default node local stmt %v", v);
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
					selector.expr       = u;
					selector.field      = index.new_type(ast.Ident, v.types[i].pos, v.types[i].end, context.temp_allocator);
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

		if generic, ok := symbol.value.(index.SymbolGenericValue); ok {

			switch v in generic.expr.derived {
			case Map_Type:
				for val in stmt.vals {
					if ident, ok := val.derived.(Ident); ok {
						store_local(ast_context, v.key, ident.pos.offset, ident.name);
						ast_context.variables[ident.name]  = true;
						ast_context.in_package[ident.name] = symbol.pkg;
					}
				}
			case Dynamic_Array_Type:
				if len(stmt.vals) >= 1 {
					if ident, ok := stmt.vals[0].derived.(Ident); ok {
						store_local(ast_context, v.elem, ident.pos.offset, ident.name);
						ast_context.variables[ident.name]  = true;
						ast_context.in_package[ident.name] = symbol.pkg;
					}
				}

				if len(stmt.vals) >= 2 {
					if ident, ok := stmt.vals[1].derived.(Ident); ok {
						store_local(ast_context, make_int_ast(), ident.pos.offset, ident.name);
						ast_context.variables[ident.name]  = true;
						ast_context.in_package[ident.name] = symbol.pkg;
					}
				}
			case Array_Type:
				if len(stmt.vals) >= 1 {

					if ident, ok := stmt.vals[0].derived.(Ident); ok {
						store_local(ast_context, v.elem, ident.pos.offset, ident.name);
						ast_context.variables[ident.name]  = true;
						ast_context.in_package[ident.name] = symbol.pkg;
					}
				}

				if len(stmt.vals) >= 2 {

					if ident, ok := stmt.vals[1].derived.(Ident); ok {
						store_local(ast_context, make_int_ast(), ident.pos.offset, ident.name);
						ast_context.variables[ident.name]  = true;
						ast_context.in_package[ident.name] = symbol.pkg;
					}
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
					ast_context.variables[str]  = true;
					ast_context.parameters[str] = true;

					if .Using in arg.flags {
						using_stmt: ast.Using_Stmt;
						using_stmt.list    = make([]^ast.Expr, 1, context.temp_allocator);
						using_stmt.list[0] = arg.type;
						get_locals_using_stmt(using_stmt, ast_context);
					}
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
					ast_context.variables[str]  = true;
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
			return fmt.tprintf("%v.%v: proc %v -> %v", pkg, symbol.name, symbol.signature, symbol.returns);
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

get_definition_location :: proc(document: ^Document, position: common.Position) -> (common.Location, bool) {

	location: common.Location;

	ast_context := make_ast_context(document.ast, document.imports, document.package_name);

	uri: string;

	position_context, ok := get_document_position_context(document, position, .Definition);

	if !ok {
		log.warn("Failed to get position context");
		return location, false;
	}

	get_globals(document.ast, &ast_context);

	if position_context.function != nil {
		get_locals(document.ast, position_context.function, &ast_context, &position_context);
	}

	if position_context.selector != nil {

		//if the base selector is the client wants to go to.
		if base, ok := position_context.selector.derived.(ast.Ident); ok && position_context.identifier != nil {

			ident := position_context.identifier.derived.(ast.Ident);

			if ident.name == base.name {

				if resolved, ok := resolve_location_identifier(&ast_context, ident); ok {
					location.range = resolved.range;

					if resolved.uri == "" {
						location.uri = document.uri.uri;
					} else {
						location.uri = resolved.uri;
					}

					return location, true;
				} else {
					return location, false;
				}
			}
		}

		//otherwise it's the field the client wants to go to.

		selector: index.Symbol;

		ast_context.use_locals      = true;
		ast_context.use_globals     = true;
		ast_context.current_package = ast_context.document_package;

		selector, ok = resolve_type_expression(&ast_context, position_context.selector);

		if !ok {
			return location, false;
		}

		field: string;

		if position_context.field != nil {

			switch v in position_context.field.derived {
			case ast.Ident:
				field = v.name;
			}
		}

		uri = selector.uri;

		#partial switch v in selector.value {
		case index.SymbolEnumValue:
			location.range = selector.range;
		case index.SymbolStructValue:
			for name, i in v.names {
				if strings.compare(name, field) == 0 {
					location.range = common.get_token_range(v.types[i]^, document.ast.src);
				}
			}
		case index.SymbolPackageValue:
			if symbol, ok := index.lookup(field, selector.pkg); ok {
				location.range = symbol.range;
				uri            = symbol.uri;
			} else {
				return location, false;
			}
		}

		if !ok {
			return location, false;
		}
	} else if position_context.identifier != nil {

		if resolved, ok := resolve_location_identifier(&ast_context, position_context.identifier.derived.(ast.Ident)); ok {
			location.range = resolved.range;
			uri            = resolved.uri;
		} else {
			return location, false;
		}
	} else {
		return location, false;
	}

	//if the symbol is generated by the ast we don't set the uri.
	if uri == "" {
		location.uri = document.uri.uri;
	} else {
		location.uri = uri;
	}

	return location, true;
}

write_hover_content :: proc(ast_context: ^AstContext, symbol: index.Symbol) -> MarkupContent {
	content: MarkupContent;

	cat := concatenate_symbols_information(ast_context, symbol, false);

	if cat != "" {
		content.kind  = "markdown";
		content.value = fmt.tprintf("```odin\n %v\n```\n%v", cat, symbol.doc);
	} else {
		content.kind = "plaintext";
	}

	return content;
}

get_signature :: proc(ast_context: ^AstContext, ident: ast.Ident, symbol: index.Symbol, was_variable := false) -> string {

	if symbol.type == .Function {
		return symbol.signature;
	}

	if is_variable, ok := ast_context.variables[ident.name]; ok && is_variable {

		if local := get_local(ast_context, ident.pos.offset, ident.name); local != nil {

			if i, ok := local.derived.(ast.Ident); ok {
				return get_signature(ast_context, i, symbol, true);
			} else {
				return index.node_to_string(local);
			}
		}

		if global, ok := ast_context.globals[ident.name]; ok {
			if i, ok := global.derived.(ast.Ident); ok {
				return get_signature(ast_context, i, symbol, true);
			} else {
				return index.node_to_string(global);
			}
		}
	}

	if !was_variable {
		#partial switch v in symbol.value {
		case index.SymbolStructValue:
			return "struct";
		case index.SymbolUnionValue:
			return "union";
		case index.SymbolEnumValue:
			return "enum";
		}
	}

	return ident.name;
}

get_signature_information :: proc(document: ^Document, position: common.Position) -> (SignatureHelp, bool) {

	signature_help: SignatureHelp;

	ast_context := make_ast_context(document.ast, document.imports, document.package_name);

	position_context, ok := get_document_position_context(document, position, .SignatureHelp);

	if !ok {
		return signature_help, true;
	}

	if position_context.call == nil {
		return signature_help, true;
	}

	get_globals(document.ast, &ast_context);

	if position_context.function != nil {
		get_locals(document.ast, position_context.function, &ast_context, &position_context);
	}

	call: index.Symbol;
	call, ok = resolve_type_expression(&ast_context, position_context.call);

	if symbol, ok := call.value.(index.SymbolProcedureValue); !ok {
		return signature_help, true;
	}

	signature_information := make([]SignatureInformation, 1, context.temp_allocator);

	signature_information[0].label         = concatenate_symbols_information(&ast_context, call, false);
	signature_information[0].documentation = call.doc;

	signature_help.signatures      = signature_information;
	signature_help.activeSignature = 0;
	signature_help.activeParameter = 0;

	return signature_help, true;
}

get_document_symbols :: proc(document: ^Document) -> []DocumentSymbol {

	ast_context := make_ast_context(document.ast, document.imports, document.package_name);

	get_globals(document.ast, &ast_context);

	symbols := make([dynamic]DocumentSymbol, context.temp_allocator);

	package_symbol: DocumentSymbol;

	if len(document.ast.decls) == 0 {
		return {};
	}

	package_symbol.kind  = .Package;
	package_symbol.name  = path.base(document.package_name, false, context.temp_allocator);
	package_symbol.range = {
		start = {
			line = document.ast.decls[0].pos.line,
		},
		end = {
			line = document.ast.decls[len(document.ast.decls) - 1].end.line,
		},
	};
	package_symbol.selectionRange = package_symbol.range;

	children_symbols := make([dynamic]DocumentSymbol, context.temp_allocator);

	for k, expr in ast_context.globals {

		symbol: DocumentSymbol;

		symbol.range          = common.get_token_range(expr, ast_context.file.src);
		symbol.selectionRange = symbol.range;
		symbol.name           = k;

		switch v in expr.derived {
		case ast.Struct_Type:
			symbol.kind = .Struct;
		case ast.Proc_Lit,ast.Proc_Group:
			symbol.kind = .Function;
		case ast.Enum_Type,ast.Union_Type:
			symbol.kind = .Enum;
		case:
			symbol.kind = .Variable;
		}

		append(&children_symbols, symbol);
	}

	package_symbol.children = children_symbols[:];

	append(&symbols, package_symbol);

	return symbols[:];
}

/*
	Figure out what exactly is at the given position and whether it is in a function, struct, etc.
*/
get_document_position_context :: proc(document: ^Document, position: common.Position, hint: DocumentPositionContextHint) -> (DocumentPositionContext, bool) {

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

	return position_context, true;
}

//terrible fallback code
fallback_position_context_completion :: proc(document: ^Document, position: common.Position, position_context: ^DocumentPositionContext) {

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

		last_dot   = false;
		last_arrow = false;

		i -= 1;
	}

	//log.error(u8(position_context.file.src[end]));

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
		err = parser_warning_handler, //empty
		warn = parser_warning_handler, //empty
		file = &position_context.file,
	};

	tokenizer.init(&p.tok, str, position_context.file.fullpath, parser_warning_handler);

	p.tok.ch          = ' ';
	p.tok.line_count  = position.line;
	p.tok.offset      = begin_offset;
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
		position_context.field    = s.field;
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

		tokenizer.init(&p.tok, position_context.file.src[0:last_dot], position_context.file.fullpath, parser_warning_handler);

		p.tok.ch          = ' ';
		p.tok.line_count  = position.line;
		p.tok.offset      = begin_offset;
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

fallback_position_context_signature :: proc(document: ^Document, position: common.Position, position_context: ^DocumentPositionContext) {

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

	if position_context.file.src[end] != '(' {
		return;
	}

	end -= 1;

	begin_offset := max(0, start);
	end_offset   := max(start, end + 1);

	str := position_context.file.src[0:end_offset];

	p := parser.Parser {
		err = parser_warning_handler, //empty
		warn = parser_warning_handler, //empty
		file = &position_context.file,
	};

	tokenizer.init(&p.tok, str, position_context.file.fullpath, parser_warning_handler);

	p.tok.ch          = ' ';
	p.tok.line_count  = position.line;
	p.tok.offset      = begin_offset;
	p.tok.read_offset = begin_offset;

	tokenizer.advance_rune(&p.tok);

	if p.tok.ch == utf8.RUNE_BOM {
		tokenizer.advance_rune(&p.tok);
	}

	parser.advance_token(&p);

	context.allocator = context.temp_allocator;

	e := parser.parse_expr(&p, true);

	if call, ok := e.derived.(ast.Call_Expr); ok {
		position_context.call = e;
	}

	//log.error(string(position_context.file.src[begin_offset:end_offset]));
}

/*
	All these fallback functions are not perfect and should be fixed. A lot of weird use of the odin tokenizer and parser.
*/

get_document_position :: proc {
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
				position_context.selector = n.expr;
				position_context.field    = n.field;
			}
		} else if (position_context.hint == .Definition || position_context.hint == .Hover) && n.field != nil {
			position_context.selector = n.expr;
			position_context.field    = n.field;
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
