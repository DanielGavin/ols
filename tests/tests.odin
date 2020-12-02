package test

import "core:log"
import "core:mem"
import "core:fmt"
import "core:os"
import "core:strings"


import src "../src"
import "shared:server"


/*
    This is really tests, but just where i quickly got look at error crashes from specific messages.

    There needs either to be a process spawned
    or just keep overwriting the writer and reader functions, but either way, there needs
    to be client mimick behavior where we can consume the text we get from the client, and make
    actual tests.
 */

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

sublime_initialize_request := `{"id":1,"jsonrpc":"2.0","method":"initialize","params":{"clientInfo":{"version":"0.14.1","name":"Sublime Text LSP"},"rootUri":"file:///C:/Users/danie/OneDrive/Desktop/Computer_Science/ols/tests/test_project/src","rootPath":"C:\\Users\\danie\\OneDrive\\Desktop\\Computer_Science\\ols\\tests\\test_project\\src","processId":17192,"workspaceFolders":[{"uri":"file:///C:/Users/danie/OneDrive/Desktop/Computer_Science/ols/tests/test_project/src","name":"src"}],"capabilities":{"window":{"workDoneProgress":true,"showMessage":{"messageActionItem":{"additionalPropertiesSupport":true}}},"workspace":{"workspaceFolders":true,"configuration":true,"workspaceEdit":{"documentChanges":true,"failureHandling":"abort"},"applyEdit":true,"executeCommand":{},"didChangeConfiguration":{"dynamicRegistration":true},"symbol":{"dynamicRegistration":true,"symbolKind":{"valueSet":[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26]}}},"textDocument":{"formatting":{"dynamicRegistration":true},"codeAction":{"codeActionLiteralSupport":{"codeActionKind":{"valueSet":[]}},"dynamicRegistration":true},"references":{"dynamicRegistration":true},"documentHighlight":{"dynamicRegistration":true},"synchronization":{"willSave":true,"willSaveWaitUntil":true,"didSave":true,"dynamicRegistration":true},"hover":{"contentFormat":["markdown","plaintext"],"dynamicRegistration":true},"signatureHelp":{"signatureInformation":{"documentationFormat":["markdown","plaintext"],"parameterInformation":{"labelOffsetSupport":true}},"dynamicRegistration":true},"rangeFormatting":{"dynamicRegistration":true},"typeDefinition":{"dynamicRegistration":true,"linkSupport":true},"completion":{"completionItemKind":{"valueSet":[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25]},"completionItem":{"snippetSupport":true},"dynamicRegistration":true},"implementation":{"dynamicRegistration":true,"linkSupport":true},"documentSymbol":{"hierarchicalDocumentSymbolSupport":true,"dynamicRegistration":true,"symbolKind":{"valueSet":[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26]}},"colorProvider":{"dynamicRegistration":true},"declaration":{"dynamicRegistration":true,"linkSupport":true},"rename":{"dynamicRegistration":true},"definition":{"dynamicRegistration":true,"linkSupport":true},"publishDiagnostics":{"relatedInformation":true}},"experimental":{}},"initializationOptions":{}}}`;

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


test_init_check_shutdown :: proc() -> bool {

    buffer := TestReadBuffer {
        data = transmute([]byte) strings.join({make_request(initialize_request), make_request(shutdown_request), make_request(exit_notification)}, "", context.allocator),
    };

    reader := server.make_reader(test_read, &buffer);
    writer := server.make_writer(src.os_write, cast(rawptr)os.stdout);

    src.run(&reader, &writer);

    delete(buffer.data);

    return true;
}


test_open_and_change_notification :: proc() -> bool {

    open_notification := `{
    "jsonrpc":"2.0",
    "id":0,
    "method": "textDocument/didOpen",
    "params": {
        "textDocument": {
            "uri": "file:///c%3A/Users/danie/OneDrive/Desktop/Computer_Science/ols/tests/test_project/src/main.odin",
            "languageId": "odin",
            "version": 1,
            "text": "package main\r\n\r\nimport \"core:fmt\"\r\n\r\nmain :: proc() {\r\n    fmt.println(\"hello ols\");\r\n}\r\n"
        }
    }
    }`;

    close_notification := `
    {
    "jsonrpc":"2.0",
    "id":0,
    "method": "textDocument/didClose",
    "params": {
        "textDocument": {
            "uri": "file:///c%3A/Users/danie/OneDrive/Desktop/Computer_Science/ols/tests/test_project/src/main.odin",
        }
    }
    }
    `;

    change_notification := `{
    "jsonrpc":"2.0",
    "id":0,
    "method": "textDocument/didChange",
    "params":  {
        "textDocument": {
        "uri": "file:///c%3A/Users/danie/OneDrive/Desktop/Computer_Science/ols/tests/test_project/src/main.odin",
        "version": 2
    },
    "contentChanges": [
        {
            "range": {
                "start": {
                    "line": 0,
                    "character": 0
                },
                "end": {
                    "line": 0,
                    "character": 0
                }
            },
            "rangeLength": 0,
            "text": "aadasfasgasgs"
        }
    ]
    }
    }`;

    change_notification_2 := `{
    "jsonrpc":"2.0",
    "id":0,
    "method": "textDocument/didChange",
    "params":  {
        "textDocument": {
        "uri": "file:///c%3A/Users/danie/OneDrive/Desktop/Computer_Science/ols/tests/test_project/src/main.odin",
        "version": 3
    },
    "contentChanges": [
        {
            "range": {
                "start": {
                    "line": 8,
                    "character": 0
                },
                "end": {
                    "line": 8,
                    "character": 1
                }
            },
            "rangeLength": 1,
            "text": ""
        }
    ]
    }
    }`;



    buffer := TestReadBuffer {
        data = transmute([]byte) strings.join({make_request(initialize_request), make_request(open_notification),
                                               make_request(change_notification), make_request(change_notification_2), make_request(close_notification), make_request(shutdown_request),
                                               make_request(exit_notification)}, "", context.allocator),
    };





    reader := server.make_reader(test_read, &buffer);
    writer := server.make_writer(src.os_write, cast(rawptr)os.stdout);

    context.logger = server.create_lsp_logger(&writer);

    src.run(&reader, &writer);

    delete(buffer.data);

    return true;
}


test_definition_request :: proc() -> bool {

    open_notification := `{
    "jsonrpc":"2.0",
    "id":0,
    "method": "textDocument/didOpen",
    "params": {
        "textDocument": {
            "uri": "file:///c%3A/Users/danie/OneDrive/Desktop/Computer_Science/ols/tests/test_project/src/main.odin",
            "languageId": "odin",
            "version": 1,
            "text": "package main\r\n\r\nimport \"core:fmt\"\r\nimport \"core:strings\"\r\nimport \"core:odin/ast\"\r\nimport \"core:time\"\r\nimport \"core:runtime\"\r\n\r\ntest_enum :: enum {\r\n    one,\r\n    two,\r\n    three,\r\n};\r\n\r\ntest_struct :: struct {\r\n    a: test_enum,\r\n};\r\n\r\n\r\nmain :: proc() {\r\n\r\n    //files := runtime.make([] ast.File, 2);\r\n\r\n\r\n    inst := test_struct {\r\n\r\n    };\r\n\r\n    c := 2;\r\n\r\n    b := inst.a.three;\r\n\r\n\r\n\r\n\r\n    /*\r\n    for file in files {\r\n        //file.pkg.\r\n\r\n    }\r\n    */\r\n\r\n\r\n\r\n\r\n\r\n}\r\n\r\n\r\n"
        }
    }
    }`;

    definition_request := `{
    "jsonrpc":"2.0",
    "id":0,
    "method": "textDocument/definition",
    "params":   {
        "textDocument": {
        "uri": "file:///c%3A/Users/danie/OneDrive/Desktop/Computer_Science/ols/tests/test_project/src/main.odin"
    },
    "position": {
        "line": 30,
        "character": 17
    }
    }

    }`;




    buffer := TestReadBuffer {
        data = transmute([]byte) strings.join({make_request(initialize_request), make_request(open_notification), make_request(definition_request),
                                               make_request(shutdown_request),
                                               make_request(exit_notification)}, "", context.allocator),
    };


    reader := server.make_reader(test_read, &buffer);
    writer := server.make_writer(src.os_write, cast(rawptr)os.stdout);

    context.logger = server.create_lsp_logger(&writer);

    src.run(&reader, &writer);

    delete(buffer.data);

    return true;
}


test_completion_request :: proc() -> bool {

    open_notification := `{
    "jsonrpc":"2.0",
    "id":0,
    "method": "textDocument/didOpen",
    "params": {
        "textDocument": {
            "uri": "file:///c%3A/Users/danie/OneDrive/Desktop/Computer_Science/ols/tests/test_project/src/main.odin",
            "languageId": "odin",
            "version": 1,
            "text":  "package main\r\n\r\nimport \"core:fmt\"\r\nimport \"core:strings\"\r\nimport \"core:odin/ast\"\r\nimport \"core:time\"\r\nimport \"core:runtime\"\r\n\r\n\r\n/*\r\nTest :: struct {\r\n    one: int,\r\n    two: int,\r\n    three: int,\r\n}\r\n\r\nPosition :: struct {\r\n    x: f32,\r\n    y: f32,\r\n    test: Test,\r\n}\r\n\r\nEntity :: struct {\r\n    pos: Position,\r\n}\r\n\r\ntransform_entity :: proc(entity: ^Entity) {\r\n    using entity.pos;\r\n    x += 1.0;\r\n    y += 1.0;\r\n}\r\n\r\n*/\r\n\r\nVector3 :: struct{x, y, z: f32};\r\n\r\nEntity :: struct {\r\n    using position: Vector3,\r\n}\r\n\r\nmain :: proc() {\r\n\r\n    entity: Entity;\r\n\r\n    context.\r\n\r\n}\r\n\r\n\r\n"
        }
    }
    }`;

    change_notification := `{
    "jsonrpc":"2.0",
    "id":0,
    "method": "textDocument/didChange",
    "params":  {
        "textDocument": {
        "uri": "file:///c%3A/Users/danie/OneDrive/Desktop/Computer_Science/ols/tests/test_project/src/main.odin",
        "version": 3
        },
        "contentChanges": [
        {
            "range": {
                "start": {
                    "line": 15,
                    "character": 4
                },
                "end": {
                    "line": 15,
                    "character": 4
                }
            },
            "rangeLength": 0,
            "text": "#p"
        }
        ]
    }
    }`;

    close_notification := `
    {
    "jsonrpc":"2.0",
    "id":0,
    "method": "textDocument/didClose",
    "params": {
        "textDocument": {
            "uri": "file:///c%3A/Users/danie/OneDrive/Desktop/Computer_Science/ols/tests/test_project/src/main.odin",
        }
    }
    }
    `;

    completion_request := `{
    "jsonrpc":"2.0",
    "id":0,
    "method": "textDocument/completion",
    "params":   {
        "textDocument": {
        "uri": "file:///c%3A/Users/danie/OneDrive/Desktop/Computer_Science/ols/tests/test_project/src/main.odin"
    },
    "position": {
        "line": 44,
        "character": 12
    },
    "context": {
        "triggerKind": 2,
        "triggerCharacter": "."
    }
    }

    }`;




    buffer := TestReadBuffer {
        data = transmute([]byte) strings.join({make_request(sublime_initialize_request), make_request(open_notification), make_request(completion_request),
                                               make_request(close_notification), make_request(shutdown_request),
                                               make_request(exit_notification)}, "", context.allocator),
    };


    reader := server.make_reader(test_read, &buffer);
    writer := server.make_writer(src.os_write, cast(rawptr)os.stdout);

    context.logger = server.create_lsp_logger(&writer);

    src.run(&reader, &writer);

    delete(buffer.data);

    return true;
}


test_signature_request :: proc() -> bool {

    open_notification := `{
    "jsonrpc":"2.0",
    "id":0,
    "method": "textDocument/didOpen",
    "params": {
        "textDocument": {
            "uri": "file:///c%3A/Users/danie/OneDrive/Desktop/Computer_Science/ols/tests/test_project/src/main.odin",
            "languageId": "odin",
            "version": 1,
            "text": "package main\r\n\r\nimport \"core:fmt\"\r\n\r\nfoo :: proc(a: int, b: int, c:int) -> int {\r\n\treturn a + b + c;\r\n}\r\n\r\nbar :: struct {\r\n\ta: sup,\r\n};\r\n\r\nsup :: struct {\r\n\ta1: int,\r\n\ta2: int,\r\n\ta3: int,\r\n};\r\n\r\nmain :: proc() {\r\n\r\n\r\n\r\n\tfoo()\r\n\r\n\r\n}\r\n\r\n\r\n"
        }
    }
    }`;

    signature_request := `{
    "jsonrpc":"2.0",
    "id":0,
    "method": "textDocument/signatureHelp",
    "params":   {
        "textDocument": {
        "uri": "file:///c%3A/Users/danie/OneDrive/Desktop/Computer_Science/ols/tests/test_project/src/main.odin"
    },
    "position": {
        "line": 22,
        "character": 5
    },
    "context": {
        "isRetrigger": false,
        "triggerCharacter": "(",
        "triggerKind": 2
    }
    }

    }`;




    buffer := TestReadBuffer {
        data = transmute([]byte) strings.join({make_request(sublime_initialize_request), make_request(open_notification), make_request(signature_request),
                                               make_request(shutdown_request),
                                               make_request(exit_notification)}, "", context.allocator),
    };


    reader := server.make_reader(test_read, &buffer);
    writer := server.make_writer(src.os_write, cast(rawptr)os.stdout);

    context.logger = server.create_lsp_logger(&writer);

    src.run(&reader, &writer);

    delete(buffer.data);

    return true;
}

test_multiple_returns :: proc() -> bool {

    open_notification := `{
    "jsonrpc":"2.0",
    "id":0,
    "method": "textDocument/didOpen",
    "params": {
        "textDocument": {
            "uri": "file:///c%3A/Users/danie/OneDrive/Desktop/Computer_Science/ols/tests/test_project/src/main.odin",
            "languageId": "odin",
            "version": 1,
            "text": "package main\r\n\r\nimport \"core:fmt\"\r\nimport \"core:strings\"\r\nimport \"core:odin/ast\"\r\nimport \"core:time\"\r\nimport \"core:runtime\"\r\n\r\n\r\n\r\n\r\nmain :: proc() {\r\n\r\n    files := runtime.make([dynamic] ast.File);\r\n\r\n    \r\n    for file in files {\r\n\r\n        //file.\r\n        //file.\r\n\r\n    }\r\n\r\n\r\n\r\n\r\n\r\n}\r\n\r\n\r\n"
        }
    }
    }`;


    completion_request := `{
    "jsonrpc":"2.0",
    "id":0,
    "method": "textDocument/completion",
    "params":   {
         "textDocument": {
        "uri": "file:///c%3A/Users/danie/OneDrive/Desktop/Computer_Science/ols/tests/test_project/src/main.odin"
    },
    "position": {
        "line": 38,
        "character": 1
    },
    "context": {
        "triggerKind": 1
    }
    }

    }`;



    buffer := TestReadBuffer {
        data = transmute([]byte) strings.join({make_request(sublime_initialize_request), make_request(open_notification),
                                               make_request(completion_request), make_request(shutdown_request),
                                               make_request(exit_notification)}, "", context.allocator),
    };


    reader := server.make_reader(test_read, &buffer);
    writer := server.make_writer(src.os_write, cast(rawptr)os.stdout);

    context.logger = server.create_lsp_logger(&writer);

    src.run(&reader, &writer);

    delete(buffer.data);

    return true;
}



main :: proc() {

    init_global_temporary_allocator(mem.megabytes(10));

    //context.logger = log.create_console_logger();

    //test_init_check_shutdown();

    //test_definition_request();

    //test_open_and_change_notification();

    test_completion_request();

    //test_signature_request();

    //test_multiple_returns();



    fmt.println();
    fmt.println();
    fmt.println("End of Tests");
    fmt.println();
    fmt.println();
}

