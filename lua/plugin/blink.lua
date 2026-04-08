require("blink.cmp").setup({
    snippets = { preset = "mini_snippets" },
    signature = { enabled = true },
    appearance = {
        use_nvim_cmp_as_default = false,
        nerd_font_variant = "normal",
    },
    sources = {
        default = { "lsp", "path", "snippets", "buffer" },
        providers = {
            cmdline = {
                min_keyword_length = 2,
            },
        },
    },
    keymap = {
        ["<C-CR>"] = { "accept", 'fallback' },
        ["<C-j>"] = { "select_next" },
        ["<C-k>"] = { "select_prev" },
    },
    cmdline = {
        enabled = false,
        completion = { menu = { auto_show = true } },
        keymap = {
            ["<C-CR>"] = { "accept_and_enter", "fallback" },
            ["<C-j>"] = { "select_next" },
            ["<C-k>"] = { "select_prev" },
        },
    },
    completion = {
        menu = {
            border = nil,
            scrolloff = 1,
            scrollbar = false,
            draw = {
                columns = {
                    { "kind_icon" },
                    { "label",      "label_description", gap = 1 },
                    { "kind" },
                    { "source_name" },
                },
            },
        },
        documentation = {
            window = {
                border = nil,
                scrollbar = false,
                winhighlight = 'Normal:BlinkCmpDoc,FloatBorder:BlinkCmpDocBorder,EndOfBuffer:BlinkCmpDoc',
            },
            auto_show = true,
            auto_show_delay_ms = 500,
        },
    },
})

require("luasnip.loaders.from_vscode").lazy_load()
local gen_loader = require('mini.snippets').gen_loader
require('mini.snippets').setup({
  snippets = {
    -- Load snippets based on current language by reading files from
    -- "snippets/" subdirectories from 'runtimepath' directories.
    gen_loader.from_lang(),
  },
  -- Module mappings. Use `''` (empty string) to disable one.
  mappings = {
    -- Expand snippet at cursor position. Created globally in Insert mode.
    expand = '<C-CR>',

    -- Interact with default `expand.insert` session.
    -- Created for the duration of active session(s)
    jump_next = '<C-l>',
    jump_prev = '<C-h>',
    stop = '<C-c>',
  },
})

