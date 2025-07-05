local dx          = require("bsi.dx")
local refactoring = require("bsi.refactoring")
local nvim        = require("bsi.utils.nvim")
local ai          = require("bsi.ai")
local nt_api      = require("nvim-tree.api")
local webify      = require("bsi.webify")
local ide         = require("bsi.utils.ide")
local fastgit     = require("bsi.fastgit")

local view        = require('nvim-tree.view') -- for focus_node()

-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- vim.keymap.set("n", "<C-/>", "<cmd>ToggleTermToggleAll<CR>")

-- Diagnostic list
vim.keymap.set('n', '<leader>e', vim.diagnostic.setqflist)

-- exit insert mode with jk
vim.keymap.set("i", "jk", "<ESC>", { noremap = true, silent = true, desc = "<ESC>" })

-- prevent save selected word
vim.keymap.set('v', 'p', '"_dP', {
    desc = 'Paste copied text without copying selected',
    noremap = true,
})

-- vim.keymap.set("n", "<leader>ee", function()
--     nt_api.tree.toggle({ find_file = true })
-- end, { desc = "NvimTreeToggle" })
--


local function find_file(dir)
    -- 1. pick navigation function (or error early)
    local navigate
    if dir == 'down' then
        navigate = nvim.move_cursor_down
    else
        navigate = nvim.move_cursor_up
    end

    navigate()

    -- 2. get the node under cursor
    local node = nt_api.tree.get_node_under_cursor()
    if not node then
        print("NvimTree: Could not find a node under the cursor.")
        return
    end

    -- 3. if it's a closed directory, descend to first/last child
    if node.type == "directory" and not node.open then
        local current = (dir == "up") and node.parent or node

        -- descend while we're on a directory
        while current and current.type == "directory" do
            local children = current.nodes
            if not children or #children == 0 then
                break
            end
            -- pick first child when going down, last child when going up
            current = children[(dir == "up") and #children or 1]
        end

        if current then
            nt_api.node.open.edit(current)
        end

        -- 4. if it's a file, just open it
    elseif node.type == "file" then
        nt_api.node.open.edit()
    end
end

-- files navigation
vim.keymap.set({ "n" }, "<C-j>", function()
    local visible = nt_api.tree.is_visible()
    nt_api.tree.open()
    find_file('down')
    if not visible then
        nt_api.tree.close()
    end
end, { noremap = true, desc = "Open next file" })
vim.keymap.set({ "n" }, "<C-k>", function()
    local visible = nt_api.tree.is_visible()
    nt_api.tree.open()
    find_file('up')
    if not visible then
        nt_api.tree.close()
    end
end, { noremap = true, desc = "Open prev file" })

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
    ai.ask()
end, { noremap = true, desc = ":Lazy" })
vim.keymap.set("v", "<leader>la", function()
    ai.ask_v()
end, { noremap = true, desc = ":Lazy" })

-- Lazygit
vim.keymap.set("n", "<leader>gg", "<cmd>LazyGit<cr>", { noremap = true, desc = "Open lazygit" })

-- Gen.nvim
vim.keymap.set({ "n", "v" }, "<leader>]", ":Gen<CR>")

-- bsi motions
vim.keymap.set({ "n" }, "<leader>h", dx.highlight_cursor_word, { noremap = true, desc = "Search word in current buffer" })
vim.keymap.set({ "v" }, "<leader>h", dx.highlight_visual, { noremap = true, desc = "Search word in current buffer" })

-- Webify

vim.keymap.set("n", "<leader>sw", function()
    local word = nvim.get_cursor_word()
    dx.search_google(word)
end, { desc = "Search word under cur" })

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
    dx.search_google(encodedlines)
end, { desc = "Search selected block" })

vim.keymap.set("n", "<D-s>", ":w<CR>", { noremap = true, silent = true })
-- Map Cmd+S to save in insert mode
vim.keymap.set("i", "<D-s>", "<Esc>:w<CR>", { noremap = true, silent = true })

-- Create a custom command to reload the init.lua file
vim.cmd([[
      command! ReloadConfig lua require('user_config').reload_config()
    ]])


-- Map command to function in Neovim
vim.api.nvim_create_user_command("OpenMergeRequest", ide.open_gitlab_mr, {})
vim.keymap.set("n", "<leader>gm", ide.open_gitlab_mr, { noremap = true })
vim.keymap.set("n", "<leader>gr", ide.open_git_repo, { noremap = true })
vim.keymap.set("n", "<leader>gc", ide.open_git_commit, { noremap = true })
vim.keymap.set("n", "<leader>gC", ide.open_git_commit_line, { noremap = true })
vim.keymap.set("n", "<leader>gp", ide.open_git_pipelines, { noremap = true })
vim.keymap.set("n", "<leader>gd", "<cmd>DiffviewFileHistory %<CR>", { noremap = true })
vim.keymap.set("n", "<leader>go", function()
    webify.open_file_in_browser()
end, { desc = "Open in web browser" })
vim.keymap.set("n", "<leader>gO", function()
    webify.open_line_in_browser()
end, { desc = "Open in web browser, including current line" })

vim.keymap.set('n', '<leader>gi', fastgit.open_gitlab_pipelines, { noremap = true, silent = true })

vim.keymap.set("v", "<leader>s", function()
    local visual = nvim.get_visual_selection()
    dx.open_url(visual)
end, { noremap = true })


-- Map Cmd+R to the ReloadConfig command
-- vim.api.nvim_set_keymap('n', '<D-r>', ':ReloadConfig<CR>', { noremap = true })

-- Unmap mappings used by tmux plugin
-- TODO(vintharas): There's likely a better way to do this.
-- vim.keymap.del("n", "<C-h>")
-- vim.keymap.del("n", "<C-j>")
-- vim.keymap.del("n", "<C-k>")
-- vim.keymap.del("n", "<C-l>")
-- vim.keymap.set("n", "<C-h>", "<cmd>TmuxNavigateLeft<cr>")
-- vim.keymap.set("n", "<C-j>", "<cmd>TmuxNavigateDown<cr>")
-- vim.keymap.set("n", "<C-k>", "<cmd>TmuxNavigateUp<cr>")
-- vim.keymap.set("n", "<C-l>", "<cmd>TmuxNavigateRight<cr>")
--
--

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
