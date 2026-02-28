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

In order for `ols` to find symbols for builtin types and procedures, the `builtin` folder in the repo needs to be located next to the `ols` binary. Alternatively you can specify the path to this folder using the `OLS_BUILTIN_FOLDER` environment variable.

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
		{ "name": "default", "checker_path": ["src"], "defines": { "ODIN_DEBUG": "false" }},
		{ "name": "linux_profile", "os": "linux", "checker_path": ["src/main.odin"], "defines": { "ODIN_DEBUG": "false" }},
		{ "name": "mac_profile", "os": "darwin", "arch": "arm64", "defines": { "ODIN_DEBUG": "false" }},
		{ "name": "windows_profile", "os": "windows", "checker_path": ["src"], "defines": { "ODIN_DEBUG": "false" }}
	]
}
```

Options:

- `enable_format`: Turns on formatting with `odinfmt`. _(Enabled by default)_

- `enable_hover`: Enables hover feature. _(Enabled by default)_

- `enable_document_symbols`: Turns on outline of all your global declarations in your document. _(Enabled by default)_

- `enable_fake_methods`: Turn on fake methods completion. This is currently highly experimental.

- `enable_overload_resolution`: Enable go-to-definition to resolve overloaded procedures from procedure groups based on call arguments.

- `enable_references`: Turns on finding references for a symbol. _(Enabled by default)_

- `enable_document_highlights`: Turns on highlighting of symbol references in file. _(Enabled by default)_

- `enable_document_links`: Follow links when opening documentation. This is usually done via `<ctrl+click>` and will open the documentation in a browser (or similar). _(Enabled by default)_

- `enable_completion_matching`: Attempt to match types and pointers when passing arguments to procedures. _(Enabled by default)_

- `enable_inlay_hints_params`: Turn on inlay hints for (non-default) parameters.

- `enable_inlay_hints_default_params`: Turn on inlay hints for default parameters.

- `enable_inlay_hints_implicit_return`: Turn on inlay hints for implicit return values.

- `enable_semantic_tokens`: Turns on syntax highlighting.

- `enable_snippets`: Turns on builtin snippets

- `enable_procedure_snippet`: Use snippets when completing procedures—adds parenthesis after the name. _(Enabled by default)_

- `enable_checker_only_saved`: Turns on only calling the checker on the package being saved. _(Enabled by default)_

- `enable_checker_diagnostics_on_start`: Turns on running all workspace diagnostics using odin check when starting ols (experimental).

- `enable_auto_import`: Automatically import packages that aren't in your import on completion.

- `enable_comp_lit_signature_help`: Provide signature help for comp lits such as when instantiating structs. Will not display correctly on some editors such as vscode.

- `enable_comp_lit_signature_help_use_docs`: Put signature help for comp lits in the documentation. This will allow it to be rendered nicely using markdown in editors that render the label without colour on one line.

- `enable_code_action_invert_if`: Enables a code action to invert if statements.

- `odin_command`: Specify the location to your Odin executable, rather than relying on the environment path.

- `odin_root_override`: Allows you to specify a custom `ODIN_ROOT` that `ols` will use to look for `odin` core libraries when implementing custom runtimes.

- `checker_args`: Pass custom arguments to `odin check`.

- `checker_skip_packages`: Paths to packages that should not be checked by `odin check`.

- `verbose`: Logs warnings instead of just errors.

- `profile`: What profile to currently use.

- `profiles`: List of different profiles that describe the environment ols is running under. This allows you to define different operating systems, architectures and defines for `ols` to use during development, easily switching between them using the `profile` configuration.

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

- `character_width`: How many characters it takes before it line breaks it.

- `spaces`: How many spaces is in one indentation.

- `newline_limit`: The limit of newlines between statements and declarations.

- `tabs`: Tabs or spaces.

- `tabs_width`: How many characters one tab represents.

- `convert_do`: Convert all do statements to brace blocks.

- `brace_style`: Style of braces. One of `_1TBS`, `Allman`, `Stroustrup`, `K_And_R`.

- `indent_cases`: Indent case statements within a switch.

- `newline_style`: Line endings to use. One of `CRLF`, `LF`.

- `sort_imports`: A boolean that defaults to true, which can be set to false to disable sorting imports.

- `inline_single_stmt_case`: When statement in the clause contains one simple statement, it will inline the case and statement in one line.

- `spaces_around_colons`: Put a space on both sides of a single colon during variable/field declaration, such as `foo : bar`

- `space_single_line_blocks`: Put spaces around braces of single-line blocks: `{return 0}` => `{ return 0 }`

- `align_struct_fields`: Align the types of struct fields so they all start at the same column.

- `align_struct_values`: Align the values of struct fields when assigning a struct value to a variable so they all start at the same column.

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

There is a plugin that makes the setup easier, called [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig). You can install it with your preferred package manager.

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

Neovim can run Odinfmt on save using the [conform](https://github.com/stevearc/conform.nvim) plugin. Here is a sample configuration using the [lazy.nvim](https://github.com/folke/lazy.nvim) package manager:

```lua
local M = {
   "stevearc/conform.nvim",
   opts = {
      notify_on_error = false,
      -- Odinfmt gets its configuration from odinfmt.json. It defaults
      -- writing to stdout but needs to be told to read from stdin.
      formatters = {
         odinfmt = {
            -- Change where to find the command if it isn't in your path.
            command = "odinfmt",
            args = { "-stdin" },
            stdin = true,
         },
      },
      -- and instruct conform to use odinfmt.
      formatters_by_ft = {
         odin = { "odinfmt" },
      },
   },
}
return M
```

### Emacs

For Emacs, there are two packages available for LSP; lsp-mode and eglot.

The latter is built-in, spec-compliant and favours built-in Emacs functionality and the former offers richer UI elements and automatic installation for some of the servers.

In either case, you'll also need an associated major mode.

Pick either of the below, the former is likely to be more stable but the latter will allow you to take advantage of tree-sitter and other packages that integrate with it.

The `use-package` statements below assume you're using a package manager like Straight or Elpaca and as such should be taken as references rather than guaranteed copy/pasteable. If you're using `package.el` or another package manager then you'll have to look into instructions for that yourself.

```elisp
;; Enable odin-mode and configure OLS as the language server
(use-package odin-mode
  :ensure (:host github :repo "mattt-b/odin-mode")
  :mode ("\\.odin\\'" . odin-mode))

;; Or use the WIP tree-sitter mode
(use-package odin-ts-mode
  :ensure (:host github :repo "Sampie159/odin-ts-mode")
  :mode ("\\.odin\\'" . odin-ts-mode))
```

And then choose either the built-in `eglot` or `lsp-mode` packages below. Both should work very similarly.

#### lsp-mode

As of lsp-mode pull request [4818](https://github.com/emacs-lsp/lsp-mode/pull/4818) ols is included as a pre-configured client. You will need to install lsp-mode from source until version 9.1 has been released. Just `M-x lsp-install-server` and select ols. This will download and install the latest version of ols from the releases. Then start lsp-mode with `M-x lsp` or add hook on the below package

```elisp
;; Pull the lsp-mode package from elpa
(use-package lsp-mode
  :commands (lsp lsp-deferred))

;; OR Pull lsp-mode from source using Straight this snippet has the install instructions for installing straight.el
(defvar straight-use-package-by-default t)
(defvar straight-recipes-repo-clone-depth 1)
(defvar straight-enable-github-repos t)
(defvar bootstrap-version)
(let ((bootstrap-file
       (expand-file-name
        "straight/repos/straight.el/bootstrap.el"
        (or (bound-and-true-p straight-base-dir)
            user-emacs-directory)))
      (bootstrap-version 7))
  (unless (file-exists-p bootstrap-file)
    (with-current-buffer
        (url-retrieve-synchronously
         "https://raw.githubusercontent.com/radian-software/straight.el/develop/install.el"
         'silent 'inhibit-cookies)
      (goto-char (point-max))
      (eval-print-last-sexp)))
  (load bootstrap-file nil 'nomessage))

;; Configure straight.el
(straight-use-package 'use-package)

(use-package lsp-mode
  :straight (lsp-mode :host github :repo "emacs-lsp/lsp-mode")
  :commands (lsp lsp-deferred))

;; Add a hook to autostart OLS
(add-hook 'odin-mode-hook #'lsp-deferred)
(add-hook 'odin-ts-mode-hook #'lsp-deferred) ;; If you're using the TS mode
```

#### eglot

```elisp
;; Add OLS to the list of available programs
;; NOTE: As of Emacs 30, this is not needed.
(with-eval-after-load 'eglot
  (add-to-list 'eglot-server-programs '((odin-mode odin-ts-mode) . ("ols"))))

;; Add a hook to autostart OLS
(add-hook 'odin-mode-hook #'eglot-ensure)
(add-hook 'odin-ts-mode-hook #'eglot-ensure) ;; If you're using the TS mode
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
