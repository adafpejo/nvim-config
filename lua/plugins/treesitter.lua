return {
    -- Better syntax highlighting & much more
    {
        "nvim-treesitter/nvim-treesitter",
        build = ":TSUpdate",
        lazy = vim.fn.argc(-1) == 0, -- load treesitter early when opening a file from the cmdline
        init = function(plugin)
            -- PERF: add nvim-treesitter queries to the rtp and it's custom query predicates early
            -- This is needed because a bunch of plugins no longer `require("nvim-treesitter")`, which
            -- no longer trigger the **nvim-treesitter** module to be loaded in time.
            -- Luckily, the only things that those plugins need are the custom queries, which we make available
            -- during startup.
            require("nvim-treesitter.query_predicates")
        end,
        cmd = { "TSUpdateSync", "TSUpdate", "TSInstall" },
        config = function()
            local configs = require("nvim-treesitter.configs")

            configs.setup({
                ensure_installed = {
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
                    "git_config", -- ??
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
                },
                highlight = { enable = true },
                indent = { enable = true },
                autotag = { enable = true, enable_close_on_slash = false },
            })
        end,
    },
}
