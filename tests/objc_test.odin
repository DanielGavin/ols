package tests

import "core:slice"
import "core:strings"
import "core:testing"

import test "src:testing"

// Objective-C regressions: contextual instancetype through inheritance, aliases,
// calls and parentheses; method definition locations and inferred selector names;
// inherited ivars, shadowing and completion order with fake methods retained;
// Objc_Block capture completion/hover and handler edits for incomplete calls.

objc_test_packages :: proc() -> []test.Package {
	packages := make([dynamic]test.Package, context.temp_allocator)
	append(
		&packages,
		test.Package {
			pkg = "base/intrinsics",
			source = `package intrinsics_test
objc_instancetype :: distinct rawptr
Objc_Block :: struct($T: typeid) {}
objc_block :: proc(invoke: $T, args: ..any) -> ^Objc_Block(T) ---
`,
		},
		test.Package {
			pkg = "CA",
			source = `package CA
import intrinsics "base/intrinsics"

InstanceType :: intrinsics.objc_instancetype

Drawable :: struct {}

@(objc_class="CALayer")
Layer :: struct {}

@(objc_type=Layer, objc_name="layer", objc_is_class_method=true)
Layer_layer :: proc "c" () -> InstanceType ---

@(objc_class="CAMetalLayer")
MetalLayer :: struct {using _: Layer}

@(objc_type=MetalLayer, objc_name="nextDrawable")
MetalLayer_nextDrawable :: proc "c" (self: ^MetalLayer) -> ^Drawable ---

IvarGrandparentStorage :: struct {
	grandparent_value: int,
}

@(objc_class="IvarGrandparent", objc_implement, objc_ivar=IvarGrandparentStorage)
IvarGrandparent :: struct {}

IvarParentStorage :: struct {
	parent_value: int,
	shared:       int,
}

@(objc_class="IvarParent", objc_implement, objc_superclass=IvarGrandparent, objc_ivar=IvarParentStorage)
IvarParent :: struct {}

IvarChildStorage :: struct {
	child_value: string,
	shared:      bool,
}

@(objc_class="IvarChild", objc_implement, objc_superclass=IvarParent, objc_ivar=IvarChildStorage)
IvarChild :: struct {}

@(objc_type=IvarChild, objc_name="perform")
IvarChild_perform :: proc "c" (self: ^IvarChild) ---

@(objc_type=IvarChild, objc_name="observe")
IvarChild_observe :: proc "c" (self: ^IvarChild, block: ^intrinsics.Objc_Block(proc(value: int))) ---

@(objc_type=IvarChild)
IvarChild_inferred :: proc "c" (self: ^IvarChild) ---

@(objc_type=IvarChild)
Unrelated_name :: proc "c" (self: ^IvarChild) ---

@(objc_type=IvarChild, objc_name="renamed")
IvarChild_physical :: proc "c" (self: ^IvarChild) ---

@(objc_class="IvarLeaf", objc_implement, objc_superclass=IvarChild)
IvarLeaf :: struct {}

@(objc_type=IvarLeaf, objc_name="perform")
IvarLeaf_perform :: proc "c" (self: ^IvarLeaf) ---

IvarLeaf_fake_method :: proc(self: ^IvarLeaf) ---
`,
		},
		test.Package {
			pkg = "NS",
			source = `package NS
import intrinsics "base/intrinsics"

A :: intrinsics.objc_instancetype
B :: A
C :: B

@(objc_class="NSObject")
Object :: struct {}

@(objc_type=Object, objc_name="alloc", objc_is_class_method=true)
Object_alloc :: proc "c" () -> C ---

@(objc_type=Object, objc_name="init")
Object_init :: proc "c" (self: ^Object) -> C ---

@(objc_class="NSAutoreleasePool")
AutoreleasePool :: struct {using _: Object}

@(objc_type=AutoreleasePool, objc_name="drain")
AutoreleasePool_drain :: proc "c" (self: ^AutoreleasePool) ---

@(objc_class="NSNotification")
Notification :: struct {using _: Object}

@(objc_class="NSNotificationCenter")
NotificationCenter :: struct {using _: Object}

@(objc_type=NotificationCenter, objc_name="defaultCenter", objc_is_class_method=true)
NotificationCenter_defaultCenter :: proc "c" () -> ^NotificationCenter ---

@(objc_type=NotificationCenter, objc_name="centerWithName", objc_is_class_method=true)
NotificationCenter_centerWithName :: proc "c" (name: string) -> ^NotificationCenter ---

@(objc_type=NotificationCenter, objc_name="addObserverForName")
NotificationCenter_addObserverForName :: proc "c" (
	self: ^NotificationCenter,
	name, object, queue: int,
	block: ^intrinsics.Objc_Block(proc(notification: ^Notification)),
) ---
`,
		},
		test.Package {
			pkg = "AppKit",
			source = `package AppKit
import Foundation "NS"

Object :: Foundation.Object

@(objc_class="GestureRecognizer", objc_superclass=Foundation.Object)
GestureRecognizer :: struct {using _: Object}

@(objc_class="RotationGestureRecognizer", objc_superclass=GestureRecognizer)
RotationGestureRecognizer :: struct {using _: GestureRecognizer}
`,
		},
		test.Package {
			pkg = "Cross",
			// This helper returns the package, so its file list must outlive this call.
			files = slice.clone([]test.File {
				{
					name = "aliases.odin",
					source = `package Cross
import intrinsics "base/intrinsics"

InstanceType :: intrinsics.objc_instancetype
`,
				},
				{
					name = "class.odin",
					source = `package Cross

@(objc_class="CrossLayer")
CrossLayer :: struct {}

@(objc_type=CrossLayer, objc_name="layer", objc_is_class_method=true)
CrossLayer_layer :: proc "c" () -> InstanceType ---
`,
				},
			}, context.temp_allocator),
		},
		test.Package {
			pkg = "IvarBase",
			source = `package IvarBase

Storage :: struct {
	base_value: int,
}

@(objc_class="IvarBase", objc_implement, objc_ivar=Storage)
Base :: struct {}
`,
		},
		test.Package {
			pkg = "IvarCross",
			source = `package IvarCross
import Parent "IvarBase"

@(objc_class="IvarCross", objc_implement, objc_superclass=Parent.Base)
Child :: struct {}
`,
		},
		test.Package {
			pkg = "Fake",
			source = `package Fake
import intrinsics "base/intrinsics"

objc_instancetype :: rawptr
FakeInstanceType :: distinct intrinsics.objc_instancetype
A :: B
B :: A

@(objc_class="FakeThing")
Thing :: struct {}

@(objc_type=Thing, objc_name="fake", objc_is_class_method=true)
Thing_fake :: proc "c" () -> objc_instancetype ---

@(objc_type=Thing, objc_name="distinctFake", objc_is_class_method=true)
Thing_distinct_fake :: proc "c" () -> FakeInstanceType ---

@(objc_type=Thing, objc_name="cyclicFake", objc_is_class_method=true)
Thing_cyclic_fake :: proc "c" () -> A ---

@(objc_type=Thing, objc_name="unresolvedFake", objc_is_class_method=true)
Thing_unresolved_fake :: proc "c" () -> Missing ---

@(objc_type=Thing, objc_name="next")
Thing_next :: proc "c" (self: ^Thing) ---
`,
		},
	)
	return packages[:]
}


@(test)
objc_instancetype_static_result_in_local :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test
import "CA"

main :: proc() {
	metal_layer := CA.MetalLayer.layer()
	metal_layer->nextDraw{*}able()
}
`,
		packages = objc_test_packages(),
	}

	test.expect_definition_locations(
		t,
		&source,
		{{range = {{line = 17, character = 0}, {line = 17, character = 23}}, uri = "file://test/CA/package.odin"}},
	)
}

@(test)
objc_instancetype_fully_chained_static_call :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test
import "CA"

main :: proc() {
	drawable := CA.MetalLayer.layer()->nextDraw{*}able()
}
`,
		packages = objc_test_packages(),
	}

	test.expect_definition_locations(
		t,
		&source,
		{{range = {{line = 17, character = 0}, {line = 17, character = 23}}, uri = "file://test/CA/package.odin"}},
	)
}

@(test)
objc_instancetype_inherited_static_definition :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test
import "CA"

main :: proc() {
	metal_layer := CA.MetalLayer.la{*}yer()
}
`,
		packages = objc_test_packages(),
	}

	test.expect_definition_locations(
		t,
		&source,
		{{range = {{line = 11, character = 0}, {line = 11, character = 11}}, uri = "file://test/CA/package.odin"}},
	)
}

@(test)
objc_instancetype_initializer_chain_definition :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test
import "NS"

main :: proc() {
	pool := NS.AutoreleasePool.alloc()->in{*}it()
}
`,
		packages = objc_test_packages(),
	}

	test.expect_definition_locations(
		t,
		&source,
		{{range = {{line = 14, character = 0}, {line = 14, character = 11}}, uri = "file://test/NS/package.odin"}},
	)
}

@(test)
objc_instancetype_long_chain_definition :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test
import "NS"

main :: proc() {
	NS.AutoreleasePool.alloc()->init()->dr{*}ain()
}
`,
		packages = objc_test_packages(),
	}

	test.expect_definition_locations(
		t,
		&source,
		{{range = {{line = 20, character = 0}, {line = 20, character = 21}}, uri = "file://test/NS/package.odin"}},
	)
}

@(test)
objc_instancetype_parenthesized_completed_call :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test
import "CA"

main :: proc() {
	drawable := (CA.MetalLayer.layer())->nextDraw{*}able()
}
`,
		packages = objc_test_packages(),
	}

	test.expect_definition_locations(
		t,
		&source,
		{{range = {{line = 17, character = 0}, {line = 17, character = 23}}, uri = "file://test/CA/package.odin"}},
	)
}

@(test)
objc_instancetype_parenthesized_callee :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test
import "CA"

main :: proc() {
	drawable := (CA.MetalLayer.layer)()->nextDraw{*}able()
}
`,
		packages = objc_test_packages(),
	}

	test.expect_definition_locations(
		t,
		&source,
		{{range = {{line = 17, character = 0}, {line = 17, character = 23}}, uri = "file://test/CA/package.odin"}},
	)
}

@(test)
objc_instancetype_contextual_hover :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test
import "CA"

main :: proc() {
	metal_{*}layer := CA.MetalLayer.layer()
}
`,
		packages = objc_test_packages(),
	}

	test.expect_hover(t, &source, "test.metal_layer: ^CA.MetalLayer")
}

@(test)
objc_instancetype_contextual_completion :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test
import "CA"

main :: proc() {
	metal_layer := CA.MetalLayer.layer()
	metal_layer->{*}
}
`,
		packages = objc_test_packages(),
	}

	test.expect_completion_docs(
		t,
		&source,
		"->",
		{"@(objc_type=MetalLayer, objc_name=\"nextDrawable\")\nMetalLayer.nextDrawable: CA.MetalLayer_nextDrawable"},
	)
}

@(test)
objc_class_completion_includes_inherited_methods :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
import "NS"

main :: proc() {
	NS.AutoreleasePool.{*}
}
`,
		packages = objc_test_packages(),
	}

	test.expect_completion_labels(t, &source, ".", {"alloc"}, {"init", "drain"})
}

@(test)
objc_class_completion_through_package_alias :: proc(t: ^testing.T) {
	names := []string{"Object", "RotationGestureRecognizer"}
	for name in names {
		main, _ := strings.replace_all(`package test
import NS "AppKit"

main :: proc() {
	NS.CLASS_NAME.{*}
}
`, "CLASS_NAME", name, allocator = context.temp_allocator)
		source := test.Source {
			main = main,
			packages = objc_test_packages(),
		}

		test.expect_completion_labels(t, &source, ".", {"alloc"}, {"init"})
	}
}

@(test)
objc_class_completion_inserts_call_parentheses :: proc(t: ^testing.T) {
	names := []string{"Object", "RotationGestureRecognizer"}
	for name in names {
		main, _ := strings.replace_all(`package test
import NS "AppKit"

main :: proc() {
	NS.CLASS_NAME.{*}
}
`, "CLASS_NAME", name, allocator = context.temp_allocator)
		source := test.Source {
			main = main,
			packages = objc_test_packages(),
			config = {enable_snippets = true, enable_procedure_snippet = true},
		}

		test.expect_completion_edit_text(t, &source, ".", "alloc", "alloc()$0")
	}

	source := test.Source {
		main = `package test
import "NS"

main :: proc() {
	NS.NotificationCenter.{*}
}
`,
		packages = objc_test_packages(),
		config = {enable_snippets = true, enable_procedure_snippet = true},
	}

	test.expect_completion_edit_text(t, &source, ".", "centerWithName", "centerWithName($0)")
}

@(test)
objc_completion_through_struct_field :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
import "CA"

Wrapper :: struct {
	impl: ^CA.MetalLayer,
}

main :: proc(self: ^Wrapper) {
	self.impl->{*}
}
`,
		packages = objc_test_packages(),
	}

	test.expect_completion_docs(
		t,
		&source,
		"->",
		{"@(objc_type=MetalLayer, objc_name=\"nextDrawable\")\nMetalLayer.nextDrawable: CA.MetalLayer_nextDrawable"},
	)
}

@(test)
objc_ivar_completion_includes_parent_fields :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
import "CA"

main :: proc(self: ^CA.IvarChild) {
	self->{*}
}
`,
		packages = objc_test_packages(),
	}

	test.expect_completion_label_order(
		t,
		&source,
		"->",
		{"child_value", "grandparent_value", "parent_value", "shared", "perform"},
	)
}

@(test)
objc_ivar_completion_with_field_selector :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
import "CA"

main :: proc(self: ^CA.IvarLeaf) {
	self.{*}
}
`,
		packages = objc_test_packages(),
		config = {enable_fake_method = true},
	}

	test.expect_completion_labels(
		t,
		&source,
		".",
		{
			"child_value",
			"grandparent_value",
			"parent_value",
			"shared",
			"IvarLeaf_perform",
			"IvarLeaf_fake_method",
		},
	)
}

@(test)
objc_ivar_completion_ranks_fields_before_fake_methods :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
import "CA"

main :: proc(self: ^CA.IvarLeaf) {
	self.{*}
}
`,
		packages = objc_test_packages(),
		config = {enable_fake_method = true},
	}

	test.expect_completion_label_order(
		t,
		&source,
		".",
		{"child_value", "grandparent_value", "parent_value", "shared", "IvarLeaf_fake_method"},
	)
}

@(test)
objc_ivar_child_shadows_parent :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
import "CA"

main :: proc(self: ^CA.IvarChild) {
	_ = self.sha{*}red
}
`,
		packages = objc_test_packages(),
	}

	test.expect_hover(t, &source, "IvarChild.shared: bool")
}

@(test)
objc_ivar_completion_across_package_superclass :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
import "IvarCross"

main :: proc(self: ^IvarCross.Child) {
	self.{*}
}
`,
		packages = objc_test_packages(),
	}

	test.expect_completion_labels(t, &source, ".", {"base_value"})
}

@(test)
objc_name_inferred_from_procedure_prefix :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
import "CA"

main :: proc(self: ^CA.IvarChild) {
	self->{*}
}
`,
		packages = objc_test_packages(),
	}

	test.expect_completion_labels(t, &source, "->", {"inferred", "renamed"}, {"name", "physical"})
}

@(test)
objc_block_capture_completion_uses_handler_type :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
import intrinsics "base/intrinsics"

objc_block :: intrinsics.objc_block

main :: proc() {
	word: string
	objc_block(wo{*}, proc(captured: string) {})
}
`,
		packages = objc_test_packages(),
		config = {enable_completion_matching = true},
	}

	test.expect_completion_insert_text(t, &source, "", {"word"})
}

@(test)
objc_block_capture_completion_maps_trailing_handler_parameters :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
import intrinsics "base/intrinsics"

main :: proc() {
	count: int
	text: string
	intrinsics.objc_block(count, te{*}, proc(api_value: bool, captured_count: int, captured_text: string) {})
}
`,
		packages = objc_test_packages(),
		config = {enable_completion_matching = true},
	}

	test.expect_completion_insert_text(t, &source, "", {"text"})
}

@(test)
objc_block_capture_completion_handles_pointer_type :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
import intrinsics "base/intrinsics"

main :: proc() {
	index: int
	intrinsics.objc_block(inde{*}, proc(captured: ^int) {})
}
`,
		packages = objc_test_packages(),
		config = {enable_completion_matching = true},
	}

	test.expect_completion_insert_text(t, &source, "", {"&index"})
}

@(test)
objc_block_capture_completion_handles_handler_reference :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
import intrinsics "base/intrinsics"

handler :: proc(api_value: bool, captured: string) {}

main :: proc() {
	word: string
	intrinsics.objc_block(wo{*}, handler)
}
`,
		packages = objc_test_packages(),
		config = {enable_completion_matching = true},
	}

	test.expect_completion_insert_text(t, &source, "", {"word"})
}

@(test)
objc_block_hover_separates_callback_and_capture_types :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test
import intrinsics "base/intrinsics"

Foo :: struct {}

main :: proc(foo: ^Foo) {
	block := intrinsics.objc_block(foo, proc(value: int, foo: ^Foo) {})
	bl{*}ock
}
`,
		packages = objc_test_packages(),
	}

	test.expect_hover(t, &source, "test.block: ^Objc_Block(int, [^Foo])")
}

@(test)
objc_block_handler_action_completes_capture_parameters :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test
import intrinsics "base/intrinsics"

Foo :: struct {}

main :: proc(foo: ^Foo, bar: string) {
	intrinsics.objc_block(foo, bar, {*})
}
`,
		packages = objc_test_packages(),
	}

	test.expect_action_with_edit(
		t,
		&source,
		"complete Objective-C block handler",
		"proc(foo: ^Foo, bar: string) {\n\t\t\n\t}",
	)
}

@(test)
objc_block_handler_action_adds_missing_comma :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test
import intrinsics "base/intrinsics"

main :: proc(foo: int) {
	intrinsics.objc_block(foo{*})
}
`,
		packages = objc_test_packages(),
	}

	test.expect_action_with_edit(t, &source, "complete Objective-C block handler", ", proc(foo: int) {\n\t\t\n\t}")
}

@(test)
objc_block_handler_action_uses_expected_block_type_without_captures :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test
import intrinsics "base/intrinsics"

consume :: proc(block: ^intrinsics.Objc_Block(proc(value: int) -> bool)) {}

main :: proc() {
	consume(intrinsics.objc_block({*}))
}
`,
		packages = objc_test_packages(),
	}

	test.expect_action_with_edit(
		t,
		&source,
		"complete Objective-C block handler",
		"proc(value: int) -> bool {\n\t\t\n\t}",
	)
}

@(test)
objc_block_handler_action_handles_unclosed_call :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test
import intrinsics "base/intrinsics"

main :: proc(foo: int) {
	intrinsics.objc_block(foo, {*}
}
`,
		packages = objc_test_packages(),
	}

	test.expect_action_with_edit(t, &source, "complete Objective-C block handler", "proc(foo: int) {\n\t\t\n\t})")
}

@(test)
objc_block_handler_action_handles_unclosed_call_without_comma :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test
import intrinsics "base/intrinsics"

main :: proc(foo: int) {
	intrinsics.objc_block(foo{*}
}
`,
		packages = objc_test_packages(),
	}

	test.expect_action_with_edit(t, &source, "complete Objective-C block handler", ", proc(foo: int) {\n\t\t\n\t})")
}

@(test)
objc_block_handler_action_handles_unclosed_empty_call_with_expected_type :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test
import intrinsics "base/intrinsics"

main :: proc() {
	block: ^intrinsics.Objc_Block(proc(value: int)) = intrinsics.objc_block({*}
}
`,
		packages = objc_test_packages(),
	}

	test.expect_action_with_edit(t, &source, "complete Objective-C block handler", "proc(value: int) {\n\t\t\n\t})")
}

@(test)
objc_block_handler_action_leaves_unknown_capture_type_empty :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test
import intrinsics "base/intrinsics"

main :: proc(foo: int) {
	intrinsics.objc_block(foo, missing, {*})
}
`,
		packages = objc_test_packages(),
	}

	test.expect_action_with_edit(
		t,
		&source,
		"complete Objective-C block handler",
		"proc(foo: int, missing:) {\n\t\t\n\t}",
	)
}

@(test)
objc_block_handler_action_combines_callback_and_capture_parameters :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
import intrinsics "base/intrinsics"

Foo :: struct {}
consume :: proc(block: ^intrinsics.Objc_Block(proc(value: int) -> bool)) {}

main :: proc(foo: ^Foo) {
	consume(intrinsics.objc_block(foo, {*}))
}
`,
		packages = objc_test_packages(),
	}

	test.expect_action_with_edit(
		t,
		&source,
		"complete Objective-C block handler",
		"proc(value: int, foo: ^Foo) -> bool {\n\t\t\n\t}",
	)
}

@(test)
objc_block_handler_action_uses_objc_method_block_type :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
import "CA"
import intrinsics "base/intrinsics"

main :: proc(self: ^CA.IvarChild, foo: string) {
	self->observe(intrinsics.objc_block(foo, {*}))
}
`,
		packages = objc_test_packages(),
	}

	test.expect_action_with_edit(
		t,
		&source,
		"complete Objective-C block handler",
		"proc(value: int, foo: string) {\n\t\t\n\t}",
	)
}

@(test)
objc_block_handler_action_uses_inferred_external_objc_receiver :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
import Cocoa "NS"
import intrinsics "base/intrinsics"

main :: proc(self: ^Cocoa.Object) {
	ncenter := Cocoa.NotificationCenter.defaultCenter()
	ncenter->addObserverForName(0, 0, 0, intrinsics.objc_block(self, {*}))
}
`,
		packages = objc_test_packages(),
	}

	test.expect_action_with_edit(
		t,
		&source,
		"complete Objective-C block handler",
		"proc(notification: ^Cocoa.Notification, self: ^Cocoa.Object) {\n\t\t\n\t}",
	)
}

@(test)
objc_block_handler_action_is_not_offered_for_existing_handler :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
import intrinsics "base/intrinsics"

main :: proc(foo: int) {
	intrinsics.objc_block(foo, {*}proc(foo: int) {})
}
`,
		packages = objc_test_packages(),
	}

	test.expect_action(t, &source, {})
}

@(test)
objc_instancetype_contextual_type_definition :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test
import "NS"

main :: proc() {
	pool := NS.AutoreleasePool.alloc()->init{*}()
}
`,
		packages = objc_test_packages(),
	}

	test.expect_type_definition_locations(
		t,
		&source,
		{{range = {{line = 17, character = 0}, {line = 17, character = 15}}, uri = "file://test/NS/package.odin"}},
	)
}

@(test)
objc_instancetype_same_package_alias_across_files :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test
import "Cross"

main :: proc() {
	cro{*}ss := Cross.CrossLayer.layer()
}
`,
		packages = objc_test_packages(),
	}

	test.expect_hover(t, &source, "test.cross: ^Cross.CrossLayer")
}

@(test)
objc_instancetype_rejects_name_lookalike :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test
import "Fake"

main :: proc() {
	value := Fake.Thing.fake()
	value->ne{*}xt()
}
`,
		packages = objc_test_packages(),
	}

	test.expect_definition_locations(
		t,
		&source,
		{{range = {{line = 3, character = 0}, {line = 3, character = 17}}, uri = "file://test/Fake/package.odin"}},
	)
}

@(test)
objc_instancetype_rejects_distinct_alias :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test
import "Fake"

main :: proc() {
	value := Fake.Thing.distinctFake()
	value->ne{*}xt()
}
`,
		packages = objc_test_packages(),
	}

	test.expect_definition_locations(
		t,
		&source,
		{{range = {{line = 4, character = 0}, {line = 4, character = 16}}, uri = "file://test/Fake/package.odin"}},
	)
}

@(test)
objc_instancetype_rejects_cyclic_alias :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test
import "Fake"

main :: proc() {
	value := Fake.Thing.cyclicFake()
	value->ne{*}xt()
}
`,
		packages = objc_test_packages(),
	}

	test.expect_definition_locations(t, &source, {})
}

@(test)
objc_instancetype_rejects_unresolved_alias :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test
import "Fake"

main :: proc() {
	value := Fake.Thing.unresolvedFake()
	value->ne{*}xt()
}
`,
		packages = objc_test_packages(),
	}

	test.expect_definition_locations(t, &source, {})
}


@(test)
objc_return_type_with_selector_expression :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

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

	test.expect_completion_docs(
		t,
		&source,
		"->",
		{"@(objc_type=Window, objc_name=\"initWithContentRect\")\nWindow.initWithContentRect: my_package.Window_initWithContentRect"},
	)
}

@(test)
objc_return_type_with_selector_expression_2 :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

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
            window := my_package.Window.alloc()->initWithContentRect(
				{{0, 0}, {500, 400}},
				{.Titled, .Closable, .Resizable},
				.Buffered,
				false,
			)	

			window->{*}
		}
		`,
		packages = packages[:],
	}

	test.expect_completion_docs(
		t,
		&source,
		"->",
		{"@(objc_type=Window, objc_name=\"initWithContentRect\")\nWindow.initWithContentRect: my_package.Window_initWithContentRect"},
	)
}


@(test)
objc_hover_chained_selector :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

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

			My_Struct :: struct {
				dummy: int,
			}
		`,
		},
	)

	source := test.Source {
		main     = `package test
        import "my_package"

		main :: proc() {
            window := my_package.Window.alloc()->initWithConte{*}ntRect(
				{{0, 0}, {500, 400}},
				{.Titled, .Closable, .Resizable},
				.Buffered,
				false,
			)	
		}
		`,
		packages = packages[:],
	}

	test.expect_hover(
		t,
		&source,
		"@(objc_type=Window, objc_name=\"initWithContentRect\")\nWindow.initWithContentRect: my_package.Window_initWithContentRect",
	)
}

@(test)
objc_implicit_enum_completion :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(
		&packages,
		test.Package {
			pkg = "my_package",
			source = `package my_package
			My_Enum :: enum {
				Regular    = 0,
				Accessory  = 1,
				Prohibited = 2,
			}
		
            @(objc_class="NSWindow")
            Window :: struct { dummy: int}

            @(objc_type=Window, objc_name="alloc", objc_is_class_method=true)
            Window_alloc :: proc "c" () -> ^Window {
            }
			@(objc_type=Window, objc_name="initWithContentRect")
			Window_initWithContentRect :: proc (self: ^Window, my_enum: My_Enum) -> ^Window {			
			}

			My_Struct :: struct {
				dummy: int,
			}
		`,
		},
	)

	source := test.Source {
		main     = `package test
        import "my_package"

		main :: proc() {
            window := my_package.Window.alloc()->initWithContentRect(
				.{*}
			)	
		}
		`,
		packages = packages[:],
	}

	test.expect_completion_labels(t, &source, ".", {"Accessory"})
}
