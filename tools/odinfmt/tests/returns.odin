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
	return GRADIENTS_4D[gi] * delta.x +
        GRADIENTS_4D[gi | 1] * delta.y +
        GRADIENTS_4D[gi | 2] * delta.z + GRADIENTS_4D[gi | 3] * delta.w    
}