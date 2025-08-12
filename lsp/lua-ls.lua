local blink = require("blink.cmp")
return {
    cmd = { vim.fn.expand("~/.local/share/nvim/mason/bin/lua-language-server"), },
    filetypes = { "lua" },
    root_markers = {
        '.luarc.json',
        '.luarc.jsonc',
        '.luacheckrc',
        '.stylua.toml',
        'stylua.toml',
        'selene.toml',
        'selene.yml',
        '.git',
    },
    settings = {
        Lua = {
            runtime = {
                version = 'LuaJIT', -- Neovim uses LuaJIT
            },
            workspace = {
                library = vim.api.nvim_get_runtime_file("", true), -- Include Neovim runtime files
            },
            telemetry = { enable = false },                        -- Optional: disable telemetry,
        },
    },
    capabilities = vim.tbl_deep_extend(
        "force",
        {},
        vim.lsp.protocol.make_client_capabilities(),
        blink.get_lsp_capabilities(),
        {
            fileOperations = {
                didRename = true,
                willRename = true,
            },
        }
    ),
}
