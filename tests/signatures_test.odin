package tests

import "core:testing"
import "core:fmt"

import test "shared:testing"


@(test)
ast_declare_proc_signature :: proc(t: ^testing.T) {

    source := test.Source {
        main = `package test
        main :: proc(*)
        `,
        source_packages = {},
    };

    test.expect_signature_labels(t, &source, {});
}

@(test)
ast_simple_proc_signature :: proc(t: ^testing.T) {

    source := test.Source {
        main = `package test
        cool_function :: proc(a: int) {

        }

        main :: proc() { 
            cool_function(*)
        }
        `,
        source_packages = {},
    };

    test.expect_signature_labels(t, &source, {"test.cool_function: proc(a: int)"});
}

@(test)
ast_proc_group_signature_empty_call :: proc(t: ^testing.T) {

    source := test.Source {
        main = `package test
        int_function :: proc(a: int) {

        }

        bool_function :: proc(a: bool) {

        }

        group_function :: proc {
            int_function,
            bool_function,
        };

        main :: proc() {
            group_function(*)
        }
        `,
        source_packages = {},
    };

    test.expect_signature_labels(t, &source, {"test.int_function: proc(a: int)", "test.bool_function: proc(a: bool)"});
}

@(test)
ast_proc_group_signature_basic_types :: proc(t: ^testing.T) {

    source := test.Source {
        main = `package test
        int_function :: proc(a: int, b: bool, c: int) {

        }

        bool_function :: proc(a: bool, b: bool, c: bool) {

        }

        group_function :: proc {
            int_function,
            bool_function,
        };

        main :: proc() {
            group_function(2, true, *)
        }
        `,
        source_packages = {},
    };

    test.expect_signature_labels(t, &source, {"test.int_function: proc(a: int, b: bool, c: int)"});
}