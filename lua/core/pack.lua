local gh = function(x) return 'https://github.com/' .. x end
local languages = require("languages")

-- vim.pack has no build= hook. Compile sniprun locally on install/update
-- (macOS cannot use the Linux prebuilt binary; cargo is required).
vim.api.nvim_create_autocmd("PackChanged", {
    callback = function(ev)
        local data = ev.data or {}
        local spec = data.spec or {}
        if spec.name ~= "sniprun" then
            return
        end
        if data.kind ~= "install" and data.kind ~= "update" then
            return
        end
        local cargo_bin = vim.fn.expand("~/.cargo/bin")
        local env = vim.fn.environ()
        env.PATH = cargo_bin .. ":" .. (env.PATH or "")
        local result = vim.system({ "sh", "install.sh", "1" }, {
            cwd = data.path,
            env = env,
        }):wait()
        if result.code ~= 0 then
            vim.notify("sniprun build failed:\n" .. (result.stderr or result.stdout or ""), vim.log.levels.ERROR)
        end
    end,
})

vim.pack.add({
    gh("nvim-lua/plenary.nvim"),          -- lua functions that many plugins use
    gh("christoomey/vim-tmux-navigator"), -- tmux & split window navigation
    gh("MunifTanjim/nui.nvim"),
    gh("L3MON4D3/LuaSnip"),

    -- mason
    gh("williamboman/mason.nvim"),

    -- nvim-treesetter
    gh("nvim-treesitter/nvim-treesitter"),
    gh("nvim-treesitter/nvim-treesitter-textobjects"),
    gh("nvim-mini/mini.nvim"),

    -- dap
    gh("mfussenegger/nvim-dap"),
    gh("leoluz/nvim-dap-go"),
    gh("rcarriga/nvim-dap-ui"),
    gh("theHamsta/nvim-dap-virtual-text"),

    -- git
    gh("sindrets/diffview.nvim"),

    -- named TUI floats (hide window, keep job)
    gh("akinsho/toggleterm.nvim"),

    -- markdown
    gh("MeanderingProgrammer/render-markdown.nvim"),

    -- ui
    gh("rcarriga/nvim-notify"),
    gh("nvim-lualine/lualine.nvim"),
    gh("MunifTanjim/nui.nvim"),
    gh("folke/zen-mode.nvim"),

    -- lualine
    gh("nvim-lualine/lualine.nvim"),

    -- telescope
    gh("nvim-telescope/telescope.nvim"),
    gh("nvim-telescope/telescope-live-grep-args.nvim"),
    { src = gh("nvim-telescope/telescope-fzf-native.nvim"), build = 'make' },

    -- nvim-tree
    gh("nvim-tree/nvim-tree.lua"),
    gh("nvim-tree/nvim-web-devicons"),

    -- blink
    { src = gh("saghen/blink.cmp"), version = "v1" },
    gh("rafamadriz/friendly-snippets"),
    gh("echasnovski/mini.snippets"),

    -- colorshema
    gh("folke/tokyonight.nvim"),

    -- replace-all
    gh("MagicDuck/grug-far.nvim"),

    gh("tpope/vim-surround"),
    gh("tpope/vim-commentary"),
    gh("christoomey/vim-tmux-navigator"),
    gh("lewis6991/gitsigns.nvim"),

    -- harpoon
    gh("ThePrimeagen/harpoon"),

    -- xcode
    gh("wojciech-kulik/xcodebuild.nvim"),

    -- test
    gh("nvim-neotest/neotest"),
    gh("nvim-neotest/nvim-nio"),
    gh("antoinemadec/FixCursorHold.nvim"),

    gh("vim-test/vim-test"),
    gh("nvim-neotest/neotest-jest"),
    gh("marilari88/neotest-vitest"),
    gh("HiPhish/neotest-busted"),
    gh("thenbe/neotest-playwright"),
    gh("nvim-neotest/neotest-python"),

    -- adapters
    { src = gh("nvim-neotest/neotest-go"), version = "05535cb2cfe3ce5c960f65784896d40109572f89" }, -- https://github.com/nvim-neotest/neotest-go/issues/57
    gh("andythigpen/nvim-coverage"),
    gh("stevearc/conform.nvim"),
    gh("mfussenegger/nvim-lint"),

    -- claude code
    gh("greggh/claude-code.nvim"),

    -- snippet runner (Rust binary; compiled via PackChanged + install.sh)
    gh("michaelb/sniprun"),
})

-- Java plugins. Toggle in lua/languages.local.lua.
if languages.java then
    vim.pack.add({
        gh("mfussenegger/nvim-jdtls"),
        gh("rcasia/neotest-java"),
    })
end

-- setup
require("plugin.mason")
require("plugin.blink")
require("plugin.gitsigns")
require("plugin.diffview")
require("plugin.nvim-tree")
require("plugin.lualine")
require("plugin.treesitter")
require("plugin.telescope")
require("plugin.test")
require("plugin.conform")
require("plugin.lint")
require("plugin.render-markdown")
require("plugin.sniprun")
require("plugin.toggleterm")
require("xcodebuild").setup({})
require("grug-far").setup({})
require("claude-code").setup({
  window = {
    position = "float",
    float = {
      width = "90%",      -- Take up 90% of the editor width
      height = "90%",     -- Take up 90% of the editor height
      row = "center",     -- Center vertically
      col = "center",     -- Center horizontally
      relative = "editor",
      border = "double",  -- Use double border style
    },
  },
})

-- require("jdtls").setup()
