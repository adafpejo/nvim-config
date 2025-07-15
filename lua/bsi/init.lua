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
        "diffview"
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

vim.api.nvim_create_autocmd("LspAttach", {
    group = vim.api.nvim_create_augroup('lsp-attach', { clear = true }),
    callback = function(event)
        local map = function(keys, func, desc)
            vim.keymap.set("n", keys, func, { buffer = event.buf, desc = "LSP: " .. desc })
        end

        map("gl", vim.diagnostic.open_float, "Open Diagnostic Float")
        map("D", vim.lsp.buf.hover, "Hover Documentation")
        map("gs", vim.lsp.buf.signature_help, "Signature Documentation")
        map("gD", vim.lsp.buf.declaration, "Goto Declaration")
        map("<leader>v", "<cmd>vsplit | lua vim.lsp.buf.definition()<cr>", "Goto Definition in Vertical Split")

        local function client_supports_method(client, method, bufnr)
            if vim.fn.has 'nvim-0.11' == 1 then
                return client:supports_method(method, bufnr)
            else
                return client.supports_method(method, { bufnr = bufnr })
            end
        end

        local client = vim.lsp.get_client_by_id(event.data.client_id)
        if client and client_supports_method(client, vim.lsp.protocol.Methods.textDocument_documentHighlight, event.buf) then
            local highlight_augroup = vim.api.nvim_create_augroup('lsp-highlight', { clear = false })
            vim.api.nvim_create_autocmd({ 'CursorHold', 'CursorHoldI' }, {
                buffer = event.buf,
                group = highlight_augroup,
                callback = vim.lsp.buf.document_highlight,
            })

            vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
                buffer = event.buf,
                group = highlight_augroup,
                callback = vim.lsp.buf.clear_references,
            })

            vim.api.nvim_create_autocmd('LspDetach', {
                group = vim.api.nvim_create_augroup('lsp-detach', { clear = true }),
                callback = function(event2)
                    vim.lsp.buf.clear_references()
                    vim.api.nvim_clear_autocmds { group = 'lsp-highlight', buffer = event2.buf }
                end,
            })
        end


        if client and client_supports_method(client, vim.lsp.protocol.Methods.textDocument_inlayHint, event.buf) then
            map('<leader>th', function()
                vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled { bufnr = event.buf })
            end, '[T]oggle Inlay [H]ints')
        end
    end,

})

