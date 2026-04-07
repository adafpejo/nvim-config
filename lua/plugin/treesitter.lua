require("nvim-treesitter-textobjects").setup({
  textobjects = {
    select = {
      enable = true,
      lookahead = true,
      keymaps = {
        ["aa"] = "@parameter.outer",
        ["ia"] = "@parameter.inner",
        ["af"] = "@function.outer",
        ["if"] = "@function.inner",
        ["ac"] = "@class.outer",
        ["ic"] = "@class.inner",
      },
    },
    move = {
      enable = true,
      set_jumps = true,
      goto_next_start = {
        ["]m"] = "@function.outer",
        ["]]"] = "@class.outer",
      },
      goto_next_end = {
        ["]M"] = "@function.outer",
        ["]["] = "@class.outer",
      },
      goto_previous_start = {
        ["[m"] = "@function.outer",
        ["[["] = "@class.outer",
      },
      goto_previous_end = {
        ["[M"] = "@function.outer",
        ["[]"] = "@class.outer",
      },
    },
  },
})

local ensureInstalled = {
    "angular",
    "astro",
    "bash",
    "c",
    "c_sharp",
    "cmake",
    "comment",
    "cpp",
    "css",
    "csv",
    "dart",
    "diff",
    "dockerfile",
    "dot",
    "git_config",     -- ??
    "go",
    "goctl",
    "gomod",
    "gosum",
    "gotmpl",
    "gowork",
    "graphql",
    "helm",
    "html",
    "http",
    "ini",
    "jinja",
    "java",
    "javascript",
    "jsdoc",
    "json",
    "json5",
    "kotlin",
    "lua",
    "luau",
    "luadoc",
    "make",
    "markdown",
    "markdown_inline",
    "nginx",
    "php",
    "php_only",
    "phpdoc",
    "proto",
    "python",
    "regex",
    "scss",
    "sql",
    "svelte",
    "templ",
    "tsx",
    "typescript",
    "vim",
    "vimdoc",
    "xml",
    "yaml",
    "zig"
}

vim.api.nvim_create_autocmd('FileType', {
    callback = function()
        -- Enable treesitter highlighting and disable regex syntax
        pcall(vim.treesitter.start)
        -- Enable treesitter-based indentation
        vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
    end,
})

local alreadyInstalled = require('nvim-treesitter.config').get_installed()
local parsersToInstall = vim.iter(ensureInstalled)
    :filter(function(parser)
        return not vim.tbl_contains(alreadyInstalled, parser)
    end)
    :totable()
require('nvim-treesitter').install(parsersToInstall)

