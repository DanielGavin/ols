# ols
Language server for Odin. This project is still in early development. 

**Status**: Apple M1 does not currently work.

## Table Of Contents
- [Installation](#installation)
  - [Configuration](#Configuration)
- [Features](#features)
- [Clients](#clients)
  - [Vs Code](#vs-code)
  - [Sublime](#sublime)
  - [Vim](#vim)
  - [Emacs](#emacs)

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
  "enable_document_symbols": true,
  "enable_hover": true,
  "enable_format": true,
  "enable_snippets": true,
  "formatter": {
  	"tabs": true,
	"characters": 90
  }
}

```

## Features
  Support Language server features:
  - Completion
  - Go to definition
  - Semantic tokens(really unstable and unfinished)
  - Document symbols
  - Signature help
  - Hover

## Clients

### VS Code
Install the extension https://marketplace.visualstudio.com/items?itemName=DanielGavin.ols
### Sublime
Install the package https://github.com/sublimelsp/LSP

Configuration of the LSP:
```
{
	"clients":
	{
		"odin":
		{
		    "command":
		    [
			"C:/path/to/ols.exe"
		    ],
		    "enabled": false, // true for globally-enabled, but not required due to 'Enable In Project' command
		    "selector": "source.odin",
		}
	},
	"only_show_lsp_completions": true,
}

```

### Vim
Install [Coc](https://github.com/neoclide/coc.nvim).

Configuration of the LSP:
```
{
  "languageserver": {
    "odin": {
      "command": "ols",
      "filetypes": ["odin"],
      "rootPatterns": ["ols.json"]
    }
  }
}
```

### Emacs
```
;; With odin-mode (https://github.com/mattt-b/odin-mode) and lsp-mode already added to your init.el of course!.
(setq-default lsp-auto-guess-root t) ;; if you work with Projectile/project.el this will help find the ols.json file.
(defvar lsp-language-id-configuration '((odin-mode . "odin")))
(lsp-register-client
 (make-lsp-client :new-connection (lsp-stdio-connection "/path/to/ols/executable")
                  :major-modes '(odin-mode)
                  :server-id 'ols
                  :multi-root t)) ;; This is just so lsp-mode sends the "workspaceFolders" param to the server.
(add-hook 'odin-mode-hook #'lsp)
```
