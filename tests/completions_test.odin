package tests

import "core:testing"
import "core:fmt"

import test "shared:testing"

@(test)
ast_simple_struct_completion :: proc(t: ^testing.T) {
    source := test.Source {
        main = `package test

        My_Struct :: struct {
            one: int,
            two: int,
            three: int,
        }

        main :: proc() {
            my_struct: My_Struct;
            my_struct.*
        }
        `,
        source_packages = {},
    };

    test.expect_completion_details(t, &source, ".", {"My_Struct.one: int", "My_Struct.two: int", "My_Struct.three: int"});
}

@(test)
ast_index_array_completion :: proc(t: ^testing.T) {
    source := test.Source {
        main = `package test

        My_Struct :: struct {
            one: int,
            two: int,
            three: int,
        }

        main :: proc() {
            my_struct: [] My_Struct;
            my_struct[2].*
        }
        `,
        source_packages = {},
    };

    test.expect_completion_details(t, &source, ".", {"My_Struct.one: int", "My_Struct.two: int", "My_Struct.three: int"});
}

@(test)
ast_struct_pointer_completion :: proc(t: ^testing.T) {
    source := test.Source {
        main = `package test

        My_Struct :: struct {
            one: int,
            two: int,
            three: int,
        }

        main :: proc() {
            my_struct: ^My_Struct;
            my_struct.*
        }
        `,
        source_packages = {},
    };

    test.expect_completion_details(t, &source, ".", {"My_Struct.one: int", "My_Struct.two: int", "My_Struct.three: int"});
}

@(test)
ast_struct_take_address_completion :: proc(t: ^testing.T) {
    source := test.Source {
        main = `package test

        My_Struct :: struct {
            one: int,
            two: int,
            three: int,
        }

        main :: proc() {
            my_struct: My_Struct;
            my_pointer := &my_struct;
            my_pointer.*
        }
        `,
        source_packages = {},
    };

    test.expect_completion_details(t, &source, ".", {"My_Struct.one: int", "My_Struct.two: int", "My_Struct.three: int"});
}

@(test)
ast_struct_deref_completion :: proc(t: ^testing.T) {
    source := test.Source {
        main = `package test

        My_Struct :: struct {
            one: int,
            two: int,
            three: int,
        }

        main :: proc() {
            my_struct: ^^My_Struct;
            my_deref := my_struct^;
            my_deref.*
        }
        `,
        source_packages = {},
    };

    test.expect_completion_details(t, &source, ".", {"My_Struct.one: int", "My_Struct.two: int", "My_Struct.three: int"});
}

@(test)
ast_range_map :: proc(t: ^testing.T) {
    source := test.Source {
        main = `package test

        My_Struct :: struct {
            one: int,
            two: int,
            three: int,
        }

        main :: proc() {
            my_map: map[int]My_Struct;
            
            for key, value in my_map {
                value.*
            }

        }
        `,
        source_packages = {},
    };

    test.expect_completion_details(t, &source, ".", {"My_Struct.one: int", "My_Struct.two: int", "My_Struct.three: int"});
}

@(test)
ast_range_array :: proc(t: ^testing.T) {
    source := test.Source {
        main = `package test

        My_Struct :: struct {
            one: int,
            two: int,
            three: int,
        }

        main :: proc() {
            my_array: []My_Struct;
            
            for value in my_array {
                value.*
            }

        }
        `,
        source_packages = {},
    };

    test.expect_completion_details(t, &source, ".", {"My_Struct.one: int", "My_Struct.two: int", "My_Struct.three: int"});
}

@(test)
ast_completion_identifier_proc_group :: proc(t: ^testing.T) {

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
            grou*
        }
        `,
        source_packages = {},
    };

    test.expect_completion_details(t, &source, "", {"group_function"});
}

@(test)
index_completion_in_comp_lit_type :: proc(t: ^testing.T) {

    source := test.Source {
        main = `package test

        My_Struct :: struct {
            one: int,
            two: int,
            three: int,
        }

        main :: proc() {
            my_comp := M* {

            };
        }
        `,
        source_packages = {},
    };

    //test.expect_completion_details(t, &source, "", {"My_Struct: struct"});
}


