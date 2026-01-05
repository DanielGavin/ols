#+feature dynamic-literals
package server

import "core:fmt"
import "core:log"
import "core:mem"
import "core:odin/ast"
import "core:odin/tokenizer"
import "core:path/filepath"
import path "core:path/slashpath"
import "core:reflect"
import "core:strconv"
import "core:strings"

import "src:common"

DeferredDepth :: 35

UsingStatement :: struct {
	alias:    string,
	pkg_name: string,
}

AstContext :: struct {
	locals:                    [dynamic]LocalGroup, //locals all the way to the document position
	globals:                   map[string]GlobalExpr,
	recursion_map:             map[rawptr]struct{},
	usings:                    [dynamic]UsingStatement,
	file:                      ast.File,
	allocator:                 mem.Allocator,
	imports:                   []Package, //imports for the current document
	current_package:           string,
	document_package:          string,
	deferred_package:          [DeferredDepth]string, //When a package change happens when resolving
	deferred_count:            int,
	use_locals:                bool,
	use_usings:                bool,
	call:                      ^ast.Call_Expr, //used to determine the types for generics and the correct function for overloaded functions
	value_decl:                ^ast.Value_Decl,
	field_name:                ast.Ident,
	uri:                       string,
	fullpath:                  string,
	non_mutable_only:          bool, //Only store local value declarations that are non mutable.
	overloading:               bool,
	position_hint:             DocumentPositionContextHint,
	resolving_locals:          bool,
	// Explicitly set whether to only resolve the correct overload, rather than have it be inferred by
	// whether we're resolving locals and the position hint
	//
	// We should probably rework how this is handled in the future
	resolve_specific_overload: bool,
	call_expr_recursion_cache: map[rawptr]SymbolResult,
}

SymbolResult :: struct {
	symbol: Symbol,
	ok:     bool,
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
		locals                    = make([dynamic]map[string][dynamic]DocumentLocal, 0, allocator),
		globals                   = make(map[string]GlobalExpr, 0, allocator),
		usings                    = make([dynamic]UsingStatement, allocator),
		recursion_map             = make(map[rawptr]struct{}, 0, allocator),
		call_expr_recursion_cache = make(map[rawptr]SymbolResult, 0, allocator),
		file                      = file,
		imports                   = imports,
		use_locals                = true,
		use_usings                = true,
		document_package          = package_name,
		current_package           = package_name,
		uri                       = uri,
		fullpath                  = fullpath,
		allocator                 = allocator,
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

// odinfmt: disable
untyped_map: [SymbolUntypedValueType][]string = {
	.Integer    = {
		"int", "uint", "u8", "i8", "u16", "i16", "u32", "i32", "u64", "i64", "u128", "i128", "byte",
		"i16le", "i16be", "i32le", "i32be", "i64le", "i64be", "i128le", "i128be",
		"u16le", "u16be", "u32le", "u32be", "u64le", "u64be", "u128le", "u128be",
	},
	.Bool       = {"bool", "b8", "b16", "b32", "b64"},
	.Float      = {"f16", "f32", "f64", "f16le", "f16be", "f32le", "f32be", "f64le", "f64be"},
	.String     = {"string", "cstring"},
	.Complex    = {"complex32", "complex64", "complex128"},
	.Quaternion = {"quaternion64", "quaternion128", "quaternion256"},
}
// odinfmt: enable

// NOTE: This function is not commutative
are_symbol_untyped_basic_same_typed :: proc(a, b: Symbol) -> (bool, bool) {
	if untyped, ok := a.value.(SymbolUntypedValue); ok {
		if basic, ok := b.value.(SymbolBasicValue); ok {
			names := untyped_map[untyped.type]
			for name in names {
				if basic.ident.name == name {
					return true, true
				}
			}
			// Untyped ints are allowed to map to floats
			if untyped.type == .Integer {
				names := untyped_map[.Float]
				for name in names {
					if basic.ident.name == name {
						return true, true
					}
				}
			}
			return false, true
		} else if untyped_b, ok := b.value.(SymbolUntypedValue); ok {
			return untyped.type == untyped_b.type, true
		}
	}
	return false, false
}

are_symbol_basic_same_keywords :: proc(a, b: Symbol) -> bool {
	if are_keyword_aliases(a.name, b.name) {
		return true
	}
	a_value, a_ok := a.value.(SymbolBasicValue)
	if !a_ok {
		return false
	}

	b_value, b_ok := b.value.(SymbolBasicValue)
	if !b_ok {
		return false
	}
	if a_value.ident.name != b_value.ident.name {
		return false
	}
	if _, ok := keyword_map[a_value.ident.name]; !ok {
		return false
	}
	if _, ok := keyword_map[b_value.ident.name]; !ok {
		return false
	}

	return true
}

is_valid_nil_symbol :: proc(symbol: Symbol) -> bool {
	if symbol.pointers > 0 {
		return true
	}

	#partial switch v in symbol.value {
	case SymbolMapValue, SymbolSliceValue, SymbolProcedureValue, SymbolDynamicArrayValue:
		return true
	case SymbolUnionValue:
		return v.kind != .no_nil
	}

	return false
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
			names := untyped_map[.Integer]
			for name in names {
				if a.name == name {
					return true
				}
			}
		}
	}

	if are_symbol_basic_same_keywords(a, b) {
		return true
	}

	#partial switch a_value in a.value {
	case SymbolBasicValue:
		b_value := b.value.(SymbolBasicValue)
		return a_value.ident.name == b_value.ident.name && a.pkg == b.pkg
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
		if !are_same_size(ast_context, a_value.len, b_value.len) {
			return false
		}

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
	case SymbolMatrixValue:
		b_value := b.value.(SymbolMatrixValue)
		if !are_same_size(ast_context, a_value.x, b_value.x) {
			return false
		}

		if !are_same_size(ast_context, a_value.y, b_value.y) {
			return false
		}

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
	}

	return false
}

are_same_size :: proc(ast_context: ^AstContext, a, b: ^ast.Expr) -> bool {
	if a_symbol, ok := resolve_type_expression(ast_context, a); ok {
		if b_symbol, ok := resolve_type_expression(ast_context, b); ok {
			if a_len, ok := a_symbol.value.(SymbolUntypedValue); ok && a_len.type == .Integer {
				if b_len, ok := b_symbol.value.(SymbolUntypedValue); ok && b_len.type == .Integer {
					return a_len.tok.text == b_len.tok.text
				}
			}
		}
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


should_resolve_all_proc_overload_possibilities :: proc(ast_context: ^AstContext, call_expr: ^ast.Call_Expr) -> bool {
	// TODO: We need a better way to handle this
	if ast_context.resolve_specific_overload {
		return false
	}

	if ast_context.resolving_locals {
		return false
	}

	return ast_context.position_hint == .Completion || ast_context.position_hint == .SignatureHelp || call_expr == nil
}

/*
	Figure out which function the call expression is using out of the list from proc group
*/
resolve_function_overload :: proc(ast_context: ^AstContext, group: ^ast.Proc_Group) -> (Symbol, bool) {
	old_overloading := ast_context.overloading
	ast_context.overloading = true
	defer {
		ast_context.overloading = old_overloading
	}

	call_expr := ast_context.call
	if call_expr == nil || len(call_expr.args) == 0 {
		ast_context.overloading = false
	} else if call_expr != nil {
		// Due to some infinite loops with resolving symbols, we add an explicit cache for this function.
		// We may want to expand this in the future.
		//
		// See https://github.com/DanielGavin/ols/issues/1182
		if result, ok := check_call_expr_cache(ast_context, call_expr); ok {
			return result.symbol, result.ok
		}
	}

	resolve_all_possibilities := should_resolve_all_proc_overload_possibilities(ast_context, call_expr)
	call_unnamed_arg_count := 0
	if call_expr != nil {
		call_unnamed_arg_count = get_unnamed_arg_count(call_expr.args)
	}

	candidates := make([dynamic]Candidate, context.temp_allocator)

	for arg_expr in group.args {
		f := Symbol{}
		next_fn: if ok := internal_resolve_type_expression(ast_context, arg_expr, &f); ok {
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
					if call_expr != nil && arg_count < len(call_expr.args) {
						break next_fn
					}
					if arg_count == len(call_expr.args) {
						candidate.score /= 2
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
						is_call_arg_nil: bool
						implicit_selector: ^ast.Implicit_Selector_Expr

						if _, ok = call_arg.derived.(^ast.Bad_Expr); ok {
							continue
						}

						//named parameter
						if field, is_field := call_arg.derived.(^ast.Field_Value); is_field {
							named = true
							if ident, is_ident := field.value.derived.(^ast.Ident); is_ident && ident.name == "nil" {
								is_call_arg_nil = true
								ok = true
							} else if implicit, is_implicit := field.value.derived.(^ast.Implicit_Selector_Expr);
							   is_implicit {
								implicit_selector = implicit
								ok = true
							} else {
								call_symbol, ok = resolve_call_arg_type_expression(ast_context, field.value)
								if !ok {
									break next_fn
								}
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
							if ident, is_ident := call_arg.derived.(^ast.Ident); is_ident && ident.name == "nil" {
								is_call_arg_nil = true
								ok = true
							} else if implicit, is_implicit_selector := call_arg.derived.(^ast.Implicit_Selector_Expr);
							   is_implicit_selector {
								implicit_selector = implicit
								ok = true
							} else {
								call_symbol, ok = resolve_call_arg_type_expression(ast_context, call_arg)
							}
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

						// If an arg is a parapoly type, we assume it can match any symbol and return all possible
						// matches
						if _, ok := call_symbol.value.(SymbolPolyTypeValue); ok {
							resolve_all_possibilities = true
							continue
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

						if implicit_selector != nil {
							if value, ok := arg_symbol.value.(SymbolEnumValue); ok {
								found: bool
								for name in value.names {
									if implicit_selector.field.name == name {
										found = true
										break
									}
								}
								if found {
									continue
								}

							}
							break next_fn
						}

						if is_call_arg_nil {
							if is_valid_nil_symbol(arg_symbol) {
								continue
							} else {
								break next_fn
							}

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

	get_candidate_symbol :: proc(candidates: []Candidate, resolve_all_possibilities: bool) -> (Symbol, bool) {
		if candidate, ok := get_top_candiate(candidates); ok {
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
		return {}, false
	}

	symbol, ok := get_candidate_symbol(candidates[:], resolve_all_possibilities)
	if call_expr != nil {
		ast_context.call_expr_recursion_cache[cast(rawptr)call_expr] = SymbolResult {
			symbol = symbol,
			ok     = ok,
		}
	}
	return symbol, ok
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

	#partial switch basic_lit.tok.kind {
	case .Integer:
		value.type = .Integer
	case .Float:
		value.type = .Float
	case .Imag:
		if v, ok := strconv.parse_complex64(basic_lit.tok.text); ok {
			value.type = .Complex
		} else {
			value.type = .Quaternion
		}
	case:
		if v, ok := strconv.parse_int(basic_lit.tok.text); ok {
			value.type = .Integer
		} else if v, ok := strconv.parse_bool(basic_lit.tok.text); ok {
			value.type = .Bool
		} else if v, ok := strconv.parse_f64(basic_lit.tok.text); ok {
			value.type = .Float
		} else {
			value.type = .String
		}
	}

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
	if ret, ok := check_builtin_proc_return_type(ast_context, symbol, call, is_mutable); ok {
		appended := false
		if call, ok := ret.derived.(^ast.Call_Expr); ok {
			symbol := Symbol{}
			if ok := internal_resolve_type_expression(ast_context, call.expr, &symbol); ok {
				return get_proc_return_types(ast_context, symbol, call, true)
			}
		}
		append(&return_types, ret)
	} else if v, ok := symbol.value.(SymbolProcedureValue); ok {
		for ret in v.return_types {
			// Need min 1 loop for when return types aren't named, and to loop correctly when we have returns
			// like -> (a, b, c: int)
			for _ in 0 ..< max(1, len(ret.names)) {
				if ret.type != nil {
					append(&return_types, ret.type)
				} else if ret.default_value != nil {
					append(&return_types, ret.default_value)
				}
			}
		}
	}

	return return_types[:]
}

check_node_recursion :: proc(ast_context: ^AstContext, node: ^ast.Node) -> bool {
	raw := cast(rawptr)node

	if raw in ast_context.recursion_map {
		return true
	}

	ast_context.recursion_map[raw] = {}

	return false
}

check_call_expr_cache :: proc(ast_context: ^AstContext, expr: ^ast.Call_Expr) -> (SymbolResult, bool) {
	if result, ok := ast_context.call_expr_recursion_cache[cast(rawptr)expr]; ok {
		return result, ok
	}

	return {}, false
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
	symbol := Symbol{}
	ok := internal_resolve_type_expression(ast_context, node, &symbol)
	return symbol, ok
}

// We use an out param for the symbol in this proc due to issues with the stack size
//
// See https://github.com/odin-lang/Odin/issues/5528
internal_resolve_type_expression :: proc(ast_context: ^AstContext, node: ^ast.Expr, out: ^Symbol) -> bool {
	if node == nil {
		return false
	}

	//Try to prevent stack overflows and prevent indexing out of bounds.
	if ast_context.deferred_count >= DeferredDepth {
		return false
	}

	set_ast_package_from_node_scoped(ast_context, node)

	if check_node_recursion(ast_context, node) {
		return false
	}

	using ast
	ok := false

	#partial switch v in node.derived {
	case ^ast.Typeid_Type:
		ident := new_type(ast.Ident, v.pos, v.end, context.temp_allocator)
		ident.name = "typeid"
		out^, ok = make_symbol_basic_type_from_ast(ast_context, ident), true
		return ok
	case ^ast.Value_Decl:
		if v.type != nil {
			return internal_resolve_type_expression(ast_context, v.type, out)
		} else if len(v.values) > 0 {
			return internal_resolve_type_expression(ast_context, v.values[0], out)
		}
	case ^Union_Type:
		out^, ok = make_symbol_union_from_ast(ast_context, v^, ast_context.field_name.name, true), true
		return ok
	case ^Enum_Type:
		out^, ok = make_symbol_enum_from_ast(ast_context, v^, ast_context.field_name.name, true), true
		return ok
	case ^Struct_Type:
		out^, ok = make_symbol_struct_from_ast(ast_context, v, ast_context.field_name.name, {}, true), true
		return ok
	case ^Bit_Set_Type:
		out^, ok = make_symbol_bitset_from_ast(ast_context, v^, ast_context.field_name, true), true
		return ok
	case ^Array_Type:
		out^, ok = make_symbol_array_from_ast(ast_context, v^, ast_context.field_name), true
		return ok
	case ^Matrix_Type:
		out^, ok = make_symbol_matrix_from_ast(ast_context, v^, ast_context.field_name), true
		return ok
	case ^Dynamic_Array_Type:
		out^, ok = make_symbol_dynamic_array_from_ast(ast_context, v^, ast_context.field_name), true
		return ok
	case ^Multi_Pointer_Type:
		out^, ok = make_symbol_multi_pointer_from_ast(ast_context, v^, ast_context.field_name), true
		return ok
	case ^Map_Type:
		out^, ok = make_symbol_map_from_ast(ast_context, v^, ast_context.field_name), true
		return ok
	case ^Proc_Type:
		out^, ok =
			make_symbol_procedure_from_ast(ast_context, node, v^, ast_context.field_name.name, {}, true, .None, nil),
			true
		return ok
	case ^Bit_Field_Type:
		out^, ok = make_symbol_bit_field_from_ast(ast_context, v, ast_context.field_name.name, true), true
		return ok
	case ^Basic_Directive:
		out^, ok = resolve_basic_directive(ast_context, v^)
		return ok
	case ^Binary_Expr:
		out^, ok = resolve_binary_expression(ast_context, v)
		return ok
	case ^Ident:
		delete_key(&ast_context.recursion_map, v)
		out^, ok = internal_resolve_type_identifier(ast_context, v^)
		return ok
	case ^Basic_Lit:
		out^, ok = resolve_basic_lit(ast_context, v^)
		return ok
	case ^Type_Cast:
		ok = internal_resolve_type_expression(ast_context, v.type, out)
		out.type = .Variable
		return ok
	case ^Auto_Cast:
		ok = internal_resolve_type_expression(ast_context, v.expr, out)
		out.type = .Variable
		return ok
	case ^Comp_Lit:
		return internal_resolve_type_expression(ast_context, v.type, out)
	case ^Unary_Expr:
		ok := internal_resolve_type_expression(ast_context, v.expr, out)
		if v.op.kind == .And {
			out.pointers += 1
		} else if v.op.kind == .Sub || v.op.kind == .Add || v.op.kind == .Not || v.op.kind == .Xor {
			if value, ok := out.value.(SymbolProcedureValue); ok {
				if len(value.return_types) > 0 {
					type := value.return_types[0].type
					if type == nil {
						type = value.return_types[0].default_value
					}
					ok = internal_resolve_type_expression(ast_context, type, out)
					return ok
				}
			}
		}
		return ok
	case ^Deref_Expr:
		ok := internal_resolve_type_expression(ast_context, v.expr, out)
		out.pointers -= 1
		return ok
	case ^Paren_Expr:
		ok = internal_resolve_type_expression(ast_context, v.expr, out)
		if value, ok := out.value.(SymbolProcedureValue); ok {
			if len(value.return_types) > 0 {
				type := value.return_types[0].type
				if type == nil {
					type = value.return_types[0].default_value
				}
				ok = internal_resolve_type_expression(ast_context, type, out)
				return ok
			}
		}
		return ok
	case ^Slice_Expr:
		out^, ok = resolve_slice_expression(ast_context, v, v.expr)
		return ok
	case ^Tag_Expr:
		return internal_resolve_type_expression(ast_context, v.expr, out)
	case ^Helper_Type:
		return internal_resolve_type_expression(ast_context, v.type, out)
	case ^Ellipsis:
		out.range = common.get_token_range(v.node, ast_context.file.src)
		out.type = .Type
		out.pkg = get_package_from_node(v.node)
		out.name = ast_context.field_name.name
		out.uri = common.create_uri(v.pos.file, ast_context.allocator).uri
		out.value = SymbolSliceValue {
			expr = v.expr,
		}
		return true
	case ^Implicit:
		ident := new_type(Ident, v.node.pos, v.node.end, ast_context.allocator)
		ident.name = v.tok.text
		out^, ok = internal_resolve_type_identifier(ast_context, ident^)
		return ok
	case ^Type_Assertion:
		out^, ok = resolve_type_assertion_expr(ast_context, v)
		return ok
	case ^Proc_Lit:
		if v.type.results != nil {
			if len(v.type.results.list) > 0 {
				return internal_resolve_type_expression(ast_context, v.type.results.list[0].type, out)
			}
		}
	case ^Pointer_Type:
		ok := internal_resolve_type_expression(ast_context, v.elem, out)
		out.pointers += 1
		if pointer_is_soa(v^) {
			out.flags += {.SoaPointer}
		}
		return ok
	case ^Matrix_Index_Expr:
		if ok := internal_resolve_type_expression(ast_context, v.expr, out); ok {
			if mat, ok := out.value.(SymbolMatrixValue); ok {
				return internal_resolve_type_expression(ast_context, mat.expr, out)
			}
		}
	case ^Index_Expr:
		out^, ok = resolve_index_expr(ast_context, v, v.expr)
		return ok
	case ^Call_Expr:
		old_call := ast_context.call
		ast_context.call = cast(^Call_Expr)node

		defer {
			ast_context.call = old_call
		}
		out^, ok = resolve_call_expr(ast_context, v)
		return ok
	case ^Selector_Call_Expr:
		out^, ok = resolve_selector_call_expr(ast_context, v)
		return ok
	case ^Selector_Expr:
		out^, ok = resolve_selector_expression(ast_context, v)
		return ok
	case ^ast.Poly_Type:
		if v.specialization != nil {
			return internal_resolve_type_expression(ast_context, v.specialization, out)
		}
		out^ = make_symbol_poly_type_from_ast(ast_context, v.type)
		return true
	case ^ast.Ternary_If_Expr:
		ok = internal_resolve_type_expression(ast_context, v.x, out)
		return ok
	case ^ast.Ternary_When_Expr:
		ok = internal_resolve_type_expression(ast_context, v.x, out)
		return ok
	case:
		log.warnf("default node kind, internal_resolve_type_expression: %v", v)
	}

	return false
}

resolve_call_expr :: proc(ast_context: ^AstContext, v: ^ast.Call_Expr) -> (Symbol, bool) {
	symbol := Symbol{}
	// The function being called may be a local variable
	ast_context.use_locals = true
	if ident, ok := v.expr.derived.(^ast.Ident); ok && len(v.args) >= 1 {
		switch ident.name {
		case "type_of":
			ast_context.call = nil
			ok = internal_resolve_type_expression(ast_context, v.args[0], &symbol)
			return symbol, ok
		}
	} else if call, ok := v.expr.derived.(^ast.Call_Expr); ok {
		// handle the case where we immediately call a proc returned by another proc
		// in this case we don't want to resolve all possibilities for a proc overload
		ast_context.resolve_specific_overload = true
		defer ast_context.resolve_specific_overload = false
		if ok := internal_resolve_type_expression(ast_context, v.expr, &symbol); ok {
			if value, ok := symbol.value.(SymbolProcedureValue); ok {
				if len(value.return_types) == 1 {
					ok = internal_resolve_type_expression(ast_context, value.return_types[0].type, &symbol)
					return symbol, ok
				}
			}
			return symbol, ok
		} else {
			return {}, false
		}
	} else if directive, ok := v.expr.derived.(^ast.Basic_Directive); ok {
		return resolve_call_directive(ast_context, v)
	}

	ok := internal_resolve_type_expression(ast_context, v.expr, &symbol)
	return symbol, ok
}

resolve_call_directive :: proc(ast_context: ^AstContext, call: ^ast.Call_Expr) -> (Symbol, bool) {
	directive, ok := call.expr.derived.(^ast.Basic_Directive)
	if !ok {
		return {}, false
	}

	switch directive.name {
	case "config":
		return resolve_type_expression(ast_context, call.args[1])
	case "load":
		if len(call.args) == 1 {
			ident := new_type(ast.Ident, call.pos, call.end, ast_context.allocator)
			ident.name = "u8"
			value := SymbolSliceValue {
				expr = ident,
			}
			symbol := Symbol {
				name  = "#load",
				pkg   = ast_context.current_package,
				value = value,
			}
			return symbol, true
		} else if len(call.args) == 2 {
			return resolve_type_expression(ast_context, call.args[1])
		}
	case "location":
		return lookup("Source_Code_Location", indexer.runtime_package, call.pos.file)
	case "hash", "load_hash":
		ident := new_type(ast.Ident, call.pos, call.end, ast_context.allocator)
		ident.name = "int"
		return resolve_type_identifier(ast_context, ident^)
	case "load_directory":
		pkg := new_type(ast.Ident, call.pos, call.end, ast_context.allocator)
		pkg.name = "runtime"
		field := new_type(ast.Ident, call.pos, call.end, ast_context.allocator)
		field.name = "Load_Directory_File"
		selector := new_type(ast.Selector_Expr, call.pos, call.end, ast_context.allocator)
		selector.expr = pkg
		selector.field = field
		value := SymbolSliceValue {
			expr = selector,
		}
		symbol := Symbol {
			name  = "#load_directory",
			pkg   = ast_context.current_package,
			value = value,
		}
		return symbol, true
	}

	return {}, false
}

resolve_index_expr :: proc(ast_context: ^AstContext, index_expr: ^ast.Index_Expr, expr: ^ast.Expr) -> (Symbol, bool) {
	indexed := Symbol{}
	ok := internal_resolve_type_expression(ast_context, expr, &indexed)

	if !ok {
		return {}, false
	}

	symbol: Symbol

	#partial switch v in indexed.value {
	case SymbolDynamicArrayValue:
		if .Soa in indexed.flags {
			indexed.flags |= { .SoaPointer }
			return indexed, true
		}
		ok = internal_resolve_type_expression(ast_context, v.expr, &symbol)
	case SymbolSliceValue:
		ok = internal_resolve_type_expression(ast_context, v.expr, &symbol)
		if .Soa in indexed.flags {
			indexed.flags |= { .SoaPointer }
			return indexed, true
		}
	case SymbolFixedArrayValue:
		ok = internal_resolve_type_expression(ast_context, v.expr, &symbol)
		if .Soa in indexed.flags {
			indexed.flags |= { .SoaPointer }
			return indexed, true
		}
	case SymbolMapValue:
		ok = internal_resolve_type_expression(ast_context, v.value, &symbol)
	case SymbolMultiPointerValue:
		ok = internal_resolve_type_expression(ast_context, v.expr, &symbol)
	case SymbolBasicValue:
		if v.ident.name == "string" {
			v.ident.name = "u8"
			indexed.name = "u8"
			return indexed, true
		}
		return {}, false
	case SymbolUntypedValue:
		if v.type == .String {
			value := SymbolBasicValue {
				ident = ast.new(ast.Ident, v.tok.pos, v.tok.pos),
			}
			value.ident.name = "u8"
			indexed.name = "u8"
			indexed.value = value
			return indexed, true
		}
		return {}, false
	case SymbolMatrixValue:
		value := SymbolFixedArrayValue {
			expr = v.expr,
			len  = v.x,
		}
		indexed.value = value
		return indexed, true
	case SymbolProcedureValue:
		if len(v.return_types) != 1 {
			return {}, false
		}
		return resolve_index_expr(ast_context, index_expr, v.return_types[0].type)
	}

	symbol.type = indexed.type
	if .Soa in indexed.flags {
		symbol.flags |= {.SoaPointer}
	}

	return symbol, ok
}

resolve_selector_call_expr :: proc(ast_context: ^AstContext, v: ^ast.Selector_Call_Expr) -> (Symbol, bool) {
	selector := Symbol{}
	if ok := internal_resolve_type_expression(ast_context, v.expr, &selector); ok {
		ast_context.use_locals = false

		set_ast_package_from_symbol_scoped(ast_context, selector)

		#partial switch s in selector.value {
		case SymbolProcedureValue:
			if len(s.return_types) == 1 {
				symbol := Symbol{}
				ok := internal_resolve_type_expression(ast_context, s.return_types[0].type, &symbol)
				return symbol, ok
			}
		}

		return selector, true
	}
	return {}, false
}

resolve_type_assertion_expr :: proc(ast_context: ^AstContext, v: ^ast.Type_Assertion) -> (Symbol, bool) {
	symbol := Symbol{}
	if unary, ok := v.type.derived.(^ast.Unary_Expr); ok {
		if unary.op.kind == .Question {
			if ok := internal_resolve_type_expression(ast_context, v.expr, &symbol); ok {
				//To handle type assertions for unions, i.e. my_maybe_variable.?
				if union_value, ok := symbol.value.(SymbolUnionValue); ok {
					if len(union_value.types) != 1 {
						return {}, false
					}
					ok = internal_resolve_type_expression(ast_context, union_value.types[0], &symbol)
					return symbol, ok
				} else if proc_value, ok := symbol.value.(SymbolProcedureValue); ok {
					//To handle type assertions for unions returned from procedures, i.e: my_function().?
					if len(proc_value.return_types) != 1 || proc_value.return_types[0].type == nil {
						return {}, false
					}

					if ok := internal_resolve_type_expression(ast_context, proc_value.return_types[0].type, &symbol);
					   ok {
						if union_value, ok := symbol.value.(SymbolUnionValue); ok {
							if len(union_value.types) != 1 {
								return {}, false
							}
							ok = internal_resolve_type_expression(ast_context, union_value.types[0], &symbol)
							return symbol, ok
						}
					}
				}

			}
		}
	}
	ok := internal_resolve_type_expression(ast_context, v.type, &symbol)
	return symbol, ok
}

resolve_soa_selector_field :: proc(
	ast_context: ^AstContext,
	selector: Symbol,
	expr: ^ast.Expr,
	size: ^ast.Expr,
	name: string,
) -> (
	Symbol,
	bool,
) {
	if .Soa not_in selector.flags && .SoaPointer not_in selector.flags {
		return {}, false
	}

	ast_context.use_locals = true
	if symbol, ok := resolve_type_expression(ast_context, expr); ok {
		if v, ok := symbol.value.(SymbolStructValue); ok {
			for n, i in v.names {
				if n == name {
					if .SoaPointer in selector.flags {
						if resolved, ok := resolve_type_expression(ast_context, v.types[i]); ok {
							resolved.pkg = symbol.name
							resolved.range = v.ranges[i]
							resolved.type = .Field
							return resolved, ok
						} else {
							return {}, false
						}
					} else if size != nil {
						symbol.value = SymbolFixedArrayValue {
							expr = v.types[i],
							len  = size,
						}
					} else {
						symbol.value = SymbolMultiPointerValue {
							expr = v.types[i],
						}
					}

					symbol.name = name
					symbol.type = .Field
					symbol.range = v.ranges[i]
					return symbol, true
				}
			}
		}
	}

	return {}, false
}

resolve_selector_expression :: proc(ast_context: ^AstContext, node: ^ast.Selector_Expr) -> (Symbol, bool) {
	selector := Symbol{}
	if ok := internal_resolve_type_expression(ast_context, node.expr, &selector); ok {
		set_ast_package_from_symbol_scoped(ast_context, selector)

		symbol := Symbol{}
		#partial switch s in selector.value {
		case SymbolFixedArrayValue:
			if symbol, ok := resolve_soa_selector_field(ast_context, selector, s.expr, s.len, node.field.name); ok {
				return symbol, ok
			}
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

				ok := internal_resolve_type_expression(ast_context, s.expr, &symbol)
				symbol.type = .Field
				symbol.flags |= {.Mutable}
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
				ok := internal_resolve_type_expression(ast_context, selector_expr, &symbol)
				return symbol, ok
			}
		case SymbolStructValue:
			for name, i in s.names {
				if node.field != nil && name == node.field.name {
					set_ast_package_from_node_scoped(ast_context, s.types[i])
					ast_context.field_name = node.field^
					ok := internal_resolve_type_expression(ast_context, s.types[i], &symbol)
					symbol.type = .Field
					symbol.flags |= {.Mutable}
					return symbol, ok
				}
			}
		case SymbolBitFieldValue:
			for name, i in s.names {
				if node.field != nil && name == node.field.name {
					ast_context.field_name = node.field^
					ok := internal_resolve_type_expression(ast_context, s.types[i], &symbol)
					symbol.type = .Field
					symbol.flags |= {.Mutable}
					return symbol, ok
				}
			}
		case SymbolPackageValue:
			try_build_package(ast_context.current_package)

			if node.field != nil {
				return resolve_symbol_return(ast_context, lookup(node.field.name, selector.pkg, node.pos.file))
			} else {
				return Symbol{}, false
			}
		case SymbolEnumValue:
			// enum members probably require own symbol value
			selector.type = .EnumMember
			return selector, true
		case SymbolSliceValue:
			return resolve_soa_selector_field(ast_context, selector, s.expr, nil, node.field.name)
		case SymbolDynamicArrayValue:
			if node.field.name == "allocator" {
				return resolve_container_allocator(ast_context, "Raw_Dynamic_Array")
			}
			return resolve_soa_selector_field(ast_context, selector, s.expr, nil, node.field.name)
		case SymbolMapValue:
			if node.field.name == "allocator" {
				return resolve_container_allocator(ast_context, "Raw_Map")
			}
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

resolve_type_identifier :: proc(ast_context: ^AstContext, node: ast.Ident) -> (Symbol, bool) {
	return internal_resolve_type_identifier(ast_context, node)
}

internal_resolve_type_identifier :: proc(ast_context: ^AstContext, node: ast.Ident) -> (Symbol, bool) {
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
		return resolve_local_identifier(ast_context, node, &local)
	}

	if ast_context.use_usings {
		for u in ast_context.usings {
			for imp in ast_context.imports {
				if strings.compare(imp.name, u.pkg_name) == 0 {
					if symbol, ok := lookup(node.name, imp.name, node.pos.file); ok {
						return resolve_symbol_return(ast_context, symbol)
					}
				}
			}
		}
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
		return resolve_global_identifier(ast_context, node, &global)
	}

	switch node.name {
	case "context":
		for built in indexer.builtin_packages {
			if symbol, ok := lookup("Context", built, ""); ok {
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
		if symbol, ok := lookup(node.name, "$builtin", node.pos.file); ok {
			return resolve_symbol_return(ast_context, symbol)
		}
	}

	//last option is to check the index
	if symbol, ok := lookup(node.name, ast_context.current_package, node.pos.file); ok {
		return resolve_symbol_return(ast_context, symbol)
	}

	if !is_runtime {
		if symbol, ok := lookup(node.name, "$builtin", node.pos.file); ok {
			return resolve_symbol_return(ast_context, symbol)
		}
	}

	for built in indexer.builtin_packages {
		if symbol, ok := lookup(node.name, built, node.pos.file); ok {
			return resolve_symbol_return(ast_context, symbol)
		}
	}

	return Symbol{}, false
}

resolve_local_identifier :: proc(ast_context: ^AstContext, node: ast.Ident, local: ^DocumentLocal) -> (Symbol, bool) {
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
	case ^ast.Ident:
		return_symbol, ok = internal_resolve_type_identifier(ast_context, v^)
	case ^ast.Union_Type:
		return_symbol, ok = make_symbol_union_from_ast(ast_context, v^, node.name), true
		return_symbol.name = node.name
	case ^ast.Enum_Type:
		return_symbol, ok = make_symbol_enum_from_ast(ast_context, v^, node.name), true
		return_symbol.name = node.name
	case ^ast.Struct_Type:
		return_symbol, ok = make_symbol_struct_from_ast(ast_context, v, node.name, {}), true
		return_symbol.name = node.name
	case ^ast.Bit_Set_Type:
		return_symbol, ok = make_symbol_bitset_from_ast(ast_context, v^, node), true
		return_symbol.name = node.name
	case ^ast.Bit_Field_Type:
		return_symbol, ok = make_symbol_bit_field_from_ast(ast_context, v, node.name), true
		return_symbol.name = node.name
	case ^ast.Proc_Lit:
		return_symbol, ok = resolve_proc_lit(ast_context, local.rhs, v, node.name, {}, false)
	case ^ast.Proc_Group:
		return_symbol, ok = resolve_function_overload(ast_context, v)
	case ^ast.Array_Type:
		return_symbol, ok = make_symbol_array_from_ast(ast_context, v^, node), true
	case ^ast.Multi_Pointer_Type:
		return_symbol, ok = make_symbol_multi_pointer_from_ast(ast_context, v^, node), true
	case ^ast.Dynamic_Array_Type:
		return_symbol, ok = make_symbol_dynamic_array_from_ast(ast_context, v^, node), true
	case ^ast.Matrix_Type:
		return_symbol, ok = make_symbol_matrix_from_ast(ast_context, v^, node), true
	case ^ast.Map_Type:
		return_symbol, ok = make_symbol_map_from_ast(ast_context, v^, node), true
	case ^ast.Basic_Lit:
		return_symbol, ok = resolve_basic_lit(ast_context, v^)
		return_symbol.name = node.name
		return_symbol.type = .Mutable in local.flags ? .Variable : .Constant
	case ^ast.Binary_Expr:
		return_symbol, ok = resolve_binary_expression(ast_context, v)
	case:
		ok = internal_resolve_type_expression(ast_context, local.rhs, &return_symbol)
	}

	if is_distinct {
		return_symbol.name = node.name
		return_symbol.flags |= {.Distinct}
	}

	if local.parameter {
		return_symbol.flags |= {.Parameter}
	}

	if .Mutable in local.flags {
		return_symbol.type = .Variable
		return_symbol.flags |= {.Mutable}
	}
	if .Variable in local.flags {
		return_symbol.flags |= {.Variable}
	}

	return_symbol.flags |= {.Local}
	return_symbol.value_expr = local.value_expr
	return_symbol.type_expr = local.type_expr
	return_symbol.doc = get_comment(local.docs, ast_context.allocator)
	return_symbol.comment = get_comment(local.comment, ast_context.allocator)

	return return_symbol, ok
}

resolve_global_identifier :: proc(ast_context: ^AstContext, node: ast.Ident, global: ^GlobalExpr) -> (Symbol, bool) {
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
	case ^ast.Ident:
		return_symbol, ok = internal_resolve_type_identifier(ast_context, v^)
	case ^ast.Call_Expr:
		old_call := ast_context.call
		ast_context.call = cast(^ast.Call_Expr)global.expr

		defer {
			ast_context.call = old_call
		}
		if _, ok = v.expr.derived.(^ast.Basic_Directive); ok {
			return_symbol, ok = resolve_call_directive(ast_context, v)
		} else if ok = internal_resolve_type_expression(ast_context, v.expr, &return_symbol); ok {
			return_types := get_proc_return_types(ast_context, return_symbol, v, .Mutable in global.flags)
			if len(return_types) > 0 {
				ok = internal_resolve_type_expression(ast_context, return_types[0], &return_symbol)
			}
			// Otherwise should be a parapoly style
		}

	case ^ast.Struct_Type:
		return_symbol, ok = make_symbol_struct_from_ast(ast_context, v, node.name, global.attributes), true
		return_symbol.name = node.name
	case ^ast.Bit_Set_Type:
		return_symbol, ok = make_symbol_bitset_from_ast(ast_context, v^, node), true
		return_symbol.name = node.name
	case ^ast.Union_Type:
		return_symbol, ok = make_symbol_union_from_ast(ast_context, v^, node.name), true
		return_symbol.name = node.name
	case ^ast.Enum_Type:
		return_symbol, ok = make_symbol_enum_from_ast(ast_context, v^, node.name), true
		return_symbol.name = node.name
	case ^ast.Bit_Field_Type:
		return_symbol, ok = make_symbol_bit_field_from_ast(ast_context, v, node.name), true
		return_symbol.name = node.name
	case ^ast.Proc_Lit:
		return_symbol, ok = resolve_proc_lit(ast_context, global.expr, v, node.name, global.attributes, false)
	case ^ast.Proc_Group:
		return_symbol, ok = resolve_function_overload(ast_context, v)
	case ^ast.Array_Type:
		return_symbol, ok = make_symbol_array_from_ast(ast_context, v^, node), true
	case ^ast.Dynamic_Array_Type:
		return_symbol, ok = make_symbol_dynamic_array_from_ast(ast_context, v^, node), true
	case ^ast.Matrix_Type:
		return_symbol, ok = make_symbol_matrix_from_ast(ast_context, v^, node), true
	case ^ast.Map_Type:
		return_symbol, ok = make_symbol_map_from_ast(ast_context, v^, node), true
	case ^ast.Basic_Lit:
		return_symbol, ok = resolve_basic_lit(ast_context, v^)
		return_symbol.name = node.name
		return_symbol.type = .Mutable in global.flags ? .Variable : .Constant
	case:
		ok = internal_resolve_type_expression(ast_context, global.expr, &return_symbol)
	}

	if is_distinct {
		return_symbol.name = node.name
		return_symbol.flags |= {.Distinct}
	}

	if .Mutable in global.flags {
		return_symbol.type = .Variable
		return_symbol.flags |= {.Mutable}
	}

	if .Variable in global.flags {
		return_symbol.flags |= {.Variable}
	}

	if global.docs != nil {
		return_symbol.doc = get_comment(global.docs, ast_context.allocator)
	}

	if global.comment != nil {
		return_symbol.comment = get_comment(global.comment, ast_context.allocator)
	}

	return_symbol.type_expr = global.type_expr
	return_symbol.value_expr = global.value_expr

	return return_symbol, ok
}

resolve_proc_lit :: proc(
	ast_context: ^AstContext,
	node: ^ast.Node,
	proc_lit: ^ast.Proc_Lit,
	name: string,
	attributes: []^ast.Attribute,
	type: bool,
) -> (
	Symbol,
	bool,
) {
	symbol := make_symbol_procedure_from_ast(
		ast_context,
		node,
		proc_lit.type^,
		name,
		attributes,
		type,
		proc_lit.inlining,
		proc_lit.where_clauses,
	)

	if is_procedure_generic(proc_lit.type) {
		if generic_symbol, ok := resolve_generic_function(ast_context, proc_lit^, symbol); ok {
			return generic_symbol, ok
		} else if ast_context.overloading {
			return {}, false
		}
	}
	return symbol, true
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


resolve_slice_expression :: proc(
	ast_context: ^AstContext,
	slice_expr: ^ast.Slice_Expr,
	expr: ^ast.Expr,
) -> (
	symbol: Symbol,
	ok: bool,
) {
	symbol = resolve_type_expression(ast_context, expr) or_return

	expr: ^ast.Expr

	#partial switch v in symbol.value {
	case SymbolSliceValue:
		expr = v.expr
	case SymbolFixedArrayValue:
		expr = v.expr
	case SymbolDynamicArrayValue:
		expr = v.expr
	case SymbolMultiPointerValue:
		// Slicing multi-pointer behaviour outlined here: https://odin-lang.org/docs/overview/#multi-pointers
		if slice_expr.high == nil {
			return symbol, true
		}
		expr = v.expr
	case SymbolUntypedValue:
		if v.type == .String {
			return symbol, true
		}
		return {}, false
	case SymbolBasicValue:
		if v.ident.name == "string" {
			return symbol, true
		}
		return {}, false
	case SymbolProcedureValue:
		if len(v.return_types) != 1 {
			return {}, false
		}
		return resolve_slice_expression(ast_context, slice_expr, v.return_types[0].type)
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
	return internal_resolve_comp_literal(ast_context, position_context, resolve_type_expression)
}

resolve_location_comp_literal :: proc(
	ast_context: ^AstContext,
	position_context: ^DocumentPositionContext,
) -> (
	symbol: Symbol,
	ok: bool,
) {
	return internal_resolve_comp_literal(ast_context, position_context, resolve_location_type_expression)
}

internal_resolve_comp_literal :: proc(
	ast_context: ^AstContext,
	position_context: ^DocumentPositionContext,
	resolve_proc: proc(ast_context: ^AstContext, node: ^ast.Expr) -> (Symbol, bool),
) -> (
	symbol: Symbol,
	ok: bool,
) {
	if position_context.parent_comp_lit != nil && position_context.parent_comp_lit.type != nil {
		symbol = resolve_proc(ast_context, position_context.parent_comp_lit.type) or_return
	} else if position_context.call != nil {
		if call_expr, ok := position_context.call.derived.(^ast.Call_Expr); ok {
			type := get_call_argument_type(ast_context, position_context, call_expr) or_return
			symbol = resolve_proc(ast_context, type) or_return
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
			symbol = resolve_proc(
				ast_context,
				position_context.function.type.results.list[return_index].type,
			) or_return
		}
	} else if position_context.assign != nil {
		if len(position_context.assign.lhs) > 0 {
			if position_in_exprs(position_context.assign.lhs, position_context.position) {
				for n in position_context.assign.lhs {
					if position_in_node(n, position_context.position) {
						// check if we're a comp literal of a map key
						if index_expr, ok := n.derived.(^ast.Index_Expr); ok {
							if s, ok := resolve_proc(ast_context, index_expr.expr); ok {
								if value, ok := s.value.(SymbolMapValue); ok {
									symbol = resolve_proc(ast_context, value.key) or_return
								}
							}
						} else {
							symbol = resolve_proc(ast_context, n) or_return
						}
						break
					}
				}
			} else {
				index := 0
				for value, i in position_context.assign.rhs {
					if position_in_node(value, position_context.position) {
						index = i
						break
					}
				}
				// Just to be safe
				if index >= len(position_context.assign.lhs) {
					index = 0
				}
				symbol = resolve_proc(ast_context, position_context.assign.lhs[index]) or_return
			}
		}
	} else if position_context.value_decl != nil && position_context.value_decl.type != nil {
		symbol = resolve_proc(ast_context, position_context.value_decl.type) or_return
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

get_struct_comp_lit_type :: proc(
	position_context: ^DocumentPositionContext,
	comp_lit: ^ast.Comp_Lit,
	s: SymbolStructValue,
	field_name: string,
) -> ^ast.Expr {
	elem_index := -1

	for elem, i in comp_lit.elems {
		if position_in_node(elem, position_context.position) {
			elem_index = i
			if field_value, ok := elem.derived.(^ast.Field_Value); ok {
				// If our field is another comp_lit, check to see if we're actually in that one
				if cl, ok := field_value.value.derived.(^ast.Comp_Lit); ok {
					if type := get_struct_comp_lit_type(position_context, cl, s, field_name); type != nil {
						return type
					}
				}
			}
		}
	}

	if elem_index == -1 {
		return nil
	}

	type: ^ast.Expr

	for name, i in s.names {
		if name != field_name {
			continue
		}

		type = s.types[i]
		break
	}

	if type == nil && len(s.types) > elem_index && elem_index != -1 {
		type = s.types[elem_index]
	}

	return type
}


resolve_implicit_selector_comp_literal :: proc(
	ast_context: ^AstContext,
	position_context: ^DocumentPositionContext,
	symbol: Symbol,
) -> (
	Symbol,
	bool,
) {
	field_name := ""
	if position_context.field_value != nil {
		field_name, _ = get_field_value_name(position_context.field_value)
	}
	if comp_symbol, comp_lit, ok := resolve_type_comp_literal(
		ast_context,
		position_context,
		symbol,
		position_context.parent_comp_lit,
	); ok {
		#partial switch v in comp_symbol.value {
		case SymbolEnumValue, SymbolBitSetValue:
			return comp_symbol, ok
		case SymbolStructValue:
			set_ast_package_set_scoped(ast_context, comp_symbol.pkg)

			type := get_struct_comp_lit_type(position_context, comp_lit, v, field_name)

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
			if position_in_node(v.len, position_context.position) {
				return resolve_type_expression(ast_context, v.len)
			} else if position_in_node(v.expr, position_context.position) {
				return resolve_type_expression(ast_context, v.expr)
			}
			if _, _, ok := unwrap_enum(ast_context, v.len); ok {
				for elem in comp_lit.elems {
					if position_in_node(elem, position_context.position) {
						if field, ok := elem.derived.(^ast.Field_Value); ok {
							if position_in_node(field.field, position_context.position) {
								return resolve_type_expression(ast_context, v.len)
							}
							return resolve_type_expression(ast_context, v.expr)
						}
						return resolve_type_expression(ast_context, v.len)
					}
				}
			}
			return resolve_type_expression(ast_context, v.expr)
		case SymbolSliceValue:
			return resolve_type_expression(ast_context, v.expr)
		case SymbolDynamicArrayValue:
			return resolve_type_expression(ast_context, v.expr)
		case SymbolMapValue:
			for elem in comp_lit.elems {
				if position_in_node(elem, position_context.position) {
					if _, ok := elem.derived.(^ast.Field_Value); ok {
						return resolve_type_expression(ast_context, v.value)
					}
					return resolve_type_expression(ast_context, v.key)
				}
			}
		}
	}
	return {}, false
}

resolve_implicit_selector :: proc(
	ast_context: ^AstContext,
	position_context: ^DocumentPositionContext,
) -> (
	Symbol,
	bool,
) {
	if position_context.binary != nil {
		if position_in_node(position_context.binary, position_context.position) {
			// We resolve whichever is not the implicit_selector
			if implicit, ok := position_context.binary.left.derived.(^ast.Implicit_Selector_Expr); ok {
				return resolve_type_expression(ast_context, position_context.binary.right)
			}
			return resolve_type_expression(ast_context, position_context.binary.left)
		}
	}

	if position_context.call != nil {
		if call, ok := position_context.call.derived.(^ast.Call_Expr); ok {
			parameter_index, parameter_ok := find_position_in_call_param(position_context, call^)
			old := ast_context.resolve_specific_overload
			ast_context.resolve_specific_overload = true
			defer {
				ast_context.resolve_specific_overload = old
			}
			if symbol, ok := resolve_type_expression(ast_context, call.expr); ok && parameter_ok {
				if proc_value, ok := symbol.value.(SymbolProcedureValue); ok {
					if len(proc_value.arg_types) <= parameter_index {
						return {}, false
					}

					arg := proc_value.arg_types[parameter_index]
					type := arg.type
					if type == nil {
						type = arg.default_value
					}

					return resolve_type_expression(ast_context, type)
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

	if position_context.comp_lit != nil && position_context.parent_comp_lit != nil {
		if symbol, ok := resolve_comp_literal(ast_context, position_context); ok {
			return resolve_implicit_selector_comp_literal(ast_context, position_context, symbol)
		}
	}

	if position_context.value_decl != nil && position_context.value_decl.type != nil {
		if symbol, ok := resolve_type_expression(ast_context, position_context.value_decl.type); ok {
			if !ok {
				return {}, false
			}
			if position_context.parent_comp_lit != nil && position_context.field_value != nil {
				return resolve_implicit_selector_comp_literal(ast_context, position_context, symbol)
			}
		}
	}

	if position_context.switch_stmt != nil {
		ast_context.use_locals = true
		if position_in_node(position_context.switch_stmt.cond, position_context.position) {
			if symbol, ok := resolve_type_expression(ast_context, position_context.switch_stmt.cond); ok {
				return symbol, ok
			}
		}
		if body, ok := position_context.switch_stmt.body.derived.(^ast.Block_Stmt); ok {
			for stmt in body.stmts {
				if cc, ok := stmt.derived.(^ast.Case_Clause); ok {
					for item in cc.list {
						if position_in_node(item, position_context.position) {
							if symbol, ok := resolve_type_expression(ast_context, position_context.switch_stmt.cond);
							   ok {
								return symbol, ok
							}
						}
					}
				}
			}
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
				return resolve_implicit_selector_comp_literal(ast_context, position_context, current_symbol)
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
		if s, ok := resolve_function_overload(ast_context, v.group.derived.(^ast.Proc_Group)); ok {
			if s.doc == "" {
				s.doc = symbol.doc
			}
			if s.comment == "" {
				s.comment = symbol.comment
			}
			s.range = symbol.range
			s.uri = symbol.uri
			return s, true
		} else {
			return s, false
		}
	case SymbolProcedureValue:
		if v.generic {
			if resolved_symbol, ok := resolve_generic_function(
				ast_context,
				v.arg_types,
				v.return_types,
				v.inlining,
				symbol,
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
		b := symbol_struct_value_builder_make(symbol, v, ast_context.allocator)
		if v.poly != nil {
			clear(&b.types)
			for type in v.types {
				append(&b.types, clone_expr(type, context.temp_allocator, nil))
			}
			b.poly = cast(^ast.Field_List)clone_type(v.poly, context.temp_allocator, nil)
			resolve_poly_struct(ast_context, &b, v.poly)
		}

		//expand the types and names from the using - can't be done while indexing without complicating everything(this also saves memory)
		expand_objc(ast_context, &b)
		expand_usings(ast_context, &b)
		return to_symbol(b), ok
	case SymbolGenericValue:
		ret, ok := resolve_type_expression(ast_context, v.expr)
		if symbol.type == .Variable {
			ret.type = symbol.type
		}
		if .Variable in symbol.flags {
			ret.flags |= {.Variable}
		}
		if .Mutable in symbol.flags {
			ret.flags |= {.Mutable}
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
			symbol.flags |= ret.flags
			if symbol.doc == "" {
				symbol.doc = ret.doc
			}
			if symbol.comment == "" {
				symbol.comment = ret.comment
			}
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
	}

	if ast_context.use_usings {
		usings := get_using_packages(ast_context)

		for pkg in usings {
			if symbol, ok := lookup(node.name, pkg, node.pos.file); ok {
				return symbol, ok
			}
		}
	}

	if global, ok := ast_context.globals[node.name]; ok {
		symbol.range = common.get_token_range(global.name_expr, ast_context.file.src)
		uri := common.create_uri(global.expr.pos.file, ast_context.allocator)
		symbol.pkg = ast_context.document_package
		symbol.uri = uri.uri
		return symbol, true
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
				range = imp.range,
			}

			try_build_package(symbol.pkg)

			return symbol, true
		}
	}

	pkg := get_package_from_node(node)
	if symbol, ok := lookup(node.name, pkg, node.pos.file); ok {
		return symbol, ok
	}

	if symbol, ok := lookup(node.name, "$builtin", node.pos.file); ok {
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
		for arg in value.arg_types {
			for name_expr in arg.names {
				if name, ok := name_expr.derived.(^ast.Ident); ok {
					if name.name == ident.name {
						type := arg.type
						if type == nil {
							type = arg.default_value
						}
						if symbol, ok := resolve_type_expression(ast_context, type); ok {
							symbol.type_pkg = symbol.pkg
							symbol.type_name = symbol.name
							symbol.pkg = call_symbol.name
							symbol.name = ident.name
							symbol.type = .Field
							return symbol, true
						}
					}
				}
			}
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

	symbol = resolve_implicit_selector(ast_context, position_context) or_return

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

resolve_container_allocator :: proc(ast_context: ^AstContext, container_name: string) -> (Symbol, bool) {
	for built in indexer.builtin_packages {
		if symbol, ok := lookup(container_name, built, ast_context.fullpath); ok {
			if v, ok := symbol.value.(SymbolStructValue); ok {
				for name, i in v.names {
					if name == "allocator" {
						if symbol, ok := resolve_type_expression(ast_context, v.types[i]); ok {
							construct_struct_field_symbol(&symbol, container_name, v, i)
							build_documentation(ast_context, &symbol, true)
							return symbol, true
						}
					}
				}
			}
		}
	}

	return {}, false
}

resolve_container_allocator_location :: proc(ast_context: ^AstContext, container_name: string) -> (Symbol, bool) {
	for built in indexer.builtin_packages {
		if symbol, ok := lookup(container_name, built, ast_context.fullpath); ok {
			if v, ok := symbol.value.(SymbolStructValue); ok {
				for name, i in v.names {
					if name == "allocator" {
						symbol.range = v.ranges[i]
						symbol.type = .Field
						return symbol, true
					}
				}
			}
		}
	}

	return {}, false
}

resolve_location_selector :: proc(ast_context: ^AstContext, selector_expr: ^ast.Node) -> (symbol: Symbol, ok: bool) {
	reset_ast_context(ast_context)

	set_ast_package_set_scoped(ast_context, ast_context.document_package)

	if selector, ok := selector_expr.derived.(^ast.Selector_Expr); ok {
		ast_context.use_usings = false
		defer ast_context.use_usings = true

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
				symbol.type = .EnumMember
			}
		}
	case SymbolStructValue:
		for name, i in v.names {
			if strings.compare(name, field) == 0 {
				symbol.range = v.ranges[i]
				symbol.type = .Field
			}
		}
	case SymbolBitFieldValue:
		for name, i in v.names {
			if strings.compare(name, field) == 0 {
				symbol.range = v.ranges[i]
				symbol.type = .Field
			}
		}
	case SymbolPackageValue:
		if pkg, ok := lookup(field, symbol.pkg, symbol.uri); ok {
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
	case SymbolSliceValue:
		return resolve_soa_selector_field(ast_context, symbol, v.expr, nil, field)
	case SymbolDynamicArrayValue:
		if field == "allocator" {
			return resolve_container_allocator_location(ast_context, "Raw_Dynamic_Array")
		}
		return resolve_soa_selector_field(ast_context, symbol, v.expr, nil, field)
	case SymbolFixedArrayValue:
		return resolve_soa_selector_field(ast_context, symbol, v.expr, v.len, field)
	case SymbolMapValue:
		if field == "allocator" {
			return resolve_container_allocator_location(ast_context, "Raw_Map")
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
	case .Cmp_Eq, .Gt, .Gt_Eq, .Lt, .Lt_Eq, .Not_Eq, .In, .Not_In:
		symbol_a.value = SymbolUntypedValue {
			type = .Bool,
		}
		return symbol_a, true
	case .Shl, .Shr:
		return resolve_type_expression(ast_context, binary.left)
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
		// we return the type that was correctly resolved, if one of them was
		if ok_a {
			return symbol_a, true
		}
		if ok_b {
			return symbol_b, true
		}
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
		// we return the type that was correctly resolved, if one of them was
		if ok_a {
			return symbol_a, true
		}
		if ok_b {
			return symbol_b, true
		}
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

	if value_a, ok := symbol_a.value.(SymbolUntypedValue); ok {
		if value_b, ok := symbol_b.value.(SymbolUntypedValue); ok {
			if value_a.type == .Float {
				return symbol_a, true
			}
			return symbol_b, true
		} else {
			return symbol_b, ok_b
		}
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

get_call_argument_type :: proc(
	ast_context: ^AstContext,
	position_context: ^DocumentPositionContext,
	call: ^ast.Call_Expr,
) -> (
	expr: ^ast.Expr,
	ok: bool,
) {
	index := find_position_in_call_param(position_context, call^) or_return
	symbol := resolve_type_expression(ast_context, call) or_return
	value := symbol.value.(SymbolProcedureValue) or_return

	arg: ^ast.Field
	if field, ok := call.args[index].derived.(^ast.Field_Value); ok {
		ident := field.field.derived.(^ast.Ident) or_return
		arg = get_proc_arg_type_from_name(value, ident.name) or_return
	} else {
		arg = get_proc_arg_type_from_index(value, index) or_return
	}

	if arg.type == nil {
		return arg.default_value, true
	}

	return arg.type, true
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
	return get_package_from_filepath(node.pos.file)
}

get_package_from_filepath :: proc(file_path: string) -> string {
	slashed, _ := filepath.to_slash(file_path, context.temp_allocator)
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

// Returns whether the provided package is being used with a `using` statement
is_using_package :: proc(ast_context: ^AstContext, pkg: string) -> bool {
	for u in ast_context.usings {
		if strings.compare(pkg, u.pkg_name) == 0 {
			return true
		}
	}
	return false
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
	name: string,
	attributes: []^ast.Attribute,
	type: bool,
	inlining: ast.Proc_Inlining,
	where_clauses: []^ast.Expr,
) -> Symbol {
	pkg := ""
	if n != nil {
		pkg = get_package_from_node(n^)
	}
	symbol := Symbol {
		range = common.get_token_range(v, ast_context.file.src),
		type  = .Function if !type else .Type_Function,
		pkg   = pkg,
		name  = name,
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

	if expr, ok := ast_context.globals[name]; ok {
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
		where_clauses      = where_clauses,
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
	if array_is_simd(v) {
		symbol.flags |= {.Simd}
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

make_symbol_poly_type_from_ast :: proc(ast_context: ^AstContext, n: ^ast.Ident) -> Symbol {
	symbol := Symbol {
		range = common.get_token_range(n^, ast_context.file.src),
		type  = .Variable,
		pkg   = get_package_from_node(n^),
	}

	symbol.value = SymbolPolyTypeValue {
		ident = n,
	}

	return symbol
}

make_symbol_union_from_ast :: proc(
	ast_context: ^AstContext,
	v: ast.Union_Type,
	name: string,
	inlined := false,
) -> Symbol {
	symbol := Symbol {
		range = common.get_token_range(v, ast_context.file.src),
		type  = .Union,
		pkg   = get_package_from_node(v.node),
		name  = name,
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

	docs, comments := get_field_docs_and_comments(ast_context.file, v.variants, ast_context.allocator)

	symbol.value = SymbolUnionValue {
		types         = types[:],
		poly          = v.poly_params,
		docs          = docs[:],
		comments      = comments[:],
		kind          = v.kind,
		align         = v.align,
		where_clauses = v.where_clauses,
	}

	if v.poly_params != nil {
		resolve_poly_union(ast_context, v.poly_params, &symbol)
	}

	return symbol
}

make_symbol_enum_from_ast :: proc(
	ast_context: ^AstContext,
	v: ast.Enum_Type,
	name: string,
	inlined := false,
) -> Symbol {
	symbol := Symbol {
		range = common.get_token_range(v, ast_context.file.src),
		type  = .Enum,
		name  = name,
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

	docs, comments := get_field_docs_and_comments(ast_context.file, v.fields, ast_context.allocator)

	symbol.value = SymbolEnumValue {
		names     = names[:],
		ranges    = ranges[:],
		base_type = v.base_type,
		values    = values[:],
		docs      = docs[:],
		comments  = comments[:],
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
	name: string,
	attributes: []^ast.Attribute,
	inlined := false,
) -> Symbol {
	node := v.node
	symbol := Symbol {
		range = common.get_token_range(v, ast_context.file.src),
		type  = .Struct,
		pkg   = get_package_from_node(v.node),
		name  = name,
		uri   = common.create_uri(v.pos.file, ast_context.allocator).uri,
	}

	if inlined {
		symbol.flags |= {.Anonymous}
		symbol.name = "struct"
	}

	b := symbol_struct_value_builder_make(symbol, ast_context.allocator)
	write_struct_type(ast_context, &b, v, attributes, -1)
	symbol = to_symbol(b)
	return symbol
}

make_symbol_bit_field_from_ast :: proc(
	ast_context: ^AstContext,
	v: ^ast.Bit_Field_Type,
	name: string,
	inlined := false,
) -> Symbol {
	// We clone this so we don't override docs and comments with temp allocated docs and comments
	v := cast(^ast.Bit_Field_Type)clone_node(v, ast_context.allocator, nil)
	construct_bit_field_field_docs(ast_context.file, v)
	symbol := Symbol {
		range = common.get_token_range(v, ast_context.file.src),
		type  = .Struct,
		pkg   = get_package_from_node(v.node),
		name  = name,
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

// Returns the unwrapped enum, whether it unwrapped a super enum, whether it was successful
unwrap_enum :: proc(ast_context: ^AstContext, node: ^ast.Expr) -> (SymbolEnumValue, bool, bool) {
	if node == nil {
		return {}, false, false
	}

	if enum_symbol, ok := resolve_type_expression(ast_context, node); ok {
		#partial switch value in enum_symbol.value {
		case SymbolEnumValue:
			return value, false, true
		case SymbolUnionValue:
			result, ok := unwrap_super_enum(ast_context, value)
			return result, true, ok
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

	return {}, false, false
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
			for name in value.names {
				if ast_context.current_package != symbol.pkg {
					pkg_name := get_pkg_name(ast_context, symbol.pkg)
					append(
						&names,
						fmt.aprintf("%s.%s.%s", pkg_name, symbol.name, name, allocator = ast_context.allocator),
					)
				} else {
					append(&names, fmt.aprintf("%s.%s", symbol.name, name, allocator = ast_context.allocator))
				}
			}
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

position_in_struct_decl :: proc(position_context: ^DocumentPositionContext) -> bool {
	if position_context.value_decl == nil {
		return false
	}

	if len(position_context.value_decl.values) != 1 {
		return false
	}

	if _, ok := position_context.value_decl.values[0].derived.(^ast.Struct_Type); ok {
		return true
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
