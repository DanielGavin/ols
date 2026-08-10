package odinfmt_test

return_with_paren_1 :: proc() {
	return(
		GRADIENTS_4D[gi] * delta.x +
		GRADIENTS_4D[gi | 1] * delta.y +
		GRADIENTS_4D[gi | 2] * delta.z +
		GRADIENTS_4D[gi | 3] * delta.w \
	)
}

return_without_paren_1 :: proc() {
	return(
		GRADIENTS_4D[gi] * delta.x +
		GRADIENTS_4D[gi | 1] * delta.y +
		GRADIENTS_4D[gi | 2] * delta.z +
		GRADIENTS_4D[gi | 3] * delta.w \
	)
}

returns_with_call_expression :: proc() {
	return resolve_type_comp_literal(
		ast_context,
		position_context,
		symbol,
		cast(^ast.Comp_Lit)field_value.value,
	)
}


return_with_multiple_identifiers :: proc() {
	return aaaaaaaaaaaaaaaaaa,
		bbbbbbbbbbbbbbbbbbbb,
		cccccccccccccccccccc,
		dddddddddddddddddddddddddd
}


return_with_call_expression_in_the_end :: proc() {
	return newlines_before_comment, cons_with_nopl(
		document,
		cons(text(p.indentation), line_suffix(comment.text)),
	)
}

return_with_comp_lit_expression_in_the_end :: proc() {
	return {
		alloc_fn = allocator_alloc_func,
		free_fn = allocator_free_func,
		user_data = cast(rawptr)context_ptr,
	}
}
