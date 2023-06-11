# ols
Language server for Odin. This project is still in early development. 

**Status**: All platforms work.

## Table Of Contents
- [Installation](#installation)
  - [Configuration](#Configuration)
- [Features](#features)
- [Clients](#clients)
  - [Vs Code](#vs-code)
  - [Sublime](#sublime)
  - [Vim](#vim)
  - [Neovim](#neovim)
  - [Emacs](#emacs)

## Installation

 ```
 cd ols

 //for windows
 ./build.bat 

 //for linux
 ./build.sh
 ```

### Configuration

All configurations is contained in one json file that must be named ```ols.json``` in your main workspace.

In order for the language server to index your files, the ols.json must contain all the collections in your project.

Example of ols.json:

```json
{
  "collections": [{ "name": "core", "path": "c:/path/to/Odin/core" },
                  { "name": "shared", "path": "c:/path/to/MyProject/src" }],
  "enable_semantic_tokens": false,
  "enable_document_symbols": true,
  "enable_hover": true,
  "enable_snippets": true
}

```

You can also set `ODIN_ROOT` environment variable to the path where ols should look for core and vendor libraries.

Options:

`enable_hover`: Enables hover feature

`enable_snippets`: Turns on builtin snippets

`enable_semantic_tokens`: Turns on syntax highlighting.

`enable_document_symbols`: Turns on outline of all your global declarations in your document. 

`odin_command`: Allows you to specifiy your Odin location, instead of just relying on the environment path.

`checker_args`: Pass custom arguments to ```odin check```.

`verbose`: Logs warnings instead of just errors.




### Odinfmt configurations
Odinfmt reads configuration through `odinfmt.json`.

Example:

```json
{
	"character_width": 80,
	"tabs": true,
	"tabs_width": 4
}
```

Options:

`character_width`: How many characters it takes before it line breaks it.

`spaces`: How many spaces is in one indentation.

`newline_limit`: The limit of newlines between statements and declarations.

`tabs`: Tabs or spaces.

`tabs_width`: How many characters one tab represents

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

### Neovim
Neovim has a builtin support for LSP.

There is a plugin that turns easier the setup, called [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig). You can
install it with you prefered package manager.

A simple configuration to use with Odin would be like this:
```lua
local lspconfig = require('lspconfig')
lspconfig.ols.setup({})
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

### Helix
```
[[language]]
name = "odin"
scope = "scope.odin"
file-types = ["odin"]
comment-token = "//"
indent = { tab-width = 2, unit = " " }
language-server = { command = "ols" }
injection-regex = "odin"
roots = ["ols.json"]
formatter = { command = "odinfmt", args = [ "-stdin", "true" ] }
```
