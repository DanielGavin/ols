package server

import "core:fmt"
import "core:log"
import "core:mem"
import "core:odin/ast"
import "core:odin/parser"
import "core:odin/tokenizer"
import "core:path/filepath"
import path "core:path/slashpath"
import "core:reflect"
import "core:slice"
import "core:sort"
import "core:strconv"
import "core:strings"
import "core:unicode/utf8"

import "src:common"

DocumentPositionContextHint :: enum {
	Completion,
	SignatureHelp,
	Definition,
	Hover,
}

DocumentPositionContext :: struct {
	file:                   ast.File,
	position:               common.AbsolutePosition,
	line:                   int,
	function:               ^ast.Proc_Lit, //used to help with type resolving in function scope
	functions:              [dynamic]^ast.Proc_Lit, //stores all the functions that have been iterated through to find the position
	selector:               ^ast.Expr, //used for completion
	selector_expr:          ^ast.Selector_Expr,
	identifier:             ^ast.Node,
	implicit_context:       ^ast.Implicit,
	tag:                    ^ast.Node,
	field:                  ^ast.Expr, //used for completion
	call:                   ^ast.Expr, //used for signature help
	returns:                ^ast.Return_Stmt, //used for completion
	comp_lit:               ^ast.Comp_Lit, //used for completion
	parent_comp_lit:        ^ast.Comp_Lit, //used for completion
	basic_lit:              ^ast.Basic_Lit,
	struct_type:            ^ast.Struct_Type,
	union_type:             ^ast.Union_Type,
	bitset_type:            ^ast.Bit_Set_Type,
	enum_type:              ^ast.Enum_Type,
	field_value:            ^ast.Field_Value,
	implicit:               bool, //used for completion
	arrow:                  bool,
	binary:                 ^ast.Binary_Expr, //used for completion
	parent_binary:          ^ast.Binary_Expr, //used for completion
	assign:                 ^ast.Assign_Stmt, //used for completion
	switch_stmt:            ^ast.Switch_Stmt, //used for completion
	switch_type_stmt:       ^ast.Type_Switch_Stmt, //used for completion
	case_clause:            ^ast.Case_Clause, //used for completion
	value_decl:             ^ast.Value_Decl, //used for completion
	implicit_selector_expr: ^ast.Implicit_Selector_Expr,
	abort_completion:       bool,
	hint:                   DocumentPositionContextHint,
	global_lhs_stmt:        bool,
	import_stmt:            ^ast.Import_Decl,
	call_commas:            []int,
}

DocumentLocal :: struct {
	lhs:             ^ast.Expr,
	rhs:             ^ast.Expr,
	offset:          int,
	resolved_global: bool, //Some locals have already been resolved and are now in global space
	local_global:    bool, //Some locals act like globals, i.e. functions defined inside functions.
	id:              int, //Id that can used to connect the local to something, i.e. for stmt begin offset
	pkg:             string,
	variable:        bool,
	parameter:       bool,
}

AstContext :: struct {
	locals:           map[int]map[string][dynamic]DocumentLocal, //locals all the way to the document position
	globals:          map[string]common.GlobalExpr,
	recursion_map:    map[rawptr]bool,
	usings:           [dynamic]string,
	file:             ast.File,
	allocator:        mem.Allocator,
	imports:          []Package, //imports for the current document
	current_package:  string,
	document_package: string,
	use_locals:       bool,
	local_id:         int,
	call:             ^ast.Call_Expr, //used to determine the types for generics and the correct function for overloaded functions
	value_decl:       ^ast.Value_Decl,
	field_name:       ast.Ident,
	uri:              string,
	fullpath:         string,
	non_mutable_only: bool,
}

make_ast_context :: proc(
	file: ast.File,
	imports: []Package,
	package_name: string,
	uri: string,
	fullpath: string,
	allocator := context.temp_allocator,
) -> AstContext {
	ast_context := AstContext {
		locals           = make(
			map[int]map[string][dynamic]DocumentLocal,
			0,
			allocator,
		),
		globals          = make(map[string]common.GlobalExpr, 0, allocator),
		usings           = make([dynamic]string, allocator),
		recursion_map    = make(map[rawptr]bool, 0, allocator),
		file             = file,
		imports          = imports,
		use_locals       = true,
		document_package = package_name,
		current_package  = package_name,
		uri              = uri,
		fullpath         = fullpath,
		allocator        = allocator,
	}

	add_local_group(&ast_context, 0)

	return ast_context
}

reset_ast_context :: proc(ast_context: ^AstContext) {
	ast_context.use_locals = true
	clear(&ast_context.recursion_map)
}

tokenizer_error_handler :: proc(pos: tokenizer.Pos, msg: string, args: ..any) {
}


resolve_type_comp_literal :: proc(
	ast_context: ^AstContext,
	position_context: ^DocumentPositionContext,
	current_symbol: Symbol,
	current_comp_lit: ^ast.Comp_Lit,
) -> (
	Symbol,
	^ast.Comp_Lit,
	bool,
) {
	if position_context.comp_lit == current_comp_lit {
		return current_symbol, current_comp_lit, true
	} else if current_comp_lit == nil {
		return {}, nil, false
	}


	prev_package := ast_context.current_package
	ast_context.current_package = current_symbol.pkg

	defer ast_context.current_package = prev_package

	for elem, element_index in current_comp_lit.elems {
		if !position_in_node(elem, position_context.position) {
			continue
		}

		if field_value, ok := elem.derived.(^ast.Field_Value); ok { 	//named
			if comp_lit, ok := field_value.value.derived.(^ast.Comp_Lit); ok {
				if s, ok := current_symbol.value.(SymbolStructValue); ok {
					for name, i in s.names {
						if name ==
						   field_value.field.derived.(^ast.Ident).name {
							if symbol, ok := resolve_type_expression(
								ast_context,
								s.types[i],
							); ok {
								//Stop at bitset, because we don't want to enter a comp_lit of a bitset
								if _, ok := symbol.value.(SymbolBitSetValue);
								   ok {
									return current_symbol,
										current_comp_lit,
										true
								}
								return resolve_type_comp_literal(
									ast_context,
									position_context,
									symbol,
									cast(^ast.Comp_Lit)field_value.value,
								)
							}
						}
					}
				}
			}
		} else if comp_value, ok := elem.derived.(^ast.Comp_Lit); ok { 	//indexed
			#partial switch s in current_symbol.value {
			case SymbolStructValue:
				if len(s.types) <= element_index {
					return {}, {}, false
				}

				if symbol, ok := resolve_type_expression(
					ast_context,
					s.types[element_index],
				); ok {
					//Stop at bitset, because we don't want to enter a comp_lit of a bitset
					if _, ok := symbol.value.(SymbolBitSetValue); ok {
						return current_symbol, current_comp_lit, true
					}
					return resolve_type_comp_literal(
						ast_context,
						position_context,
						symbol,
						comp_value,
					)
				}
			case SymbolSliceValue:
				if symbol, ok := resolve_type_expression(ast_context, s.expr);
				   ok {
					return resolve_type_comp_literal(
						ast_context,
						position_context,
						symbol,
						comp_value,
					)
				}

			case SymbolDynamicArrayValue:
				if symbol, ok := resolve_type_expression(ast_context, s.expr);
				   ok {
					return resolve_type_comp_literal(
						ast_context,
						position_context,
						symbol,
						comp_value,
					)
				}

			case SymbolFixedArrayValue:
				if symbol, ok := resolve_type_expression(ast_context, s.expr);
				   ok {
					return resolve_type_comp_literal(
						ast_context,
						position_context,
						symbol,
						comp_value,
					)
				}
			}
		}
	}

	return current_symbol, current_comp_lit, true
}


is_symbol_same_typed :: proc(
	ast_context: ^AstContext,
	a, b: Symbol,
	flags: ast.Field_Flags = {},
) -> bool {
	//relying on the fact that a is the call argument to avoid checking both sides for untyped.
	if untyped, ok := a.value.(SymbolUntypedValue); ok {
		if basic, ok := b.value.(SymbolBasicValue); ok {
			switch untyped.type {
			case .Integer:
				switch basic.ident.name {
				case "int", "uint", "u32", "i32", "u8", "i8", "u64", "u16", "i16":
					return true
				case:
					return false
				}
			case .Bool:
				switch basic.ident.name {
				case "bool", "b32", "b64":
					return true
				case:
					return false
				}
			case .String:
				switch basic.ident.name {
				case "string", "cstring":
					return true
				case:
					return false
				}
			case .Float:
				switch basic.ident.name {
				case "f32", "f64":
					return true
				case:
					return false
				}
			}
		}
	}

	a_id := reflect.union_variant_typeid(a.value)
	b_id := reflect.union_variant_typeid(b.value)

	if a_id != b_id {
		return false
	}

	if a.pointers != b.pointers {
		return false
	}

	if .Distinct in a.flags != .Distinct in b.flags {
		return false
	}

	if .Distinct in a.flags == .Distinct in b.flags &&
	   .Distinct in a.flags &&
	   a.name == b.name &&
	   a.pkg == b.pkg {
		return true
	}

	#partial switch b_value in b.value {
	case SymbolBasicValue:
		if .Any_Int in flags {
			//Temporary - make a function that finds the base type of basic values 
			//This code only works with non distinct ints
			switch a.name {
			case "int", "uint", "u32", "i32", "u8", "i8", "u64", "u16", "i16":
				return true
			}
		}
	}

	#partial switch a_value in a.value {
	case SymbolBasicValue:
		return a.name == b.name && a.pkg == b.pkg
	case SymbolStructValue, SymbolEnumValue, SymbolUnionValue, SymbolBitSetValue:
		return a.name == b.name && a.pkg == b.pkg
	case SymbolSliceValue:
		b_value := b.value.(SymbolSliceValue)

		a_symbol: Symbol
		b_symbol: Symbol
		ok: bool

		a_symbol, ok = resolve_type_expression(ast_context, a_value.expr)

		if !ok {
			return false
		}

		b_symbol, ok = resolve_type_expression(ast_context, b_value.expr)

		if !ok {
			return false
		}

		return is_symbol_same_typed(ast_context, a_symbol, b_symbol)
	case SymbolFixedArrayValue:
		b_value := b.value.(SymbolFixedArrayValue)

		a_symbol: Symbol
		b_symbol: Symbol
		ok: bool

		a_symbol, ok = resolve_type_expression(ast_context, a_value.expr)

		if !ok {
			return false
		}

		b_symbol, ok = resolve_type_expression(ast_context, b_value.expr)

		if !ok {
			return false
		}

		return is_symbol_same_typed(ast_context, a_symbol, b_symbol)
	case SymbolMultiPointer:
		b_value := b.value.(SymbolMultiPointer)

		a_symbol: Symbol
		b_symbol: Symbol
		ok: bool

		a_symbol, ok = resolve_type_expression(ast_context, a_value.expr)

		if !ok {
			return false
		}

		b_symbol, ok = resolve_type_expression(ast_context, b_value.expr)

		if !ok {
			return false
		}

		return is_symbol_same_typed(ast_context, a_symbol, b_symbol)
	case SymbolDynamicArrayValue:
		b_value := b.value.(SymbolDynamicArrayValue)

		a_symbol: Symbol
		b_symbol: Symbol
		ok: bool

		a_symbol, ok = resolve_type_expression(ast_context, a_value.expr)

		if !ok {
			return false
		}

		b_symbol, ok = resolve_type_expression(ast_context, b_value.expr)

		if !ok {
			return false
		}

		return is_symbol_same_typed(ast_context, a_symbol, b_symbol)
	case SymbolMapValue:
		b_value := b.value.(SymbolMapValue)

		a_key_symbol: Symbol
		b_key_symbol: Symbol
		a_value_symbol: Symbol
		b_value_symbol: Symbol
		ok: bool

		a_key_symbol, ok = resolve_type_expression(ast_context, a_value.key)

		if !ok {
			return false
		}

		b_key_symbol, ok = resolve_type_expression(ast_context, b_value.key)

		if !ok {
			return false
		}

		a_value_symbol, ok = resolve_type_expression(
			ast_context,
			a_value.value,
		)

		if !ok {
			return false
		}

		b_value_symbol, ok = resolve_type_expression(
			ast_context,
			b_value.value,
		)

		if !ok {
			return false
		}

		return(
			is_symbol_same_typed(ast_context, a_key_symbol, b_key_symbol) &&
			is_symbol_same_typed(ast_context, a_value_symbol, b_value_symbol) \
		)
	}

	return false
}

get_field_list_name_index :: proc(
	name: string,
	field_list: []^ast.Field,
) -> (
	int,
	bool,
) {
	for field, i in field_list {
		for field_name in field.names {
			if ident, ok := field_name.derived.(^ast.Ident); ok {
				if name == ident.name {
					return i, true
				}
			}
		}
	}

	return 0, false
}

/*
	Figure out which function the call expression is using out of the list from proc group
*/
resolve_function_overload :: proc(
	ast_context: ^AstContext,
	group: ast.Proc_Group,
) -> (
	Symbol,
	bool,
) {
	using ast

	call_expr := ast_context.call

	candidates := make([dynamic]Symbol, context.temp_allocator)

	for arg_expr in group.args {
		next_fn: if f, ok := internal_resolve_type_expression(
			ast_context,
			arg_expr,
		); ok {
			if call_expr == nil || len(call_expr.args) == 0 {
				append(&candidates, f)
				break next_fn
			}

			if procedure, ok := f.value.(SymbolProcedureValue); ok {
				count_required_params := 0

				for arg in procedure.arg_types {
					if arg.default_value == nil {
						count_required_params += 1
					}
				}

				if len(procedure.arg_types) < len(call_expr.args) {
					continue
				}

				for arg, i in call_expr.args {
					ast_context.use_locals = true

					call_symbol: Symbol
					arg_symbol: Symbol
					ok: bool
					i := i

					if _, ok = arg.derived.(^ast.Bad_Expr); ok {
						continue
					}

					//named parameter
					if field, is_field := arg.derived.(^ast.Field_Value);
					   is_field {
						call_symbol, ok = resolve_type_expression(
							ast_context,
							field.value,
						)
						if !ok {
							break next_fn
						}

						if ident, is_ident := field.field.derived.(^ast.Ident);
						   is_ident {
							i, ok = get_field_list_name_index(
								field.field.derived.(^ast.Ident).name,
								procedure.arg_types,
							)
						} else {
							break next_fn
						}
					} else {
						call_symbol, ok = resolve_type_expression(
							ast_context,
							arg,
						)
					}

					if !ok {
						break next_fn
					}

					if p, ok := call_symbol.value.(SymbolProcedureValue); ok {
						if len(p.return_types) != 1 {
							break next_fn
						}
						if s, ok := resolve_type_expression(
							ast_context,
							p.return_types[0].type,
						); ok {
							call_symbol = s
						}
					}

					if procedure.arg_types[i].type != nil {
						arg_symbol, ok = resolve_type_expression(
							ast_context,
							procedure.arg_types[i].type,
						)
					} else {
						arg_symbol, ok = resolve_type_expression(
							ast_context,
							procedure.arg_types[i].default_value,
						)
					}

					if !ok {
						break next_fn
					}

					if !is_symbol_same_typed(
						ast_context,
						call_symbol,
						arg_symbol,
						procedure.arg_types[i].flags,
					) {
						break next_fn
					}
				}

				append(&candidates, f)
			}
		}
	}

	if len(candidates) > 1 {
		return Symbol {
				type = candidates[0].type,
				name = candidates[0].name,
				pkg = candidates[0].pkg,
				value = SymbolAggregateValue{symbols = candidates[:]},
			},
			true
	} else if len(candidates) == 1 {
		return candidates[0], true
	}

	return Symbol{}, false
}

resolve_basic_lit :: proc(
	ast_context: ^AstContext,
	basic_lit: ast.Basic_Lit,
) -> (
	Symbol,
	bool,
) {
	symbol := Symbol {
		type = .Constant,
	}

	value: SymbolUntypedValue

	value.tok = basic_lit.tok

	if len(basic_lit.tok.text) == 0 {
		return {}, false
	}

	if v, ok := strconv.parse_int(basic_lit.tok.text); ok {
		value.type = .Integer
	} else if v, ok := strconv.parse_bool(basic_lit.tok.text); ok {
		value.type = .Bool
	} else if v, ok := strconv.parse_int(basic_lit.tok.text[0:1]); ok {
		value.type = .Float
	} else {
		value.type = .String
	}

	/*
	out commented because of an infinite loop in parse_f64
	else if v, ok := strconv.parse_f64(basic_lit.tok.text); ok {
		value.type = .Float
	} 
	*/

	symbol.pkg = ast_context.current_package
	symbol.value = value

	return symbol, true
}

resolve_basic_directive :: proc(
	ast_context: ^AstContext,
	directive: ast.Basic_Directive,
	a := #caller_location,
) -> (
	Symbol,
	bool,
) {
	switch directive.name {
	case "caller_location":
		ident := new_type(
			ast.Ident,
			directive.pos,
			directive.end,
			ast_context.allocator,
		)
		ident.name = "Source_Code_Location"
		ast_context.current_package = ast_context.document_package
		return internal_resolve_type_identifier(ast_context, ident^)
	}

	return {}, false
}

check_node_recursion :: proc(
	ast_context: ^AstContext,
	node: ^ast.Node,
) -> bool {
	raw := cast(rawptr)node

	if raw in ast_context.recursion_map {
		return true
	}

	ast_context.recursion_map[raw] = true

	return false
}

resolve_type_expression :: proc(
	ast_context: ^AstContext,
	node: ^ast.Expr,
) -> (
	Symbol,
	bool,
) {
	clear(&ast_context.recursion_map)
	return internal_resolve_type_expression(ast_context, node)
}

internal_resolve_type_expression :: proc(
	ast_context: ^AstContext,
	node: ^ast.Expr,
) -> (
	Symbol,
	bool,
) {
	if node == nil {
		return {}, false
	}

	saved_package := ast_context.current_package

	defer {
		ast_context.current_package = saved_package
	}

	if check_node_recursion(ast_context, node) {
		return {}, false
	}

	using ast

	#partial switch v in node.derived {
	case ^ast.Typeid_Type:
		ident := new_type(ast.Ident, v.pos, v.end, context.temp_allocator)
		ident.name = "typeid"
		return make_symbol_basic_type_from_ast(ast_context, ident), true
	case ^ast.Value_Decl:
		if v.type != nil {
			return internal_resolve_type_expression(ast_context, v.type)
		} else if len(v.values) > 0 {
			return internal_resolve_type_expression(ast_context, v.values[0])
		}
	case ^Union_Type:
		return make_symbol_union_from_ast(
				ast_context,
				v^,
				ast_context.field_name,
				true,
			),
			true
	case ^Enum_Type:
		return make_symbol_enum_from_ast(
				ast_context,
				v^,
				ast_context.field_name,
				true,
			),
			true
	case ^Struct_Type:
		return make_symbol_struct_from_ast(
				ast_context,
				v^,
				ast_context.field_name,
				{},
				true,
			),
			true
	case ^Bit_Set_Type:
		return make_symbol_bitset_from_ast(
				ast_context,
				v^,
				ast_context.field_name,
				true,
			),
			true
	case ^Array_Type:
		return make_symbol_array_from_ast(
				ast_context,
				v^,
				ast_context.field_name,
			),
			true
	case ^Matrix_Type:
		return make_symbol_matrix_from_ast(
				ast_context,
				v^,
				ast_context.field_name,
			),
			true
	case ^Dynamic_Array_Type:
		return make_symbol_dynamic_array_from_ast(
				ast_context,
				v^,
				ast_context.field_name,
			),
			true
	case ^Multi_Pointer_Type:
		return make_symbol_multi_pointer_from_ast(
				ast_context,
				v^,
				ast_context.field_name,
			),
			true
	case ^Map_Type:
		return make_symbol_map_from_ast(
				ast_context,
				v^,
				ast_context.field_name,
			),
			true
	case ^Proc_Type:
		return make_symbol_procedure_from_ast(
				ast_context,
				node,
				v^,
				ast_context.field_name,
				{},
				true,
			),
			true
	case ^Basic_Directive:
		return resolve_basic_directive(ast_context, v^)
	case ^Binary_Expr:
		return resolve_binary_expression(ast_context, v)
	case ^Ident:
		delete_key(&ast_context.recursion_map, v)
		return internal_resolve_type_identifier(ast_context, v^)
	case ^Basic_Lit:
		return resolve_basic_lit(ast_context, v^)
	case ^Type_Cast:
		return internal_resolve_type_expression(ast_context, v.type)
	case ^Auto_Cast:
		return internal_resolve_type_expression(ast_context, v.expr)
	case ^Comp_Lit:
		return internal_resolve_type_expression(ast_context, v.type)
	case ^Unary_Expr:
		if v.op.kind == .And {
			symbol, ok := internal_resolve_type_expression(ast_context, v.expr)
			symbol.pointers += 1
			return symbol, ok
		} else {
			return internal_resolve_type_expression(ast_context, v.expr)
		}
	case ^Deref_Expr:
		symbol, ok := internal_resolve_type_expression(ast_context, v.expr)
		symbol.pointers -= 1
		return symbol, ok
	case ^Paren_Expr:
		return internal_resolve_type_expression(ast_context, v.expr)
	case ^Slice_Expr:
		return resolve_slice_expression(ast_context, v)
	case ^Tag_Expr:
		return internal_resolve_type_expression(ast_context, v.expr)
	case ^Helper_Type:
		return internal_resolve_type_expression(ast_context, v.type)
	case ^Ellipsis:
		return internal_resolve_type_expression(ast_context, v.expr)
	case ^Implicit:
		ident := new_type(Ident, v.node.pos, v.node.end, ast_context.allocator)
		ident.name = v.tok.text
		return internal_resolve_type_identifier(ast_context, ident^)
	case ^Type_Assertion:
		if unary, ok := v.type.derived.(^ast.Unary_Expr); ok {
			if unary.op.kind == .Question {
				if symbol, ok := internal_resolve_type_expression(
					ast_context,
					v.expr,
				); ok {
					if union_value, ok := symbol.value.(SymbolUnionValue); ok {
						if len(union_value.types) != 1 {
							return {}, false
						}
						return internal_resolve_type_expression(
							ast_context,
							union_value.types[0],
						)
					}
				}
			}
		} else {
			return internal_resolve_type_expression(ast_context, v.type)
		}
	case ^Proc_Lit:
		if v.type.results != nil {
			if len(v.type.results.list) == 1 {
				return internal_resolve_type_expression(
					ast_context,
					v.type.results.list[0].type,
				)
			}
		}
	case ^Pointer_Type:
		symbol, ok := internal_resolve_type_expression(ast_context, v.elem)
		symbol.pointers += 1
		return symbol, ok
	case ^Matrix_Index_Expr:
		if symbol, ok := internal_resolve_type_expression(ast_context, v.expr);
		   ok {
			if mat, ok := symbol.value.(SymbolMatrixValue); ok {
				return internal_resolve_type_expression(ast_context, mat.expr)
			}
		}
	case ^Index_Expr:
		indexed, ok := internal_resolve_type_expression(ast_context, v.expr)

		if !ok {
			return {}, false
		}

		ast_context.current_package = indexed.pkg

		symbol: Symbol

		#partial switch v2 in indexed.value {
		case SymbolDynamicArrayValue:
			symbol, ok = internal_resolve_type_expression(ast_context, v2.expr)
		case SymbolSliceValue:
			symbol, ok = internal_resolve_type_expression(ast_context, v2.expr)
		case SymbolFixedArrayValue:
			symbol, ok = internal_resolve_type_expression(ast_context, v2.expr)
		case SymbolMapValue:
			symbol, ok = internal_resolve_type_expression(
				ast_context,
				v2.value,
			)
		case SymbolMultiPointer:
			symbol, ok = internal_resolve_type_expression(ast_context, v2.expr)
		}


		symbol.type = indexed.type

		return symbol, ok
	case ^Call_Expr:
		old_call := ast_context.call
		ast_context.call = cast(^Call_Expr)node

		defer {
			ast_context.call = old_call
		}

		if ident, ok := v.expr.derived.(^ast.Ident); ok && len(v.args) >= 1 {
			switch ident.name {
			case "type_of":
				ast_context.call = nil
				return internal_resolve_type_expression(ast_context, v.args[0])
			}
		}

		return internal_resolve_type_expression(ast_context, v.expr)
	case ^Selector_Call_Expr:
		if selector, ok := internal_resolve_type_expression(
			ast_context,
			v.expr,
		); ok {
			ast_context.use_locals = false

			if selector.pkg != "" {
				ast_context.current_package = selector.pkg
			} else {
				ast_context.current_package = ast_context.document_package
			}

			#partial switch s in selector.value {
			case SymbolProcedureValue:
				if len(s.return_types) == 1 {
					return internal_resolve_type_expression(
						ast_context,
						s.return_types[0].type,
					)
				}
			}

			return selector, true
		}
	case ^Selector_Expr:
		if selector, ok := internal_resolve_type_expression(
			ast_context,
			v.expr,
		); ok {
			ast_context.use_locals = false

			if selector.pkg != "" {
				ast_context.current_package = selector.pkg
			} else {
				ast_context.current_package = ast_context.document_package
			}

			#partial switch s in selector.value {
			case SymbolFixedArrayValue:
				components_count := 0
				for c in v.field.name {
					if c == 'x' ||
					   c == 'y' ||
					   c == 'z' ||
					   c == 'w' ||
					   c == 'r' ||
					   c == 'g' ||
					   c == 'b' ||
					   c == 'a' {
						components_count += 1
					}
				}

				if components_count == 0 {
					return {}, false
				}

				if components_count == 1 {
					if selector.pkg != "" {
						ast_context.current_package = selector.pkg
					} else {
						ast_context.current_package =
							ast_context.document_package
					}
					symbol, ok := internal_resolve_type_expression(
						ast_context,
						s.expr,
					)
					symbol.type = .Variable
					return symbol, ok
				} else {
					value := SymbolFixedArrayValue {
						expr = s.expr,
						len  = make_int_basic_value(
							ast_context,
							components_count,
							s.len.pos,
							s.len.end,
						),
					}
					selector.value = value
					selector.type = .Variable
					return selector, true
				}
			case SymbolProcedureValue:
				if len(s.return_types) == 1 {
					selector_expr := new_type(
						ast.Selector_Expr,
						s.return_types[0].node.pos,
						s.return_types[0].node.end,
						ast_context.allocator,
					)
					selector_expr.expr = s.return_types[0].type
					selector_expr.field = v.field

					return internal_resolve_type_expression(
						ast_context,
						selector_expr,
					)
				}
			case SymbolStructValue:
				for name, i in s.names {
					if v.field != nil && name == v.field.name {
						ast_context.field_name = v.field^
						symbol, ok := internal_resolve_type_expression(
							ast_context,
							s.types[i],
						)
						symbol.type = .Variable
						return symbol, ok
					}
				}
			case SymbolPackageValue:
				try_build_package(ast_context.current_package)

				if v.field != nil {
					return resolve_symbol_return(
						ast_context,
						lookup(v.field.name, selector.pkg),
					)
				} else {
					return Symbol{}, false
				}
			}
		}
	case:
		log.warnf("default node kind, internal_resolve_type_expression: %v", v)
	}

	return Symbol{}, false
}

store_local :: proc(
	ast_context: ^AstContext,
	lhs: ^ast.Expr,
	rhs: ^ast.Expr,
	offset: int,
	name: string,
	id: int,
	local_global: bool,
	resolved_global: bool,
	variable: bool,
	pkg: string,
	parameter: bool,
) {
	local_stack := &ast_context.locals[id][name]

	if local_stack == nil {
		locals := &ast_context.locals[id]
		locals[name] = make([dynamic]DocumentLocal, ast_context.allocator)
		local_stack = &locals[name]
	}

	append(
		local_stack,
		DocumentLocal {
			lhs = lhs,
			rhs = rhs,
			offset = offset,
			id = id,
			resolved_global = resolved_global,
			local_global = local_global,
			pkg = pkg,
			variable = variable,
			parameter = parameter,
		},
	)
}

add_local_group :: proc(ast_context: ^AstContext, id: int) {
	ast_context.locals[id] = make(
		map[string][dynamic]DocumentLocal,
		100,
		ast_context.allocator,
	)
}

clear_local_group :: proc(ast_context: ^AstContext, id: int) {
	ast_context.locals[id] = {}
}

get_local :: proc(
	ast_context: ^AstContext,
	offset: int,
	name: string,
) -> (
	DocumentLocal,
	bool,
) {
	for _, locals in &ast_context.locals {
		if local_stack, ok := locals[name]; ok {
			for i := len(local_stack) - 1; i >= 0; i -= 1 {
				if local_stack[i].offset <= offset ||
				   local_stack[i].local_global {
					if i < 0 {
						return {}, false
					} else {
						ret := local_stack[i].rhs
						if ident, ok := ret.derived.(^ast.Ident);
						   ok && ident.name == name {
							if i - 1 < 0 {
								return {}, false
							}
						}
						return local_stack[i], true
					}
				}
			}
		}
	}

	return {}, false
}

get_local_offset :: proc(
	ast_context: ^AstContext,
	offset: int,
	name: string,
) -> int {
	for _, locals in &ast_context.locals {
		if local_stack, ok := locals[name]; ok {
			for i := len(local_stack) - 1; i >= 0; i -= 1 {
				if local_stack[i].offset <= offset ||
				   local_stack[i].local_global {
					if i < 0 {
						return -1
					} else {
						return local_stack[i].offset
					}
				}
			}
		}
	}

	return -1
}

resolve_type_identifier :: proc(
	ast_context: ^AstContext,
	node: ast.Ident,
) -> (
	Symbol,
	bool,
) {
	return internal_resolve_type_identifier(ast_context, node)
}

internal_resolve_type_identifier :: proc(
	ast_context: ^AstContext,
	node: ast.Ident,
) -> (
	_symbol: Symbol,
	_ok: bool,
) {
	using ast

	if check_node_recursion(ast_context, node.derived.(^ast.Ident)) {
		return {}, false
	}

	saved_package := ast_context.current_package

	defer {
		ast_context.current_package = saved_package
	}

	if v, ok := common.keyword_map[node.name]; ok {
		//keywords
		ident := new_type(Ident, node.pos, node.end, ast_context.allocator)
		ident.name = node.name

		symbol: Symbol

		switch ident.name {
		case "true", "false":
			symbol = Symbol {
				type = .Keyword,
				signature = node.name,
				pkg = ast_context.current_package,
				value = SymbolUntypedValue{type = .Bool},
			}
		case:
			symbol = Symbol {
				type = .Keyword,
				signature = node.name,
				name = ident.name,
				pkg = ast_context.current_package,
				value = SymbolBasicValue{ident = ident},
			}
		}

		return symbol, true
	}

	if local, ok := get_local(ast_context, node.pos.offset, node.name);
	   ok && ast_context.use_locals {
		is_distinct := false

		if local.parameter {
			for imp in ast_context.imports {
				if strings.compare(imp.base, node.name) == 0 {
					symbol := Symbol {
						type  = .Package,
						pkg   = imp.name,
						value = SymbolPackageValue{},
					}

					return symbol, true
				}
			}
		}

		if local.pkg != "" {
			ast_context.current_package = local.pkg
		}

		//Sometimes the locals are semi resolved and can no longer use the locals
		if local.resolved_global {
			ast_context.use_locals = false
		}

		if dist, ok := local.rhs.derived.(^ast.Distinct_Type); ok {
			if dist.type != nil {
				local.rhs = dist.type
				is_distinct = true
			}
		}

		return_symbol: Symbol
		ok: bool

		#partial switch v in local.rhs.derived {
		case ^Ident:
			return_symbol, ok = internal_resolve_type_identifier(
				ast_context,
				v^,
			)
		case ^Union_Type:
			return_symbol, ok =
				make_symbol_union_from_ast(ast_context, v^, node), true
			return_symbol.name = node.name
		case ^Enum_Type:
			return_symbol, ok =
				make_symbol_enum_from_ast(ast_context, v^, node), true
			return_symbol.name = node.name
		case ^Struct_Type:
			return_symbol, ok =
				make_symbol_struct_from_ast(ast_context, v^, node, {}), true
			return_symbol.name = node.name
		case ^Bit_Set_Type:
			return_symbol, ok =
				make_symbol_bitset_from_ast(ast_context, v^, node), true
			return_symbol.name = node.name
		case ^Proc_Lit:
			if !is_procedure_generic(v.type) {
				return_symbol, ok =
					make_symbol_procedure_from_ast(
						ast_context,
						local.rhs,
						v.type^,
						node,
						{},
						false,
					),
					true
			} else {
				if return_symbol, ok = resolve_generic_function(
					ast_context,
					v^,
				); !ok {
					return_symbol, ok =
						make_symbol_procedure_from_ast(
							ast_context,
							local.rhs,
							v.type^,
							node,
							{},
							false,
						),
						true
				}
			}
		case ^Proc_Group:
			return_symbol, ok = resolve_function_overload(ast_context, v^)
		case ^Array_Type:
			return_symbol, ok =
				make_symbol_array_from_ast(ast_context, v^, node), true
		case ^Dynamic_Array_Type:
			return_symbol, ok =
				make_symbol_dynamic_array_from_ast(ast_context, v^, node), true
		case ^Matrix_Type:
			return_symbol, ok =
				make_symbol_matrix_from_ast(ast_context, v^, node), true
		case ^Map_Type:
			return_symbol, ok =
				make_symbol_map_from_ast(ast_context, v^, node), true
		case ^Basic_Lit:
			return_symbol, ok = resolve_basic_lit(ast_context, v^)
			return_symbol.name = node.name
			return_symbol.type = local.variable ? .Variable : .Constant
		case:
			return_symbol, ok = internal_resolve_type_expression(
				ast_context,
				local.rhs,
			)
		}

		if is_distinct {
			return_symbol.name = node.name
			return_symbol.flags |= {.Distinct}
		}

		if local.variable {
			return_symbol.type = .Variable
		}

		return_symbol.flags |= {.Local}

		return return_symbol, ok

	} else if global, ok := ast_context.globals[node.name];
	   ast_context.current_package == ast_context.document_package && ok {
		is_distinct := false
		ast_context.use_locals = false

		if dist, ok := global.expr.derived.(^ast.Distinct_Type); ok {
			if dist.type != nil {
				global.expr = dist.type
				is_distinct = true
			}
		}

		return_symbol: Symbol
		ok: bool

		#partial switch v in global.expr.derived {
		case ^Ident:
			return_symbol, ok = internal_resolve_type_identifier(
				ast_context,
				v^,
			)
		case ^ast.Call_Expr:
			old_call := ast_context.call
			ast_context.call = cast(^Call_Expr)global.expr

			defer {
				ast_context.call = old_call
			}

			call_symbol := internal_resolve_type_expression(
				ast_context,
				v.expr,
			) or_return

			proc_value := call_symbol.value.(SymbolProcedureValue) or_return

			if len(proc_value.return_types) >= 1 &&
			   proc_value.return_types[0].type != nil {
				return_symbol, ok = internal_resolve_type_expression(
					ast_context,
					proc_value.return_types[0].type,
				)
			}
		case ^Struct_Type:
			return_symbol, ok =
				make_symbol_struct_from_ast(
					ast_context,
					v^,
					node,
					global.attributes,
				),
				true
			return_symbol.name = node.name
		case ^Bit_Set_Type:
			return_symbol, ok =
				make_symbol_bitset_from_ast(ast_context, v^, node), true
			return_symbol.name = node.name
		case ^Union_Type:
			return_symbol, ok =
				make_symbol_union_from_ast(ast_context, v^, node), true
			return_symbol.name = node.name
		case ^Enum_Type:
			return_symbol, ok =
				make_symbol_enum_from_ast(ast_context, v^, node), true
			return_symbol.name = node.name
		case ^Proc_Lit:
			if !is_procedure_generic(v.type) {
				return_symbol, ok =
					make_symbol_procedure_from_ast(
						ast_context,
						global.expr,
						v.type^,
						node,
						global.attributes,
						false,
					),
					true
			} else {
				if return_symbol, ok = resolve_generic_function(
					ast_context,
					v^,
				); !ok {
					return_symbol, ok =
						make_symbol_procedure_from_ast(
							ast_context,
							global.expr,
							v.type^,
							node,
							global.attributes,
							false,
						),
						true
				}
			}
		case ^Proc_Group:
			return_symbol, ok = resolve_function_overload(ast_context, v^)
		case ^Array_Type:
			return_symbol, ok =
				make_symbol_array_from_ast(ast_context, v^, node), true
		case ^Dynamic_Array_Type:
			return_symbol, ok =
				make_symbol_dynamic_array_from_ast(ast_context, v^, node), true
		case ^Matrix_Type:
			return_symbol, ok =
				make_symbol_matrix_from_ast(ast_context, v^, node), true
		case ^Map_Type:
			return_symbol, ok =
				make_symbol_map_from_ast(ast_context, v^, node), true
		case ^Basic_Lit:
			return_symbol, ok = resolve_basic_lit(ast_context, v^)
			return_symbol.name = node.name
			return_symbol.type = global.mutable ? .Variable : .Constant
		case:
			return_symbol, ok = internal_resolve_type_expression(
				ast_context,
				global.expr,
			)
		}

		if is_distinct {
			return_symbol.name = node.name
			return_symbol.flags |= {.Distinct}
		}

		if global.mutable {
			return_symbol.type = .Variable
		}

		return_symbol.doc = common.get_doc(global.docs, ast_context.allocator)

		return return_symbol, ok
	} else {
		switch node.name {
		case "context":
			for built in indexer.builtin_packages {
				if symbol, ok := lookup("Context", built); ok {
					symbol.type = .Variable
					return symbol, ok
				}
			}
		}


		//right now we replace the package ident with the absolute directory name, so it should have '/' which is not a valid ident character
		if strings.contains(node.name, "/") {
			symbol := Symbol {
				type  = .Package,
				pkg   = node.name,
				value = SymbolPackageValue{},
			}

			try_build_package(symbol.pkg)

			return symbol, true
		}

		is_runtime := strings.contains(
			ast_context.current_package,
			"base/runtime",
		)

		if is_runtime {
			if symbol, ok := lookup(node.name, "$builtin"); ok {
				return resolve_symbol_return(ast_context, symbol)
			}
		}

		//last option is to check the index
		if symbol, ok := lookup(node.name, ast_context.current_package); ok {
			return resolve_symbol_return(ast_context, symbol)
		}

		if !is_runtime {
			if symbol, ok := lookup(node.name, "$builtin"); ok {
				return resolve_symbol_return(ast_context, symbol)
			}
		}

		for imp in ast_context.imports {
			if strings.compare(imp.base, node.name) == 0 {
				symbol := Symbol {
					type  = .Package,
					pkg   = imp.name,
					value = SymbolPackageValue{},
				}

				try_build_package(symbol.pkg)

				return symbol, true
			}
		}

		for built in indexer.builtin_packages {
			if symbol, ok := lookup(node.name, built); ok {
				return resolve_symbol_return(ast_context, symbol)
			}
		}

		for u in ast_context.usings {
			//TODO(Daniel, make into a map, not really required for performance but looks nicer)
			for imp in ast_context.imports {
				if strings.compare(imp.base, u) == 0 {
					if symbol, ok := lookup(node.name, imp.name); ok {
						return resolve_symbol_return(ast_context, symbol)
					}
				}
			}
		}
	}

	return Symbol{}, false
}

expand_struct_usings :: proc(
	ast_context: ^AstContext,
	symbol: Symbol,
	value: SymbolStructValue,
) -> SymbolStructValue {
	names := slice.to_dynamic(value.names, ast_context.allocator)
	types := slice.to_dynamic(value.types, ast_context.allocator)
	ranges := slice.to_dynamic(value.ranges, ast_context.allocator)

	for k, v in value.usings {
		ast_context.current_package = symbol.pkg

		field_expr: ^ast.Expr

		field_expr = value.types[k]

		if field_expr == nil {
			continue
		}

		if s, ok := resolve_type_expression(ast_context, field_expr); ok {
			if struct_value, ok := s.value.(SymbolStructValue); ok {
				for name in struct_value.names {
					append(&names, name)
				}

				for type in struct_value.types {
					append(&types, type)
				}

				for range in struct_value.ranges {
					append(&ranges, range)
				}
			}
		}
	}

	if .ObjC in symbol.flags {
		pkg := indexer.index.collection.packages[symbol.pkg]

		if obj_struct, ok := pkg.objc_structs[symbol.name]; ok {
			for function, i in obj_struct.functions {
				base := new_type(ast.Ident, {}, {}, context.temp_allocator)
				base.name = obj_struct.pkg

				field := new_type(ast.Ident, {}, {}, context.temp_allocator)
				field.name = function.physical_name

				selector := new_type(
					ast.Selector_Expr,
					{},
					{},
					context.temp_allocator,
				)

				selector.field = field
				selector.expr = base

				append(&names, function.logical_name)
				append(&types, selector)
				append(&ranges, obj_struct.ranges[i])
			}

		}
	}

	return {names = names[:], types = types[:], ranges = ranges[:]}
}

resolve_slice_expression :: proc(
	ast_context: ^AstContext,
	slice_expr: ^ast.Slice_Expr,
) -> (
	symbol: Symbol,
	ok: bool,
) {
	symbol = resolve_type_expression(ast_context, slice_expr.expr) or_return

	expr: ^ast.Expr

	#partial switch v in symbol.value {
	case SymbolSliceValue:
		expr = v.expr
	case SymbolFixedArrayValue:
		expr = v.expr
	case SymbolDynamicArrayValue:
		expr = v.expr
	case:
		return {}, false
	}

	symbol.value = SymbolSliceValue {
		expr = expr,
	}

	return symbol, true
}

resolve_comp_literal :: proc(
	ast_context: ^AstContext,
	position_context: ^DocumentPositionContext,
) -> (
	symbol: Symbol,
	ok: bool,
) {
	if position_context.parent_comp_lit.type != nil {
		symbol = resolve_type_expression(
			ast_context,
			position_context.parent_comp_lit.type,
		) or_return
	} else if position_context.call != nil {
		if call_expr, ok := position_context.call.derived.(^ast.Call_Expr);
		   ok {
			arg_index := find_position_in_call_param(
				position_context,
				call_expr^,
			) or_return

			symbol = resolve_type_expression(
				ast_context,
				position_context.call,
			) or_return

			value := symbol.value.(SymbolProcedureValue) or_return

			if len(value.arg_types) <= arg_index {
				return {}, false
			}

			if value.arg_types[arg_index].type == nil {
				return {}, false
			}

			symbol = resolve_type_expression(
				ast_context,
				value.arg_types[arg_index].type,
			) or_return
		}
	}

	old_package := ast_context.current_package
	ast_context.current_package = symbol.pkg

	symbol, _ = resolve_type_comp_literal(
		ast_context,
		position_context,
		symbol,
		position_context.parent_comp_lit,
	) or_return

	ast_context.current_package = old_package

	return symbol, true
}

resolve_implicit_selector :: proc(
	ast_context: ^AstContext,
	position_context: ^DocumentPositionContext,
	selector_expr: ^ast.Implicit_Selector_Expr,
) -> (
	Symbol,
	bool,
) {

	if position_context.call != nil {
		if call, ok := position_context.call.derived.(^ast.Call_Expr); ok {
			parameter_index, parameter_ok := find_position_in_call_param(
				position_context,
				call^,
			)
			if symbol, ok := resolve_type_expression(ast_context, call.expr);
			   ok && parameter_ok {
				if proc_value, ok := symbol.value.(SymbolProcedureValue); ok {
					if len(proc_value.arg_types) <= parameter_index {
						return {}, false
					}

					return resolve_type_expression(
						ast_context,
						proc_value.arg_types[parameter_index].type,
					)
				} else if enum_value, ok := symbol.value.(SymbolEnumValue);
				   ok {
					return symbol, true
				}
			}
		}
	}

	if position_context.switch_stmt != nil {
		return resolve_type_expression(
			ast_context,
			position_context.switch_stmt.cond,
		)
	}

	if position_context.assign != nil &&
	   len(position_context.assign.lhs) == len(position_context.assign.rhs) {

		for _, i in position_context.assign.lhs {
			if position_in_node(
				   position_context.assign.rhs[i],
				   position_context.position,
			   ) {
				return resolve_type_expression(
					ast_context,
					position_context.assign.lhs[i],
				)
			}
		}
	}

	if position_context.binary != nil {
		if position_in_node(
			   position_context.binary.left,
			   position_context.position,
		   ) {
			return resolve_type_expression(
				ast_context,
				position_context.binary.right,
			)
		} else {
			return resolve_type_expression(
				ast_context,
				position_context.binary.left,
			)
		}
	}

	if position_context.returns != nil && position_context.function != nil {
		return_index: int

		if position_context.returns.results == nil {
			return {}, false
		}

		for result, i in position_context.returns.results {
			if position_in_node(result, position_context.position) {
				return_index = i
				break
			}
		}

		if position_context.function.type == nil {
			return {}, false
		}

		if position_context.function.type.results == nil {
			return {}, false
		}

		if len(position_context.function.type.results.list) > return_index {
			return resolve_type_expression(
				ast_context,
				position_context.function.type.results.list[return_index].type,
			)
		}
	}

	if position_context.value_decl != nil &&
	   position_context.value_decl.type != nil {
		return resolve_type_expression(
			ast_context,
			position_context.value_decl.type,
		)
	}

	if position_context.comp_lit != nil {
		if position_context.parent_comp_lit.type == nil {
			return {}, false
		}

		field_name: string

		if position_context.field_value != nil {
			if field, ok := position_context.field_value.field.derived.(^ast.Ident);
			   ok {
				field_name = field.name
			} else {
				return {}, false
			}
		}


		if symbol, ok := resolve_type_expression(
			ast_context,
			position_context.parent_comp_lit.type,
		); ok {
			if comp_symbol, comp_lit, ok := resolve_type_comp_literal(
				ast_context,
				position_context,
				symbol,
				position_context.parent_comp_lit,
			); ok {
				if s, ok := comp_symbol.value.(SymbolStructValue); ok {
					ast_context.current_package = comp_symbol.pkg

					//We can either have the final 
					elem_index := -1

					for elem, i in comp_lit.elems {
						if position_in_node(elem, position_context.position) {
							elem_index = i
						}
					}

					type: ^ast.Expr

					for name, i in s.names {
						if name != field_name {
							continue
						}

						type = s.types[i]
						break
					}

					if type == nil && len(s.types) > elem_index {
						type = s.types[elem_index]
					}

					return resolve_type_expression(ast_context, type)
				}
			}
		}
	}


	return {}, false
}

resolve_symbol_return :: proc(
	ast_context: ^AstContext,
	symbol: Symbol,
	ok := true,
) -> (
	Symbol,
	bool,
) {
	if !ok {
		return symbol, ok
	}

	symbol := symbol

	if symbol.type == .Unresolved {
		if !resolve_unresolved_symbol(ast_context, &symbol) {
			return {}, false
		}
	}

	#partial switch v in &symbol.value {
	case SymbolProcedureGroupValue:
		if symbol, ok := resolve_function_overload(
			ast_context,
			v.group.derived.(^ast.Proc_Group)^,
		); ok {
			return symbol, true
		} else {
			return symbol, false
		}
	case SymbolProcedureValue:
		if v.generic {
			if resolved_symbol, ok := resolve_generic_function(
				ast_context,
				v.arg_types,
				v.return_types,
			); ok {
				return resolved_symbol, ok
			} else {
				return symbol, true
			}
		} else {
			return symbol, true
		}
	case SymbolUnionValue:
		if v.poly != nil {
			types := make([dynamic]^ast.Expr, ast_context.allocator)

			for type in v.types {
				append(&types, clone_expr(type, context.temp_allocator, nil))
			}

			v.types = types[:]

			resolve_poly_union(ast_context, v.poly, &symbol)
		}
		return symbol, ok
	case SymbolStructValue:
		if v.poly != nil {
			types := make([dynamic]^ast.Expr, ast_context.allocator)

			for type in v.types {
				append(&types, clone_expr(type, context.temp_allocator, nil))
			}

			v.types = types[:]

			resolve_poly_struct(ast_context, v.poly, &symbol)
		}

		//expand the types and names from the using - can't be done while indexing without complicating everything(this also saves memory)
		if len(v.usings) > 0 || .ObjC in symbol.flags {
			expanded := symbol
			expanded.value = expand_struct_usings(ast_context, symbol, v)
			return expanded, true
		} else {
			return symbol, true
		}
	case SymbolGenericValue:
		ret, ok := resolve_type_expression(ast_context, v.expr)
		if symbol.type == .Variable {
			ret.type = symbol.type
		}
		return ret, ok
	}

	return symbol, true
}

resolve_unresolved_symbol :: proc(
	ast_context: ^AstContext,
	symbol: ^Symbol,
) -> bool {
	if symbol.type != .Unresolved {
		return true
	}

	#partial switch v in symbol.value {
	case SymbolStructValue:
		symbol.type = .Struct
	case SymbolPackageValue:
		symbol.type = .Package
	case SymbolProcedureValue, SymbolProcedureGroupValue:
		symbol.type = .Function
	case SymbolUnionValue:
		symbol.type = .Enum
	case SymbolEnumValue:
		symbol.type = .Enum
	case SymbolBitSetValue:
		symbol.type = .Enum
	case SymbolGenericValue:
		ast_context.current_package = symbol.pkg
		if ret, ok := resolve_type_expression(ast_context, v.expr); ok {
			symbol.type = ret.type
			symbol.signature = ret.signature
			symbol.value = ret.value
			symbol.pkg = ret.pkg
		} else {
			return false
		}
	}

	return true
}

resolve_location_identifier :: proc(
	ast_context: ^AstContext,
	node: ast.Ident,
) -> (
	Symbol,
	bool,
) {
	symbol: Symbol

	if local, ok := get_local(ast_context, node.pos.offset, node.name); ok {
		symbol.range = common.get_token_range(local.lhs, ast_context.file.src)
		uri := common.create_uri(local.lhs.pos.file, ast_context.allocator)
		symbol.pkg = ast_context.document_package
		symbol.uri = uri.uri
		return symbol, true
	} else if global, ok := ast_context.globals[node.name]; ok {
		symbol.range = common.get_token_range(
			global.name_expr,
			ast_context.file.src,
		)
		uri := common.create_uri(global.expr.pos.file, ast_context.allocator)
		symbol.pkg = ast_context.document_package
		symbol.uri = uri.uri
		return symbol, true
	}

	if symbol, ok := lookup(node.name, ast_context.document_package); ok {
		return symbol, ok
	}

	usings := get_using_packages(ast_context)

	for pkg in usings {
		if symbol, ok := lookup(node.name, pkg); ok {
			return symbol, ok
		}
	}

	return {}, false
}
resolve_location_comp_lit_field :: proc(
	ast_context: ^AstContext,
	position_context: ^DocumentPositionContext,
) -> (
	symbol: Symbol,
	ok: bool,
) {
	reset_ast_context(ast_context)

	ast_context.current_package = ast_context.document_package

	symbol = resolve_comp_literal(ast_context, position_context) or_return

	field := position_context.field_value.field.derived.(^ast.Ident) or_return

	if struct_value, ok := symbol.value.(SymbolStructValue); ok {
		for name, i in struct_value.names {
			if name == field.name {
				symbol.range = struct_value.ranges[i]
			}

		}
	}

	return symbol, true
}

resolve_location_implicit_selector :: proc(
	ast_context: ^AstContext,
	position_context: ^DocumentPositionContext,
	implicit_selector: ^ast.Implicit_Selector_Expr,
) -> (
	symbol: Symbol,
	ok: bool,
) {
	reset_ast_context(ast_context)

	ast_context.current_package = ast_context.document_package

	symbol = resolve_implicit_selector(
		ast_context,
		position_context,
		implicit_selector,
	) or_return

	#partial switch v in symbol.value {
	case SymbolEnumValue:
		for name, i in v.names {
			if strings.compare(name, implicit_selector.field.name) == 0 {
				symbol.range = v.ranges[i]
			}
		}
	}

	return symbol, ok
}

resolve_location_selector :: proc(
	ast_context: ^AstContext,
	selector: ^ast.Selector_Expr,
) -> (
	symbol: Symbol,
	ok: bool,
) {
	reset_ast_context(ast_context)
	ast_context.current_package = ast_context.document_package

	symbol = resolve_type_expression(ast_context, selector.expr) or_return

	field: string

	if selector.field != nil {
		#partial switch v in selector.field.derived {
		case ^ast.Ident:
			field = v.name
		}
	}

	#partial switch v in symbol.value {
	case SymbolStructValue:
		for name, i in v.names {
			if strings.compare(name, field) == 0 {
				symbol.range = v.ranges[i]
			}
		}
	case SymbolPackageValue:
		if pkg, ok := lookup(field, symbol.pkg); ok {
			symbol.range = pkg.range
			symbol.uri = pkg.uri
		} else {
			return {}, false
		}
	}

	return symbol, true
}


resolve_first_symbol_from_binary_expression :: proc(
	ast_context: ^AstContext,
	binary: ^ast.Binary_Expr,
) -> (
	Symbol,
	bool,
) {
	if binary.left != nil {
		if ident, ok := binary.left.derived.(^ast.Ident); ok {
			if s, ok := resolve_type_identifier(ast_context, ident^); ok {
				return s, ok
			}
		} else if _, ok := binary.left.derived.(^ast.Binary_Expr); ok {
			if s, ok := resolve_first_symbol_from_binary_expression(
				ast_context,
				cast(^ast.Binary_Expr)binary.left,
			); ok {
				return s, ok
			}
		}
	}

	if binary.right != nil {
		if ident, ok := binary.right.derived.(^ast.Ident); ok {
			if s, ok := resolve_type_identifier(ast_context, ident^); ok {
				return s, ok
			}
		} else if _, ok := binary.right.derived.(^ast.Binary_Expr); ok {
			if s, ok := resolve_first_symbol_from_binary_expression(
				ast_context,
				cast(^ast.Binary_Expr)binary.right,
			); ok {
				return s, ok
			}
		}
	}

	return {}, false
}

resolve_binary_expression :: proc(
	ast_context: ^AstContext,
	binary: ^ast.Binary_Expr,
) -> (
	Symbol,
	bool,
) {
	if binary.left == nil || binary.right == nil {
		return {}, false
	}

	symbol_a, symbol_b: Symbol
	ok_a, ok_b: bool

	if expr, ok := binary.left.derived.(^ast.Binary_Expr); ok {
		symbol_a, ok_a = resolve_binary_expression(ast_context, expr)
	} else {
		ast_context.use_locals = true
		symbol_a, ok_a = resolve_type_expression(ast_context, binary.left)
	}

	if expr, ok := binary.right.derived.(^ast.Binary_Expr); ok {
		symbol_b, ok_b = resolve_binary_expression(ast_context, expr)
	} else {
		ast_context.use_locals = true
		symbol_b, ok_b = resolve_type_expression(ast_context, binary.right)
	}

	if !ok_a || !ok_b {
		return {}, false
	}

	if symbol, ok := symbol_a.value.(SymbolProcedureValue);
	   ok && len(symbol.return_types) > 0 {
		symbol_a, ok_a = resolve_type_expression(
			ast_context,
			symbol.return_types[0].type != nil \
			? symbol.return_types[0].type \
			: symbol.return_types[0].default_value,
		)
	}

	if symbol, ok := symbol_b.value.(SymbolProcedureValue);
	   ok && len(symbol.return_types) > 0 {
		symbol_b, ok_b = resolve_type_expression(
			ast_context,
			symbol.return_types[0].type != nil \
			? symbol.return_types[0].type \
			: symbol.return_types[0].default_value,
		)
	}

	if !ok_a || !ok_b {
		return {}, false
	}


	matrix_value_a, is_matrix_a := symbol_a.value.(SymbolMatrixValue)
	matrix_value_b, is_matrix_b := symbol_b.value.(SymbolMatrixValue)

	vector_value_a, is_vector_a := symbol_a.value.(SymbolFixedArrayValue)
	vector_value_b, is_vector_b := symbol_b.value.(SymbolFixedArrayValue)

	//Handle matrix multication specially because it can actual change the return type dimension
	if is_matrix_a && is_matrix_b && binary.op.kind == .Mul {
		symbol_a.value = SymbolMatrixValue {
			expr = matrix_value_a.expr,
			x    = matrix_value_a.x,
			y    = matrix_value_b.y,
		}
		return symbol_a, true
	} else if is_matrix_a && is_vector_b && binary.op.kind == .Mul {
		symbol_a.value = SymbolFixedArrayValue {
			expr = matrix_value_a.expr,
			len  = matrix_value_a.y,
		}
		return symbol_a, true

	} else if is_vector_a && is_matrix_b && binary.op.kind == .Mul {
		symbol_a.value = SymbolFixedArrayValue {
			expr = matrix_value_b.expr,
			len  = matrix_value_b.x,
		}
		return symbol_a, true
	} else if is_vector_a &&
	   !is_matrix_b &&
	   !is_vector_b &&
	   binary.op.kind == .Mul {
		return symbol_a, true
	} else if is_vector_b &&
	   !is_matrix_a &&
	   !is_vector_a &&
	   binary.op.kind == .Mul {
		return symbol_b, true
	} else if is_matrix_a &&
	   !is_matrix_b &&
	   !is_vector_b &&
	   binary.op.kind == .Mul {
		return symbol_a, true
	} else if is_matrix_b &&
	   !is_matrix_a &&
	   !is_vector_a &&
	   binary.op.kind == .Mul {
		return symbol_b, true
	}


	//Otherwise just choose the first type, we do not handle error cases - that is done with the checker
	return symbol_a, ok_a
}

find_position_in_call_param :: proc(
	position_context: ^DocumentPositionContext,
	call: ast.Call_Expr,
) -> (
	int,
	bool,
) {
	if call.args == nil {
		return 0, false
	}

	for arg, i in call.args {
		if position_in_node(arg, position_context.position) {
			return i, true
		}
	}

	return len(call.args) - 1, true
}

make_pointer_ast :: proc(
	ast_context: ^AstContext,
	elem: ^ast.Expr,
) -> ^ast.Pointer_Type {
	pointer := new_type(
		ast.Pointer_Type,
		elem.pos,
		elem.end,
		ast_context.allocator,
	)
	pointer.elem = elem
	return pointer
}

make_bool_ast :: proc(
	ast_context: ^AstContext,
	pos: tokenizer.Pos,
	end: tokenizer.Pos,
) -> ^ast.Ident {
	ident := new_type(ast.Ident, pos, end, ast_context.allocator)
	ident.name = "bool"
	return ident
}

make_int_ast :: proc(
	ast_context: ^AstContext,
	pos: tokenizer.Pos,
	end: tokenizer.Pos,
) -> ^ast.Ident {
	ident := new_type(ast.Ident, pos, end, ast_context.allocator)
	ident.name = "int"
	return ident
}

make_ident_ast :: proc(
	ast_context: ^AstContext,
	pos: tokenizer.Pos,
	end: tokenizer.Pos,
	name: string,
) -> ^ast.Ident {
	ident := new_type(ast.Ident, pos, end, ast_context.allocator)
	ident.name = name
	return ident
}

make_int_basic_value :: proc(
	ast_context: ^AstContext,
	n: int,
	pos: tokenizer.Pos,
	end: tokenizer.Pos,
) -> ^ast.Basic_Lit {
	basic := new_type(ast.Basic_Lit, pos, end, ast_context.allocator)
	basic.tok.text = fmt.tprintf("%v", n)
	return basic
}

get_package_from_node :: proc(node: ast.Node) -> string {
	slashed, _ := filepath.to_slash(node.pos.file, context.temp_allocator)
	ret := path.dir(slashed, context.temp_allocator)
	return ret
}

wrap_pointer :: proc(expr: ^ast.Expr, times: int) -> ^ast.Expr {
	n := 0
	expr := expr

	for i in 0 ..< times {
		new_pointer := new_type(
			ast.Pointer_Type,
			expr.pos,
			expr.end,
			context.temp_allocator,
		)

		new_pointer.elem = expr

		expr = new_pointer
	}


	return expr
}

get_using_packages :: proc(ast_context: ^AstContext) -> []string {
	usings := make([]string, len(ast_context.usings), context.temp_allocator)

	if len(ast_context.usings) == 0 {
		return usings
	}

	//probably map instead
	for u, i in ast_context.usings {
		for imp in ast_context.imports {
			if strings.compare(imp.base, u) == 0 {
				usings[i] = imp.name
			}
		}
	}

	return usings
}

get_symbol_pkg_name :: proc(
	ast_context: ^AstContext,
	symbol: Symbol,
) -> string {

	name := path.base(symbol.pkg, false, context.temp_allocator)

	for imp in ast_context.imports {
		if imp.base_original == name {
			return imp.base
		}
	}

	return name
}


make_symbol_procedure_from_ast :: proc(
	ast_context: ^AstContext,
	n: ^ast.Node,
	v: ast.Proc_Type,
	name: ast.Ident,
	attributes: []^ast.Attribute,
	type: bool,
) -> Symbol {
	symbol := Symbol {
		range = common.get_token_range(name, ast_context.file.src),
		type  = .Function if !type else .Type_Function,
		pkg   = get_package_from_node(n^),
		name  = name.name,
	}

	return_types := make([dynamic]^ast.Field, ast_context.allocator)
	arg_types := make([dynamic]^ast.Field, ast_context.allocator)

	if v.results != nil {
		for ret in v.results.list {
			append(&return_types, ret)
		}
	}

	if v.params != nil {
		for param in v.params.list {
			append(&arg_types, param)
		}
	}

	if expr, ok := ast_context.globals[name.name]; ok {
		if expr.deprecated {
			symbol.flags |= {.Distinct}
		}
	}

	symbol.value = SymbolProcedureValue {
		return_types = return_types[:],
		arg_types    = arg_types[:],
		generic      = v.generic,
	}

	if _, ok := common.get_attribute_objc_name(attributes); ok {
		symbol.flags |= {.ObjC}
		if common.get_attribute_objc_is_class_method(attributes) {
			symbol.flags |= {.ObjCIsClassMethod}
		}
	}

	return symbol
}

make_symbol_array_from_ast :: proc(
	ast_context: ^AstContext,
	v: ast.Array_Type,
	name: ast.Ident,
) -> Symbol {
	symbol := Symbol {
		range = common.get_token_range(v.node, ast_context.file.src),
		type  = .Constant,
		pkg   = get_package_from_node(v.node),
		name  = name.name,
	}

	if v.len != nil {
		symbol.value = SymbolFixedArrayValue {
			expr = v.elem,
			len  = v.len,
		}
	} else {
		symbol.value = SymbolSliceValue {
			expr = v.elem,
		}
	}

	return symbol
}

make_symbol_dynamic_array_from_ast :: proc(
	ast_context: ^AstContext,
	v: ast.Dynamic_Array_Type,
	name: ast.Ident,
) -> Symbol {
	symbol := Symbol {
		range = common.get_token_range(v.node, ast_context.file.src),
		type  = .Constant,
		pkg   = get_package_from_node(v.node),
		name  = name.name,
	}

	symbol.value = SymbolDynamicArrayValue {
		expr = v.elem,
	}

	return symbol
}

make_symbol_matrix_from_ast :: proc(
	ast_context: ^AstContext,
	v: ast.Matrix_Type,
	name: ast.Ident,
) -> Symbol {
	symbol := Symbol {
		range = common.get_token_range(v.node, ast_context.file.src),
		type  = .Constant,
		pkg   = get_package_from_node(v.node),
		name  = name.name,
	}

	symbol.value = SymbolMatrixValue {
		expr = v.elem,
		x    = v.row_count,
		y    = v.column_count,
	}

	return symbol
}


make_symbol_multi_pointer_from_ast :: proc(
	ast_context: ^AstContext,
	v: ast.Multi_Pointer_Type,
	name: ast.Ident,
) -> Symbol {
	symbol := Symbol {
		range = common.get_token_range(v.node, ast_context.file.src),
		type  = .Constant,
		pkg   = get_package_from_node(v.node),
		name  = name.name,
	}

	symbol.value = SymbolMultiPointer {
		expr = v.elem,
	}

	return symbol
}

make_symbol_map_from_ast :: proc(
	ast_context: ^AstContext,
	v: ast.Map_Type,
	name: ast.Ident,
) -> Symbol {
	symbol := Symbol {
		range = common.get_token_range(v.node, ast_context.file.src),
		type  = .Constant,
		pkg   = get_package_from_node(v.node),
		name  = name.name,
	}

	symbol.value = SymbolMapValue {
		key   = v.key,
		value = v.value,
	}

	return symbol
}

make_symbol_basic_type_from_ast :: proc(
	ast_context: ^AstContext,
	n: ^ast.Ident,
) -> Symbol {
	symbol := Symbol {
		range = common.get_token_range(n^, ast_context.file.src),
		type  = .Variable,
		pkg   = get_package_from_node(n^),
	}

	symbol.value = SymbolBasicValue {
		ident = n,
	}

	return symbol
}

make_symbol_union_from_ast :: proc(
	ast_context: ^AstContext,
	v: ast.Union_Type,
	ident: ast.Ident,
	inlined := false,
) -> Symbol {
	symbol := Symbol {
		range = common.get_token_range(v, ast_context.file.src),
		type  = .Union,
		pkg   = get_package_from_node(v.node),
		name  = ident.name,
	}

	if inlined {
		symbol.flags |= {.Anonymous}
		symbol.name = "union"
	}

	types := make([dynamic]^ast.Expr, ast_context.allocator)

	for variant in v.variants {
		if v.poly_params != nil {
			append(&types, clone_type(variant, ast_context.allocator, nil))
		} else {
			append(&types, variant)
		}
	}

	symbol.value = SymbolUnionValue {
		types = types[:],
	}

	if v.poly_params != nil {
		resolve_poly_union(ast_context, v.poly_params, &symbol)
	}

	return symbol
}

make_symbol_enum_from_ast :: proc(
	ast_context: ^AstContext,
	v: ast.Enum_Type,
	ident: ast.Ident,
	inlined := false,
) -> Symbol {
	symbol := Symbol {
		range = common.get_token_range(v, ast_context.file.src),
		type  = .Enum,
		name  = ident.name,
		pkg   = get_package_from_node(v.node),
	}

	if inlined {
		symbol.flags |= {.Anonymous}
		symbol.name = "enum"
	}


	names := make([dynamic]string, ast_context.allocator)
	ranges := make([dynamic]common.Range, ast_context.allocator)

	for n in v.fields {
		append(&ranges, common.get_token_range(n, ast_context.file.src))

		if ident, ok := n.derived.(^ast.Ident); ok {
			append(&names, ident.name)
		} else if field, ok := n.derived.(^ast.Field_Value); ok {
			if ident, ok := field.field.derived.(^ast.Ident); ok {
				append(&names, ident.name)
			} else if binary, ok := field.field.derived.(^ast.Binary_Expr);
			   ok {
				append(&names, binary.left.derived.(^ast.Ident).name)
			}
		}
	}

	symbol.value = SymbolEnumValue {
		names  = names[:],
		ranges = ranges[:],
	}

	return symbol
}

make_symbol_bitset_from_ast :: proc(
	ast_context: ^AstContext,
	v: ast.Bit_Set_Type,
	ident: ast.Ident,
	inlined := false,
) -> Symbol {
	symbol := Symbol {
		range = common.get_token_range(v, ast_context.file.src),
		type  = .Enum,
		name  = ident.name,
		pkg   = get_package_from_node(v.node),
	}

	if inlined {
		symbol.flags |= {.Anonymous}
		symbol.name = "bitset"
	}

	symbol.value = SymbolBitSetValue {
		expr = v.elem,
	}

	return symbol
}

make_symbol_struct_from_ast :: proc(
	ast_context: ^AstContext,
	v: ast.Struct_Type,
	ident: ast.Ident,
	attributes: []^ast.Attribute,
	inlined := false,
) -> Symbol {
	symbol := Symbol {
		range = common.get_token_range(v, ast_context.file.src),
		type  = .Struct,
		pkg   = get_package_from_node(v.node),
		name  = ident.name,
	}

	if inlined {
		symbol.flags |= {.Anonymous}
		symbol.name = "struct"
	}

	names := make([dynamic]string, ast_context.allocator)
	types := make([dynamic]^ast.Expr, ast_context.allocator)
	usings := make(map[int]bool, 0, ast_context.allocator)
	ranges := make([dynamic]common.Range, 0, ast_context.allocator)

	for field in v.fields.list {
		for n in field.names {
			if identifier, ok := n.derived.(^ast.Ident);
			   ok && field.type != nil {
				if .Using in field.flags {
					usings[len(types)] = true
				}

				append(&names, identifier.name)
				if v.poly_params != nil {
					append(
						&types,
						clone_type(field.type, ast_context.allocator, nil),
					)
				} else {
					append(&types, field.type)
				}

				append(
					&ranges,
					common.get_token_range(n, ast_context.file.src),
				)
			}
		}
	}

	symbol.value = SymbolStructValue {
		names  = names[:],
		types  = types[:],
		ranges = ranges[:],
		usings = usings,
		poly   = v.poly_params,
	}

	if _, ok := common.get_attribute_objc_class_name(attributes); ok {
		symbol.flags |= {.ObjC}
		if common.get_attribute_objc_is_class_method(attributes) {
			symbol.flags |= {.ObjCIsClassMethod}
		}
	}

	if v.poly_params != nil {
		resolve_poly_struct(ast_context, v.poly_params, &symbol)
	}

	//TODO change the expand to not double copy the array, but just pass the dynamic arrays
	if len(usings) > 0 || .ObjC in symbol.flags {
		symbol.value = expand_struct_usings(
			ast_context,
			symbol,
			symbol.value.(SymbolStructValue),
		)
	}

	return symbol
}

get_globals :: proc(file: ast.File, ast_context: ^AstContext) {
	exprs := common.collect_globals(file)

	for expr in exprs {
		ast_context.globals[expr.name] = expr
	}
}

get_generic_assignment :: proc(
	file: ast.File,
	value: ^ast.Expr,
	ast_context: ^AstContext,
	results: ^[dynamic]^ast.Expr,
	calls: ^map[int]bool,
) {
	using ast

	reset_ast_context(ast_context)

	#partial switch v in value.derived {
	case ^Or_Return_Expr:
		get_generic_assignment(file, v.expr, ast_context, results, calls)
	case ^Call_Expr:
		old_call := ast_context.call
		ast_context.call = cast(^ast.Call_Expr)value

		defer {
			ast_context.call = old_call
		}

		if symbol, ok := resolve_type_expression(ast_context, v.expr); ok {
			if procedure, ok := symbol.value.(SymbolProcedureValue); ok {
				for ret in procedure.return_types {
					if ret.type != nil {
						calls[len(results)] = true
						append(results, ret.type)
					} else if ret.default_value != nil {
						calls[len(results)] = true
						append(results, ret.default_value)
					}
				}
			}
		}
	case ^Comp_Lit:
		if v.type != nil {
			append(results, v.type)
		}
	case ^Array_Type:
		if v.elem != nil {
			append(results, v.elem)
		}
	case ^Dynamic_Array_Type:
		if v.elem != nil {
			append(results, v.elem)
		}
	case ^Selector_Expr:
		if v.expr != nil {
			append(results, value)
		}
	case ^ast.Index_Expr:
		append(results, v)
		b := make_bool_ast(ast_context, v.expr.pos, v.expr.end)
		append(results, b)
	case ^Type_Assertion:
		if v.type != nil {
			if unary, ok := v.type.derived.(^ast.Unary_Expr);
			   ok && unary.op.kind == .Question {
				append(results, cast(^ast.Expr)&v.node)
			} else {
				append(results, v.type)
			}

			b := make_bool_ast(ast_context, v.type.pos, v.type.end)

			append(results, b)
		}
	case:
		//log.debugf("default node get_generic_assignment %v", v);
		append(results, value)
	}
}

get_locals_value_decl :: proc(
	file: ast.File,
	value_decl: ast.Value_Decl,
	ast_context: ^AstContext,
) {
	using ast

	if len(value_decl.names) <= 0 {
		return
	}

	if value_decl.is_using {
		if value_decl.type != nil {
			get_locals_using(value_decl.type, ast_context)
		} else {
			for expr in value_decl.values {
				get_locals_using(expr, ast_context)
			}
		}
	}

	if value_decl.type != nil {
		for name, i in value_decl.names {
			str := common.get_ast_node_string(value_decl.names[i], file.src)
			store_local(
				ast_context,
				name,
				value_decl.type,
				value_decl.end.offset,
				str,
				ast_context.local_id,
				ast_context.non_mutable_only,
				false,
				value_decl.is_mutable,
				"",
				false,
			)
		}
		return
	}

	results := make([dynamic]^Expr, context.temp_allocator)
	calls := make(map[int]bool, 0, context.temp_allocator) //Have to track the calls, since they disallow use of variables afterwards

	for value in value_decl.values {
		get_generic_assignment(file, value, ast_context, &results, &calls)
	}

	if len(results) == 0 {
		return
	}

	for name, i in value_decl.names {
		result_i := min(len(results) - 1, i)
		str := common.get_ast_node_string(name, file.src)

		call := false

		store_local(
			ast_context,
			name,
			results[result_i],
			value_decl.end.offset,
			str,
			ast_context.local_id,
			ast_context.non_mutable_only,
			calls[result_i] or_else false,
			value_decl.is_mutable,
			get_package_from_node(results[result_i]^),
			false,
		)
	}
}

get_locals_stmt :: proc(
	file: ast.File,
	stmt: ^ast.Stmt,
	ast_context: ^AstContext,
	document_position: ^DocumentPositionContext,
	save_assign := false,
) {
	reset_ast_context(ast_context)
	ast_context.current_package = ast_context.document_package

	using ast

	if stmt == nil {
		return
	}

	if stmt.pos.offset > document_position.position {
		return
	}

	#partial switch v in stmt.derived {
	case ^Value_Decl:
		get_locals_value_decl(file, v^, ast_context)
	case ^Type_Switch_Stmt:
		get_locals_type_switch_stmt(file, v^, ast_context, document_position)
	case ^Switch_Stmt:
		get_locals_switch_stmt(file, v^, ast_context, document_position)
	case ^For_Stmt:
		get_locals_for_stmt(file, v^, ast_context, document_position)
	case ^Inline_Range_Stmt:
		get_locals_stmt(file, v.body, ast_context, document_position)
	case ^Range_Stmt:
		get_locals_for_range_stmt(file, v^, ast_context, document_position)
	case ^If_Stmt:
		get_locals_if_stmt(file, v^, ast_context, document_position)
	case ^Block_Stmt:
		get_locals_block_stmt(file, v^, ast_context, document_position)
	case ^Proc_Lit:
		get_locals_stmt(file, v.body, ast_context, document_position)
	case ^Assign_Stmt:
		if save_assign {
			get_locals_assign_stmt(file, v^, ast_context)
		}
	case ^Using_Stmt:
		get_locals_using_stmt(v^, ast_context)
	case ^When_Stmt:
		get_locals_stmt(file, v.else_stmt, ast_context, document_position)
		get_locals_stmt(file, v.body, ast_context, document_position)
	case ^Case_Clause:
		for stmt in v.body {
			get_locals_stmt(file, stmt, ast_context, document_position)
		}
	case:
	//log.debugf("default node local stmt %v", v);
	}
}

get_locals_block_stmt :: proc(
	file: ast.File,
	block: ast.Block_Stmt,
	ast_context: ^AstContext,
	document_position: ^DocumentPositionContext,
) {
	if !(block.pos.offset <= document_position.position &&
		   document_position.position <= block.end.offset) {
		return
	}

	for stmt in block.stmts {
		if ast_context.non_mutable_only {
			if value_decl, ok := stmt.derived.(^ast.Value_Decl);
			   ok && !value_decl.is_mutable {
				get_locals_stmt(file, stmt, ast_context, document_position)
			}
		} else {
			get_locals_stmt(file, stmt, ast_context, document_position)
		}
	}
}

get_locals_using :: proc(expr: ^ast.Expr, ast_context: ^AstContext) {
	if symbol, expr, ok := unwrap_procedure_until_struct_or_package(
		ast_context,
		expr,
	); ok {
		#partial switch v in symbol.value {
		case SymbolPackageValue:
			if ident, ok := expr.derived.(^ast.Ident); ok {
				append(&ast_context.usings, ident.name)
			}
		case SymbolStructValue:
			for name, i in v.names {
				selector := new_type(
					ast.Selector_Expr,
					v.types[i].pos,
					v.types[i].end,
					ast_context.allocator,
				)
				selector.expr = expr
				selector.field = new_type(
					ast.Ident,
					v.types[i].pos,
					v.types[i].end,
					ast_context.allocator,
				)
				selector.field.name = name
				store_local(
					ast_context,
					expr,
					selector,
					0,
					name,
					ast_context.local_id,
					false,
					ast_context.non_mutable_only,
					true,
					"",
					false,
				)
			}
		}
	}
}

get_locals_using_stmt :: proc(stmt: ast.Using_Stmt, ast_context: ^AstContext) {
	for u in stmt.list {
		get_locals_using(u, ast_context)
	}
}

get_locals_assign_stmt :: proc(
	file: ast.File,
	stmt: ast.Assign_Stmt,
	ast_context: ^AstContext,
) {
	using ast

	if stmt.lhs == nil || stmt.rhs == nil {
		return
	}

	results := make([dynamic]^Expr, context.temp_allocator)
	calls := make(map[int]bool, 0, context.temp_allocator)

	for rhs in stmt.rhs {
		get_generic_assignment(file, rhs, ast_context, &results, &calls)
	}

	if len(stmt.lhs) != len(results) {
		return
	}

	for lhs, i in stmt.lhs {
		if ident, ok := lhs.derived.(^ast.Ident); ok {
			store_local(
				ast_context,
				lhs,
				results[i],
				ident.pos.offset,
				ident.name,
				ast_context.local_id,
				ast_context.non_mutable_only,
				false,
				true,
				"",
				false,
			)
		}
	}
}

get_locals_if_stmt :: proc(
	file: ast.File,
	stmt: ast.If_Stmt,
	ast_context: ^AstContext,
	document_position: ^DocumentPositionContext,
) {
	if !(stmt.pos.offset <= document_position.position &&
		   document_position.position <= stmt.end.offset) {
		return
	}

	get_locals_stmt(file, stmt.init, ast_context, document_position, false)
	get_locals_stmt(file, stmt.body, ast_context, document_position)
	get_locals_stmt(file, stmt.else_stmt, ast_context, document_position)
}

get_locals_for_range_stmt :: proc(
	file: ast.File,
	stmt: ast.Range_Stmt,
	ast_context: ^AstContext,
	document_position: ^DocumentPositionContext,
) {
	using ast

	if !(stmt.pos.offset <= document_position.position &&
		   document_position.position <= stmt.end.offset) {
		return
	}

	results := make([dynamic]^Expr, context.temp_allocator)

	if stmt.expr == nil {
		return
	}

	if binary, ok := stmt.expr.derived.(^ast.Binary_Expr); ok {
		if binary.op.kind == .Range_Half {
			if len(stmt.vals) >= 1 {
				if ident, ok := unwrap_ident(stmt.vals[0]); ok {
					store_local(
						ast_context,
						ident,
						make_int_ast(ast_context, ident.pos, ident.end),
						ident.pos.offset,
						ident.name,
						ast_context.local_id,
						ast_context.non_mutable_only,
						false,
						true,
						"",
						false,
					)
				}
			}
		}
	}

	if symbol, ok := resolve_type_expression(ast_context, stmt.expr); ok {
		#partial switch v in symbol.value {
		case SymbolMapValue:
			if len(stmt.vals) >= 1 {
				if ident, ok := unwrap_ident(stmt.vals[0]); ok {
					store_local(
						ast_context,
						ident,
						v.key,
						ident.pos.offset,
						ident.name,
						ast_context.local_id,
						ast_context.non_mutable_only,
						false,
						true,
						symbol.pkg,
						false,
					)
				}
			}
			if len(stmt.vals) >= 2 {
				if ident, ok := unwrap_ident(stmt.vals[1]); ok {
					store_local(
						ast_context,
						ident,
						v.value,
						ident.pos.offset,
						ident.name,
						ast_context.local_id,
						ast_context.non_mutable_only,
						false,
						true,
						symbol.pkg,
						false,
					)
				}
			}
		case SymbolDynamicArrayValue:
			if len(stmt.vals) >= 1 {
				if ident, ok := unwrap_ident(stmt.vals[0]); ok {
					store_local(
						ast_context,
						ident,
						v.expr,
						ident.pos.offset,
						ident.name,
						ast_context.local_id,
						ast_context.non_mutable_only,
						false,
						true,
						symbol.pkg,
						false,
					)
				}
			}
			if len(stmt.vals) >= 2 {
				if ident, ok := unwrap_ident(stmt.vals[1]); ok {
					store_local(
						ast_context,
						ident,
						make_int_ast(ast_context, ident.pos, ident.end),
						ident.pos.offset,
						ident.name,
						ast_context.local_id,
						ast_context.non_mutable_only,
						false,
						true,
						symbol.pkg,
						false,
					)
				}
			}
		case SymbolFixedArrayValue:
			if len(stmt.vals) >= 1 {
				if ident, ok := unwrap_ident(stmt.vals[0]); ok {
					store_local(
						ast_context,
						ident,
						v.expr,
						ident.pos.offset,
						ident.name,
						ast_context.local_id,
						ast_context.non_mutable_only,
						false,
						true,
						symbol.pkg,
						false,
					)
				}
			}

			if len(stmt.vals) >= 2 {
				if ident, ok := unwrap_ident(stmt.vals[1]); ok {
					store_local(
						ast_context,
						ident,
						make_int_ast(ast_context, ident.pos, ident.end),
						ident.pos.offset,
						ident.name,
						ast_context.local_id,
						ast_context.non_mutable_only,
						false,
						true,
						symbol.pkg,
						false,
					)
				}
			}
		case SymbolSliceValue:
			if len(stmt.vals) >= 1 {
				if ident, ok := unwrap_ident(stmt.vals[0]); ok {
					store_local(
						ast_context,
						ident,
						v.expr,
						ident.pos.offset,
						ident.name,
						ast_context.local_id,
						ast_context.non_mutable_only,
						false,
						true,
						symbol.pkg,
						false,
					)
				}
			}
			if len(stmt.vals) >= 2 {
				if ident, ok := unwrap_ident(stmt.vals[1]); ok {
					store_local(
						ast_context,
						ident,
						make_int_ast(ast_context, ident.pos, ident.end),
						ident.pos.offset,
						ident.name,
						ast_context.local_id,
						ast_context.non_mutable_only,
						false,
						true,
						symbol.pkg,
						false,
					)
				}
			}
		}
	}

	get_locals_stmt(file, stmt.body, ast_context, document_position)
}

get_locals_for_stmt :: proc(
	file: ast.File,
	stmt: ast.For_Stmt,
	ast_context: ^AstContext,
	document_position: ^DocumentPositionContext,
) {
	if !(stmt.pos.offset <= document_position.position &&
		   document_position.position <= stmt.end.offset) {
		return
	}

	get_locals_stmt(file, stmt.init, ast_context, document_position, false)
	get_locals_stmt(file, stmt.body, ast_context, document_position)
}

get_locals_switch_stmt :: proc(
	file: ast.File,
	stmt: ast.Switch_Stmt,
	ast_context: ^AstContext,
	document_position: ^DocumentPositionContext,
) {
	if !(stmt.pos.offset <= document_position.position &&
		   document_position.position <= stmt.end.offset) {
		return
	}

	get_locals_stmt(file, stmt.body, ast_context, document_position)
}

get_locals_type_switch_stmt :: proc(
	file: ast.File,
	stmt: ast.Type_Switch_Stmt,
	ast_context: ^AstContext,
	document_position: ^DocumentPositionContext,
) {
	using ast

	if !(stmt.pos.offset <= document_position.position &&
		   document_position.position <= stmt.end.offset) {
		return
	}

	if stmt.body == nil {
		return
	}

	if block, ok := stmt.body.derived.(^Block_Stmt); ok {
		for block_stmt in block.stmts {
			if cause, ok := block_stmt.derived.(^Case_Clause);
			   ok &&
			   cause.pos.offset <= document_position.position &&
			   document_position.position <= cause.end.offset {
				tag := stmt.tag.derived.(^Assign_Stmt)

				if len(tag.lhs) == 1 && len(cause.list) == 1 {
					ident, _ := unwrap_ident(tag.lhs[0])
					store_local(
						ast_context,
						ident,
						cause.list[0],
						ident.pos.offset,
						ident.name,
						ast_context.local_id,
						ast_context.non_mutable_only,
						false,
						true,
						"",
						false,
					)
				}

				for b in cause.body {
					get_locals_stmt(file, b, ast_context, document_position)
				}
			}
		}
	}
}

get_locals_proc_param_and_results :: proc(
	file: ast.File,
	function: ast.Proc_Lit,
	ast_context: ^AstContext,
	document_position: ^DocumentPositionContext,
) {
	proc_lit, ok := function.derived.(^ast.Proc_Lit)

	if !ok || proc_lit.body == nil {
		return
	}

	if proc_lit.type != nil && proc_lit.type.params != nil {
		for arg in proc_lit.type.params.list {
			for name in arg.names {
				if arg.type != nil {
					str := common.get_ast_node_string(name, file.src)
					store_local(
						ast_context,
						name,
						arg.type,
						name.pos.offset,
						str,
						ast_context.local_id,
						ast_context.non_mutable_only,
						false,
						true,
						"",
						true,
					)

					if .Using in arg.flags {
						using_stmt: ast.Using_Stmt
						using_stmt.list = make(
							[]^ast.Expr,
							1,
							context.temp_allocator,
						)
						using_stmt.list[0] = arg.type
						get_locals_using_stmt(using_stmt, ast_context)
					}
				} else {
					str := common.get_ast_node_string(name, file.src)
					store_local(
						ast_context,
						name,
						arg.default_value,
						name.pos.offset,
						str,
						ast_context.local_id,
						ast_context.non_mutable_only,
						false,
						true,
						"",
						true,
					)
				}
			}
		}
	}

	if proc_lit.type != nil && proc_lit.type.results != nil {
		for result in proc_lit.type.results.list {
			for name in result.names {
				if result.type != nil {
					str := common.get_ast_node_string(name, file.src)
					store_local(
						ast_context,
						name,
						result.type,
						name.pos.offset,
						str,
						ast_context.local_id,
						ast_context.non_mutable_only,
						false,
						true,
						"",
						true,
					)
				} else {
					str := common.get_ast_node_string(name, file.src)
					store_local(
						ast_context,
						name,
						result.default_value,
						name.pos.offset,
						str,
						ast_context.local_id,
						ast_context.non_mutable_only,
						false,
						true,
						"",
						true,
					)
				}
			}
		}
	}
}

get_locals :: proc(
	file: ast.File,
	function: ^ast.Node,
	ast_context: ^AstContext,
	document_position: ^DocumentPositionContext,
) {
	proc_lit, ok := function.derived.(^ast.Proc_Lit)

	if !ok || proc_lit.body == nil {
		return
	}

	get_locals_proc_param_and_results(
		file,
		proc_lit^,
		ast_context,
		document_position,
	)

	block: ^ast.Block_Stmt
	block, ok = proc_lit.body.derived.(^ast.Block_Stmt)

	if !ok {
		log.error("Proc_List body not block")
		return
	}

	for stmt in block.stmts {
		get_locals_stmt(file, stmt, ast_context, document_position)
	}

	old_position := document_position.position

	for function in document_position.functions {
		ast_context.non_mutable_only = true
		document_position.position = function.end.offset
		get_locals_stmt(file, function.body, ast_context, document_position)
	}

	document_position.position = old_position
}

clear_locals :: proc(ast_context: ^AstContext) {
	clear(&ast_context.locals)
	clear(&ast_context.usings)
}

ResolveReferenceFlag :: enum {
	None,
	Variable,
	Constant,
	StructElement,
	EnumElement,
}

resolve_entire_file :: proc(
	document: ^Document,
	reference := "",
	flag := ResolveReferenceFlag.None,
	save_unresolved := false,
	allocator := context.allocator,
) -> map[uintptr]SymbolAndNode {
	ast_context := make_ast_context(
		document.ast,
		document.imports,
		document.package_name,
		document.uri.uri,
		document.fullpath,
		allocator,
	)

	get_globals(document.ast, &ast_context)

	ast_context.current_package = ast_context.document_package

	symbols := make(map[uintptr]SymbolAndNode, 10000, allocator)

	for decl in document.ast.decls {
		if _, is_value := decl.derived.(^ast.Value_Decl); !is_value {
			continue
		}

		resolve_entire_decl(
			&ast_context,
			document,
			decl,
			&symbols,
			reference,
			flag,
			save_unresolved,
			allocator,
		)
		clear(&ast_context.locals)
	}

	return symbols
}

resolve_entire_decl :: proc(
	ast_context: ^AstContext,
	document: ^Document,
	decl: ^ast.Node,
	symbols: ^map[uintptr]SymbolAndNode,
	reference := "",
	flag := ResolveReferenceFlag.None,
	save_unresolved := false,
	allocator := context.allocator,
) {
	Scope :: struct {
		offset: int,
		id:     int,
	}

	Visit_Data :: struct {
		ast_context:     ^AstContext,
		symbols:         ^map[uintptr]SymbolAndNode,
		scopes:          [dynamic]Scope,
		id_counter:      int,
		last_visit:      ^ast.Node,
		resolve_flag:    ResolveReferenceFlag,
		reference:       string,
		save_unresolved: bool,
		document:        ^Document,
	}

	data := Visit_Data {
		ast_context     = ast_context,
		symbols         = symbols,
		scopes          = make([dynamic]Scope, allocator),
		resolve_flag    = flag,
		reference       = reference,
		document        = document,
		save_unresolved = save_unresolved,
	}

	visit :: proc(visitor: ^ast.Visitor, node: ^ast.Node) -> ^ast.Visitor {
		if node == nil || visitor == nil {
			return nil
		}
		data := cast(^Visit_Data)visitor.data
		ast_context := data.ast_context

		reset_ast_context(ast_context)

		data.last_visit = node

		//It's somewhat silly to check the scope everytime, but the alternative is to implement my own walker function.
		if len(data.scopes) > 0 {
			current_scope := data.scopes[len(data.scopes) - 1]

			if current_scope.offset < node.end.offset {
				clear_local_group(ast_context, current_scope.id)

				pop(&data.scopes)

				if len(data.scopes) > 0 {
					current_scope = data.scopes[len(data.scopes) - 1]
					ast_context.local_id = current_scope.id
				} else {
					ast_context.local_id = 0
				}
			}
		}

		#partial switch v in node.derived {
		case ^ast.Proc_Lit:
			if v.body == nil {
				break
			}

			scope: Scope
			scope.id = data.id_counter
			scope.offset = node.end.offset
			data.id_counter += 1
			ast_context.local_id = scope.id

			append(&data.scopes, scope)
			add_local_group(ast_context, scope.id)

			position_context: DocumentPositionContext
			position_context.position = node.end.offset

			get_locals_proc_param_and_results(
				ast_context.file,
				v^,
				ast_context,
				&position_context,
			)
			get_locals_stmt(
				ast_context.file,
				cast(^ast.Stmt)node,
				ast_context,
				&position_context,
			)
		case ^ast.If_Stmt, ^ast.For_Stmt, ^ast.Range_Stmt, ^ast.Inline_Range_Stmt:
			scope: Scope
			scope.id = data.id_counter
			scope.offset = node.end.offset
			data.id_counter += 1
			ast_context.local_id = scope.id

			append(&data.scopes, scope)
			add_local_group(ast_context, scope.id)

			position_context: DocumentPositionContext
			position_context.position = node.end.offset
			get_locals_stmt(
				ast_context.file,
				cast(^ast.Stmt)node,
				ast_context,
				&position_context,
			)
		}

		if data.resolve_flag == .None {
			#partial switch v in node.derived {
			case ^ast.Ident:
				if symbol, ok := resolve_type_identifier(ast_context, v^); ok {
					data.symbols[cast(uintptr)node] = SymbolAndNode {
						node        = v,
						symbol      = symbol,
						is_resolved = true,
					}
				} else if data.save_unresolved {
					data.symbols[cast(uintptr)node] = SymbolAndNode {
						node = v,
					}
				}
			case ^ast.Selector_Expr:
				if symbol, ok := resolve_type_expression(ast_context, &v.node);
				   ok {
					data.symbols[cast(uintptr)node] = SymbolAndNode {
						node        = v,
						symbol      = symbol,
						is_resolved = true,
					}
				} else if data.save_unresolved {
					data.symbols[cast(uintptr)node] = SymbolAndNode {
						node = v,
					}
				}
			case ^ast.Call_Expr:
				if symbol, ok := resolve_type_expression(ast_context, &v.node);
				   ok {
					data.symbols[cast(uintptr)node] = SymbolAndNode {
						node        = v,
						symbol      = symbol,
						is_resolved = true,
					}
				} else if data.save_unresolved {
					data.symbols[cast(uintptr)node] = SymbolAndNode {
						node = v,
					}
				}
			}
		} else {
			#partial done: switch v in node.derived {
			case ^ast.Selector_Expr:
				document: ^Document = data.document

				position_context := DocumentPositionContext {
					position = v.pos.offset,
				}

				get_document_position_decls(
					document.ast.decls[:],
					&position_context,
				)

				if symbol, ok := resolve_location_selector(ast_context, v);
				   ok {
					data.symbols[cast(uintptr)node] = SymbolAndNode {
						node   = v.field,
						symbol = symbol,
					}
				}

				if _, is_ident := v.field.derived.(^ast.Ident); is_ident {
					if data.resolve_flag == .Constant ||
					   data.resolve_flag == .Variable {
						return nil
					}
				}
			case ^ast.Ident:
				if data.resolve_flag == .Variable && v.name != data.reference {
					break done
				}

				document: ^Document = data.document

				position_context := DocumentPositionContext {
					position = v.pos.offset,
				}

				get_document_position_decls(
					document.ast.decls[:],
					&position_context,
				)

				if position_context.field_value != nil &&
				   position_in_node(
					   position_context.field_value.field,
					   v.pos.offset,
				   ) {
					break done
				} else if position_context.struct_type != nil &&
				   data.resolve_flag != .StructElement {
					break done
				} else if position_context.enum_type != nil &&
				   data.resolve_flag != .EnumElement {
					break done
				}

				if symbol, ok := resolve_location_identifier(ast_context, v^);
				   ok {
					data.symbols[cast(uintptr)node] = SymbolAndNode {
						node   = v,
						symbol = symbol,
					}
				}
			}
		}

		return visitor
	}

	visitor := ast.Visitor {
		data  = &data,
		visit = visit,
	}

	ast.walk(&visitor, decl)
}

concatenate_symbol_information :: proc {
	concatenate_raw_symbol_information,
	concatenate_raw_string_information,
}

concatenate_raw_symbol_information :: proc(
	ast_context: ^AstContext,
	symbol: Symbol,
	is_completion: bool,
) -> string {
	return concatenate_raw_string_information(
		ast_context,
		symbol.pkg,
		symbol.name,
		symbol.signature,
		symbol.type,
		is_completion,
	)
}

concatenate_raw_string_information :: proc(
	ast_context: ^AstContext,
	pkg: string,
	name: string,
	signature: string,
	type: SymbolType,
	is_completion: bool,
) -> string {
	pkg := path.base(pkg, false, context.temp_allocator)

	if type == .Package {
		return fmt.tprintf("%v: package", name)
	} else if type == .Keyword && is_completion {
		return name
	} else {
		if signature != "" {
			return fmt.tprintf("%v.%v: %v", pkg, name, signature)
		} else {
			return fmt.tprintf("%v.%v", pkg, name)
		}
	}
}

unwrap_procedure_until_struct_or_package :: proc(
	ast_context: ^AstContext,
	node: ^ast.Expr,
) -> (
	symbol: Symbol,
	expr: ^ast.Expr,
	ok: bool,
) {
	expr = node
	symbol, ok = resolve_type_expression(ast_context, node)

	if !ok {
		return
	}

	for true {
		ok = false
		#partial switch v in symbol.value {
		case SymbolProcedureValue:
			if len(v.return_types) == 0 {
				return
			}

			if v.return_types[0].type == nil {
				return
			}

			symbol, ok = resolve_type_expression(
				ast_context,
				v.return_types[0].type,
			)

			if !ok {
				return
			}

			expr = v.return_types[0].type
		case SymbolStructValue, SymbolPackageValue:
			ok = true
			return
		case:
			return
		}
	}

	return
}

unwrap_ident :: proc(node: ^ast.Expr) -> (^ast.Ident, bool) {
	if ident, ok := node.derived.(^ast.Ident); ok {
		return ident, true
	}

	if unary, ok := node.derived.(^ast.Unary_Expr); ok {
		if ident, ok := unary.expr.derived.(^ast.Ident); ok {
			return ident, true
		}
	}

	return {}, false
}

unwrap_enum :: proc(
	ast_context: ^AstContext,
	node: ^ast.Expr,
) -> (
	SymbolEnumValue,
	bool,
) {
	if node == nil {
		return {}, false
	}

	if enum_symbol, ok := resolve_type_expression(ast_context, node); ok {
		if enum_value, ok := enum_symbol.value.(SymbolEnumValue); ok {
			return enum_value, true
		}
	}

	return {}, false
}

unwrap_union :: proc(
	ast_context: ^AstContext,
	node: ^ast.Expr,
) -> (
	SymbolUnionValue,
	bool,
) {
	if union_symbol, ok := resolve_type_expression(ast_context, node); ok {
		ast_context.current_package = union_symbol.pkg
		if union_value, ok := union_symbol.value.(SymbolUnionValue); ok {
			return union_value, true
		}
	}

	return {}, false
}

unwrap_bitset :: proc(
	ast_context: ^AstContext,
	bitset_symbol: Symbol,
) -> (
	SymbolEnumValue,
	bool,
) {
	if bitset_value, ok := bitset_symbol.value.(SymbolBitSetValue); ok {
		if enum_symbol, ok := resolve_type_expression(
			ast_context,
			bitset_value.expr,
		); ok {
			if enum_value, ok := enum_symbol.value.(SymbolEnumValue); ok {
				return enum_value, true
			}
		}
	}

	return {}, false
}

get_signature :: proc(
	ast_context: ^AstContext,
	ident: ast.Ident,
	symbol: Symbol,
	was_variable := false,
) -> string {
	if symbol.type == .Function {
		return symbol.signature
	}

	if .Distinct in symbol.flags {
		return symbol.name
	}

	is_variable := symbol.type == .Variable


	pointer_prefix := common.repeat(
		"^",
		symbol.pointers,
		context.temp_allocator,
	)


	#partial switch v in symbol.value {
	case SymbolBasicValue:
		return strings.concatenate(
			{pointer_prefix, common.node_to_string(v.ident)},
			ast_context.allocator,
		)
	case SymbolBitSetValue:
		return strings.concatenate(
			a =  {
				pointer_prefix,
				"bit_set[",
				common.node_to_string(v.expr),
				"]",
			},
			allocator = ast_context.allocator,
		)
	case SymbolEnumValue:
		if is_variable {
			return symbol.name
		} else {
			return "enum"
		}
	case SymbolMapValue:
		return strings.concatenate(
			a =  {
				pointer_prefix,
				"map[",
				common.node_to_string(v.key),
				"]",
				common.node_to_string(v.value),
			},
			allocator = ast_context.allocator,
		)
	case SymbolProcedureValue:
		return "proc"
	case SymbolStructValue:
		if is_variable {
			return strings.concatenate(
				{pointer_prefix, symbol.name},
				ast_context.allocator,
			)
		} else {
			return "struct"
		}
	case SymbolUnionValue:
		if is_variable {
			return strings.concatenate(
				{pointer_prefix, symbol.name},
				ast_context.allocator,
			)
		} else {
			return "union"
		}
	case SymbolMultiPointer:
		return strings.concatenate(
			a = {pointer_prefix, "[^]", common.node_to_string(v.expr)},
			allocator = ast_context.allocator,
		)
	case SymbolDynamicArrayValue:
		return strings.concatenate(
			a = {pointer_prefix, "[dynamic]", common.node_to_string(v.expr)},
			allocator = ast_context.allocator,
		)
	case SymbolSliceValue:
		return strings.concatenate(
			a = {pointer_prefix, "[]", common.node_to_string(v.expr)},
			allocator = ast_context.allocator,
		)
	case SymbolFixedArrayValue:
		return strings.concatenate(
			a =  {
				pointer_prefix,
				"[",
				common.node_to_string(v.len),
				"]",
				common.node_to_string(v.expr),
			},
			allocator = ast_context.allocator,
		)
	case SymbolMatrixValue:
		return strings.concatenate(
			a =  {
				pointer_prefix,
				"matrix",
				"[",
				common.node_to_string(v.x),
				",",
				common.node_to_string(v.y),
				"]",
				common.node_to_string(v.expr),
			},
			allocator = ast_context.allocator,
		)
	case SymbolPackageValue:
		return "package"
	case SymbolUntypedValue:
		switch v.type {
		case .Float:
			return "float"
		case .String:
			return "string"
		case .Bool:
			return "bool"
		case .Integer:
			return "int"
		}
	}

	return ""
}

position_in_proc_decl :: proc(
	position_context: ^DocumentPositionContext,
) -> bool {
	if position_context.value_decl == nil {
		return false
	}

	if len(position_context.value_decl.values) != 1 {
		return false
	}

	if _, ok := position_context.value_decl.values[0].derived.(^ast.Proc_Type);
	   ok {
		return true
	}

	if proc_lit, ok := position_context.value_decl.values[0].derived.(^ast.Proc_Lit);
	   ok {
		if proc_lit.type != nil &&
		   position_in_node(proc_lit.type, position_context.position) {
			return true
		}
	}

	return false
}


is_lhs_comp_lit :: proc(position_context: ^DocumentPositionContext) -> bool {
	if position_context.position <= position_context.comp_lit.open.offset {
		return false
	}

	if len(position_context.comp_lit.elems) == 0 {
		return true
	}

	for elem in position_context.comp_lit.elems {
		if position_in_node(elem, position_context.position) {
			if ident, ok := elem.derived.(^ast.Ident); ok {
				return true
			} else if field, ok := elem.derived.(^ast.Field_Value); ok {

				if position_in_node(field.value, position_context.position) {
					return false
				}
			}
		}
	}

	return true
}

field_exists_in_comp_lit :: proc(
	comp_lit: ^ast.Comp_Lit,
	name: string,
) -> bool {
	for elem in comp_lit.elems {
		if field, ok := elem.derived.(^ast.Field_Value); ok {
			if field.field != nil {
				if ident, ok := field.field.derived.(^ast.Ident); ok {
					if ident.name == name {
						return true
					}
				}
			}
		}
	}

	return false
}

/*
	Parser gives ranges of expression, but not actually where the commas are placed.
*/
get_call_commas :: proc(
	position_context: ^DocumentPositionContext,
	document: ^Document,
) {
	if position_context.call == nil {
		return
	}

	commas := make([dynamic]int, 0, 10, context.temp_allocator)

	paren_count := 0
	bracket_count := 0
	brace_count := 0

	if call, ok := position_context.call.derived.(^ast.Call_Expr); ok {
		if document.text[call.open.offset] == '(' {
			paren_count -= 1
		}
		for i := call.open.offset; i < call.close.offset; i += 1 {
			switch document.text[i] {
			case '[':
				paren_count += 1
			case ']':
				paren_count -= 1
			case '{':
				brace_count += 1
			case '}':
				brace_count -= 1
			case '(':
				paren_count += 1
			case ')':
				paren_count -= 1
			case ',':
				if paren_count == 0 && brace_count == 0 && bracket_count == 0 {
					append(&commas, i)
				}
			}
		}
	}

	position_context.call_commas = commas[:]
}

type_to_string :: proc(ast_context: ^AstContext, expr: ^ast.Expr) -> string {
	if symbol, ok := resolve_type_expression(ast_context, expr); ok {
		if .Anonymous in symbol.flags {
			return symbol.name
		}
	}

	return common.node_to_string(expr)
}

get_document_position_decls :: proc(
	decls: []^ast.Stmt,
	position_context: ^DocumentPositionContext,
) -> bool {
	exists_in_decl := false
	for decl in decls {
		if position_in_node(decl, position_context.position) {
			get_document_position(decl, position_context)
			exists_in_decl = true
			#partial switch v in decl.derived {
			case ^ast.Expr_Stmt:
				position_context.global_lhs_stmt = true
			}
			break
		}
	}
	return exists_in_decl
}

/*
	Figure out what exactly is at the given position and whether it is in a function, struct, etc.
*/
get_document_position_context :: proc(
	document: ^Document,
	position: common.Position,
	hint: DocumentPositionContextHint,
) -> (
	DocumentPositionContext,
	bool,
) {
	position_context: DocumentPositionContext

	position_context.hint = hint
	position_context.file = document.ast
	position_context.line = position.line

	position_context.functions = make(
		[dynamic]^ast.Proc_Lit,
		context.temp_allocator,
	)

	absolute_position, ok := common.get_absolute_position(
		position,
		document.text,
	)

	if !ok {
		log.error("failed to get absolute position")
		return position_context, false
	}

	position_context.position = absolute_position

	exists_in_decl := get_document_position_decls(
		document.ast.decls[:],
		&position_context,
	)

	for import_stmt in document.ast.imports {
		if position_in_node(import_stmt, position_context.position) {
			position_context.import_stmt = import_stmt
			break
		}
	}

	if !exists_in_decl && position_context.import_stmt == nil {
		position_context.abort_completion = true
	}

	if !position_in_node(
		position_context.comp_lit,
		position_context.position,
	) {
		position_context.comp_lit = nil
	}

	if !position_in_node(
		position_context.parent_comp_lit,
		position_context.position,
	) {
		position_context.parent_comp_lit = nil
	}

	if !position_in_node(position_context.assign, position_context.position) {
		position_context.assign = nil
	}

	if !position_in_node(position_context.binary, position_context.position) {
		position_context.binary = nil
	}

	if !position_in_node(
		position_context.parent_binary,
		position_context.position,
	) {
		position_context.parent_binary = nil
	}

	if hint == .Completion &&
	   position_context.selector == nil &&
	   position_context.field == nil {
		fallback_position_context_completion(
			document,
			position,
			&position_context,
		)
	}

	if (hint == .SignatureHelp || hint == .Completion) &&
	   position_context.call == nil {
		fallback_position_context_signature(
			document,
			position,
			&position_context,
		)
	}

	if hint == .SignatureHelp {
		get_call_commas(&position_context, document)
	}

	return position_context, true
}

//terrible fallback code
fallback_position_context_completion :: proc(
	document: ^Document,
	position: common.Position,
	position_context: ^DocumentPositionContext,
) {
	paren_count: int
	bracket_count: int
	end: int
	start: int
	empty_dot: bool
	empty_arrow: bool
	last_dot: bool
	last_arrow: bool
	dots_seen: int
	partial_arrow: bool

	i := position_context.position - 1

	end = i

	for i > 0 {
		c := position_context.file.src[i]

		if c == '(' && paren_count == 0 {
			start = i + 1
			break
		} else if c == '[' && bracket_count == 0 {
			start = i + 1
			break
		} else if c == ']' && !last_dot && !last_arrow {
			start = i + 1
			break
		} else if c == ')' && !last_dot && !last_arrow {
			start = i + 1
			break
		} else if c == ')' {
			paren_count -= 1
		} else if c == '(' {
			paren_count += 1
		} else if c == '[' {
			bracket_count += 1
		} else if c == ']' {
			bracket_count -= 1
		} else if c == '.' {
			dots_seen += 1
			last_dot = true
			i -= 1
			continue
		} else if position_context.file.src[max(0, i - 1)] == '-' && c == '>' {
			last_arrow = true
			i -= 2
			continue
		}

		//ignore everything in the bracket
		if bracket_count != 0 || paren_count != 0 {
			i -= 1
			continue
		}

		//yeah..
		if c == ' ' ||
		   c == '{' ||
		   c == ',' ||
		   c == '}' ||
		   c == '^' ||
		   c == ':' ||
		   c == '\n' ||
		   c == '\r' ||
		   c == '\t' ||
		   c == '=' ||
		   c == '<' ||
		   c == '-' ||
		   c == '!' ||
		   c == '+' ||
		   c == '&' ||
		   c == '|' {
			start = i + 1
			break
		} else if c == '>' {
			partial_arrow = true
		}

		last_dot = false
		last_arrow = false

		i -= 1
	}

	if i >= 0 && position_context.file.src[end] == '.' {
		empty_dot = true
		end -= 1
	} else if i >= 0 &&
	   position_context.file.src[max(0, end - 1)] == '-' &&
	   position_context.file.src[end] == '>' {
		empty_arrow = true
		end -= 2
		position_context.arrow = true
	}

	begin_offset := max(0, start)
	end_offset := max(start, end + 1)
	line_offset := begin_offset

	if line_offset < len(position_context.file.src) {
		for line_offset > 0 {
			c := position_context.file.src[line_offset]
			if c == '\n' || c == '\r' {
				line_offset += 1
				break
			}
			line_offset -= 1
		}
	}

	str := position_context.file.src[0:end_offset]

	if empty_dot && end_offset - begin_offset == 0 {
		position_context.implicit = true
		return
	}

	s := string(position_context.file.src[begin_offset:end_offset])

	if !partial_arrow {
		only_whitespaces := true

		for r in s {
			if !strings.is_space(r) {
				only_whitespaces = false
			}
		}

		if only_whitespaces {
			return
		}
	}

	p := parser.Parser {
		err   = common.parser_warning_handler, //empty
		warn  = common.parser_warning_handler, //empty
		flags = {.Optional_Semicolons},
		file  = &position_context.file,
	}

	tokenizer.init(
		&p.tok,
		str,
		position_context.file.fullpath,
		common.parser_warning_handler,
	)

	p.tok.ch = ' '
	p.tok.line_count = position.line + 1
	p.tok.line_offset = line_offset
	p.tok.offset = begin_offset
	p.tok.read_offset = begin_offset

	tokenizer.advance_rune(&p.tok)

	if p.tok.ch == utf8.RUNE_BOM {
		tokenizer.advance_rune(&p.tok)
	}

	parser.advance_token(&p)

	context.allocator = context.temp_allocator

	e := parser.parse_expr(&p, true)

	if empty_dot || empty_arrow {
		position_context.selector = e
	} else if s, ok := e.derived.(^ast.Selector_Expr); ok {
		position_context.selector = s.expr
		position_context.field = s.field
	} else if s, ok := e.derived.(^ast.Implicit_Selector_Expr); ok {
		position_context.implicit = true
		position_context.implicit_selector_expr = s
	} else if s, ok := e.derived.(^ast.Tag_Expr); ok {
		position_context.tag = s.expr
	} else if bad_expr, ok := e.derived.(^ast.Bad_Expr); ok {
		//this is most likely because of use of 'in', 'context', etc.
		//try to go back one dot.

		src_with_dot := string(
			position_context.file.src[0:min(
				len(position_context.file.src),
				end_offset + 1,
			)],
		)
		last_dot := strings.last_index(src_with_dot, ".")

		if last_dot == -1 {
			return
		}

		tokenizer.init(
			&p.tok,
			position_context.file.src[0:last_dot],
			position_context.file.fullpath,
			common.parser_warning_handler,
		)

		p.tok.ch = ' '
		p.tok.line_count = position.line + 1
		p.tok.line_offset = line_offset
		p.tok.offset = begin_offset
		p.tok.read_offset = begin_offset

		tokenizer.advance_rune(&p.tok)

		if p.tok.ch == utf8.RUNE_BOM {
			tokenizer.advance_rune(&p.tok)
		}

		parser.advance_token(&p)

		e := parser.parse_expr(&p, true)

		if e == nil {
			position_context.abort_completion = true
			return
		} else if e, ok := e.derived.(^ast.Bad_Expr); ok {
			position_context.abort_completion = true
			return
		}

		position_context.selector = e

		ident := new_type(ast.Ident, e.pos, e.end, context.temp_allocator)
		ident.name = string(position_context.file.src[last_dot + 1:end_offset])

		if ident.name != "" {
			position_context.field = ident
		}
	} else {
		position_context.identifier = e
	}
}

fallback_position_context_signature :: proc(
	document: ^Document,
	position: common.Position,
	position_context: ^DocumentPositionContext,
) {
	end: int
	start: int
	i := position_context.position - 1
	end = i

	for i > 0 {

		c := position_context.file.src[i]

		if c == ' ' || c == '\n' || c == '\r' {
			start = i + 1
			break
		}

		i -= 1
	}

	if end < 0 {
		return
	}

	if position_context.file.src[end] != '(' {
		return
	}

	end -= 1

	begin_offset := max(0, start)
	end_offset := max(start, end + 1)

	if end_offset - begin_offset <= 1 {
		return
	}

	str := position_context.file.src[0:end_offset]

	p := parser.Parser {
		err  = common.parser_warning_handler, //empty
		warn = common.parser_warning_handler, //empty
		file = &position_context.file,
	}

	tokenizer.init(
		&p.tok,
		str,
		position_context.file.fullpath,
		common.parser_warning_handler,
	)

	p.tok.ch = ' '
	p.tok.line_count = position.line
	p.tok.offset = begin_offset
	p.tok.read_offset = begin_offset

	tokenizer.advance_rune(&p.tok)

	if p.tok.ch == utf8.RUNE_BOM {
		tokenizer.advance_rune(&p.tok)
	}

	parser.advance_token(&p)

	context.allocator = context.temp_allocator

	position_context.call = parser.parse_expr(&p, true)

	if _, ok := position_context.call.derived.(^ast.Proc_Type); ok {
		position_context.call = nil
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
}

get_document_position_array :: proc(
	array: $A/[]^$T,
	position_context: ^DocumentPositionContext,
) {
	for elem, i in array {
		get_document_position(elem, position_context)
	}
}

get_document_position_dynamic_array :: proc(
	array: $A/[dynamic]^$T,
	position_context: ^DocumentPositionContext,
) {
	for elem, i in array {
		get_document_position(elem, position_context)
	}
}

position_in_node :: proc(
	node: ^ast.Node,
	position: common.AbsolutePosition,
) -> bool {
	return(
		node != nil &&
		node.pos.offset <= position &&
		position <= node.end.offset \
	)
}

get_document_position_node :: proc(
	node: ^ast.Node,
	position_context: ^DocumentPositionContext,
) {
	using ast

	if node == nil {
		return
	}

	if !position_in_node(node, position_context.position) {
		return
	}

	#partial switch n in node.derived {
	case ^Bad_Expr:
	case ^Ident:
		position_context.identifier = node
	case ^Implicit:
		if n.tok.text == "context" {
			position_context.implicit_context = n
		}
	case ^Undef:
	case ^Basic_Lit:
		position_context.basic_lit = cast(^Basic_Lit)node
	case ^Matrix_Index_Expr:
		get_document_position(n.expr, position_context)
		get_document_position(n.row_index, position_context)
		get_document_position(n.column_index, position_context)
	case ^Matrix_Type:
		get_document_position(n.row_count, position_context)
		get_document_position(n.column_count, position_context)
		get_document_position(n.elem, position_context)
	case ^Ellipsis:
		get_document_position(n.expr, position_context)
	case ^Proc_Lit:
		get_document_position(n.type, position_context)

		if position_in_node(n.body, position_context.position) {
			position_context.function = cast(^Proc_Lit)node
			append(&position_context.functions, position_context.function)
			get_document_position(n.body, position_context)
		}
	case ^Comp_Lit:
		//only set this for the parent comp literal, since we will need to walk through it to infer types.
		if position_context.parent_comp_lit == nil {
			position_context.parent_comp_lit = cast(^Comp_Lit)node
		}

		position_context.comp_lit = cast(^Comp_Lit)node

		get_document_position(n.type, position_context)
		get_document_position(n.elems, position_context)
	case ^Tag_Expr:
		get_document_position(n.expr, position_context)
	case ^Unary_Expr:
		get_document_position(n.expr, position_context)
	case ^Binary_Expr:
		if position_context.parent_binary == nil {
			position_context.parent_binary = cast(^Binary_Expr)node
		}
		position_context.binary = cast(^Binary_Expr)node
		get_document_position(n.left, position_context)
		get_document_position(n.right, position_context)
	case ^Paren_Expr:
		get_document_position(n.expr, position_context)
	case ^Call_Expr:
		if position_context.hint == .SignatureHelp ||
		   position_context.hint == .Completion ||
		   position_context.hint == .Definition {
			position_context.call = cast(^Expr)node
		}
		get_document_position(n.expr, position_context)
		get_document_position(n.args, position_context)
	case ^Selector_Call_Expr:
		if position_context.hint == .Definition ||
		   position_context.hint == .Hover ||
		   position_context.hint == .SignatureHelp ||
		   position_context.hint == .Completion {
			position_context.selector = n.expr
			position_context.field = n.call
			position_context.selector_expr = cast(^Selector_Expr)node

			if _, ok := n.call.derived.(^ast.Call_Expr); ok {
				position_context.call = n.call
			}

			get_document_position(n.expr, position_context)
			get_document_position(n.call, position_context)

			if position_context.hint == .SignatureHelp {
				position_context.arrow = true
			}
		}
	case ^Selector_Expr:
		if position_context.hint == .Completion {
			if n.field != nil &&
			   n.field.pos.line - 1 == position_context.line {
				//The parser is not fault tolerant enough, relying on the fallback as the main completion parsing for now
				//position_context.selector = n.expr;
				//position_context.field = n.field;
			}
		} else if position_context.hint == .Definition ||
		   position_context.hint == .Hover && n.field != nil {
			position_context.selector = n.expr
			position_context.field = n.field
			position_context.selector_expr = cast(^Selector_Expr)node
			get_document_position(n.expr, position_context)
			get_document_position(n.field, position_context)
		} else {
			get_document_position(n.expr, position_context)
			get_document_position(n.field, position_context)
		}
	case ^Index_Expr:
		get_document_position(n.expr, position_context)
		get_document_position(n.index, position_context)
	case ^Deref_Expr:
		get_document_position(n.expr, position_context)
	case ^Slice_Expr:
		get_document_position(n.expr, position_context)
		get_document_position(n.low, position_context)
		get_document_position(n.high, position_context)
	case ^Field_Value:
		position_context.field_value = cast(^Field_Value)node
		get_document_position(n.field, position_context)
		get_document_position(n.value, position_context)
	case ^Ternary_If_Expr:
		get_document_position(n.x, position_context)
		get_document_position(n.cond, position_context)
		get_document_position(n.y, position_context)
	case ^Ternary_When_Expr:
		get_document_position(n.x, position_context)
		get_document_position(n.cond, position_context)
		get_document_position(n.y, position_context)
	case ^Type_Assertion:
		get_document_position(n.expr, position_context)
		get_document_position(n.type, position_context)
	case ^Type_Cast:
		get_document_position(n.type, position_context)
		get_document_position(n.expr, position_context)
	case ^Auto_Cast:
		get_document_position(n.expr, position_context)
	case ^Bad_Stmt:
	case ^Empty_Stmt:
	case ^Expr_Stmt:
		get_document_position(n.expr, position_context)
	case ^Tag_Stmt:
		r := cast(^Tag_Stmt)node
		get_document_position(r.stmt, position_context)
	case ^Assign_Stmt:
		position_context.assign = cast(^Assign_Stmt)node
		get_document_position(n.lhs, position_context)
		get_document_position(n.rhs, position_context)
	case ^Block_Stmt:
		get_document_position(n.label, position_context)
		get_document_position(n.stmts, position_context)
	case ^If_Stmt:
		get_document_position(n.label, position_context)
		get_document_position(n.init, position_context)
		get_document_position(n.cond, position_context)
		get_document_position(n.body, position_context)
		get_document_position(n.else_stmt, position_context)
	case ^When_Stmt:
		get_document_position(n.cond, position_context)
		get_document_position(n.body, position_context)
		get_document_position(n.else_stmt, position_context)
	case ^Return_Stmt:
		position_context.returns = cast(^Return_Stmt)node
		get_document_position(n.results, position_context)
	case ^Defer_Stmt:
		get_document_position(n.stmt, position_context)
	case ^For_Stmt:
		get_document_position(n.label, position_context)
		get_document_position(n.init, position_context)
		get_document_position(n.cond, position_context)
		get_document_position(n.post, position_context)
		get_document_position(n.body, position_context)
	case ^Range_Stmt:
		get_document_position(n.label, position_context)
		get_document_position(n.vals, position_context)
		get_document_position(n.expr, position_context)
		get_document_position(n.body, position_context)
	case ^Case_Clause:
		for elem in n.list {
			if position_in_node(elem, position_context.position) {
				position_context.case_clause = cast(^Case_Clause)node
				break
			}
		}

		get_document_position(n.list, position_context)
		get_document_position(n.body, position_context)
	case ^Switch_Stmt:
		position_context.switch_stmt = cast(^Switch_Stmt)node
		get_document_position(n.label, position_context)
		get_document_position(n.init, position_context)
		get_document_position(n.cond, position_context)
		get_document_position(n.body, position_context)
	case ^Type_Switch_Stmt:
		position_context.switch_type_stmt = cast(^Type_Switch_Stmt)node
		get_document_position(n.label, position_context)
		get_document_position(n.tag, position_context)
		get_document_position(n.expr, position_context)
		get_document_position(n.body, position_context)
	case ^Branch_Stmt:
		get_document_position(n.label, position_context)
	case ^Using_Stmt:
		get_document_position(n.list, position_context)
	case ^Bad_Decl:
	case ^Value_Decl:
		position_context.value_decl = cast(^Value_Decl)node
		get_document_position(n.attributes, position_context)

		for name in n.names {
			if position_in_node(name, position_context.position) &&
			   n.end.line - 1 == position_context.line {
				position_context.abort_completion = true
				break
			}
		}
		get_document_position(n.names, position_context)
		get_document_position(n.type, position_context)
		get_document_position(n.values, position_context)
	case ^Package_Decl:
	case ^Import_Decl:
	case ^Foreign_Block_Decl:
		get_document_position(n.attributes, position_context)
		get_document_position(n.foreign_library, position_context)
		get_document_position(n.body, position_context)
	case ^Foreign_Import_Decl:
		get_document_position(n.name, position_context)
	case ^Proc_Group:
		get_document_position(n.args, position_context)
	case ^Attribute:
		get_document_position(n.elems, position_context)
	case ^Field:
		get_document_position(n.names, position_context)
		get_document_position(n.type, position_context)
		get_document_position(n.default_value, position_context)
	case ^Field_List:
		get_document_position(n.list, position_context)
	case ^Typeid_Type:
		get_document_position(n.specialization, position_context)
	case ^Helper_Type:
		get_document_position(n.type, position_context)
	case ^Distinct_Type:
		get_document_position(n.type, position_context)
	case ^Poly_Type:
		get_document_position(n.type, position_context)
		get_document_position(n.specialization, position_context)
	case ^Proc_Type:
		get_document_position(n.params, position_context)
		get_document_position(n.results, position_context)
	case ^Pointer_Type:
		get_document_position(n.elem, position_context)
	case ^Array_Type:
		get_document_position(n.len, position_context)
		get_document_position(n.elem, position_context)
	case ^Dynamic_Array_Type:
		get_document_position(n.elem, position_context)
	case ^Multi_Pointer_Type:
		get_document_position(n.elem, position_context)
	case ^Struct_Type:
		position_context.struct_type = cast(^Struct_Type)node
		get_document_position(n.poly_params, position_context)
		get_document_position(n.align, position_context)
		get_document_position(n.fields, position_context)
	case ^Union_Type:
		position_context.union_type = cast(^Union_Type)node
		get_document_position(n.poly_params, position_context)
		get_document_position(n.align, position_context)
		get_document_position(n.variants, position_context)
	case ^Enum_Type:
		position_context.enum_type = cast(^Enum_Type)node
		get_document_position(n.base_type, position_context)
		get_document_position(n.fields, position_context)
	case ^Bit_Set_Type:
		position_context.bitset_type = cast(^Bit_Set_Type)node
		get_document_position(n.elem, position_context)
		get_document_position(n.underlying, position_context)
	case ^Map_Type:
		get_document_position(n.key, position_context)
		get_document_position(n.value, position_context)
	case ^Implicit_Selector_Expr:
		position_context.implicit = true
		position_context.implicit_selector_expr = n
		get_document_position(n.field, position_context)
	case ^ast.Or_Else_Expr:
		get_document_position(n.x, position_context)
		get_document_position(n.y, position_context)
	case ^ast.Or_Return_Expr:
		get_document_position(n.expr, position_context)
	case:
	}
}
