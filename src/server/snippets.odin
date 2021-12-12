package server

Snippet_Info :: struct {
	insert:   string,
	detail:   string,
	packages: []string,
}

snippets: map[string]Snippet_Info = {
	"ff" = {insert = "fmt.printf(\"${1:text}\", ${0:args})", packages = []string{"fmt"}, detail = "printf"},
	"fl" = {insert = "fmt.println(\"${1:text}\")", packages = []string{"fmt"}, detail = "println"},
}
