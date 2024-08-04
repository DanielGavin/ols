package odinfmt_test


main :: proc() {
	a :=
		.Group in options ? group(visit_expr(p, expr, called_from, options)) : visit_expr(p, expr, called_from, options)


	document = cons(
		document,
		.Group in options ? group(visit_expr(p, expr, called_from, options)) : visit_expr(p, expr, called_from, options),
	)
}
