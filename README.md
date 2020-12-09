# ols
Language server for Odin. This project is still in early development.

## Table Of Contents
- [Installation](#installation)
  - [Configuration](#Configuration)
- [Features](#features)
- [Clients](#clients)
  
## Installation

 ```
 cd ols
 ./build.bat
 ```

### Configuration

All configurations is contained in one json file that must be named ```ols.json``` in your main workspace.

In order for the language server to index your files, the ols.json must contain all the collections in your project.

Example of ols.json:

```
{
  "collections": [{ "name": "core", "path": "c:/path/to/Odin/core" },
                  { "name": "shared", "path": "c:/path/to/MyProject/src" }],
  "thread_pool_count": 4,
  "enable_semantic_tokens": false,
  "enable_document_symbols": false,
}

```

## Features
  Support Language server features:
  - Completion
  - Go to definition
  - Semantic tokens
  - Document symbols
  
## Clients
  
  ### VS Code
    [Extension] (https://github.com/DanielGavin/ols-vscode)
  
