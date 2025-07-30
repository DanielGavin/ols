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
	nested_position:        common.AbsolutePosition, //When doing the non-mutable local gathering we still need to know where in the nested block the position is.
	line:                   int,
	function:               ^ast.Proc_Lit, //used to help with type resolving in function scope
	functions:              [dynamic]^ast.Proc_Lit, //stores all the functions that have been iterated through to find the position
	selector:               ^ast.Expr, //used for completion
	selector_expr:          ^ast.Node,
	identifier:             ^ast.Node,
	label:                  ^ast.Ident,
	implicit_context:       ^ast.Implicit,
	index:                  ^ast.Index_Expr,
	previous_index:         ^ast.Index_Expr,
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
	bit_field_type:         ^ast.Bit_Field_Type,
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
	pkg:             string,
	variable:        bool,
	parameter:       bool,
}

DeferredDepth :: 35

LocalGroup :: map[string][dynamic]DocumentLocal

UsingStatement :: struct {
	alias:    string,
	pkg_name: string,
}

AstContext :: struct {
	locals:           [dynamic]LocalGroup, //locals all the way to the document position
	globals:          map[string]GlobalExpr,
	recursion_map:    map[rawptr]bool,
	usings:           [dynamic]UsingStatement,
	file:             ast.File,
	allocator:        mem.Allocator,
	imports:          []Package, //imports for the current document
	current_package:  string,
	document_package: string,
	deferred_package: [DeferredDepth]string, //When a package change happens when resolving
	deferred_count:   int,
	use_locals:       bool,
	call:             ^ast.Call_Expr, //used to determine the types for generics and the correct function for overloaded functions
	value_decl:       ^ast.Value_Decl,
	field_name:       ast.Ident,
	uri:              string,
	fullpath:         string,
	non_mutable_only: bool, //Only store local value declarations that are non mutable.
	overloading:      bool,
	position_hint:    DocumentPositionContextHint,
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
		locals           = make([dynamic]map[string][dynamic]DocumentLocal, 0, allocator),
		globals          = make(map[string]GlobalExpr, 0, allocator),
		usings           = make([dynamic]UsingStatement, allocator),
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

	add_local_group(&ast_context)

	return ast_context
}

add_using :: proc(ast_context: ^AstContext, using_name: string, pkg_name: string) {
	for u in ast_context.usings {
		if u.alias == using_name {
			return
		}
	}

	append(&ast_context.usings, UsingStatement{alias = using_name, pkg_name = pkg_name})
}

set_ast_package_deferred :: proc(ast_context: ^AstContext, pkg: string) {
	if ast_context.deferred_count <= 0 {
		return
	}
	ast_context.deferred_count -= 1
	ast_context.current_package = ast_context.deferred_package[ast_context.deferred_count]
}

@(deferred_in = set_ast_package_deferred)
set_ast_package_set_scoped :: proc(ast_context: ^AstContext, pkg: string) {
	if ast_context.deferred_count >= DeferredDepth {
		return
	}
	ast_context.deferred_package[ast_context.deferred_count] = ast_context.current_package
	ast_context.deferred_count += 1
	ast_context.current_package = pkg
}

set_ast_package_none_deferred :: proc(ast_context: ^AstContext) {
	if ast_context.deferred_count <= 0 {
		return
	}
	ast_context.deferred_count -= 1
	ast_context.current_package = ast_context.deferred_package[ast_context.deferred_count]
}

@(deferred_in = set_ast_package_none_deferred)
set_ast_package_scoped :: proc(ast_context: ^AstContext) {
	if ast_context.deferred_count >= DeferredDepth {
		return
	}
	ast_context.deferred_package[ast_context.deferred_count] = ast_context.current_package
	ast_context.deferred_count += 1
}

set_ast_package_from_symbol_deferred :: proc(ast_context: ^AstContext, symbol: Symbol) {
	if ast_context.deferred_count <= 0 {
		return
	}
	ast_context.deferred_count -= 1
	ast_context.current_package = ast_context.deferred_package[ast_context.deferred_count]
}

@(deferred_in = set_ast_package_from_symbol_deferred)
set_ast_package_from_symbol_scoped :: proc(ast_context: ^AstContext, symbol: Symbol) {
	if ast_context.deferred_count >= DeferredDepth {
		return
	}

	ast_context.deferred_package[ast_context.deferred_count] = ast_context.current_package
	ast_context.deferred_count += 1

	if symbol.pkg != "" {
		ast_context.current_package = symbol.pkg
	} else {
		ast_context.current_package = ast_context.document_package
	}
}

set_ast_package_from_node_deferred :: proc(ast_context: ^AstContext, node: ast.Node) {
	if ast_context.deferred_count <= 0 {
		return
	}
	ast_context.deferred_count -= 1
	ast_context.current_package = ast_context.deferred_package[ast_context.deferred_count]
}

@(deferred_in = set_ast_package_from_node_deferred)
set_ast_package_from_node_scoped :: proc(ast_context: ^AstContext, node: ast.Node) {
	if ast_context.deferred_count >= DeferredDepth {
		return
	}

	ast_context.deferred_package[ast_context.deferred_count] = ast_context.current_package
	ast_context.deferred_count += 1
	pkg := get_package_from_node(node)

	if pkg != "" && pkg != "." {
		ast_context.current_package = pkg
	} else {
		ast_context.current_package = ast_context.document_package
	}
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
	// If the symbol is a MultiPointerValue, we retrieve the symbol of the underlying expression and
	// retry with that.
	if s, ok := current_symbol.value.(SymbolMultiPointerValue); ok {
		if symbol, ok := resolve_type_expression(ast_context, s.expr); ok {
			return resolve_type_comp_literal(ast_context, position_context, symbol, current_comp_lit)
		}
	}

	if position_context.comp_lit == current_comp_lit {
		return current_symbol, current_comp_lit, true
	} else if current_comp_lit == nil {
		return {}, nil, false
	}

	set_ast_package_set_scoped(ast_context, current_symbol.pkg)

	for elem, element_index in current_comp_lit.elems {
		if !position_in_node(elem, position_context.position) {
			continue
		}

		if field_value, ok := elem.derived.(^ast.Field_Value); ok { 	//named
			if comp_lit, ref_n, ok := unwrap_comp_literal(field_value.value); ok {
				if s, ok := current_symbol.value.(SymbolStructValue); ok {
					for name, i in s.names {
						// TODO: may need to handle the other cases
						if field_name, ok := field_value.field.derived.(^ast.Ident); ok {
							if name == field_name.name {
								if symbol, ok := resolve_type_expression(ast_context, s.types[i]); ok {
									//Stop at bitset, because we don't want to enter a comp_lit of a bitset
									if _, ok := symbol.value.(SymbolBitSetValue); ok {
										return current_symbol, current_comp_lit, true
									}

									//If we get an union, we just need return the argument expression in the union.
									if _, ok := symbol.value.(SymbolUnionValue); ok {
										if call_expr, ok := s.types[i].derived.(^ast.Call_Expr);
										   ok && len(call_expr.args) == 1 {
											if symbol, ok := resolve_type_expression(ast_context, call_expr.args[0]);
											   ok {
												return resolve_type_comp_literal(
													ast_context,
													position_context,
													symbol,
													cast(^ast.Comp_Lit)field_value.value,
												)
											}
										}
									}

									return resolve_type_comp_literal(ast_context, position_context, symbol, comp_lit)
								}
							}
						}
					}
				} else if s, ok := current_symbol.value.(SymbolBitFieldValue); ok {
					for name, i in s.names {
						if field_name, ok := field_value.field.derived.(^ast.Ident); ok {
							if name == field_name.name {
								if symbol, ok := resolve_type_expression(ast_context, s.types[i]); ok {
									//Stop at bitset, because we don't want to enter a comp_lit of a bitset
									if _, ok := symbol.value.(SymbolBitSetValue); ok {
										return current_symbol, current_comp_lit, true
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
				} else if s, ok := current_symbol.value.(SymbolFixedArrayValue); ok {
					if symbol, ok := resolve_type_expression(ast_context, s.expr); ok {
						return resolve_type_comp_literal(ast_context, position_context, symbol, comp_lit)
					}
				}
			}
		} else if comp_value, ok := elem.derived.(^ast.Comp_Lit); ok { 	//indexed
			#partial switch s in current_symbol.value {
			case SymbolStructValue:
				return resolve_type_comp_literal(ast_context, position_context, current_symbol, comp_value)
			case SymbolBitFieldValue:
				return resolve_type_comp_literal(ast_context, position_context, current_symbol, comp_value)
			case SymbolSliceValue:
				if symbol, ok := resolve_type_expression(ast_context, s.expr); ok {
					return resolve_type_comp_literal(ast_context, position_context, symbol, comp_value)
				}

			case SymbolDynamicArrayValue:
				if symbol, ok := resolve_type_expression(ast_context, s.expr); ok {
					return resolve_type_comp_literal(ast_context, position_context, symbol, comp_value)
				}

			case SymbolFixedArrayValue:
				if symbol, ok := resolve_type_expression(ast_context, s.expr); ok {
					return resolve_type_comp_literal(ast_context, position_context, symbol, comp_value)
				}
			}
		}
	}

	return current_symbol, current_comp_lit, true
}

// NOTE: This function is not commutative
are_symbol_untyped_basic_same_typed :: proc(a, b: Symbol) -> (bool, bool) {
	if untyped, ok := a.value.(SymbolUntypedValue); ok {
		if basic, ok := b.value.(SymbolBasicValue); ok {
			switch untyped.type {
			case .Integer:
				switch basic.ident.name {
				case "int", "uint", "u8", "i8", "u16", "i16", "u32", "i32", "u64", "i64", "u128", "i128":
					return true, true
				case:
					return false, true
				}
			case .Bool:
				switch basic.ident.name {
				case "bool", "b32", "b64":
					return true, true
				case:
					return false, true
				}
			case .String:
				switch basic.ident.name {
				case "string", "cstring":
					return true, true
				case:
					return false, true
				}
			case .Float:
				switch basic.ident.name {
				case "f32", "f64":
					return true, true
				case:
					return false, true
				}
			}
		} else if untyped_b, ok := b.value.(SymbolUntypedValue); ok {
			return untyped.type == untyped_b.type, true
		}
	}
	return false, false
}

are_symbol_basic_same_keywords :: proc(a, b: Symbol) -> bool {
	if a.name != b.name {
		return false
	}
	if _, ok := a.value.(SymbolBasicValue); !ok {
		return false
	}
	if _, ok := b.value.(SymbolBasicValue); !ok {
		return false
	}
	if _, ok := keyword_map[a.name]; !ok {
		return false
	}
	if _, ok := keyword_map[b.name]; !ok {
		return false
	}

	return true
}

is_symbol_same_typed :: proc(ast_context: ^AstContext, a, b: Symbol, flags: ast.Field_Flags = {}) -> bool {
	// In order to correctly equate the symbols for overloaded functions, we need to check both directions
	if same, ok := are_symbol_untyped_basic_same_typed(a, b); ok {
		return same
	} else if same, ok := are_symbol_untyped_basic_same_typed(b, a); ok {
		return same
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

	if .Distinct in a.flags == .Distinct in b.flags && .Distinct in a.flags && a.name == b.name && a.pkg == b.pkg {
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

	if are_symbol_basic_same_keywords(a, b) {
		return true
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

		set_ast_package_from_symbol_scoped(ast_context, a)

		a_symbol, ok = resolve_type_expression(ast_context, a_value.expr)

		if !ok {
			return false
		}

		set_ast_package_from_symbol_scoped(ast_context, b)

		b_symbol, ok = resolve_type_expression(ast_context, b_value.expr)

		if !ok {
			return false
		}

		a_is_soa := .Soa in a_symbol.flags
		b_is_soa := .Soa in a_symbol.flags

		return is_symbol_same_typed(ast_context, a_symbol, b_symbol) && a_is_soa == b_is_soa
	case SymbolFixedArrayValue:
		b_value := b.value.(SymbolFixedArrayValue)

		a_symbol: Symbol
		b_symbol: Symbol
		ok: bool

		set_ast_package_from_symbol_scoped(ast_context, a)

		a_symbol, ok = resolve_type_expression(ast_context, a_value.expr)

		if !ok {
			return false
		}

		set_ast_package_from_symbol_scoped(ast_context, b)

		b_symbol, ok = resolve_type_expression(ast_context, b_value.expr)

		if !ok {
			return false
		}

		return is_symbol_same_typed(ast_context, a_symbol, b_symbol)
	case SymbolMultiPointerValue:
		b_value := b.value.(SymbolMultiPointerValue)

		a_symbol: Symbol
		b_symbol: Symbol
		ok: bool

		set_ast_package_from_symbol_scoped(ast_context, a)

		a_symbol, ok = resolve_type_expression(ast_context, a_value.expr)

		if !ok {
			return false
		}

		set_ast_package_from_symbol_scoped(ast_context, b)

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

		set_ast_package_from_symbol_scoped(ast_context, a)

		a_symbol, ok = resolve_type_expression(ast_context, a_value.expr)

		if !ok {
			return false
		}

		set_ast_package_from_symbol_scoped(ast_context, b)

		b_symbol, ok = resolve_type_expression(ast_context, b_value.expr)

		if !ok {
			return false
		}

		a_is_soa := .Soa in a_symbol.flags
		b_is_soa := .Soa in a_symbol.flags

		return is_symbol_same_typed(ast_context, a_symbol, b_symbol) && a_is_soa == b_is_soa
	case SymbolMapValue:
		b_value := b.value.(SymbolMapValue)

		a_key_symbol: Symbol
		b_key_symbol: Symbol
		a_value_symbol: Symbol
		b_value_symbol: Symbol
		ok: bool

		set_ast_package_from_symbol_scoped(ast_context, a)

		a_key_symbol, ok = resolve_type_expression(ast_context, a_value.key)

		if !ok {
			return false
		}

		set_ast_package_from_symbol_scoped(ast_context, b)

		b_key_symbol, ok = resolve_type_expression(ast_context, b_value.key)

		if !ok {
			return false
		}

		set_ast_package_from_symbol_scoped(ast_context, a)


		a_value_symbol, ok = resolve_type_expression(ast_context, a_value.value)

		if !ok {
			return false
		}

		set_ast_package_from_symbol_scoped(ast_context, b)

		b_value_symbol, ok = resolve_type_expression(ast_context, b_value.value)

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

get_field_list_name_index :: proc(name: string, field_list: []^ast.Field) -> (int, bool) {
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

get_unnamed_arg_count :: proc(args: []^ast.Expr) -> int {
	total := 0
	for arg in args {
		if field, is_field := arg.derived.(^ast.Field_Value); !is_field {
			total += 1
		}
	}
	return total
}

Candidate :: struct {
	symbol: Symbol,
	score:  int,
}

get_top_candiate :: proc(candidates: []Candidate) -> (Candidate, bool) {
	if len(candidates) == 0 {
		return {}, false
	}

	top := candidates[0]
	for candidate in candidates {
		if candidate.score < top.score {
			top = candidate
		}
	}
	return top, true
}

/*
	Figure out which function the call expression is using out of the list from proc group
*/
resolve_function_overload :: proc(ast_context: ^AstContext, group: ast.Proc_Group) -> (Symbol, bool) {
	old_overloading := ast_context.overloading
	ast_context.overloading = true

	defer {
		ast_context.overloading = old_overloading
	}

	call_expr := ast_context.call

	if call_expr == nil || len(call_expr.args) == 0 {
		ast_context.overloading = false
	}

	resolve_all_possibilities :=
		ast_context.position_hint == .Completion || ast_context.position_hint == .SignatureHelp || call_expr == nil

	call_unnamed_arg_count := 0
	if call_expr != nil {
		call_unnamed_arg_count = get_unnamed_arg_count(call_expr.args)
	}

	candidates := make([dynamic]Candidate, context.temp_allocator)

	for arg_expr in group.args {
		next_fn: if f, ok := internal_resolve_type_expression(ast_context, arg_expr); ok {
			candidate := Candidate {
				symbol = f,
				score  = 1,
			}
			if call_expr == nil || (resolve_all_possibilities && len(call_expr.args) == 0) {
				append(&candidates, candidate)
				break next_fn
			}
			if procedure, ok := f.value.(SymbolProcedureValue); ok {
				i := 0
				named := false

				if !resolve_all_possibilities {
					arg_count := get_proc_arg_count(procedure)
					if call_expr != nil && arg_count < call_unnamed_arg_count {
						break next_fn
					}
				}
				for proc_arg in procedure.arg_types {
					for name in proc_arg.names {
						if i >= len(call_expr.args) {
							continue
						}

						call_arg := call_expr.args[i]

						ast_context.use_locals = true

						call_symbol: Symbol
						arg_symbol: Symbol
						ok: bool

						if _, ok = call_arg.derived.(^ast.Bad_Expr); ok {
							continue
						}

						//named parameter
						if field, is_field := call_arg.derived.(^ast.Field_Value); is_field {
							named = true
							call_symbol, ok = resolve_call_arg_type_expression(ast_context, field.value)
							if !ok {
								break next_fn
							}

							if ident, is_ident := field.field.derived.(^ast.Ident); is_ident {
								i, ok = get_field_list_name_index(
									field.field.derived.(^ast.Ident).name,
									procedure.arg_types,
								)
							} else {
								break next_fn
							}
						} else {
							if named {
								log.error("Expected name parameter after starting named parmeter phase")
								return {}, false
							}
							call_symbol, ok = resolve_call_arg_type_expression(ast_context, call_arg)
						}

						if !ok {
							break next_fn
						}

						if p, ok := call_symbol.value.(SymbolProcedureValue); ok {
							if len(p.return_types) != 1 {
								break next_fn
							}
							if s, ok := resolve_call_arg_type_expression(ast_context, p.return_types[0].type); ok {
								call_symbol = s
							}
						}

						proc_arg := proc_arg

						if named {
							proc_arg = procedure.arg_types[i]
						}

						if proc_arg.type != nil {
							arg_symbol, ok = resolve_call_arg_type_expression(ast_context, proc_arg.type)
						} else {
							arg_symbol, ok = resolve_call_arg_type_expression(ast_context, proc_arg.default_value)
						}

						if !ok {
							break next_fn
						}

						if !is_symbol_same_typed(ast_context, call_symbol, arg_symbol, proc_arg.flags) {
							found := false
							// Are we a union variant
							if value, ok := arg_symbol.value.(SymbolUnionValue); ok {
								for variant in value.types {
									if symbol, ok := resolve_type_expression(ast_context, variant); ok {
										if is_symbol_same_typed(ast_context, call_symbol, symbol, proc_arg.flags) {
											// matching union types are a low priority
											candidate.score = 1000000
											found = true
											break
										}
									}
								}
							}

							// Do we contain a using that matches
							if value, ok := call_symbol.value.(SymbolStructValue); ok {
								using_score := 1000000
								for k in value.usings {
									if symbol, ok := resolve_type_expression(ast_context, value.types[k]); ok {
										symbol.pointers = call_symbol.pointers
										if is_symbol_same_typed(ast_context, symbol, arg_symbol, proc_arg.flags) {
											if k < using_score {
												using_score = k
											}
											found = true
										}
									}
								}
								candidate.score = using_score
							}

							if !found {
								break next_fn
							}
						}

						i += 1
					}
				}

				append(&candidates, candidate)
			}
		}
	}

	if candidate, ok := get_top_candiate(candidates[:]); ok {
		if !resolve_all_possibilities {
			return candidate.symbol, true
		} else if len(candidates) > 1 {
			symbols := make([dynamic]Symbol, context.temp_allocator)
			for c in candidates {
				append(&symbols, c.symbol)
			}
			return Symbol {
					type = candidate.symbol.type,
					name = candidate.symbol.name,
					pkg = candidate.symbol.pkg,
					uri = candidate.symbol.uri,
					value = SymbolAggregateValue{symbols = symbols[:]},
				},
				true
		} else if len(candidates) == 1 {
			return candidate.symbol, true
		}
	}


	return Symbol{}, false
}

resolve_call_arg_type_expression :: proc(ast_context: ^AstContext, node: ^ast.Expr) -> (Symbol, bool) {
	old_current_package := ast_context.current_package
	ast_context.current_package = ast_context.document_package
	defer {
		ast_context.current_package = old_current_package
	}

	return resolve_type_expression(ast_context, node)
}

resolve_basic_lit :: proc(ast_context: ^AstContext, basic_lit: ast.Basic_Lit) -> (Symbol, bool) {
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
		ident := new_type(ast.Ident, directive.pos, directive.end, ast_context.allocator)
		ident.name = "Source_Code_Location"
		set_ast_package_set_scoped(ast_context, ast_context.document_package)
		return internal_resolve_type_identifier(ast_context, ident^)
	}

	return {}, false
}

// Gets the return type of the proc.
// Requires the underlying call expression to handle some builtin procs
get_proc_return_types :: proc(
	ast_context: ^AstContext,
	symbol: Symbol,
	call: ^ast.Call_Expr,
	is_mutable: bool,
) -> []^ast.Expr {
	return_types := make([dynamic]^ast.Expr, context.temp_allocator)
	if ret, ok := check_builtin_proc_return_type(symbol, call, is_mutable); ok {
		if call, ok := ret.derived.(^ast.Call_Expr); ok {
			if symbol, ok := internal_resolve_type_expression(ast_context, call.expr); ok {
				return get_proc_return_types(ast_context, symbol, call, true)
			}
		}
		append(&return_types, ret)
	} else if v, ok := symbol.value.(SymbolProcedureValue); ok {
		for ret in v.return_types {
			if ret.type != nil {
				append(&return_types, ret.type)
			} else if ret.default_value != nil {
				append(&return_types, ret.default_value)
			}
		}
	}

	return return_types[:]
}

// Attempts to resolve the type of the builtin proc by following the rules of the odin type checker
// defined in `check_builtin.cpp`.
// We don't need to worry about whether the inputs to the procs are valid which eliminates most edge cases.
// The basic rules are as follows:
//    - For values not known at compile time (eg values return from procs), just return that type.
//        The correct value will either be that type or a compiler error.
//    - If all values are known at compile time, then we essentially compute the relevant value
//        and return that type.
// There is a difference in the returned types between constants and variables. Constants will use an untyped
// value whereas variables will be typed (as either `int` or `f64`).
check_builtin_proc_return_type :: proc(symbol: Symbol, call: ^ast.Call_Expr, is_mutable: bool) -> (^ast.Expr, bool) {
	convert_candidate :: proc(candidate: ^ast.Basic_Lit, is_mutable: bool) -> ^ast.Expr {
		if is_mutable {
			ident := ast.new(ast.Ident, candidate.pos, candidate.end)
			if candidate.tok.kind == .Integer {
				ident.name = "int"
			} else {
				ident.name = "f64"
			}
			return ident
		}

		return candidate
	}

	compare_basic_lit_value :: proc(a, b: f64, name: string) -> bool {
		if name == "max" {
			return a > b
		} else if name == "min" {
			return a < b
		}
		return a > b
	}

	get_basic_lit_value :: proc(n: ^ast.Expr) -> (^ast.Basic_Lit, f64, bool) {
		n := n

		op := ""
		if u, ok := n.derived.(^ast.Unary_Expr); ok {
			op = u.op.text
			n = u.expr
		}

		if lit, ok := n.derived.(^ast.Basic_Lit); ok {
			text := lit.tok.text
			if op != "" {
				text = fmt.tprintf("%s%s", op, text)
			}
			value, ok := strconv.parse_f64(text)
			if !ok {
				return nil, 0, false
			}

			return lit, value, true
		}

		return nil, 0, false
	}

	if symbol.pkg == "$builtin" {
		switch symbol.name {
		case "max", "min":
			curr_candidate: ^ast.Basic_Lit
			curr_value := 0.0
			for arg, i in call.args {
				if lit, value, ok := get_basic_lit_value(arg); ok {
					if i != 0 {
						if compare_basic_lit_value(value, curr_value, symbol.name) {
							curr_candidate = lit
							curr_value = value
						}
					} else {
						curr_candidate = lit
						curr_value = value
					}
				}
				if lit, ok := arg.derived.(^ast.Basic_Lit); ok {
				} else {
					return arg, true
				}
			}
			if curr_candidate != nil {
				return convert_candidate(curr_candidate, is_mutable), true
			}
		case "abs":
			for arg in call.args {
				if lit, _, ok := get_basic_lit_value(arg); ok {
					return convert_candidate(lit, is_mutable), true
				}
				return arg, true
			}
		case "clamp":
			if len(call.args) == 3 {

				value_lit, value_value, value_ok := get_basic_lit_value(call.args[0])
				if !value_ok {
					return call.args[0], true
				}

				minimum_lit, minimum_value, minimum_ok := get_basic_lit_value(call.args[1])
				if !minimum_ok {
					return call.args[1], true
				}

				maximum_lit, maximum_value, maximum_ok := get_basic_lit_value(call.args[2])
				if !maximum_ok {
					return call.args[2], true
				}

				if value_value < minimum_value {
					return convert_candidate(minimum_lit, is_mutable), true
				}
				if value_value > maximum_value {
					return convert_candidate(maximum_lit, is_mutable), true
				}

				return convert_candidate(value_lit, is_mutable), true
			}
		}

	}

	return nil, false
}

check_node_recursion :: proc(ast_context: ^AstContext, node: ^ast.Node) -> bool {
	raw := cast(rawptr)node

	if raw in ast_context.recursion_map {
		return true
	}

	ast_context.recursion_map[raw] = true

	return false
}

// Resolves the location of the underlying type of the expression
resolve_location_type_expression :: proc(ast_context: ^AstContext, node: ^ast.Expr) -> (Symbol, bool) {
	if node == nil {
		return {}, false
	}

	//Try to prevent stack overflows and prevent indexing out of bounds.
	if ast_context.deferred_count >= DeferredDepth {
		return {}, false
	}

	set_ast_package_scoped(ast_context)

	if check_node_recursion(ast_context, node) {
		return {}, false
	}

	// TODO: there is likely more of these that will need to be added
	#partial switch n in node.derived {
	case ^ast.Ident:
		if _, ok := keyword_map[n.name]; ok {
			return {}, true
		}
		return resolve_location_type_identifier(ast_context, n^)
	case ^ast.Basic_Lit:
		return {}, true
	case ^ast.Array_Type:
		return resolve_location_type_expression(ast_context, n.elem)
	case ^ast.Dynamic_Array_Type:
		return resolve_location_type_expression(ast_context, n.elem)
	case ^ast.Pointer_Type:
		return resolve_location_type_expression(ast_context, n.elem)
	case ^ast.Multi_Pointer_Type:
		return resolve_location_type_expression(ast_context, n.elem)
	case ^ast.Comp_Lit:
		return resolve_location_type_expression(ast_context, n.type)
	}
	return resolve_type_expression(ast_context, node)
}

resolve_type_expression :: proc(ast_context: ^AstContext, node: ^ast.Expr) -> (Symbol, bool) {
	clear(&ast_context.recursion_map)
	return internal_resolve_type_expression(ast_context, node)
}

internal_resolve_type_expression :: proc(ast_context: ^AstContext, node: ^ast.Expr) -> (Symbol, bool) {
	if node == nil {
		return {}, false
	}

	//Try to prevent stack overflows and prevent indexing out of bounds.
	if ast_context.deferred_count >= DeferredDepth {
		return {}, false
	}

	set_ast_package_from_node_scoped(ast_context, node)

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
		return make_symbol_union_from_ast(ast_context, v^, ast_context.field_name, true), true
	case ^Enum_Type:
		return make_symbol_enum_from_ast(ast_context, v^, ast_context.field_name, true), true
	case ^Struct_Type:
		return make_symbol_struct_from_ast(ast_context, v, ast_context.field_name, {}, true), true
	case ^Bit_Set_Type:
		return make_symbol_bitset_from_ast(ast_context, v^, ast_context.field_name, true), true
	case ^Array_Type:
		return make_symbol_array_from_ast(ast_context, v^, ast_context.field_name), true
	case ^Matrix_Type:
		return make_symbol_matrix_from_ast(ast_context, v^, ast_context.field_name), true
	case ^Dynamic_Array_Type:
		return make_symbol_dynamic_array_from_ast(ast_context, v^, ast_context.field_name), true
	case ^Multi_Pointer_Type:
		return make_symbol_multi_pointer_from_ast(ast_context, v^, ast_context.field_name), true
	case ^Map_Type:
		return make_symbol_map_from_ast(ast_context, v^, ast_context.field_name), true
	case ^Proc_Type:
		return make_symbol_procedure_from_ast(ast_context, node, v^, ast_context.field_name, {}, true, .None), true
	case ^Bit_Field_Type:
		return make_symbol_bit_field_from_ast(ast_context, v, ast_context.field_name, true), true
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
				if symbol, ok := internal_resolve_type_expression(ast_context, v.expr); ok {
					//To handle type assertions for unions, i.e. my_maybe_variable.?
					if union_value, ok := symbol.value.(SymbolUnionValue); ok {
						if len(union_value.types) != 1 {
							return {}, false
						}
						return internal_resolve_type_expression(ast_context, union_value.types[0])
					} else if proc_value, ok := symbol.value.(SymbolProcedureValue); ok {
						//To handle type assertions for unions returned from procedures, i.e: my_function().?
						if len(proc_value.return_types) != 1 || proc_value.return_types[0].type == nil {
							return {}, false
						}

						if symbol, ok := internal_resolve_type_expression(
							ast_context,
							proc_value.return_types[0].type,
						); ok {
							if union_value, ok := symbol.value.(SymbolUnionValue); ok {
								if len(union_value.types) != 1 {
									return {}, false
								}
								return internal_resolve_type_expression(ast_context, union_value.types[0])
							}
						}
					}

				}
			}
		} else {
			return internal_resolve_type_expression(ast_context, v.type)
		}
	case ^Proc_Lit:
		if v.type.results != nil {
			if len(v.type.results.list) > 0 {
				return internal_resolve_type_expression(ast_context, v.type.results.list[0].type)
			}
		}
	case ^Pointer_Type:
		symbol, ok := internal_resolve_type_expression(ast_context, v.elem)
		symbol.pointers += 1
		return symbol, ok
	case ^Matrix_Index_Expr:
		if symbol, ok := internal_resolve_type_expression(ast_context, v.expr); ok {
			if mat, ok := symbol.value.(SymbolMatrixValue); ok {
				return internal_resolve_type_expression(ast_context, mat.expr)
			}
		}
	case ^Index_Expr:
		indexed, ok := internal_resolve_type_expression(ast_context, v.expr)

		if !ok {
			return {}, false
		}

		set_ast_package_set_scoped(ast_context, indexed.pkg)

		symbol: Symbol

		#partial switch v2 in indexed.value {
		case SymbolDynamicArrayValue:
			symbol, ok = internal_resolve_type_expression(ast_context, v2.expr)
		case SymbolSliceValue:
			symbol, ok = internal_resolve_type_expression(ast_context, v2.expr)
		case SymbolFixedArrayValue:
			symbol, ok = internal_resolve_type_expression(ast_context, v2.expr)
		case SymbolMapValue:
			symbol, ok = internal_resolve_type_expression(ast_context, v2.value)
		case SymbolMultiPointerValue:
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
		if selector, ok := internal_resolve_type_expression(ast_context, v.expr); ok {
			ast_context.use_locals = false

			set_ast_package_from_symbol_scoped(ast_context, selector)

			#partial switch s in selector.value {
			case SymbolProcedureValue:
				if len(s.return_types) == 1 {
					return internal_resolve_type_expression(ast_context, s.return_types[0].type)
				}
			}

			return selector, true
		}
	case ^Selector_Expr:
		return resolve_selector_expression(ast_context, v)
	case ^ast.Poly_Type:
		if v.specialization != nil {
			return internal_resolve_type_expression(ast_context, v.specialization)
		}

	case:
		log.warnf("default node kind, internal_resolve_type_expression: %v", v)
	}

	return Symbol{}, false
}

resolve_selector_expression :: proc(ast_context: ^AstContext, node: ^ast.Selector_Expr) -> (Symbol, bool) {
	if selector, ok := internal_resolve_type_expression(ast_context, node.expr); ok {
		ast_context.use_locals = false

		set_ast_package_from_symbol_scoped(ast_context, selector)

		#partial switch s in selector.value {
		case SymbolFixedArrayValue:
			components_count := 0
			for c in node.field.name {
				if c == 'x' || c == 'y' || c == 'z' || c == 'w' || c == 'r' || c == 'g' || c == 'b' || c == 'a' {
					components_count += 1
				} else {
					return {}, false
				}
			}

			if components_count == 0 {
				return {}, false
			}

			if components_count == 1 {
				set_ast_package_from_symbol_scoped(ast_context, selector)

				symbol, ok := internal_resolve_type_expression(ast_context, s.expr)
				symbol.type = .Variable
				return symbol, ok
			} else {
				value := SymbolFixedArrayValue {
					expr = s.expr,
					len  = make_int_basic_value(ast_context, components_count, s.len.pos, s.len.end),
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
				selector_expr.field = node.field
				return internal_resolve_type_expression(ast_context, selector_expr)
			}
		case SymbolStructValue:
			for name, i in s.names {
				if node.field != nil && name == node.field.name {
					set_ast_package_from_node_scoped(ast_context, s.types[i])
					ast_context.field_name = node.field^
					symbol, ok := internal_resolve_type_expression(ast_context, s.types[i])
					symbol.type = .Variable
					return symbol, ok
				}
			}
		case SymbolBitFieldValue:
			for name, i in s.names {
				if node.field != nil && name == node.field.name {
					ast_context.field_name = node.field^
					symbol, ok := internal_resolve_type_expression(ast_context, s.types[i])
					symbol.type = .Variable
					return symbol, ok
				}
			}
		case SymbolPackageValue:
			try_build_package(ast_context.current_package)

			if node.field != nil {
				return resolve_symbol_return(ast_context, lookup(node.field.name, selector.pkg))
			} else {
				return Symbol{}, false
			}
		case SymbolEnumValue:
			// enum members probably require own symbol value
			selector.type = .EnumMember
			return selector, true
		}
	}

	return {}, false
}

// returns the symbol of the first return type of a proc
resolve_symbol_proc_first_return_symbol :: proc(ast_context: ^AstContext, symbol: Symbol) -> (Symbol, bool) {
	if v, ok := symbol.value.(SymbolProcedureValue); ok {
		if len(v.return_types) > 0 {
			if ast_context.current_package != symbol.pkg {
				current_package := ast_context.current_package
				defer {
					ast_context.current_package = current_package
				}
				ast_context.current_package = symbol.pkg
				return resolve_type_expression(ast_context, v.return_types[0].type)
			} else {
				return resolve_location_type_expression(ast_context, v.return_types[0].type)
			}
		} else {
			return {}, true
		}
	}
	return {}, false
}

store_local :: proc(
	ast_context: ^AstContext,
	lhs: ^ast.Expr,
	rhs: ^ast.Expr,
	offset: int,
	name: string,
	local_global: bool,
	resolved_global: bool,
	variable: bool,
	pkg: string,
	parameter: bool,
) {
	local_group := get_local_group(ast_context)
	local_stack := &local_group[name]

	if local_stack == nil {
		local_group[name] = make([dynamic]DocumentLocal, ast_context.allocator)
		local_stack = &local_group[name]
	}

	append(
		local_stack,
		DocumentLocal {
			lhs = lhs,
			rhs = rhs,
			offset = offset,
			resolved_global = resolved_global,
			local_global = local_global,
			pkg = pkg,
			variable = variable,
			parameter = parameter,
		},
	)
}

add_local_group :: proc(ast_context: ^AstContext) {
	append(&ast_context.locals, make(LocalGroup, 100, ast_context.allocator))
}

pop_local_group :: proc(ast_context: ^AstContext) {
	pop(&ast_context.locals)
}

get_local_group :: proc(ast_context: ^AstContext) -> ^LocalGroup {
	if len(ast_context.locals) == 0 {
		add_local_group(ast_context)
	}
	return &ast_context.locals[len(ast_context.locals) - 1]
}

get_local :: proc(ast_context: AstContext, ident: ast.Ident) -> (DocumentLocal, bool) {
	#reverse for locals in ast_context.locals {
		local_stack := locals[ident.name] or_continue

		#reverse for local in local_stack {
			// Ensure that if the identifier has a file, the local is also part of the same file
			// and the context is in the correct package
			correct_file := ident.pos.file == "" || local.lhs.pos.file == ident.pos.file
			correct_package := ast_context.current_package == ast_context.document_package
			if !correct_file || !correct_package {
				continue
			}

			if local.local_global {
				return local, true
			}
			if local.offset <= ident.pos.offset || local.lhs.pos.offset == ident.pos.offset {
				// checking equal offsets is a hack to allow matching lhs ident in var decls
				// because otherwise minimal offset begins after the decl
				return local, true
			}
		}
	}

	return {}, false
}

get_local_offset :: proc(ast_context: ^AstContext, offset: int, name: string) -> int {
	#reverse for locals in &ast_context.locals {
		if local_stack, ok := locals[name]; ok {
			#reverse for local, i in local_stack {
				if local.offset <= offset || local.local_global {
					if i < 0 {
						return -1
					} else {
						return local.offset
					}
				}
			}
		}
	}

	return -1
}

resolve_type_identifier :: proc(ast_context: ^AstContext, node: ast.Ident) -> (Symbol, bool) {
	return internal_resolve_type_identifier(ast_context, node)
}

internal_resolve_type_identifier :: proc(ast_context: ^AstContext, node: ast.Ident) -> (_symbol: Symbol, _ok: bool) {
	using ast

	if check_node_recursion(ast_context, node.derived.(^ast.Ident)) {
		return {}, false
	}

	//Try to prevent stack overflows and prevent indexing out of bounds.
	if ast_context.deferred_count >= DeferredDepth {
		return {}, false
	}

	set_ast_package_scoped(ast_context)


	if v, ok := keyword_map[node.name]; ok {
		//keywords
		ident := new_type(Ident, node.pos, node.end, ast_context.allocator)
		ident.name = node.name

		switch ident.name {
		case "nil":
			return {}, false
		case "true", "false":
			token := tokenizer.Token {
				text = ident.name,
			}
			return {
					type = .Keyword,
					signature = node.name,
					pkg = ast_context.current_package,
					value = SymbolUntypedValue{type = .Bool, tok = token},
				},
				true
		case:
			return {
					type = .Keyword,
					signature = node.name,
					name = ident.name,
					pkg = ast_context.current_package,
					value = SymbolBasicValue{ident = ident},
					uri = common.create_uri(ident.pos.file, ast_context.allocator).uri,
				},
				true
		}
	}

	if local, ok := get_local(ast_context^, node); ok && (ast_context.use_locals || local.local_global) {
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
			return_symbol, ok = internal_resolve_type_identifier(ast_context, v^)
		case ^Union_Type:
			return_symbol, ok = make_symbol_union_from_ast(ast_context, v^, node), true
			return_symbol.name = node.name
		case ^Enum_Type:
			return_symbol, ok = make_symbol_enum_from_ast(ast_context, v^, node), true
			return_symbol.name = node.name
		case ^Struct_Type:
			return_symbol, ok = make_symbol_struct_from_ast(ast_context, v, node, {}), true
			return_symbol.name = node.name
		case ^Bit_Set_Type:
			return_symbol, ok = make_symbol_bitset_from_ast(ast_context, v^, node), true
			return_symbol.name = node.name
		case ^Bit_Field_Type:
			return_symbol, ok = make_symbol_bit_field_from_ast(ast_context, v, node), true
			return_symbol.name = node.name
		case ^Proc_Lit:
			if is_procedure_generic(v.type) {
				return_symbol, ok = resolve_generic_function(ast_context, v^)

				if !ok && !ast_context.overloading {
					return_symbol, ok =
						make_symbol_procedure_from_ast(ast_context, local.rhs, v.type^, node, {}, false, v.inlining),
						true
				}
			} else {
				return_symbol, ok =
					make_symbol_procedure_from_ast(ast_context, local.rhs, v.type^, node, {}, false, v.inlining), true
			}
		case ^Proc_Group:
			return_symbol, ok = resolve_function_overload(ast_context, v^)
		case ^Array_Type:
			return_symbol, ok = make_symbol_array_from_ast(ast_context, v^, node), true
		case ^Dynamic_Array_Type:
			return_symbol, ok = make_symbol_dynamic_array_from_ast(ast_context, v^, node), true
		case ^Matrix_Type:
			return_symbol, ok = make_symbol_matrix_from_ast(ast_context, v^, node), true
		case ^Map_Type:
			return_symbol, ok = make_symbol_map_from_ast(ast_context, v^, node), true
		case ^Basic_Lit:
			return_symbol, ok = resolve_basic_lit(ast_context, v^)
			return_symbol.name = node.name
			return_symbol.type = local.variable ? .Variable : .Constant
		case ^ast.Binary_Expr:
			return_symbol, ok = resolve_binary_expression(ast_context, v)
		case:
			return_symbol, ok = internal_resolve_type_expression(ast_context, local.rhs)
		}

		if is_distinct {
			return_symbol.name = node.name
			return_symbol.flags |= {.Distinct}
		}

		if local.parameter {
			return_symbol.flags |= {.Parameter}
		}

		if local.variable {
			return_symbol.type = .Variable
		}

		return_symbol.flags |= {.Local}

		return return_symbol, ok

	}

	for imp in ast_context.imports {
		if imp.name == ast_context.current_package {
			continue
		}

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

	//This could also be the runtime package, which is not required to be imported, but itself is used with selector expression in runtime functions: `my_runtime_proc :proc(a: runtime.*)`
	if node.name == "runtime" {
		symbol := Symbol {
			type  = .Package,
			pkg   = indexer.runtime_package,
			value = SymbolPackageValue{},
		}

		return symbol, true
	}

	if global, ok := ast_context.globals[node.name];
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
			return_symbol, ok = internal_resolve_type_identifier(ast_context, v^)
		case ^ast.Call_Expr:
			old_call := ast_context.call
			ast_context.call = cast(^Call_Expr)global.expr

			defer {
				ast_context.call = old_call
			}

			if return_symbol, ok = internal_resolve_type_expression(ast_context, v.expr); ok {
				return_types := get_proc_return_types(ast_context, return_symbol, v, global.mutable)
				if len(return_types) > 0 {
					return_symbol, ok = internal_resolve_type_expression(ast_context, return_types[0])
				}
				// Otherwise should be a parapoly style
			}

		case ^Struct_Type:
			return_symbol, ok = make_symbol_struct_from_ast(ast_context, v, node, global.attributes), true
			return_symbol.name = node.name
		case ^Bit_Set_Type:
			return_symbol, ok = make_symbol_bitset_from_ast(ast_context, v^, node), true
			return_symbol.name = node.name
		case ^Union_Type:
			return_symbol, ok = make_symbol_union_from_ast(ast_context, v^, node), true
			return_symbol.name = node.name
		case ^Enum_Type:
			return_symbol, ok = make_symbol_enum_from_ast(ast_context, v^, node), true
			return_symbol.name = node.name
		case ^Bit_Field_Type:
			return_symbol, ok = make_symbol_bit_field_from_ast(ast_context, v, node), true
			return_symbol.name = node.name
		case ^Proc_Lit:
			if is_procedure_generic(v.type) {
				return_symbol, ok = resolve_generic_function(ast_context, v^)

				//If we are not overloading just show the unresolved generic function
				if !ok && !ast_context.overloading {
					return_symbol, ok =
						make_symbol_procedure_from_ast(
							ast_context,
							global.expr,
							v.type^,
							node,
							global.attributes,
							false,
							v.inlining,
						),
						true
				}
			} else {
				return_symbol, ok =
					make_symbol_procedure_from_ast(
						ast_context,
						global.expr,
						v.type^,
						node,
						global.attributes,
						false,
						v.inlining,
					),
					true
			}
		case ^Proc_Group:
			return_symbol, ok = resolve_function_overload(ast_context, v^)
		case ^Array_Type:
			return_symbol, ok = make_symbol_array_from_ast(ast_context, v^, node), true
		case ^Dynamic_Array_Type:
			return_symbol, ok = make_symbol_dynamic_array_from_ast(ast_context, v^, node), true
		case ^Matrix_Type:
			return_symbol, ok = make_symbol_matrix_from_ast(ast_context, v^, node), true
		case ^Map_Type:
			return_symbol, ok = make_symbol_map_from_ast(ast_context, v^, node), true
		case ^Basic_Lit:
			return_symbol, ok = resolve_basic_lit(ast_context, v^)
			return_symbol.name = node.name
			return_symbol.type = global.mutable ? .Variable : .Constant
		case:
			return_symbol, ok = internal_resolve_type_expression(ast_context, global.expr)
		}

		if is_distinct {
			return_symbol.name = node.name
			return_symbol.flags |= {.Distinct}
		}

		if global.mutable {
			return_symbol.type = .Variable
		}

		if global.docs != nil {
			return_symbol.doc = get_doc(global.docs, ast_context.allocator)
		}

		if global.comment != nil {
			return_symbol.comment = get_comment(global.comment)
		}

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

		is_runtime := strings.contains(ast_context.current_package, "base/runtime")

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

		for built in indexer.builtin_packages {
			if symbol, ok := lookup(node.name, built); ok {
				return resolve_symbol_return(ast_context, symbol)
			}
		}

		for u in ast_context.usings {
			for imp in ast_context.imports {
				if strings.compare(imp.base, u.pkg_name) == 0 {
					if symbol, ok := lookup(node.name, imp.name); ok {
						return resolve_symbol_return(ast_context, symbol)
					}
				}
			}
		}
	}

	return Symbol{}, false
}

struct_type_from_identifier :: proc(ast_context: ^AstContext, node: ast.Ident) -> (^ast.Struct_Type, bool) {
	if check_node_recursion(ast_context, node.derived.(^ast.Ident)) {
		return {}, false
	}

	//Try to prevent stack overflows and prevent indexing out of bounds.
	if ast_context.deferred_count >= DeferredDepth {
		return {}, false
	}

	set_ast_package_scoped(ast_context)

	if local, ok := get_local(ast_context^, node); ok && (ast_context.use_locals || local.local_global) {
		v, ok := local.rhs.derived.(^ast.Struct_Type)
		return v, ok
	}

	if global, ok := ast_context.globals[node.name];
	   ast_context.current_package == ast_context.document_package && ok {
		v, ok := global.expr.derived.(^ast.Struct_Type)
		return v, ok
	}

	return nil, false
}


resolve_slice_expression :: proc(ast_context: ^AstContext, slice_expr: ^ast.Slice_Expr) -> (symbol: Symbol, ok: bool) {
	symbol = resolve_type_expression(ast_context, slice_expr.expr) or_return

	expr: ^ast.Expr

	#partial switch v in symbol.value {
	case SymbolSliceValue:
		expr = v.expr
	case SymbolFixedArrayValue:
		expr = v.expr
	case SymbolDynamicArrayValue:
		expr = v.expr
	case SymbolUntypedValue:
		if v.type == .String {
			return symbol, true
		}
		return {}, false
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
	if position_context.parent_comp_lit != nil && position_context.parent_comp_lit.type != nil {
		symbol = resolve_type_expression(ast_context, position_context.parent_comp_lit.type) or_return
	} else if position_context.call != nil {
		if call_expr, ok := position_context.call.derived.(^ast.Call_Expr); ok {
			arg_index := find_position_in_call_param(position_context, call_expr^) or_return

			symbol = resolve_type_expression(ast_context, position_context.call) or_return

			value := symbol.value.(SymbolProcedureValue) or_return

			if len(value.arg_types) <= arg_index {
				return {}, false
			}

			if value.arg_types[arg_index].type == nil {
				return {}, false
			}

			symbol = resolve_type_expression(ast_context, value.arg_types[arg_index].type) or_return
		}
	} else if position_context.returns != nil {
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
			symbol = resolve_type_expression(
				ast_context,
				position_context.function.type.results.list[return_index].type,
			) or_return
		}
	} else if position_context.value_decl != nil && position_context.value_decl.type != nil {
		symbol = resolve_type_expression(ast_context, position_context.value_decl.type) or_return
	}

	set_ast_package_set_scoped(ast_context, symbol.pkg)

	symbol, _ = resolve_type_comp_literal(
		ast_context,
		position_context,
		symbol,
		position_context.parent_comp_lit,
	) or_return

	return symbol, true
}

// Used to get the name of the field for resolving the implicit selectors
get_field_value_name :: proc(field_value: ^ast.Field_Value) -> (string, bool) {
	if field, ok := field_value.field.derived.(^ast.Ident); ok {
		return field.name, true
	} else if field, ok := field_value.field.derived.(^ast.Implicit_Selector_Expr); ok {
		return field.field.name, true
	}
	return "", false
}

resolve_implicit_selector_comp_literal :: proc(
	ast_context: ^AstContext,
	position_context: ^DocumentPositionContext,
	symbol: Symbol,
	field_name: string,
) -> (
	Symbol,
	bool,
) {
	if comp_symbol, comp_lit, ok := resolve_type_comp_literal(
		ast_context,
		position_context,
		symbol,
		position_context.parent_comp_lit,
	); ok {
		#partial switch v in comp_symbol.value {
		case SymbolEnumValue:
			return comp_symbol, ok
		case SymbolStructValue:
			set_ast_package_set_scoped(ast_context, comp_symbol.pkg)

			//We can either have the final
			elem_index := -1

			for elem, i in comp_lit.elems {
				if position_in_node(elem, position_context.position) {
					elem_index = i
				}
			}

			type: ^ast.Expr

			for name, i in v.names {
				if name != field_name {
					continue
				}

				type = v.types[i]
				break
			}

			if type == nil && elem_index != -1 && len(v.types) > elem_index {
				type = v.types[elem_index]
			}

			return resolve_type_expression(ast_context, type)
		case SymbolBitFieldValue:
			set_ast_package_set_scoped(ast_context, comp_symbol.pkg)

			//We can either have the final
			elem_index := -1

			for elem, i in comp_lit.elems {
				if position_in_node(elem, position_context.position) {
					elem_index = i
				}
			}

			type: ^ast.Expr

			for name, i in v.names {
				if name != field_name {
					continue
				}

				type = v.types[i]
				break
			}

			if type == nil && len(v.types) > elem_index {
				type = v.types[elem_index]
			}

			return resolve_type_expression(ast_context, type)
		case SymbolFixedArrayValue:
			//This will be a comp_lit for an enumerated array
			//EnumIndexedArray :: [TestEnum]u32 {
			//	.valueOne = 1,
			//	.valueTwo = 2,
			//}
			return resolve_type_expression(ast_context, v.len)
		}
	}
	return {}, false
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
			parameter_index, parameter_ok := find_position_in_call_param(position_context, call^)
			if symbol, ok := resolve_type_expression(ast_context, call.expr); ok && parameter_ok {
				if proc_value, ok := symbol.value.(SymbolProcedureValue); ok {
					if len(proc_value.arg_types) <= parameter_index {
						return {}, false
					}

					return resolve_type_expression(ast_context, proc_value.arg_types[parameter_index].type)
				} else if enum_value, ok := symbol.value.(SymbolEnumValue); ok {
					return symbol, ok
				}
			}
		}
	}

	if position_context.assign != nil && len(position_context.assign.lhs) == len(position_context.assign.rhs) {
		for _, i in position_context.assign.lhs {
			if position_in_node(position_context.assign.rhs[i], position_context.position) {
				if symbol, ok := resolve_type_expression(ast_context, position_context.assign.lhs[i]); ok {
					return symbol, ok
				}
			}
		}
	}

	if position_context.binary != nil {
		if position_in_node(position_context.binary.left, position_context.position) {
			return resolve_type_expression(ast_context, position_context.binary.right)
		} else {
			return resolve_type_expression(ast_context, position_context.binary.left)
		}
	}

	if position_context.index != nil {
		symbol: Symbol
		ok := false
		if position_context.previous_index != nil {
			symbol, ok = resolve_type_expression(ast_context, position_context.previous_index)
			if !ok {
				return {}, false
			}
		} else {
			symbol, ok = resolve_type_expression(ast_context, position_context.index.expr)
			if !ok {
				return {}, false
			}
		}

		#partial switch value in symbol.value {
		case SymbolFixedArrayValue:
			return resolve_type_expression(ast_context, value.len)
		case SymbolMapValue:
			return resolve_type_expression(ast_context, value.key)
		}
	}

	if position_context.comp_lit != nil &&
	   position_context.parent_comp_lit != nil &&
	   position_context.parent_comp_lit.type != nil {
		if position_context.field_value != nil {
			if field_name, ok := get_field_value_name(position_context.field_value); ok {
				if symbol, ok := resolve_type_expression(ast_context, position_context.parent_comp_lit.type); ok {
					return resolve_implicit_selector_comp_literal(ast_context, position_context, symbol, field_name)
				}
			}
		}
	}

	if position_context.value_decl != nil && position_context.value_decl.type != nil {
		if symbol, ok := resolve_type_expression(ast_context, position_context.value_decl.type); ok {
			if !ok {
				return {}, false
			}
			if position_context.parent_comp_lit != nil && position_context.field_value != nil {
				if field_name, ok := get_field_value_name(position_context.field_value); ok {
					return resolve_implicit_selector_comp_literal(ast_context, position_context, symbol, field_name)
				}
			}
		}
	}

	if position_context.switch_stmt != nil {
		if symbol, ok := resolve_type_expression(ast_context, position_context.switch_stmt.cond); ok {
			return symbol, ok
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
			current_symbol, ok := resolve_type_expression(
				ast_context,
				position_context.function.type.results.list[return_index].type,
			)
			if !ok {
				return {}, false
			}
			if position_context.parent_comp_lit != nil && position_context.field_value != nil {
				if field_name, ok := get_field_value_name(position_context.field_value); ok {
					return resolve_implicit_selector_comp_literal(
						ast_context,
						position_context,
						current_symbol,
						field_name,
					)
				}
			}
			return current_symbol, ok
		}
	}

	if position_context.value_decl != nil {
		if symbol, ok := resolve_type_expression(ast_context, position_context.value_decl.type); ok {
			return symbol, ok
		}
	}

	return {}, false
}

resolve_symbol_return :: proc(ast_context: ^AstContext, symbol: Symbol, ok := true) -> (Symbol, bool) {
	if !ok {
		return symbol, ok
	}

	symbol := symbol

	if symbol.type == .Unresolved {
		if !resolve_unresolved_symbol(ast_context, &symbol) {
			return {}, false
		}
	}

	#partial switch &v in symbol.value {
	case SymbolProcedureGroupValue:
		if s, ok := resolve_function_overload(ast_context, v.group.derived.(^ast.Proc_Group)^); ok {
			s.range = symbol.range
			s.uri = symbol.uri
			return s, true
		} else {
			return s, false
		}
	case SymbolProcedureValue:
		if v.generic {
			if resolved_symbol, ok := resolve_generic_function(ast_context, v.arg_types, v.return_types); ok {
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
		b := symbol_struct_value_builder_make(symbol, v, ast_context.allocator)
		if v.poly != nil {
			clear(&b.types)
			for type in v.types {
				append(&b.types, clone_expr(type, context.temp_allocator, nil))
			}
			resolve_poly_struct(ast_context, &b, v.poly)
		}

		//expand the types and names from the using - can't be done while indexing without complicating everything(this also saves memory)
		expand_usings(ast_context, &b)
		expand_objc(ast_context, &b)
		return to_symbol(b), ok
	case SymbolGenericValue:
		ret, ok := resolve_type_expression(ast_context, v.expr)
		if symbol.type == .Variable {
			ret.type = symbol.type
		}
		return ret, ok
	}

	return symbol, true
}

resolve_unresolved_symbol :: proc(ast_context: ^AstContext, symbol: ^Symbol) -> bool {
	if symbol.type != .Unresolved {
		return true
	}

	#partial switch v in symbol.value {
	case SymbolStructValue, SymbolBitFieldValue:
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
		set_ast_package_set_scoped(ast_context, symbol.pkg)

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

// Resolves the location of the underlying type of the identifier
resolve_location_type_identifier :: proc(ast_context: ^AstContext, node: ast.Ident) -> (Symbol, bool) {
	// TODO: Will also likely need to add more cases here as they come up
	if local, ok := get_local(ast_context^, node); ok {
		#partial switch n in local.rhs.derived {
		case ^ast.Ident:
			return resolve_location_identifier(ast_context, n^)
		case ^ast.Basic_Lit:
			return {}, true
		case ^ast.Array_Type:
			return resolve_location_type_expression(ast_context, n.elem)
		case ^ast.Dynamic_Array_Type:
			return resolve_location_type_expression(ast_context, n.elem)
		case ^ast.Selector_Expr:
			return resolve_selector_expression(ast_context, n)
		case ^ast.Pointer_Type:
			return resolve_location_type_expression(ast_context, n.elem)
		case ^ast.Unary_Expr:
			return resolve_location_type_expression(ast_context, n.expr)
		case ^ast.Type_Cast:
			return resolve_location_type_expression(ast_context, n.type)
		}
	} else if global, ok := ast_context.globals[node.name]; ok {
		// Ideally we'd have a way to extract the full symbol of a global, but for now
		// this seems to work. We may need to add more cases though.
		if v, ok := global.expr.derived.(^ast.Proc_Lit); ok {
			if symbol, ok := resolve_type_expression(ast_context, global.name_expr); ok {
				return symbol, ok
			}
		}
	}
	return resolve_location_identifier(ast_context, node)
}

resolve_location_identifier :: proc(ast_context: ^AstContext, node: ast.Ident) -> (Symbol, bool) {
	symbol: Symbol

	if local, ok := get_local(ast_context^, node); ok {
		symbol.range = common.get_token_range(local.lhs, ast_context.file.src)
		uri := common.create_uri(local.lhs.pos.file, ast_context.allocator)
		symbol.pkg = ast_context.document_package
		symbol.uri = uri.uri
		symbol.flags |= {.Local}
		return symbol, true
	} else if global, ok := ast_context.globals[node.name]; ok {
		symbol.range = common.get_token_range(global.name_expr, ast_context.file.src)
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

	if symbol, ok := lookup(node.name, "$builtin"); ok {
		return resolve_symbol_return(ast_context, symbol)
	}

	return {}, false
}

resolve_location_proc_param_name :: proc(
	ast_context: ^AstContext,
	position_context: ^DocumentPositionContext,
) -> (
	symbol: Symbol,
	ok: bool,
) {
	ident := position_context.field_value.field.derived.(^ast.Ident) or_return
	call := position_context.call.derived.(^ast.Call_Expr) or_return
	symbol = resolve_type_expression(ast_context, call) or_return

	reset_ast_context(ast_context)
	if value, ok := symbol.value.(SymbolProcedureValue); ok {
		if arg_name, ok := get_proc_arg_name_from_name(value, ident.name); ok {
			symbol.range = common.get_token_range(arg_name, ast_context.file.src)
		}
	}
	return symbol, true
}

resolve_type_location_proc_param_name :: proc(
	ast_context: ^AstContext,
	position_context: ^DocumentPositionContext,
) -> (
	call_symbol: Symbol,
	ok: bool,
) {
	ident := position_context.field_value.field.derived.(^ast.Ident) or_return
	call := position_context.call.derived.(^ast.Call_Expr) or_return
	call_symbol = resolve_type_expression(ast_context, call) or_return

	reset_ast_context(ast_context)
	if value, ok := call_symbol.value.(SymbolProcedureValue); ok {
		if symbol, ok := resolve_type_expression(ast_context, position_context.field_value.value); ok {
			symbol.type_pkg = symbol.pkg
			symbol.type_name = symbol.name
			symbol.pkg = call_symbol.name
			symbol.name = ident.name
			return symbol, true
		}
	}
	return call_symbol, false
}

// resolves the underlying location of type of the named param
resolve_location_proc_param_name_type :: proc(
	ast_context: ^AstContext,
	position_context: ^DocumentPositionContext,
) -> (
	call_symbol: Symbol,
	ok: bool,
) {
	ident := position_context.field_value.field.derived.(^ast.Ident) or_return
	call := position_context.call.derived.(^ast.Call_Expr) or_return
	call_symbol = resolve_type_expression(ast_context, call) or_return

	reset_ast_context(ast_context)
	if value, ok := call_symbol.value.(SymbolProcedureValue); ok {
		if arg_type, ok := get_proc_arg_type_from_name(value, ident.name); ok {
			if symbol, ok := resolve_location_type_expression(ast_context, arg_type.type); ok {
				return symbol, true
			}
		}
		if symbol, ok := resolve_location_type_expression(ast_context, position_context.field_value.value); ok {
			return symbol, true
		}
	}
	return call_symbol, false
}

resolve_location_comp_lit_field :: proc(
	ast_context: ^AstContext,
	position_context: ^DocumentPositionContext,
) -> (
	symbol: Symbol,
	ok: bool,
) {
	reset_ast_context(ast_context)

	set_ast_package_set_scoped(ast_context, ast_context.document_package)

	symbol = resolve_comp_literal(ast_context, position_context) or_return

	if field, ok := position_context.field_value.field.derived.(^ast.Ident); ok {
		if struct_value, ok := symbol.value.(SymbolStructValue); ok {
			for name, i in struct_value.names {
				if name == field.name {
					symbol.range = struct_value.ranges[i]
				}
			}
		} else if bit_field_value, ok := symbol.value.(SymbolBitFieldValue); ok {
			for name, i in bit_field_value.names {
				if name == field.name {
					symbol.range = bit_field_value.ranges[i]
				}
			}
		}
	} else if field, ok := position_context.field_value.field.derived.(^ast.Implicit_Selector_Expr); ok {
		return resolve_location_implicit_selector(ast_context, position_context, field)
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
	ok = true

	reset_ast_context(ast_context)

	set_ast_package_set_scoped(ast_context, ast_context.document_package)

	symbol = resolve_implicit_selector(ast_context, position_context, implicit_selector) or_return

	#partial switch v in symbol.value {
	case SymbolEnumValue:
		for name, i in v.names {
			if strings.compare(name, implicit_selector.field.name) == 0 {
				symbol.range = v.ranges[i]
			}
		}
	case SymbolUnionValue:
		for type in v.types {
			enum_symbol := resolve_type_expression(ast_context, type) or_return
			if value, ok := enum_symbol.value.(SymbolEnumValue); ok {
				for name, i in value.names {
					if strings.compare(name, implicit_selector.field.name) == 0 {
						symbol.range = value.ranges[i]
						symbol.uri = enum_symbol.uri
						return symbol, ok
					}
				}
			}
		}
	case SymbolBitSetValue:
		enum_symbol := resolve_type_expression(ast_context, v.expr) or_return
		if value, ok := enum_symbol.value.(SymbolEnumValue); ok {
			for name, i in value.names {
				if strings.compare(name, implicit_selector.field.name) == 0 {
					symbol.range = value.ranges[i]
					symbol.uri = enum_symbol.uri
					return symbol, ok
				}
			}
		}

	case:
		ok = false
	}

	return symbol, ok
}

resolve_location_selector :: proc(ast_context: ^AstContext, selector_expr: ^ast.Node) -> (symbol: Symbol, ok: bool) {
	reset_ast_context(ast_context)

	set_ast_package_set_scoped(ast_context, ast_context.document_package)

	if selector, ok := selector_expr.derived.(^ast.Selector_Expr); ok {
		symbol = resolve_type_expression(ast_context, selector.expr) or_return
		return resolve_symbol_selector(ast_context, selector, symbol)
	}

	return {}, false
}

resolve_symbol_selector :: proc(
	ast_context: ^AstContext,
	selector: ^ast.Selector_Expr,
	symbol: Symbol,
) -> (
	Symbol,
	bool,
) {
	field: string
	symbol := symbol

	if selector.field != nil {
		#partial switch v in selector.field.derived {
		case ^ast.Ident:
			field = v.name
		}
	}

	#partial switch v in symbol.value {
	case SymbolEnumValue:
		for name, i in v.names {
			if strings.compare(name, field) == 0 {
				symbol.range = v.ranges[i]
			}
		}
	case SymbolStructValue:
		for name, i in v.names {
			if strings.compare(name, field) == 0 {
				symbol.range = v.ranges[i]
			}
		}
	case SymbolBitFieldValue:
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
	case SymbolProcedureValue:
		if len(v.return_types) != 1 {
			return {}, false
		}
		if s, ok := resolve_type_expression(ast_context, v.return_types[0].type); ok {
			return resolve_symbol_selector(ast_context, selector, s)
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
			if s, ok := resolve_first_symbol_from_binary_expression(ast_context, cast(^ast.Binary_Expr)binary.left);
			   ok {
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
			if s, ok := resolve_first_symbol_from_binary_expression(ast_context, cast(^ast.Binary_Expr)binary.right);
			   ok {
				return s, ok
			}
		}
	}

	return {}, false
}

resolve_binary_expression :: proc(ast_context: ^AstContext, binary: ^ast.Binary_Expr) -> (Symbol, bool) {
	if binary.left == nil || binary.right == nil {
		return {}, false
	}

	set_ast_package_scoped(ast_context)

	symbol_a, symbol_b: Symbol
	ok_a, ok_b: bool

	#partial switch binary.op.kind {
	case .Cmp_Eq, .Gt, .Gt_Eq, .Lt, .Lt_Eq:
		symbol_a.value = SymbolUntypedValue {
			type = .Bool,
		}
		return symbol_a, true
	}

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

	if symbol, ok := symbol_a.value.(SymbolProcedureValue); ok && len(symbol.return_types) > 0 {
		symbol_a, ok_a = resolve_type_expression(
			ast_context,
			symbol.return_types[0].type != nil ? symbol.return_types[0].type : symbol.return_types[0].default_value,
		)
	}

	if symbol, ok := symbol_b.value.(SymbolProcedureValue); ok && len(symbol.return_types) > 0 {
		symbol_b, ok_b = resolve_type_expression(
			ast_context,
			symbol.return_types[0].type != nil ? symbol.return_types[0].type : symbol.return_types[0].default_value,
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
	} else if is_vector_a && !is_matrix_b && !is_vector_b && binary.op.kind == .Mul {
		return symbol_a, true
	} else if is_vector_b && !is_matrix_a && !is_vector_a && binary.op.kind == .Mul {
		return symbol_b, true
	} else if is_matrix_a && !is_matrix_b && !is_vector_b && binary.op.kind == .Mul {
		return symbol_a, true
	} else if is_matrix_b && !is_matrix_a && !is_vector_a && binary.op.kind == .Mul {
		return symbol_b, true
	}


	//Otherwise just choose the first type, we do not handle error cases - that is done with the checker
	return symbol_a, ok_a
}

find_position_in_call_param :: proc(position_context: ^DocumentPositionContext, call: ast.Call_Expr) -> (int, bool) {
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

make_pointer_ast :: proc(ast_context: ^AstContext, elem: ^ast.Expr) -> ^ast.Pointer_Type {
	pointer := new_type(ast.Pointer_Type, elem.pos, elem.end, ast_context.allocator)
	pointer.elem = elem
	return pointer
}

make_bool_ast :: proc(ast_context: ^AstContext, pos: tokenizer.Pos, end: tokenizer.Pos) -> ^ast.Ident {
	ident := new_type(ast.Ident, pos, end, ast_context.allocator)
	ident.name = "bool"
	return ident
}

make_int_ast :: proc(ast_context: ^AstContext, pos: tokenizer.Pos, end: tokenizer.Pos) -> ^ast.Ident {
	ident := new_type(ast.Ident, pos, end, ast_context.allocator)
	ident.name = "int"
	return ident
}

make_rune_ast :: proc(ast_context: ^AstContext, pos: tokenizer.Pos, end: tokenizer.Pos) -> ^ast.Ident {
	ident := new_type(ast.Ident, pos, end, ast_context.allocator)
	ident.name = "rune"
	return ident
}


make_ident_ast :: proc(ast_context: ^AstContext, pos: tokenizer.Pos, end: tokenizer.Pos, name: string) -> ^ast.Ident {
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
		new_pointer := new_type(ast.Pointer_Type, expr.pos, expr.end, context.temp_allocator)

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
			if u.pkg_name == imp.name {
				usings[i] = imp.name
			}
		}
	}

	return usings
}

get_symbol_pkg_name :: proc(ast_context: ^AstContext, symbol: ^Symbol) -> string {
	return get_pkg_name(ast_context, symbol.pkg)
}

get_pkg_name :: proc(ast_context: ^AstContext, pkg: string) -> string {
	name := path.base(pkg, false, context.temp_allocator)
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
	inlining: ast.Proc_Inlining,
) -> Symbol {
	symbol := Symbol {
		range = common.get_token_range(name, ast_context.file.src),
		type  = .Function if !type else .Type_Function,
		pkg   = get_package_from_node(n^),
		name  = name.name,
		uri   = common.create_uri(v.pos.file, ast_context.allocator).uri,
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
		return_types       = return_types[:],
		orig_return_types  = return_types[:],
		arg_types          = arg_types[:],
		orig_arg_types     = arg_types[:],
		generic            = v.generic,
		diverging          = v.diverging,
		calling_convention = v.calling_convention,
		tags               = v.tags,
		attributes         = attributes,
		inlining           = inlining,
	}

	if _, ok := get_attribute_objc_name(attributes); ok {
		symbol.flags |= {.ObjC}
		if get_attribute_objc_is_class_method(attributes) {
			symbol.flags |= {.ObjCIsClassMethod}
		}
	}

	return symbol
}

make_symbol_array_from_ast :: proc(ast_context: ^AstContext, v: ast.Array_Type, name: ast.Ident) -> Symbol {
	symbol := Symbol {
		range = common.get_token_range(v.node, ast_context.file.src),
		type  = .Type,
		pkg   = get_package_from_node(v.node),
		name  = name.name,
		uri   = common.create_uri(v.pos.file, ast_context.allocator).uri,
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

	if array_is_soa(v) {
		symbol.flags |= {.Soa}
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
		type  = .Type,
		pkg   = get_package_from_node(v.node),
		name  = name.name,
		uri   = common.create_uri(v.pos.file, ast_context.allocator).uri,
	}

	symbol.value = SymbolDynamicArrayValue {
		expr = v.elem,
	}


	if dynamic_array_is_soa(v) {
		symbol.flags |= {.Soa}
	}


	return symbol
}

make_symbol_matrix_from_ast :: proc(ast_context: ^AstContext, v: ast.Matrix_Type, name: ast.Ident) -> Symbol {
	symbol := Symbol {
		range = common.get_token_range(v.node, ast_context.file.src),
		type  = .Type,
		pkg   = get_package_from_node(v.node),
		name  = name.name,
		uri   = common.create_uri(v.pos.file, ast_context.allocator).uri,
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
		type  = .Type,
		pkg   = get_package_from_node(v.node),
		name  = name.name,
		uri   = common.create_uri(v.pos.file, ast_context.allocator).uri,
	}

	symbol.value = SymbolMultiPointerValue {
		expr = v.elem,
	}

	return symbol
}

make_symbol_map_from_ast :: proc(ast_context: ^AstContext, v: ast.Map_Type, name: ast.Ident) -> Symbol {
	symbol := Symbol {
		range = common.get_token_range(v.node, ast_context.file.src),
		type  = .Type,
		pkg   = get_package_from_node(v.node),
		name  = name.name,
		uri   = common.create_uri(v.pos.file, ast_context.allocator).uri,
	}

	symbol.value = SymbolMapValue {
		key   = v.key,
		value = v.value,
	}

	return symbol
}

make_symbol_basic_type_from_ast :: proc(ast_context: ^AstContext, n: ^ast.Ident) -> Symbol {
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
		uri   = common.create_uri(v.pos.file, ast_context.allocator).uri,
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
		uri   = common.create_uri(v.pos.file, ast_context.allocator).uri,
	}

	if inlined {
		symbol.flags |= {.Anonymous}
		symbol.name = "enum"
	}


	names := make([dynamic]string, ast_context.allocator)
	ranges := make([dynamic]common.Range, ast_context.allocator)
	values := make([dynamic]^ast.Expr, ast_context.allocator)

	for n in v.fields {
		name, range, value := get_enum_field_name_range_value(n, ast_context.file.src)
		append(&names, name)
		append(&ranges, range)
		append(&values, value)
	}

	symbol.value = SymbolEnumValue {
		names     = names[:],
		ranges    = ranges[:],
		base_type = v.base_type,
		values    = values[:],
	}

	return symbol
}

get_enum_field_name_range_value :: proc(n: ^ast.Expr, document_text: string) -> (string, common.Range, ^ast.Expr) {
	if ident, ok := n.derived.(^ast.Ident); ok {
		return ident.name, common.get_token_range(ident, document_text), nil
	}
	if field, ok := n.derived.(^ast.Field_Value); ok {
		if ident, ok := field.field.derived.(^ast.Ident); ok {
			return ident.name, common.get_token_range(ident, document_text), field.value
		} else if binary, ok := field.field.derived.(^ast.Binary_Expr); ok {
			return binary.left.derived.(^ast.Ident).name, common.get_token_range(binary, document_text), binary.right
		}
	}
	return "", {}, nil
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
		uri   = common.create_uri(v.pos.file, ast_context.allocator).uri,
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
	v: ^ast.Struct_Type,
	ident: ast.Ident,
	attributes: []^ast.Attribute,
	inlined := false,
) -> Symbol {
	node := v.node
	symbol := Symbol {
		range = common.get_token_range(v, ast_context.file.src),
		type  = .Struct,
		pkg   = get_package_from_node(v.node),
		name  = ident.name,
		uri   = common.create_uri(v.pos.file, ast_context.allocator).uri,
	}

	if inlined {
		symbol.flags |= {.Anonymous}
		symbol.name = "struct"
	}

	b := symbol_struct_value_builder_make(symbol, ast_context.allocator)
	write_struct_type(ast_context, &b, v, ident, attributes, -1, inlined)
	symbol = to_symbol(b)
	return symbol
}

make_symbol_bit_field_from_ast :: proc(
	ast_context: ^AstContext,
	v: ^ast.Bit_Field_Type,
	ident: ast.Ident,
	inlined := false,
) -> Symbol {
	construct_bit_field_field_docs(ast_context.file, v)
	symbol := Symbol {
		range = common.get_token_range(v, ast_context.file.src),
		type  = .Struct,
		pkg   = get_package_from_node(v.node),
		name  = ident.name,
		uri   = common.create_uri(v.pos.file, ast_context.allocator).uri,
	}

	if inlined {
		symbol.flags |= {.Anonymous}
		symbol.name = "bit_field"
	}

	names := make([dynamic]string, ast_context.allocator)
	types := make([dynamic]^ast.Expr, ast_context.allocator)
	ranges := make([dynamic]common.Range, 0, ast_context.allocator)
	docs := make([dynamic]^ast.Comment_Group, 0, ast_context.allocator)
	comments := make([dynamic]^ast.Comment_Group, 0, ast_context.allocator)
	bit_sizes := make([dynamic]^ast.Expr, 0, ast_context.allocator)

	for field in v.fields {
		if identifier, ok := field.name.derived.(^ast.Ident); ok && field.type != nil {
			append(&names, identifier.name)
			append(&types, field.type)
			append(&ranges, common.get_token_range(identifier, ast_context.file.src))
			append(&docs, field.docs)
			append(&comments, field.comments)
			append(&bit_sizes, field.bit_size)
		}
	}

	symbol.value = SymbolBitFieldValue {
		backing_type = v.backing_type,
		names        = names[:],
		types        = types[:],
		ranges       = ranges[:],
		docs         = docs[:],
		comments     = comments[:],
		bit_sizes    = bit_sizes[:],
	}

	return symbol
}

get_globals :: proc(file: ast.File, ast_context: ^AstContext) {
	exprs := collect_globals(file)

	for expr in exprs {
		ast_context.globals[expr.name] = expr
	}
}

GetGenericAssignmentFlag :: enum {
	SameLhsRhsCount,
}

GetGenericAssignmentFlags :: bit_set[GetGenericAssignmentFlag]

get_generic_assignment :: proc(
	file: ast.File,
	value: ^ast.Expr,
	ast_context: ^AstContext,
	results: ^[dynamic]^ast.Expr,
	calls: ^map[int]bool,
	flags: GetGenericAssignmentFlags,
	is_mutable: bool,
) {
	using ast

	reset_ast_context(ast_context)

	#partial switch v in value.derived {
	case ^Or_Return_Expr:
		get_generic_assignment(file, v.expr, ast_context, results, calls, flags, is_mutable)
	case ^Or_Else_Expr:
		get_generic_assignment(file, v.x, ast_context, results, calls, flags, is_mutable)
	case ^Or_Branch_Expr:
		get_generic_assignment(file, v.expr, ast_context, results, calls, flags, is_mutable)
	case ^Call_Expr:
		old_call := ast_context.call
		ast_context.call = cast(^ast.Call_Expr)value

		defer {
			ast_context.call = old_call
		}

		//Check for basic type casts
		if len(v.args) == 1 {
			if ident, ok := v.expr.derived.(^ast.Ident); ok {
				//Handle the old way of type casting
				if v, ok := keyword_map[ident.name]; ok {
					//keywords
					type_ident := new_type(Ident, ident.pos, ident.end, ast_context.allocator)
					type_ident.name = ident.name
					append(results, type_ident)
					break
				}
			}
		}

		//We have to resolve early and can't rely on lazy evalutation because it can have multiple returns.
		if symbol, ok := resolve_type_expression(ast_context, v.expr); ok {
			#partial switch symbol_value in symbol.value {
			case SymbolProcedureValue:
				return_types := get_proc_return_types(ast_context, symbol, v, is_mutable)
				for ret in return_types {
					calls[len(results)] = true
					append(results, ret)
				}
			case SymbolAggregateValue:
				//In case we can't resolve the proc group, just save it anyway, so it won't cause any issues further down the line.
				append(results, value)

			case SymbolStructValue:
				// Parametrized struct
				get_generic_assignment(file, v.expr, ast_context, results, calls, flags, is_mutable)
			case SymbolUnionValue:
				// Parametrized union
				get_generic_assignment(file, v.expr, ast_context, results, calls, flags, is_mutable)

			case:
				if ident, ok := v.expr.derived.(^ast.Ident); ok {
					//TODO: Simple assumption that you are casting it the type.
					type_ident := new_type(Ident, ident.pos, ident.end, ast_context.allocator)
					type_ident.name = ident.name
					append(results, type_ident)
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
		//In order to prevent having to actually resolve the expression, we make the assumption that we need to always add a bool node, if the lhs and rhs don't match.
		if .SameLhsRhsCount not_in flags {
			b := make_bool_ast(ast_context, v.expr.pos, v.expr.end)
			append(results, b)
		}
	case ^Type_Assertion:
		if v.type != nil {
			if unary, ok := v.type.derived.(^ast.Unary_Expr); ok && unary.op.kind == .Question {
				append(results, cast(^ast.Expr)&v.node)
			} else {
				append(results, v.type)
			}

			b := make_bool_ast(ast_context, v.type.pos, v.type.end)

			append(results, b)
		}
	case:
		append(results, value)
	}
}

get_locals_value_decl :: proc(file: ast.File, value_decl: ast.Value_Decl, ast_context: ^AstContext) {
	using ast

	if len(value_decl.names) <= 0 {
		return
	}

	//We have two stages of getting locals: local non mutable and mutables, since they are treated differently in scopes my Odin.
	if value_decl.is_mutable == ast_context.non_mutable_only {
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
			str := get_ast_node_string(value_decl.names[i], file.src)
			store_local(
				ast_context,
				name,
				value_decl.type,
				value_decl.end.offset,
				str,
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

	flags: GetGenericAssignmentFlags

	if len(value_decl.names) == len(value_decl.values) {
		flags |= {.SameLhsRhsCount}
	}

	for value in value_decl.values {
		get_generic_assignment(file, value, ast_context, &results, &calls, flags, value_decl.is_mutable)
	}

	if len(results) == 0 {
		return
	}

	for name, i in value_decl.names {
		result_i := min(len(results) - 1, i)
		str := get_ast_node_string(name, file.src)

		call := false

		store_local(
			ast_context,
			name,
			results[result_i],
			value_decl.end.offset,
			str,
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

	set_ast_package_set_scoped(ast_context, ast_context.document_package)

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
		get_locals_case_clause(file, v, ast_context, document_position)
	case:
	//log.debugf("default node local stmt %v", v);
	}
}

get_locals_case_clause :: proc(
	file: ast.File,
	case_clause: ^ast.Case_Clause,
	ast_context: ^AstContext,
	document_position: ^DocumentPositionContext,
) {
	if !(case_clause.pos.offset <= document_position.position &&
		   document_position.position <= case_clause.end.offset) {
		return
	}

	for stmt in case_clause.body {
		get_locals_stmt(file, stmt, ast_context, document_position)
	}
}

get_locals_block_stmt :: proc(
	file: ast.File,
	block: ast.Block_Stmt,
	ast_context: ^AstContext,
	document_position: ^DocumentPositionContext,
) {
	/*
	   We need to handle blocks for non mutable and mutable: non mutable has no order for their value declarations, except for nested blocks where they are hidden by scope
	   For non_mutable_only we set the document_position.position to be the end of the function to get all the non-mutable locals, but that shouldn't apply to the nested block itself,
	   but will for it's content.

	   Therefore we use nested_position that is the exact token we are interested in.

	   Example:
	   my_proc :: proc() {
			{
				my_variable = get_value() <-- document_position.nested_position
				get_value :: proc() --- This should not be hidden

				{
					get_value_2 :: proc() --- This will be hidden
				}
			}
	   } <-- document_position.position
	*/

	if ast_context.non_mutable_only {
		if !(block.pos.offset <= document_position.nested_position &&
			   document_position.nested_position <= block.end.offset) {
			return
		}
	} else {
		if !(block.pos.offset <= document_position.position && document_position.position <= block.end.offset) {
			return
		}
	}


	for stmt in block.stmts {
		get_locals_stmt(file, stmt, ast_context, document_position)
	}
}

get_locals_using :: proc(expr: ^ast.Expr, ast_context: ^AstContext) {
	if symbol, expr, ok := unwrap_procedure_until_struct_bit_field_or_package(ast_context, expr); ok {
		#partial switch v in symbol.value {
		case SymbolPackageValue:
			if ident, ok := expr.derived.(^ast.Ident); ok {
				add_using(ast_context, ident.name, symbol.pkg)
			}
		case SymbolStructValue:
			for name, i in v.names {
				selector := new_type(ast.Selector_Expr, v.types[i].pos, v.types[i].end, ast_context.allocator)
				selector.expr = expr
				selector.field = new_type(ast.Ident, v.types[i].pos, v.types[i].end, ast_context.allocator)
				selector.field.name = name
				store_local(ast_context, expr, selector, 0, name, false, ast_context.non_mutable_only, true, "", false)
			}
		case SymbolBitFieldValue:
			for name, i in v.names {
				selector := new_type(ast.Selector_Expr, v.types[i].pos, v.types[i].end, ast_context.allocator)
				selector.expr = expr
				selector.field = new_type(ast.Ident, v.types[i].pos, v.types[i].end, ast_context.allocator)
				selector.field.name = name
				store_local(ast_context, expr, selector, 0, name, false, ast_context.non_mutable_only, true, "", false)
			}
		}
	}
}

get_locals_using_stmt :: proc(stmt: ast.Using_Stmt, ast_context: ^AstContext) {
	for u in stmt.list {
		get_locals_using(u, ast_context)
	}
}

get_locals_assign_stmt :: proc(file: ast.File, stmt: ast.Assign_Stmt, ast_context: ^AstContext) {
	using ast

	if stmt.lhs == nil || stmt.rhs == nil {
		return
	}

	results := make([dynamic]^Expr, context.temp_allocator)
	calls := make(map[int]bool, 0, context.temp_allocator)

	for rhs in stmt.rhs {
		get_generic_assignment(file, rhs, ast_context, &results, &calls, {}, true)
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
	if !(stmt.pos.offset <= document_position.position && document_position.position <= stmt.end.offset) {
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

	if !(stmt.pos.offset <= document_position.position && document_position.position <= stmt.end.offset) {
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

	symbol, ok := resolve_type_expression(ast_context, stmt.expr)

	if v, ok := symbol.value.(SymbolProcedureValue); ok {
		//Not quite sure how the custom iterator is defined, but it seems that it's two or three arguments. So temporarily just assume three arguments are iterators.
		if len(v.return_types) != 3 && len(v.return_types) != 2 && len(v.return_types) != 0 {
			if v.return_types[0].type != nil {
				symbol, ok = resolve_type_expression(ast_context, v.return_types[0].type)
			} else if v.return_types[0].default_value != nil {
				symbol, ok = resolve_type_expression(ast_context, v.return_types[0].default_value)
			}
		}
	}

	if ok {
		#partial switch v in symbol.value {
		case SymbolProcedureValue:
			for val, i in stmt.vals {
				if ident, ok := unwrap_ident(val); ok {
					expr: ^ast.Expr

					if len(v.return_types) > i {

						if v.return_types[i].type != nil {
							expr = v.return_types[i].type
						} else if v.return_types[i].default_value != nil {
							expr = v.return_types[i].default_value
						}

						store_local(
							ast_context,
							ident,
							expr,
							ident.pos.offset,
							ident.name,
							ast_context.non_mutable_only,
							false,
							true,
							symbol.pkg,
							false,
						)
					}
				}
			}
		case SymbolUntypedValue:
			if len(stmt.vals) == 1 {
				if ident, ok := unwrap_ident(stmt.vals[0]); ok {
					if v.type == .String {
						store_local(
							ast_context,
							ident,
							make_rune_ast(ast_context, ident.pos, ident.end),
							ident.pos.offset,
							ident.name,
							ast_context.non_mutable_only,
							false,
							true,
							symbol.pkg,
							false,
						)
					}
				}
			}
		case SymbolBasicValue:
			if len(stmt.vals) == 1 {
				if ident, ok := unwrap_ident(stmt.vals[0]); ok {
					if v.ident.name == "string" {
						store_local(
							ast_context,
							ident,
							make_rune_ast(ast_context, ident.pos, ident.end),
							ident.pos.offset,
							ident.name,
							ast_context.non_mutable_only,
							false,
							true,
							symbol.pkg,
							false,
						)
					}
				}
			}
		case SymbolMapValue:
			if len(stmt.vals) >= 1 {
				if ident, ok := unwrap_ident(stmt.vals[0]); ok {
					store_local(
						ast_context,
						ident,
						v.key,
						ident.pos.offset,
						ident.name,
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
					//Look for enumarated arrays
					if len_symbol, ok := resolve_type_expression(ast_context, v.len); ok {
						if _, is_enum := len_symbol.value.(SymbolEnumValue); is_enum {
							store_local(
								ast_context,
								ident,
								v.len,
								ident.pos.offset,
								ident.name,
								ast_context.non_mutable_only,
								false,
								true,
								len_symbol.pkg,
								false,
							)
						}
					} else {
						store_local(
							ast_context,
							ident,
							make_int_ast(ast_context, ident.pos, ident.end),
							ident.pos.offset,
							ident.name,
							ast_context.non_mutable_only,
							false,
							true,
							symbol.pkg,
							false,
						)
					}
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
						ast_context.non_mutable_only,
						false,
						true,
						symbol.pkg,
						false,
					)
				}
			}
		case SymbolBitSetValue:
			if len(stmt.vals) >= 1 {
				if ident, ok := unwrap_ident(stmt.vals[0]); ok {
					store_local(
						ast_context,
						ident,
						v.expr,
						ident.pos.offset,
						ident.name,
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
	if !(stmt.pos.offset <= document_position.position && document_position.position <= stmt.end.offset) {
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
	if !(stmt.pos.offset <= document_position.position && document_position.position <= stmt.end.offset) {
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

	if !(stmt.pos.offset <= document_position.position && document_position.position <= stmt.end.offset) {
		return
	}

	if stmt.body == nil {
		return
	}

	if block, ok := stmt.body.derived.(^Block_Stmt); ok {
		for block_stmt in block.stmts {
			if cause, ok := block_stmt.derived.(^Case_Clause);
			   ok && cause.pos.offset <= document_position.position && document_position.position <= cause.end.offset {
				tag := stmt.tag.derived.(^Assign_Stmt)

				if len(tag.lhs) == 1 && len(cause.list) == 1 {
					ident, _ := unwrap_ident(tag.lhs[0])
					store_local(
						ast_context,
						ident,
						cause.list[0],
						ident.pos.offset,
						ident.name,
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
					str := get_ast_node_string(name, file.src)
					store_local(
						ast_context,
						name,
						arg.type,
						name.pos.offset,
						str,
						ast_context.non_mutable_only,
						false,
						true,
						"",
						true,
					)

					if .Using in arg.flags {
						using_stmt: ast.Using_Stmt
						using_stmt.list = make([]^ast.Expr, 1, context.temp_allocator)
						using_stmt.list[0] = arg.type
						get_locals_using_stmt(using_stmt, ast_context)
					}
				} else {
					str := get_ast_node_string(name, file.src)
					store_local(
						ast_context,
						name,
						arg.default_value,
						name.pos.offset,
						str,
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
					str := get_ast_node_string(name, file.src)
					store_local(
						ast_context,
						name,
						result.type,
						name.pos.offset,
						str,
						ast_context.non_mutable_only,
						false,
						true,
						"",
						true,
					)
				} else {
					str := get_ast_node_string(name, file.src)
					store_local(
						ast_context,
						name,
						result.default_value,
						name.pos.offset,
						str,
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

	get_locals_proc_param_and_results(file, proc_lit^, ast_context, document_position)

	block: ^ast.Block_Stmt
	block, ok = proc_lit.body.derived.(^ast.Block_Stmt)

	if !ok {
		log.error("Proc_List body not block")
		return
	}

	document_position.nested_position = document_position.position

	for function in document_position.functions {
		ast_context.non_mutable_only = true
		document_position.position = function.end.offset
		get_locals_stmt(file, function.body, ast_context, document_position)
	}

	document_position.position = document_position.nested_position
	ast_context.non_mutable_only = false

	for stmt in block.stmts {
		get_locals_stmt(file, stmt, ast_context, document_position)
	}

}

clear_locals :: proc(ast_context: ^AstContext) {
	clear(&ast_context.locals)
	clear(&ast_context.usings)
}

unwrap_procedure_until_struct_bit_field_or_package :: proc(
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

			symbol, ok = resolve_type_expression(ast_context, v.return_types[0].type)

			if !ok {
				return
			}

			expr = v.return_types[0].type
		case SymbolStructValue, SymbolPackageValue, SymbolBitFieldValue:
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

unwrap_enum :: proc(ast_context: ^AstContext, node: ^ast.Expr) -> (SymbolEnumValue, bool) {
	if node == nil {
		return {}, false
	}

	if enum_symbol, ok := resolve_type_expression(ast_context, node); ok {
		#partial switch value in enum_symbol.value {
		case SymbolEnumValue:
			return value, true
		case SymbolUnionValue:
			return unwrap_super_enum(ast_context, value)
		case SymbolSliceValue:
			return unwrap_enum(ast_context, value.expr)
		case SymbolFixedArrayValue:
			return unwrap_enum(ast_context, value.expr)
		case SymbolDynamicArrayValue:
			return unwrap_enum(ast_context, value.expr)
		case SymbolBitSetValue:
			return unwrap_enum(ast_context, value.expr)
		}
	}

	return {}, false
}

unwrap_super_enum :: proc(
	ast_context: ^AstContext,
	symbol_union: SymbolUnionValue,
) -> (
	ret_value: SymbolEnumValue,
	ret_ok: bool,
) {
	names := make([dynamic]string, 0, 20, ast_context.allocator)
	ranges := make([dynamic]common.Range, 0, 20, ast_context.allocator)

	for type in symbol_union.types {
		symbol := resolve_type_expression(ast_context, type) or_return
		if value, ok := symbol.value.(SymbolEnumValue); ok {
			append(&names, ..value.names)
			append(&ranges, ..value.ranges)
		}
	}

	ret_value.names = names[:]
	ret_value.ranges = ranges[:]

	return ret_value, true
}

unwrap_union :: proc(ast_context: ^AstContext, node: ^ast.Expr) -> (SymbolUnionValue, bool) {
	if union_symbol, ok := resolve_type_expression(ast_context, node); ok {
		if union_value, ok := union_symbol.value.(SymbolUnionValue); ok {
			return union_value, true
		}
	}

	return {}, false
}

unwrap_bitset :: proc(ast_context: ^AstContext, bitset_symbol: Symbol) -> (SymbolEnumValue, bool) {
	if bitset_value, ok := bitset_symbol.value.(SymbolBitSetValue); ok {
		if enum_symbol, ok := resolve_type_expression(ast_context, bitset_value.expr); ok {
			if enum_value, ok := enum_symbol.value.(SymbolEnumValue); ok {
				return enum_value, true
			} else if union_value, ok := enum_symbol.value.(SymbolUnionValue); ok {
				return unwrap_super_enum(ast_context, union_value)
			}
		}
	}

	return {}, false
}

position_in_proc_decl :: proc(position_context: ^DocumentPositionContext) -> bool {
	if position_context.value_decl == nil {
		return false
	}

	if len(position_context.value_decl.values) != 1 {
		return false
	}

	if _, ok := position_context.value_decl.values[0].derived.(^ast.Proc_Type); ok {
		return true
	}

	if proc_lit, ok := position_context.value_decl.values[0].derived.(^ast.Proc_Lit); ok {
		if proc_lit.type != nil && position_in_node(proc_lit.type, position_context.position) {
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

field_exists_in_comp_lit :: proc(comp_lit: ^ast.Comp_Lit, name: string) -> bool {
	for elem in comp_lit.elems {
		if field, ok := elem.derived.(^ast.Field_Value); ok {
			if field.field != nil {
				if ident, ok := field.field.derived.(^ast.Ident); ok {
					if ident.name == name {
						return true
					}
				} else if selector, ok := field.field.derived.(^ast.Implicit_Selector_Expr); ok {
					if selector.field != nil {
						if ident, ok := selector.field.derived.(^ast.Ident); ok {
							if ident.name == name {
								return true
							}
						}
					}
				}
			}
		} else if selector, ok := elem.derived.(^ast.Implicit_Selector_Expr); ok {
			if selector.field != nil {
				if ident, ok := selector.field.derived.(^ast.Ident); ok {
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
get_call_commas :: proc(position_context: ^DocumentPositionContext, document: ^Document) {
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

	return node_to_string(expr)
}

get_document_position_decls :: proc(decls: []^ast.Stmt, position_context: ^DocumentPositionContext) -> bool {
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

	position_context.functions = make([dynamic]^ast.Proc_Lit, context.temp_allocator)

	absolute_position, ok := common.get_absolute_position(position, document.text)

	if !ok {
		log.error("failed to get absolute position")
		return position_context, false
	}

	position_context.position = absolute_position

	exists_in_decl := get_document_position_decls(document.ast.decls[:], &position_context)

	for import_stmt in document.ast.imports {
		if position_in_node(import_stmt, position_context.position) {
			position_context.import_stmt = import_stmt
			break
		}
	}

	if !exists_in_decl && position_context.import_stmt == nil {
		position_context.abort_completion = true
	}

	if !position_in_node(position_context.comp_lit, position_context.position) {
		position_context.comp_lit = nil
	}

	if !position_in_node(position_context.parent_comp_lit, position_context.position) {
		position_context.parent_comp_lit = nil
	}

	if !position_in_node(position_context.assign, position_context.position) {
		position_context.assign = nil
	}

	if !position_in_node(position_context.binary, position_context.position) {
		position_context.binary = nil
	}

	if !position_in_node(position_context.parent_binary, position_context.position) {
		position_context.parent_binary = nil
	}

	if hint == .Completion && position_context.selector == nil && position_context.field == nil {
		fallback_position_context_completion(document, position, &position_context)
	}

	if (hint == .SignatureHelp || hint == .Completion) && position_context.call == nil {
		fallback_position_context_signature(document, position, &position_context)
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
	} else if i >= 0 && position_context.file.src[max(0, end - 1)] == '-' && position_context.file.src[end] == '>' {
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

	tokenizer.init(&p.tok, str, position_context.file.fullpath, common.parser_warning_handler)

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

		src_with_dot := string(position_context.file.src[0:min(len(position_context.file.src), end_offset + 1)])
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

	tokenizer.init(&p.tok, str, position_context.file.fullpath, common.parser_warning_handler)

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

// Used to find which sub-expr is desired by the position.
// Eg. for map[Key]Value, do we want 'map', 'Key' or 'Value'
get_desired_expr :: proc(node: ^ast.Expr, position: common.AbsolutePosition) -> ^ast.Expr {
	#partial switch n in node.derived {
	case ^ast.Array_Type:
		if position_in_node(n.tag, position) {
			return n.tag
		}
		if position_in_node(n.elem, position) {
			return n.elem
		}
		if position_in_node(n.len, position) {
			return n.len
		}
	case ^ast.Map_Type:
		if position_in_node(n.key, position) {
			return n.key
		}
		if position_in_node(n.value, position) {
			return n.key
		}
	case ^ast.Dynamic_Array_Type:
		if position_in_node(n.tag, position) {
			return n.tag
		}
		if position_in_node(n.elem, position) {
			return n.elem
		}
	case ^ast.Bit_Set_Type:
		if position_in_node(n.elem, position) {
			return n.elem
		}
	}

	return node
}

/*
	All these fallback functions are not perfect and should be fixed. A lot of weird use of the odin tokenizer and parser.
*/

get_document_position :: proc {
	get_document_position_array,
	get_document_position_dynamic_array,
	get_document_position_node,
}

get_document_position_array :: proc(array: $A/[]^$T, position_context: ^DocumentPositionContext) {
	for elem, i in array {
		get_document_position(elem, position_context)
	}
}

get_document_position_dynamic_array :: proc(array: $A/[dynamic]^$T, position_context: ^DocumentPositionContext) {
	for elem, i in array {
		get_document_position(elem, position_context)
	}
}

position_in_node :: proc(node: ^ast.Node, position: common.AbsolutePosition) -> bool {
	return node != nil && node.pos.offset <= position && position <= node.end.offset
}

position_in_exprs :: proc(nodes: []^ast.Expr, position: common.AbsolutePosition) -> bool {
	for node in nodes {
		if node != nil && node.pos.offset <= position && position <= node.end.offset {
			return true
		}
	}

	return false
}

get_document_position_label :: proc(label: ^ast.Expr, position_context: ^DocumentPositionContext) {
	if label == nil {
		return
	}

	if ident, ok := label.derived.(^ast.Ident); ok {
		position_context.label = ident
	}
}

get_document_position_node :: proc(node: ^ast.Node, position_context: ^DocumentPositionContext) {
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
		if position_in_node(n.body, position_context.position) {
			get_document_position(n.type, position_context)
			position_context.function = cast(^Proc_Lit)node
			append(&position_context.functions, position_context.function)
			get_document_position(n.body, position_context)
		} else if position_in_node(n.type, position_context.position) {
			position_context.function = cast(^Proc_Lit)node
			get_document_position(n.type, position_context)
		} else {
			for clause in n.where_clauses {
				if position_in_node(clause, position_context.position) {
					position_context.function = cast(^Proc_Lit)node
					get_document_position(clause, position_context)
				}
			}
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
			position_context.parent_binary = n
		}
		position_context.binary = n
		get_document_position(n.left, position_context)
		get_document_position(n.right, position_context)
	case ^Paren_Expr:
		get_document_position(n.expr, position_context)
	case ^Call_Expr:
		position_context.call = n
		get_document_position(n.expr, position_context)
		get_document_position(n.args, position_context)
	case ^Selector_Call_Expr:
		if position_context.hint == .Definition ||
		   position_context.hint == .Hover ||
		   position_context.hint == .SignatureHelp ||
		   position_context.hint == .Completion {
			position_context.selector = n.expr
			position_context.field = n.call
			position_context.selector_expr = node

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
		if position_context.hint == .Definition || position_context.hint == .Hover && n.field != nil {
			position_context.selector = n.expr
			position_context.field = n.field
			position_context.selector_expr = node
			get_document_position(n.expr, position_context)
			get_document_position(n.field, position_context)
		} else {
			get_document_position(n.expr, position_context)
			get_document_position(n.field, position_context)
		}
	case ^Index_Expr:
		position_context.previous_index = position_context.index
		position_context.index = n
		get_document_position(n.expr, position_context)
		get_document_position(n.index, position_context)
	case ^Deref_Expr:
		get_document_position(n.expr, position_context)
	case ^Slice_Expr:
		get_document_position(n.expr, position_context)
		get_document_position(n.low, position_context)
		get_document_position(n.high, position_context)
	case ^Field_Value:
		position_context.field_value = n
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
		r := n
		get_document_position(r.stmt, position_context)
	case ^Assign_Stmt:
		position_context.assign = n
		get_document_position(n.lhs, position_context)
		get_document_position(n.rhs, position_context)
	case ^Block_Stmt:
		get_document_position_label(n.label, position_context)
		get_document_position(n.stmts, position_context)
	case ^If_Stmt:
		get_document_position_label(n.label, position_context)
		get_document_position(n.init, position_context)
		get_document_position(n.cond, position_context)
		get_document_position(n.body, position_context)
		get_document_position(n.else_stmt, position_context)
	case ^When_Stmt:
		get_document_position(n.cond, position_context)
		get_document_position(n.body, position_context)
		get_document_position(n.else_stmt, position_context)
	case ^Return_Stmt:
		position_context.returns = n
		get_document_position(n.results, position_context)
	case ^Defer_Stmt:
		get_document_position(n.stmt, position_context)
	case ^For_Stmt:
		get_document_position_label(n.label, position_context)
		get_document_position(n.init, position_context)
		get_document_position(n.cond, position_context)
		get_document_position(n.post, position_context)
		get_document_position(n.body, position_context)
	case ^Range_Stmt:
		get_document_position_label(n.label, position_context)
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
		get_document_position_label(n.label, position_context)
		get_document_position(n.init, position_context)
		get_document_position(n.cond, position_context)
		get_document_position(n.body, position_context)
	case ^Type_Switch_Stmt:
		position_context.switch_type_stmt = cast(^Type_Switch_Stmt)node
		get_document_position_label(n.label, position_context)
		get_document_position(n.tag, position_context)
		get_document_position(n.expr, position_context)
		get_document_position(n.body, position_context)
	case ^Branch_Stmt:
		get_document_position_label(n.label, position_context)
	case ^Using_Stmt:
		get_document_position(n.list, position_context)
	case ^Bad_Decl:
	case ^Value_Decl:
		position_context.value_decl = cast(^Value_Decl)node
		get_document_position(n.attributes, position_context)

		for name in n.names {
			if position_in_node(name, position_context.position) && n.end.line - 1 == position_context.line {
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
		position_context.struct_type = n
		get_document_position(n.poly_params, position_context)
		get_document_position(n.align, position_context)
		get_document_position(n.fields, position_context)
	case ^Union_Type:
		position_context.union_type = n
		get_document_position(n.poly_params, position_context)
		get_document_position(n.align, position_context)
		get_document_position(n.variants, position_context)
	case ^Enum_Type:
		position_context.enum_type = n
		get_document_position(n.base_type, position_context)
		get_document_position(n.fields, position_context)
	case ^Bit_Set_Type:
		position_context.bitset_type = n
		get_document_position(n.elem, position_context)
		get_document_position(n.underlying, position_context)
	case ^Map_Type:
		get_document_position(n.key, position_context)
		get_document_position(n.value, position_context)
	case ^Implicit_Selector_Expr:
		position_context.implicit = true
		position_context.implicit_selector_expr = n
		get_document_position(n.field, position_context)
	case ^Or_Else_Expr:
		get_document_position(n.x, position_context)
		get_document_position(n.y, position_context)
	case ^Or_Return_Expr:
		get_document_position(n.expr, position_context)
	case ^Or_Branch_Expr:
		get_document_position_label(n.label, position_context)
		get_document_position(n.expr, position_context)
	case ^Bit_Field_Type:
		position_context.bit_field_type = n
		get_document_position(n.backing_type, position_context)
		get_document_position(n.fields, position_context)
	case ^Bit_Field_Field:
		get_document_position(n.name, position_context)
		get_document_position(n.type, position_context)
		get_document_position(n.bit_size, position_context)
	case:
	}
}
