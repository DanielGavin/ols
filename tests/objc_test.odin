package tests

import "core:fmt"
import "core:testing"

import test "src:testing"


@(test)
cobj_return_type_with_selector_expression :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package)

	append(
		&packages,
		test.Package {
			pkg = "my_package",
			source = `package my_package    
            @(objc_class="NSWindow")
            Window :: struct { dummy: int}

            @(objc_type=Window, objc_name="alloc", objc_is_class_method=true)
            Window_alloc :: proc "c" () -> ^Window {
            }
			@(objc_type=Window, objc_name="initWithContentRect")
			Window_initWithContentRect :: proc (self: ^Window, contentRect: Rect, styleMask: WindowStyleMask, backing: BackingStoreType, doDefer: BOOL) -> ^Window {			
			}
		`,
		},
	)

	source := test.Source {
		main     = `package test
        import "my_package"

		main :: proc() {
            window := my_package.Window.alloc()->{*}
		}
		`,
		packages = packages[:],
	}

	test.expect_completion_details(
		t,
		&source,
		"->",
		{"Window.initWithContentRect: my_package.Window_initWithContentRect"},
	)
}
