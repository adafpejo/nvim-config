local refactoring = require("bsi.refactoring")
local nvim        = require("bsi.utils.nvim")
local ai          = require("bsi.ai")
local ide         = require("bsi.ide")
local system      = require("bsi.system")
local fastgit     = require("bsi.fastgit")
local multigrep   = require("bsi.multigrep")
local rglist      = require("bsi.rglist")
local bsi_tree    = require("bsi.ui.tree")

-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- vim.keymap.set("n", "<C-/>", "<cmd>ToggleTermToggleAll<CR>")

-- Diagnostic list
vim.keymap.set('n', '<leader>e', vim.diagnostic.setqflist)

-- exit insert mode with jk
vim.keymap.set("i", "jk", "<ESC>", { noremap = true, silent = true, desc = "<ESC>" })

-- prevent save selected word
vim.keymap.set('v', 'p', '"_dp', {
    desc = 'Paste copied text without copying selected',
    noremap = true,
})

--- Navigate to the next/prev file using the BSI Tree (if one is currently open
--- as part of a UI layout). Does nothing if no BSI tree window exists.
---@param dir "down"|"up"
local function navigate_file(dir)
  local instances = bsi_tree.instances or {}
  for _, t in pairs(instances) do
    if t.winid and vim.api.nvim_win_is_valid(t.winid) then
      t:navigate_file(dir)
      return
    end
  end
  -- No BSI tree visible: do nothing (NvimTree integration has been removed)
end

-- files navigation (powered by BSI Tree)
vim.keymap.set({ "n" }, "<C-j>", function()
  navigate_file('down')
end, { noremap = true, desc = "Open next file" })
vim.keymap.set({ "n" }, "<C-k>", function()
  navigate_file('up')
end, { noremap = true, desc = "Open prev file" })

-- Basic vim
vim.keymap.set({ "n" }, "<CR>", ":w<CR>", { noremap = true, desc = "Save file" })

vim.keymap.set({ "n" }, "H", "^", { noremap = true, desc = "First non-blank" })
vim.keymap.set({ "n" }, "L", "g_", { noremap = true, desc = "Last non-blank" })

-- Perusing code faster with K and J
vim.keymap.set({ "n", "v" }, "K", "5k", { noremap = true, desc = "Up faster" })
vim.keymap.set({ "n", "v" }, "J", "5j", { noremap = true, desc = "Down faster" })

vim.keymap.set({ "v" }, "<", "<gv", { noremap = true, desc = "Remap to save selected" })
vim.keymap.set({ "v" }, ">", ">gv", { noremap = true, desc = "Remap to save selected" })

vim.keymap.set('n', '<leader>fh', '<cmd>Telescope help_tags<cr>', { noremap = true, silent = true })

vim.keymap.set({ "v" }, "<leader>f", refactoring.format_markdown_150, { noremap = true });

-- Remap K and J
vim.keymap.set({ "n", "v" }, "<leader>k", "K", { noremap = true, desc = "Keyword" })
vim.keymap.set({ "n", "v" }, "<leader>j", "J", { noremap = true, desc = "Join lines" })

-- format buf
vim.keymap.set("n", "<leader>f", vim.lsp.buf.format, { noremap = true, silent = true })
vim.keymap.set("n", "<leader>F", function()
    vim.lsp.buf.format()
    vim.api.nvim_command("write")
end, { noremap = true, silent = true })

-- replace whole project
vim.keymap.set("n", "<leader>fr", ":GrugFar<CR>", { noremap = true, desc = "GrugFar" })

-- Save file
vim.keymap.set("n", "<leader>w", "<cmd>w<cr>", { noremap = true, desc = "Save window" })
vim.api.nvim_create_user_command("W", function(opts)
    vim.cmd("w " .. opts.args)
end, { nargs = "*" })
vim.api.nvim_create_user_command("Msg", function(opts)
    vim.cmd("messages " .. opts.args)
end, { nargs = "*" })

-- Quike exit
vim.keymap.set("n", "<leader>qq", "<cmd>qa<cr>", { desc = "Quike quite" })

vim.keymap.set("n", "<leader>L", "<cmd>Lazy<cr>", { desc = ":Lazy" })
vim.keymap.set("n", "<leader>vd", nvim.clear_hightlights, { desc = "Remove visual" })

vim.keymap.set("n", "<M-j>", "<cmd>cnext<cr>", { desc = "Next Quike fix" })
vim.keymap.set("n", "<M-k>", "<cmd>cprev<cr>", { desc = "Next Quike fix" })

-- lsp shortcut
vim.keymap.set("n", "<leader>ci", "<cmd>LspInfo<cr>", { desc = ":Lazy" })
vim.keymap.set("n", "<leader>cl", "<cmd>LspLog<cr>", { desc = ":Lazy" })
vim.keymap.set("n", "<leader>cr", "<cmd>LspRestart<cr>", { desc = ":Lazy" })

-- llm shortcut
vim.keymap.set("v", "<leader>ls", function()
    ai.ask_english()
end, { noremap = true, desc = ":Lazy" })
vim.keymap.set("v", "<leader>lc", function()
    ai.ask_coder()
end, { noremap = true, desc = ":Lazy" })
vim.keymap.set("v", "<leader>lC", function()
    ai.ask_comment()
end, { noremap = true, desc = ":Lazy" })
vim.keymap.set("n", "<leader>la", function()
    ai.ask_goose()
end, { noremap = true, desc = ":Lazy" })
vim.keymap.set("v", "<leader>la", function()
    ai.ask_v()
end, { noremap = true, desc = ":Lazy" })

-- Lazygit
vim.keymap.set("n", "<leader>gg", "<cmd>LazyGit<cr>", { noremap = true, desc = "Open lazygit" })
-- Lazydocker
vim.keymap.set("n", "<leader>dd", "<cmd>LazyDocker<cr>", { noremap = true, desc = "Open lazydocker" })

-- Gen.nvim
vim.keymap.set({ "n", "v" }, "<leader>]", ":Gen<CR>")

-- bsi motions (highlight matches in buffer)
vim.keymap.set({ "n" }, "<leader>h", ide.highlight_cursor_word, { noremap = true, desc = "Highlight word in current buffer" })
vim.keymap.set({ "v" }, "<leader>h", ide.highlight_visual, { noremap = true, desc = "Highlight selection in current buffer" })

-- Telescope
vim.keymap.set({ "n" }, "fs", multigrep.live_multigrep, { noremap = true, desc = "Search word in current root" })
vim.api.nvim_create_user_command("TSC", multigrep.tsc_no_emit, {})
vim.api.nvim_create_user_command("RgList", rglist.run, { nargs = "*" })

-- Webify
vim.keymap.set("n", "<leader>sw", function()
    local word = nvim.get_cursor_word()
    system.search_google(word)
end, { desc = "Search word under cursor (Google)" })

-- Function to URL encode a string
local function url_encode(str)
    if str then
        str = str:gsub("\n", " "):gsub("([^%w %-%_%.%~])", function(c)
            return string.format("%%%02X", string.byte(c))
        end)
        str = str:gsub(" ", "%%20")
    end
    return str
end

vim.keymap.set("v", "<leader>si", function()
    local lines = nvim.get_visual_selection()
    local encodedlines = url_encode(lines)
    system.search_google(encodedlines)
end, { desc = "Search selected text (Google)" })

vim.keymap.set("n", "<D-s>", ":w<CR>", { noremap = true, silent = true })
-- Map Cmd+S to save in insert mode
vim.keymap.set("i", "<D-s>", "<Esc>:w<CR>", { noremap = true, silent = true })

-- Create a custom command to reload the init.lua file
vim.cmd([[
      command! ReloadConfig lua require('user_config').reload_config()
    ]])

-- Git interaction
vim.api.nvim_create_user_command("OpenMergeRequest", ide.open_gitlab_mr, {})
vim.keymap.set("n", "<leader>gm", ide.open_gitlab_mr, { noremap = true })
vim.keymap.set("n", "<leader>gr", ide.open_git_repo, { noremap = true })
vim.keymap.set("n", "<leader>gc", ide.open_git_commit, { noremap = true })
vim.keymap.set("n", "<leader>gC", ide.open_git_commit_blame, { noremap = true })
vim.keymap.set("n", "<leader>gp", ide.open_git_pipelines, { noremap = true })
vim.keymap.set("n", "<leader>gD", "<cmd>DiffviewFileHistory %<CR>", { noremap = true })
-- All git-forge web actions (repo, commit, file, blame, pipelines, MR, etc.)
-- are now available through the combined ide module.
vim.keymap.set("n", "<leader>go", ide.open_file_in_browser, { desc = "Open current file in web browser" })
vim.keymap.set("n", "<leader>gy", ide.yank_file_url, { desc = "Yank current file web URL" })
vim.keymap.set("n", "<leader>gY", ide.yank_line_url, { desc = "Yank current file+line web URL" })
vim.keymap.set('n', '<leader>gi', fastgit.open_gitlab_pipelines, { noremap = true, silent = true })
---

--- dap keymap
local dap = require('dap')

dap.adapters.go = {
  type = "server",
  host = "127.0.0.1",
  port = "38697",
}

dap.configurations.go = {
  {
    type = "go",
    name = "Attach to headless",
    request = "attach",
    mode = "remote",
  },
}

vim.keymap.set('n', '<F5>',  dap.continue)
vim.keymap.set('n', '<F10>', dap.step_over)
vim.keymap.set('n', '<F11>', dap.step_into)
vim.keymap.set('n', '<S-F11>', dap.step_out)
vim.keymap.set('n', '<F9>',  dap.toggle_breakpoint)
vim.keymap.set('n', '<F12>', dap.terminate)

vim.keymap.set('n', '<leader>db', dap.toggle_breakpoint)
vim.keymap.set('n', '<leader>dc', function()
  dap.set_breakpoint(vim.fn.input('Breakpoint condition: '))
end)
---

vim.keymap.set("v", "<leader>s", function()
    local visual = nvim.get_visual_selection()
    system.open_url(visual)
end, { noremap = true, desc = "Open visual selection as URL/path with system handler" })

local telescope = require('telescope')
local actions = require('telescope.actions')
local action_state = require('telescope.actions.state')

-- Function to fetch TypeScript files with type issues
local function get_tsc_error_files()
    local output = vim.fn.systemlist('tsc --noEmit')
    local files = {}

    for _, line in ipairs(output) do
        local file = line:match("^(.-)%(%d+,%d+%): error")
        if file then
            files[file] = true
        end
    end

    local unique_files = {}
    for file, _ in pairs(files) do
        table.insert(unique_files, file)
    end

    return unique_files
end

-- Telescope picker to iterate over files with issues
local function tsc_files_picker()
    local files = get_tsc_error_files()

    telescope.pickers.new({}, {
        prompt_title = 'TSC Issues',
        finder = telescope.finders.new_table({ results = files }),
        sorter = telescope.config.generic_sorter({}),
        attach_mappings = function(prompt_bufnr)
            actions.select_default:replace(function()
                local selection = action_state.get_selected_entry()
                actions.close(prompt_bufnr)
                vim.cmd('split ' .. selection[1]) -- opens file in split window
            end)
            return true
        end,
    }):find()
end

-- Bind the picker to a command
vim.api.nvim_create_user_command('TSCIssues', tsc_files_picker, {})
