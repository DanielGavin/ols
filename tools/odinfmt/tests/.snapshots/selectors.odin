package odinfmt_test

main :: proc() {
	app_state.scene_framebuffer, app_state.scene_framebuffer_swap =
		app_state.scene_framebuffer_swap, app_state.scene_framebuffer
}
