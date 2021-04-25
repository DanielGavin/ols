package tests

import "core:testing"

@(test)
test_declare_proc_signature :: proc(t: ^testing.T) {
    testing.expect(t, 1 == 1);
}


