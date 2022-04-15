package tests

import "core:log"
import "core:mem"
import "core:fmt"
import "core:os"
import "core:strings"


import src "../src"
import "shared:server"

initialize_request := `
{   "jsonrpc":"2.0",
    "id":0,
    "method":"initialize",
    "params": {
    "processId": 39964,
    "clientInfo": {
        "name": "vscode",
        "version": "1.50.1"
    },
    "rootPath": "c:\\Users\\danie\\OneDrive\\Desktop\\Computer_Science\\test",
    "rootUri": "file:///c%3A/Users/danie/OneDrive/Desktop/Computer_Science/test",
    "capabilities": {
        "workspace": {
            "applyEdit": true,
            "workspaceEdit": {
                "documentChanges": true,
                "resourceOperations": [
                    "create",
                    "rename",
                    "delete"
                ],
                "failureHandling": "textOnlyTransactional"
            },
            "didChangeConfiguration": {
                "dynamicRegistration": true
            },
            "didChangeWatchedFiles": {
                "dynamicRegistration": true
            },
            "symbol": {
                "dynamicRegistration": true,
                "symbolKind": {
                    "valueSet": [
                        1,
                        2,
                        3,
                        4,
                        5,
                        6,
                        7,
                        8,
                        9,
                        10,
                        11,
                        12,
                        13,
                        14,
                        15,
                        16,
                        17,
                        18,
                        19,
                        20,
                        21,
                        22,
                        23,
                        24,
                        25,
                        26
                    ]
                }
            },
            "executeCommand": {
                "dynamicRegistration": true
            },
            "configuration": true,
            "workspaceFolders": true
        },
        "textDocument": {
            "publishDiagnostics": {
                "relatedInformation": true,
                "versionSupport": false,
                "tagSupport": {
                    "valueSet": [
                        1,
                        2
                    ]
                }
            },
            "synchronization": {
                "dynamicRegistration": true,
                "willSave": true,
                "willSaveWaitUntil": true,
                "didSave": true
            },
            "completion": {
                "dynamicRegistration": true,
                "contextSupport": true,
                "completionItem": {
                    "snippetSupport": true,
                    "commitCharactersSupport": true,
                    "documentationFormat": [
                        "markdown",
                        "plaintext"
                    ],
                    "deprecatedSupport": true,
                    "preselectSupport": true,
                    "tagSupport": {
                        "valueSet": [
                            1
                        ]
                    }
                },
                "completionItemKind": {
                    "valueSet": [
                        1,
                        2,
                        3,
                        4,
                        5,
                        6,
                        7,
                        8,
                        9,
                        10,
                        11,
                        12,
                        13,
                        14,
                        15,
                        16,
                        17,
                        18,
                        19,
                        20,
                        21,
                        22,
                        23,
                        24,
                        25
                    ]
                }
            },
            "hover": {
                "dynamicRegistration": true,
                "contentFormat": [
                    "markdown",
                    "plaintext"
                ]
            },
            "signatureHelp": {
                "dynamicRegistration": true,
                "signatureInformation": {
                    "documentationFormat": [
                        "markdown",
                        "plaintext"
                    ],
                    "parameterInformation": {
                        "labelOffsetSupport": true
                    }
                },
                "contextSupport": true
            },
            "definition": {
                "dynamicRegistration": true,
                "linkSupport": true
            },
            "references": {
                "dynamicRegistration": true
            },
            "documentHighlight": {
                "dynamicRegistration": true
            },
            "documentSymbol": {
                "dynamicRegistration": true,
                "symbolKind": {
                    "valueSet": [
                        1,
                        2,
                        3,
                        4,
                        5,
                        6,
                        7,
                        8,
                        9,
                        10,
                        11,
                        12,
                        13,
                        14,
                        15,
                        16,
                        17,
                        18,
                        19,
                        20,
                        21,
                        22,
                        23,
                        24,
                        25,
                        26
                    ]
                },
                "hierarchicalDocumentSymbolSupport": true
            },
            "codeAction": {
                "dynamicRegistration": true,
                "isPreferredSupport": true,
                "codeActionLiteralSupport": {
                    "codeActionKind": {
                        "valueSet": [
                            "",
                            "quickfix",
                            "refactor",
                            "refactor.extract",
                            "refactor.inline",
                            "refactor.rewrite",
                            "source",
                            "source.organizeImports"
                        ]
                    }
                }
            },
            "codeLens": {
                "dynamicRegistration": true
            },
            "formatting": {
                "dynamicRegistration": true
            },
            "rangeFormatting": {
                "dynamicRegistration": true
            },
            "onTypeFormatting": {
                "dynamicRegistration": true
            },
            "rename": {
                "dynamicRegistration": true,
                "prepareSupport": true
            },
            "documentLink": {
                "dynamicRegistration": true,
                "tooltipSupport": true
            },
            "typeDefinition": {
                "dynamicRegistration": true,
                "linkSupport": true
            },
            "implementation": {
                "dynamicRegistration": true,
                "linkSupport": true
            },
            "colorProvider": {
                "dynamicRegistration": true
            },
            "foldingRange": {
                "dynamicRegistration": true,
                "rangeLimit": 5000,
                "lineFoldingOnly": true
            },
            "declaration": {
                "dynamicRegistration": true,
                "linkSupport": true
            },
            "selectionRange": {
                "dynamicRegistration": true
            }
        },
        "window": {
            "workDoneProgress": true
        }
    },
    "trace": "verbose",
    "workspaceFolders": [
        {
            "uri": "file:///c%3A/Users/danie/OneDrive/Desktop/Computer_Science/test",
            "name": "test"
        }
    ]
    }
}`;

shutdown_request := `{
"jsonrpc":"2.0",
"id":0,
"method":"shutdown"
}`;

exit_notification := `{
"jsonrpc":"2.0",
"id":0,
"method":"exit"
}`;



TestReadBuffer :: struct {
    index: int,
    data: [] byte,
};

test_read :: proc(handle: rawptr, data: [] byte) -> (int, int)
{
    buffer := cast(^TestReadBuffer)handle;

    if len(buffer.data) <= len(data) + buffer.index {
        dst := data[:];
        src := buffer.data[buffer.index:len(buffer.data)];

        copy(dst, src);

        buffer.index += len(src);
        return len(src), 0;
    }
    else {
        dst := data[:];
        src := buffer.data[buffer.index:];

        copy(dst, src);

        buffer.index += len(dst);
        return len(dst), 0;
    }
}

make_request :: proc(request: string) -> string {
    return fmt.tprintf("Content-Length: %v\r\n\r\n%v", len(request), request);
}

main :: proc() {




	buffer := TestReadBuffer {
        data = transmute([]byte) strings.join({make_request(initialize_request), make_request(shutdown_request), make_request(exit_notification)}, "", context.allocator),
    };

	reader := server.make_reader(test_read, &buffer);
    writer := server.make_writer(src.os_write, cast(rawptr)&os.stdout);

	tracking_allocator: mem.Tracking_Allocator;

	mem.tracking_allocator_init(&tracking_allocator, context.allocator);
	context.allocator = mem.tracking_allocator(&tracking_allocator);


	init_global_temporary_allocator(mem.Megabyte * 5);

	src.run(&reader, &writer);

    //delete(buffer.data);

	for k in tracking_allocator.bad_free_array {
		if k.memory == nil {
			continue;
		}
		
		fmt.println(k);
	}

	fmt.println("finished");
}