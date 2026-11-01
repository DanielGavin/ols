package CodeBens
// Intentional misspelling.

import "core:testing"
import "core:log"

// Should be detected as `CodeBens.one_test`
@(test)
one_test :: proc(t: ^testing.T) {
    log.infof("one test")
}

// Should be detected as `CodeBens.another_test`
@(test)
another_test :: proc(t: ^testing.T) {
    log.infof("another test")
}
