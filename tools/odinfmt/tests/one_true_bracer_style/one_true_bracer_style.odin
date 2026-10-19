
package odinfmt_test

import "core:fmt"

// A single statement immediately after the opening brace.
single_statement :: proc() {fmt.println("hello")}

// Several statements separated by semicolons.
multiple_statements :: proc() {fmt.println("one"); fmt.println("two"); fmt.println("three")}

// Local declarations and assignments on one line.
local_declarations :: proc() {a := 1; b := 2; a += b; fmt.println(a)}

// Nested blocks and else placement.
nested_blocks :: proc(ready: bool) {if ready {fmt.println("yes"); fmt.println("again")} else {fmt.println("no"); fmt.println("again")}}

// Semicolons in a for header must NOT be removed.
for_loop :: proc() {for i := 0; i < 3; i += 1 {fmt.println(i); fmt.println(i + 1)}}

// An empty block should stay compact.
empty_block :: proc() {}

// Preserve do syntax when convert_do is false.
do_statement :: proc(ready: bool) {if ready do fmt.println("ready")}

// A semicolon inside a string is not a statement separator.
string_semicolon :: proc() {fmt.println("a;b"); fmt.println("done")}
