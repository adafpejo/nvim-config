require("bsi.postload")
require("bsi.remap")
require("bsi.refactoring")

local nvim = require("bsi.utils.nvim")

require('notify').setup({
    timeout = 200
})
vim.notify_popup = require('notify')

-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
-- Add any additional autocmds here

local function augroup(name)
    return vim.api.nvim_create_augroup("lazyvim_" .. name, { clear = true })
end

local autocmd = vim.api.nvim_create_autocmd

local bsiGroup = augroup("bsi")

-- avoid new comment
vim.api.nvim_create_autocmd("FileType", {
    group = bsiGroup,
    pattern = "*",
    callback = function()
        vim.opt_local.formatoptions:remove({ 'r', 'o' })
        vim.opt.eol = true
        vim.opt.fixeol = true
    end,
})
-- lint/format buffer before save
autocmd("BufWritePre", {
    group = bsiGroup,
    pattern = "*",
    command = [[%s/\s\+$//e]],
})
autocmd("BufWritePre", {
    pattern = { "*.js", "*.ts", "*.tsx", "*.jsx" },
    group = bsiGroup,
    callback = function()
        vim.cmd("silent! EslintFixAll")
    end,
})
autocmd("FileType", {
    callback = function()
        pcall(vim.treesitter.start)
    end,
})

-- autocmd({ "FileType" }, {
--     pattern = { "json", "jsonc", "json5", "markdown" },
--     callback = function()
--         vim.wo.conceallevel = 0
--         vim.opt_local.tabstop = 2
--         vim.opt_local.softtabstop = 2
--         vim.opt_local.shiftwidth = 2
--     end,
-- })

-- local coverageLoadCallback = function()
--     require("coverage").load()
--     vim.cmd("CoverageShow")
-- end
-- autocmd({ "BufEnter", "FileType" }, {
--     group = augroup("coverage"),
--     pattern = { "javascript", "javascriptreact", "typescript", "typescriptreact" },
--     callback = coverageLoadCallback,
-- })

-- Highlight on yank
autocmd("TextYankPost", {
    group = augroup("highlight_yank"),
    callback = function()
        vim.highlight.on_yank()
    end,
})

autocmd({ 'BufNewFile', 'BufRead' }, {
    pattern = {
        "**/templates/*.yaml",
        "**/templates/*.yml",
        "**/templates/*.tpl",
        "*.gotmpl",
    },
    callback = function()
        vim.opt_local.filetype = 'helm'
    end
})

autocmd({ "FileType" }, {
    pattern = { "helm", "terraform" },
    callback = function()
        vim.schedule(function()
            nvim.stop_lsp_byname("yamlls")
        end)
    end
})

autocmd({ "FileType" }, {
    pattern = { "helm" },
    callback = function()
        vim.opt.tabstop = 2
        vim.opt.shiftwidth = 2
        vim.opt.expandtab = true
        vim.opt.autointent = true
        vim.opt.smartintent = true
    end
})

autocmd({ "FileType" }, {
    pattern = { "markdown" },
    callback = function()
        vim.opt.wrap = true
        vim.opt.linebreak = true
        vim.opt.list = false
        vim.opt.textwidth = 120
        vim.opt.wrapmargin = 0
    end
})

-- close some filetypes with <q>
autocmd("FileType", {
    group = augroup("close_with_q"),
    pattern = {
        "PlenaryTestPopup",
        "help",
        "lspinfo",
        "notify",
        "qf",
        "spectre_panel",
        "startuptime",
        "tsplayground",
        "neotest-output",
        "checkhealth",
        "neotest-summary",
        "neotest-output-panel",
        "dbout",
        "gitsigns.blame",
        "lazygit",
    },
    callback = function(event)
        vim.bo[event.buf].buflisted = false
        vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = event.buf, silent = true })
        vim.keymap.set("t", "<Esc>", "<cmd>close<cr>", { buffer = event.buf, silent = true })
    end,
})
autocmd("FileType", {
    group = augroup("close_with_q"),
    pattern = {
        "DiffviewFiles",
        "DiffviewFileHistory"
    },
    callback = function(event)
        vim.bo[event.buf].buflisted = false
        vim.keymap.set("n", "q", "<cmd>tabclose<cr>", { buffer = event.buf, silent = true })
        vim.keymap.set("t", "<Esc>", "<cmd>tabclose<cr>", { buffer = event.buf, silent = true })
    end,
})

vim.cmd("hi GitIgnore guifg=#ff0000")
vim.cmd("hi NvimTreeGitIgnored guifg=#ff0000")
vim.cmd("hi NvimTreeGitFileIgnoredHL guifg=gray")
vim.cmd("hi NvimTreeGitFolderIgnoredHL guifg=gray")

for _, group in ipairs(vim.fn.getcompletion("@lsp", "highlight")) do
    vim.api.nvim_set_hl(0, group, {})
end
