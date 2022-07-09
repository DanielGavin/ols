package odinfmt_tests

import "core:testing"
import "core:os"
import "core:fmt"

import "snapshot"


main :: proc() {
    snapshot.snapshot_directory("tests")
}
