# ols

Language server for Odin. This project is still in early development.

Note: This project is made to be up to date with the master branch of Odin.



## Table Of Contents

-   [Installation](#installation)
	-   [Configuration](#Configuration)
-   [Features](#features)
-   [Clients](#clients)
	-   [Vs Code](#vs-code)
	-   [Sublime](#sublime)
	-   [Vim](#vim)
	-   [Neovim](#neovim)
	-   [Emacs](#emacs)
	-   [Helix](#helix)
	-   [Micro](#micro)

## Installation

```bash
cd ols

# for windows
./build.bat
# To install the odinfmt formatter
./odinfmt.bat

# for linux and macos
./build.sh
# To install the odinfmt formatter
./odinfmt.sh
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
		{ "name": "custom_collection", "path": "c:/path/to/collection" }
	],
	"enable_semantic_tokens": false,
	"enable_document_symbols": true,
	"enable_hover": true,
	"enable_snippets": true,
	"profile": "default",
	"profiles": [
		{ "name": "default", "checker_path": ["src"]},
		{ "name": "linux_profile", "os": "linux", "checker_path": ["src/main.odin"]},
		{ "name": "windows_profile", "os": "windows", "checker_path": ["src"]}
	]
}
```

You can also set `ODIN_ROOT` environment variable to the path where ols should look for core and vendor libraries.

Options:

`enable_format`: Turns on formatting with `odinfmt`. _(Enabled by default)_

`enable_hover`: Enables hover feature

`enable_snippets`: Turns on builtin snippets

`enable_semantic_tokens`: Turns on syntax highlighting.

`enable_document_symbols`: Turns on outline of all your global declarations in your document.

`enable_fake_methods`: Turn on fake methods completion. This is currently highly experimental.

`enable_inlay_hints`: Turn on inlay hints for editors that support it.

`enable_procedure_snippet`: Use snippets when completing procedures—adds parenthesis after the name. _(Enabled by default)_

`enable_checker_only_saved`: Turns on only calling the checker on the package being saved. 

`enable_references`: Turns on finding references for a symbol.  (Experimental)

`enable_rename`: Turns on renaming a symbol. (Experimental)

`odin_command`: Allows you to specify your Odin location, instead of just relying on the environment path.

`checker_args`: Pass custom arguments to `odin check`.

`verbose`: Logs warnings instead of just errors.

`profile`: What profile to currently use.

`profiles`: List of different profiles that describe the environment ols is running under.

### Odinfmt configurations

Odinfmt reads configuration through `odinfmt.json`.

Example:

```json
{
	"$schema": "https://raw.githubusercontent.com/DanielGavin/ols/master/misc/odinfmt.schema.json",
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

`sort_imports`: A boolean that defaults to true, which can be set to false to disable sorting imports.

## Features

Support Language server features:

-   Completion
-   Go to definition
-   Semantic tokens
-   Document symbols
-   Rename
-   References
-   Signature help
-   Hover

## Clients

### VS Code

Install the extension https://marketplace.visualstudio.com/items?itemName=DanielGavin.ols

### Sublime

Install the package https://github.com/sublimelsp/LSP

Configuration of the LSP:

```json
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
					}
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

```json
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

There is a plugin that makes the setup easier, called [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig). You can install it with your prefered package manager.

A simple configuration that uses the default `ols` settings would be like this:

```lua
require'lspconfig'.ols.setup {}
```

And here is an example of a configuration with a couple of settings applied:

```lua
require'lspconfig'.ols.setup {
	init_options = {
		checker_args = "-strict-style",
		collections = {
			{ name = "shared", path = vim.fn.expand('$HOME/odin-lib') }
		},
	},
}
```

### Emacs

```elisp
;; Enable odin-mode and configure OLS as the language server
(use-package! odin-mode
  :mode ("\\.odin\\'" . odin-mode)
  :hook (odin-mode . lsp))

;; Set up OLS as the language server for Odin, ensuring lsp-mode is loaded first
(with-eval-after-load 'lsp-mode
  (setq-default lsp-auto-guess-root t) ;; Helps find the ols.json file with Projectile or project.el
  (setq lsp-language-id-configuration (cons '(odin-mode . "odin") lsp-language-id-configuration))

  (lsp-register-client
   (make-lsp-client :new-connection (lsp-stdio-connection "/path/to/ols/executable") ;; Adjust the path here
                    :major-modes '(odin-mode)
                    :server-id 'ols
                    :multi-root t))) ;; Ensures lsp-mode sends "workspaceFolders" to the server

(add-hook 'odin-mode-hook #'lsp)
```

### Helix

Helix supports Odin and OLS by default. It is already enabled in the [default languages.toml](https://github.com/helix-editor/helix/blob/master/languages.toml). 

If `ols` or `odinfmt` are not on your PATH environment variable, you can enable them like this:
```toml
# Optional. The default configration requires OLS in PATH env. variable. If not,
# you can set path to the executable like so:
# [language-server.ols]
# command = "path/to/executable"
```

### Micro

Install the [LSP plugin](https://github.com/AndCake/micro-plugin-lsp)

Configure the plugin in micro's settings.json:

```json
{
	"lsp.server": "c=clangd,go=gopls,odin=ols"
}
```
### Kate

First, make sure you have the LSP plugin enabled. Then, you can find LSP settings for Kate in Settings -> Configure Kate -> LSP Client -> User Server Settings.

You may have to set the folders for your Odin home path directly, like in the following example:
```json
{
    "servers": {
        "odin": {
            "command": [
                "ols"
            ],
            "filetypes": [
                "odin"
            ],
            "url": "https://github.com/DanielGavin/ols",
            "root": "%{Project:NativePath}",
            "highlightingModeRegex": "^Odin$",
            "initializationOptions": {
                "collections": [
                    {
                        "name": "core",
                        "path": "/path/to/Odin/core"
                    },
                    {
                        "name": "vendor",
                        "path": "/path/to/Odin/vendor"
                    },
                    {
                        "name": "shared",
                        "path": "/path/to/Odin/shared"
                    },
                    {
                        "name": "src", // If your project has src-collection in root folder, 
                        "path": "src"  // this will add it as a collection
                    },
                    {
                        "name": "collection_a",
                        "path": "/path/to/collection_a"
                    }
                ],
                "odin_command": "path/to/Odin",
                "verbose": true,
                "enable_document_symbols": true,
                "enable_hover": true
            }
        }
    }
}
```
Kate can infer inlay hints on its own when enabled in LSP settings, so enabling it separately in the server config
can cause some weird behavior.
