# ols

Language server for Odin. This project is still in early development.

**Status**: You have to use `odin` commit 886d0de to build. Project can't compile with the latest llvm 17 update.

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
  - [Helix](#helix)
  - [Micro](#micro)

## Installation

```bash
cd ols

# for windows
./build.bat

# for linux
./build.sh
```

### Configuration

In order for the language server to index your files, it must know about your collections.

To do that you can either configure ols via an `ols.json` file (it should be located at the root of your workspace).

Or you can provide the configuration via your editor of choice.

Example of `ols.json`:

```json
{
	"$schema": "https://raw.githubusercontent.com/DanielGavin/ols/master/misc/ols.schema.json",
	"collections": [
		{ "name": "core", "path": "c:/path/to/Odin/core" },
		{ "name": "shared", "path": "c:/path/to/MyProject/src" }
	],
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

`enable_fake_methods`: Turn on fake methods completion. This is currently highly experimental.

`enable_inlay_hints`: Turn on inlay hints for editors that support it.

`odin_command`: Allows you to specify your Odin location, instead of just relying on the environment path.

`checker_args`: Pass custom arguments to `odin check`.

`verbose`: Logs warnings instead of just errors.

### Odinfmt configurations

Odinfmt reads configuration through `odinfmt.json`.

Example:

```json
{
	"$schema": "https://raw.githubusercontent.com/DanielGavin/ols/master/misc/odinfmt.schema.json",
	"character_width": 80,
	"tabs": true
}
```

Options:

`character_width`: How many characters it takes before it line breaks it.

`spaces`: How many spaces is in one indentation.

`newline_limit`: The limit of newlines between statements and declarations.

`tabs`: Tabs or spaces.

`tabs_width`: How many characters one tab represents

`sort_imports`: A boolean that defaults to true, which can be set to false to disable sorting imports.

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
    "clients": {
        "odin": {
            "command": [
                "/path/to/ols"
            ],
            "enabled": false, // true for globally-enabled, but not required due to 'Enable In Project' command
            "selector": "source.odin",
            "initializationOptions": {
                "collections": [
                    {
                        "name": "collection_a",
                        "path": "/path/to/collection_a"
                    },
                ],
                "enable_semantic_tokens": true,
                "enable_document_symbols": true,
                "enable_hover": true,
                "enable_snippets": true,
                "enable_format": true,
            }
        }
    }
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

### Micro

Install the [LSP plugin](https://github.com/AndCake/micro-plugin-lsp)

Configure the plugin in micro's settings.json:

```json
{
	"lsp.server": "c=clangd,go=gopls,odin=ols"
}
```
