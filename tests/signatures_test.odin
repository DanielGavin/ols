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
ast_proc_signature_generic :: proc(t: ^testing.T) {

    source := test.Source {
        main = `package test

        import "core:mem"

        clone_array :: proc(array: $A/[]^$T, allocator: mem.Allocator, unique_strings: ^map[string]string) -> A {
        }
      
        main :: proc() {
            clone_array(*)
        }
        `,
        source_packages = {},
    };

    test.expect_signature_labels(t, &source, {"test.clone_array: proc (array: $A/[]^$T, allocator: mem.Allocator, unique_strings: ^map[string]string) -> (A)"});
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


@(test)
ast_proc_group_signature_distinct_basic_types :: proc(t: ^testing.T) {

    source := test.Source {
        main = `package test

        My_Int :: distinct int;

        distinct_function :: proc(a: My_Int, c: int) {

        }

        int_function :: proc(a: int, c: int) {

        }

        group_function :: proc {
            int_function,
            distinct_function,
        };

        main :: proc() {

            a: My_Int;

            group_function(a, *)
        }
        `,
        source_packages = {},
    };

    test.expect_signature_labels(t, &source, {"test.distinct_function: proc(a: My_Int, c: int)"});
}

@(test)
ast_proc_group_signature_struct :: proc(t: ^testing.T) {

    source := test.Source {
        main = `package test

        My_Int :: distinct int;

        My_Struct :: struct {
            one: int,
            two: int,
            three: int,
        }

        distinct_function :: proc(a: My_Int, c: int) {

        }

        int_function :: proc(a: int, c: int) {

        }

        struct_function :: proc(a: int, b: My_Struct, c: int) {

        }

        group_function :: proc {
            int_function,
            distinct_function,
            struct_function,
        };

        main :: proc() {
            a: int;
            b: My_Struct;
            group_function(a, b, *)
        }
        `,
        source_packages = {},
    };

    test.expect_signature_labels(t, &source, {"test.struct_function: proc(a: int, b: My_Struct, c: int)"});
}