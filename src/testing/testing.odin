package ols_testing

import "core:testing"

Package_Source :: struct {
    pkg_name: string,
    source: string,
}

Source :: struct {
    main: string,
    source_packages: Package_Source,
}

expect_signature :: proc(t: ^testing.T, src: Source, expect_arg: []string) {

}

expect_completion :: proc(t: ^testing.T, src: Source, completions: []string) {

}

expect_hover :: proc(t: ^testing.T, src: Source, hover_info: string) {

}