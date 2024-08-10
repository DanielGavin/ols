package server

Snippet_Info :: struct {
	insert:   string,
	detail:   string,
	packages: []string,
}

snippets: map[string]Snippet_Info = {
	"ff" = {insert = "fmt.printf(\"${1:text}\", ${0:args})", packages = []string{"fmt"}, detail = "printf"},
	"fl" = {insert = "fmt.println(\"${1:text}\")", packages = []string{"fmt"}, detail = "println"},
	"if" = {insert = "if ${1} {\n\t${0}\n}", packages = {}, detail = "if statement"},
	"forr" = {insert = "for ${2:elem} in ${1:range} {\n\t${0}\n}", packages = {}, detail = "for range"},
	"fori" = {insert = "for ${1} := ${2}; ${1} < ${3}; ${1}+=1 {\n\t${0}\n}", packages = {}, detail = "for index"},
	"main" = {insert = "main :: proc() {\n\t${0}\n}", packages = {}, detail = "main entrypoint"},
	"proc" = {insert = "${1:name} :: proc(${2:params}) {\n\t${0}\n}", packages = {}, detail = "procedure declaration"},
	"st" = {
		insert = "${1:name} :: struct {\n\t${2:field_name}: ${3:field_type},${0}\n}",
		packages = {},
		detail = "struct declaration",
	},
}
