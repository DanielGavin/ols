-- This is a definition to add to your code formatter in Neovim.
-- "stevearc/conform.nvim" can be configured to format on save,
-- here is a definition of odinfmt for conform using the lazy.nvim
-- plugin manager.
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
