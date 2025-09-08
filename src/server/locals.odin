package server

import "core:fmt"
import "core:log"
import "core:odin/ast"

LocalFlag :: enum {
	Mutable, // or constant
	Variable, // or type
}

DocumentLocal :: struct {
	lhs:             ^ast.Expr,
	rhs:             ^ast.Expr,
	offset:          int,
	resolved_global: bool, //Some locals have already been resolved and are now in global space
	local_global:    bool, //Some locals act like globals, i.e. functions defined inside functions.
	pkg:             string,
	flags:           bit_set[LocalFlag],
	parameter:       bool,
}

LocalGroup :: map[string][dynamic]DocumentLocal

store_local :: proc(
	ast_context: ^AstContext,
	lhs: ^ast.Expr,
	rhs: ^ast.Expr,
	offset: int,
	name: string,
	local_global: bool,
	resolved_global: bool,
	flags: bit_set[LocalFlag],
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
			flags = flags,
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

GetGenericAssignmentFlag :: enum {
	SameLhsRhsCount,
}

GetGenericAssignmentFlags :: bit_set[GetGenericAssignmentFlag]

get_generic_assignment :: proc(
	file: ast.File,
	value: ^ast.Expr,
	ast_context: ^AstContext,
	results: ^[dynamic]^ast.Expr,
	calls: ^map[int]struct{},
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

		// If we have a call expr followed immediately by another call expr, we want to return value
		// of the second call. Eg a := foo()()
		if _, ok := v.expr.derived.(^Call_Expr); ok {
			symbol := Symbol{}
			if ok := internal_resolve_type_expression(ast_context, v.expr, &symbol); ok {
				if value, ok := symbol.value.(SymbolProcedureValue); ok {
					if len(value.return_types) == 1 {
						if proc_type, ok := value.return_types[0].type.derived.(^Proc_Type); ok {
							for return_item in proc_type.results.list {
								get_generic_assignment(
									file,
									return_item.type,
									ast_context,
									results,
									calls,
									flags,
									is_mutable,
								)
							}
							return
						} else if ident, ok := value.return_types[0].type.derived.(^ast.Ident); ok {
							if ok := internal_resolve_type_expression(ast_context, ident, &symbol); ok {
								if value, ok := symbol.value.(SymbolProcedureValue); ok {
									for return_item in value.return_types {
										get_generic_assignment(
											file,
											return_item.type,
											ast_context,
											results,
											calls,
											flags,
											is_mutable,
										)
									}
								}
							}
						}
					}
				}
			}
		}

		//We have to resolve early and can't rely on lazy evalutation because it can have multiple returns.
		if symbol, ok := resolve_type_expression(ast_context, v.expr); ok {
			#partial switch symbol_value in symbol.value {
			case SymbolProcedureValue:
				return_types := get_proc_return_types(ast_context, symbol, v, is_mutable)
				for ret in return_types {
					calls[len(results)] = {}
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
			case SymbolBasicValue:
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

	//We have two stages of getting locals: local non mutable and mutables, since they are treated differently in scopes by Odin.
	if ast_context.non_mutable_only && value_decl.is_mutable {
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
			flags: bit_set[LocalFlag]
			if value_decl.is_mutable {
				flags |= {.Mutable}

			}
			store_local(
				ast_context,
				name,
				value_decl.type,
				value_decl.end.offset,
				str,
				ast_context.non_mutable_only,
				false,
				flags,
				"",
				false,
			)
		}
		return
	}

	results := make([dynamic]^Expr, context.temp_allocator)
	calls := make(map[int]struct{}, 0, context.temp_allocator) //Have to track the calls, since they disallow use of variables afterwards

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
		flags: bit_set[LocalFlag]

		expr := results[result_i]
		if is_variable_declaration(expr) {
			flags |= {.Variable}
		}
		if value_decl.is_mutable {
			flags |= {.Mutable}
		}

		store_local(
			ast_context,
			name,
			expr,
			value_decl.end.offset,
			str,
			ast_context.non_mutable_only,
			false, // calls[result_i] or_else false, // TODO: find a good way to handle this
			flags,
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
	case ^ast.Defer_Stmt:
		get_locals_stmt(file, v.stmt, ast_context, document_position)
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
				store_local(ast_context, expr, selector, 0, name, false, ast_context.non_mutable_only, {.Mutable}, "", false)
			}
		case SymbolBitFieldValue:
			for name, i in v.names {
				selector := new_type(ast.Selector_Expr, v.types[i].pos, v.types[i].end, ast_context.allocator)
				selector.expr = expr
				selector.field = new_type(ast.Ident, v.types[i].pos, v.types[i].end, ast_context.allocator)
				selector.field.name = name
				store_local(ast_context, expr, selector, 0, name, false, ast_context.non_mutable_only, {.Mutable}, "", false)
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
	calls := make(map[int]struct{}, 0, context.temp_allocator)

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
				{.Mutable},
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
						{.Mutable},
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
			calls := make(map[int]struct{}, context.temp_allocator)
			get_generic_assignment(file, stmt.expr, ast_context, &results, &calls, {}, false)
			for val, i in stmt.vals {
				if ident, ok := unwrap_ident(val); ok {
					result_i := min(len(results) - 1, i)
					store_local(
						ast_context,
						ident,
						results[result_i],
						ident.pos.offset,
						ident.name,
						ast_context.non_mutable_only,
						false,
						{.Mutable},
						symbol.pkg,
						false,
					)
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
							{.Mutable},
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
							{.Mutable},
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
						{.Mutable},
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
						{.Mutable},
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
						{.Mutable},
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
						{.Mutable},
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
						{.Mutable},
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
								{.Mutable},
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
							{.Mutable},
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
						{.Mutable},
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
						{.Mutable},
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
						{.Mutable},
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
						{.Mutable},
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

	get_locals_stmt(file, stmt.init, ast_context, document_position)
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

	get_locals_stmt(file, stmt.tag, ast_context, document_position, true)

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
						{.Mutable},
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
						{.Mutable},
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
						{.Mutable},
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
						{.Mutable},
						"",
						false,
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
						{.Mutable},
						"",
						false,
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
	ast_context.resolving_locals = true
	defer ast_context.resolving_locals = false

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
