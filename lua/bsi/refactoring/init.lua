local actions = require('telescope.actions')
local pickers = require('telescope.pickers')
local finders = require('telescope.finders')
local conf = require('telescope.config').values
local state = require('telescope.actions.state')

local command_aliases = {
    ["useLingui"] = "UseLingui",
    ["ConvertGettextToI18nT"] = "ConvertGettextToI18nT",
    ["ConvertGettextToT"] = "ConvertGettextToT",
    ["ConvertPgettextToT"] = "ConvertPgettextToT",
    ["ConvertArrayToMultiline"] = "ConvertArrayToMultiline",
}

local M = {}

-- Function to convert the alias map into a list for display in Telescope
local function get_commands_for_display()
    local display_commands = {}
    for alias, command in pairs(command_aliases) do
        table.insert(display_commands, alias)
    end
    return display_commands
end

function create_command_picker()
    pickers.new({}, {
        prompt_title = "Select Command",
        finder = finders.new_table({
            results = get_commands_for_display(),
            entry_maker = function(entry)
                -- Here, 'entry' is the alias. We return an object with the alias for display and the command for execution.
                return {
                    value = entry,
                    display = entry
                }
            end
        }),
        sorter = conf.generic_sorter({}),
        attach_mappings = function(prompt_bufnr, map)
            actions.select_default:replace(function()
                actions.close(prompt_bufnr)
                local selection = state.get_selected_entry()
                if selection then
                    -- Use the alias to find the actual command in the `command_aliases` table
                    local command = command_aliases[selection.value]
                    if command then
                        vim.api.nvim_command(command)
                    else
                        print("Command not found for alias: " .. selection.value)
                    end
                end
            end)
            return true
        end,
    }):find()
end

vim.api.nvim_set_keymap('n', '<leader>r', '<cmd>lua create_command_picker()<CR>', { noremap = true })

local function convert_gettext_to_i18n()
    local bufnr = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    for i, line in ipairs(lines) do
        -- Use Lua's string.gsub for the substitution
        lines[i] = line:gsub("gettext%('([^']+)'%)", "i18n._('%1')")
    end

    -- Replace the buffer content with the modified lines
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
end

vim.api.nvim_create_user_command("ConvertGettextToI18nT", convert_gettext_to_i18n, {})

local function convert_gettext_to_t()
    local bufnr = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    for i, line in ipairs(lines) do
        -- Use Lua's string.gsub for the substitution
        lines[i] = line:gsub("gettext%('([^']+)'%)", "t`%1`")
    end

    -- Replace the buffer content with the modified lines
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
end

vim.api.nvim_create_user_command("ConvertGettextToT", convert_gettext_to_t, {})

local function replace_npgettext()
    local bufnr = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    for i, line in ipairs(lines) do
        -- Pattern to match any npgettext function with any string values
        local pattern = "npgettext%(%s*%(%n%s*%'([^']+)%'%s*,%s*%(%n%s*%'(.+)%'%s*,%s*%(%n%s*%'(.+)%'%s*,%s*%(%n%s*%{ count }%s*%(%n%s*%) as string"

        -- Replacement string using captured groups from the pattern
        local replacement = [[plural(count, {
// context: '%1',
    one: '%2',
    other: '%3'
})]]

        -- Perform the substitution
        lines[i] = line:gsub(pattern, replacement)
    end

    -- Write back the modified lines to the buffer
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
end

-- Create a user command to trigger the function
vim.api.nvim_create_user_command("ReplaceNpgettext", replace_npgettext, {})

local function convert_pgettext_to_t()
    local bufnr = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    for i, line in ipairs(lines) do
        -- Use Lua's string.gsub for the substitution
        lines[i] = line:gsub("pgettext%('([^']+)',%s*'([^']+)'%)", "t({ context: '%1', message: '%2' })")
    end

    -- Replace the buffer content with the modified lines
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
end

vim.api.nvim_create_user_command("ConvertPgettextToT", convert_pgettext_to_t, {})

vim.api.nvim_create_user_command("ConvertGettext", function()
    convert_pgettext_to_t()
    convert_gettext_to_t()
end, {})

local function convert_array_to_multiline(line)
    -- Capture the opening and closing brackets, and handle the array content
    local opening_bracket, content, closing_bracket = line:match("^(%[)(.*)(%])$")

    if not opening_bracket then
        return line -- Return original if not an array
    end

    -- Split the content by commas, but preserve spaces around items
    local items = {}
    for item in content:gmatch("([^,]+),?%s*") do
        table.insert(items, item:match("^%s*(.-)%s*$")) -- Trim leading/trailing spaces
    end

    -- Convert each item to a new line
    local multiline_content = table.concat(items, ",\n    ")

    -- Format the result, adding newlines before and after the array content
    return string.format("%s\n    %s\n%s", opening_bracket, multiline_content, closing_bracket)
end

-- Create a user command to handle this refactoring
vim.api.nvim_create_user_command("ConvertArrayToMultiline", function()
    local bufnr = vim.api.nvim_get_current_buf()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local line_num = cursor[1] - 1 -- Zero-based index

    -- Get the line where the cursor is
    local lines = vim.api.nvim_buf_get_lines(bufnr, line_num, line_num + 1, false)
    if #lines == 0 then
        return
    end -- Check if there's a line at the cursor position

    -- Convert the line
    local new_line = convert_array_to_multiline(lines[1])

    -- Replace the line with the new formatted content
    vim.api.nvim_buf_set_lines(bufnr, line_num, line_num + 1, false, { new_line })

    -- Adjust cursor position to the end of the new line
    local new_cursor_pos = { line_num + 1, #new_line }
    vim.api.nvim_win_set_cursor(0, new_cursor_pos)
end, {})

local function refactor_function_component()
    -- Save the current position
    local saved_pos = vim.api.nvim_win_get_cursor(0)

    -- Define the patterns to match
    local old_pattern = [[const %w+: FC<%w> = () => (%b())]]
    local new_pattern = [[const %1 = () => {\n    return %2;\n}]]

    -- Perform the substitution on the entire buffer
    vim.api.nvim_command("%s/" .. old_pattern .. "/" .. new_pattern .. "/g")

    -- Restore the cursor position
    vim.api.nvim_win_set_cursor(0, saved_pos)
end

-- Usage in Neovim
vim.api.nvim_create_user_command("RefactorComponent", refactor_function_component, {})

local function insert_snippet_after_cursor()
    local bufnr = vim.api.nvim_get_current_buf()
    local line, col = unpack(vim.api.nvim_win_get_cursor(0))
    local snippet = "const { t } = useLingui();"

    -- Get the current line
    local current_line = vim.api.nvim_buf_get_lines(bufnr, line - 1, line, false)[1]

    -- Determine the indentation of the current line
    local indent = current_line:match("^%s*") or ""

    -- Split the current line at the cursor position
    local before_cursor = current_line:sub(1, col)
    local after_cursor = current_line:sub(col + 1)

    -- Construct new lines, applying the indentation to the snippet
    local new_lines = {
        before_cursor .. after_cursor,
        indent .. snippet,
    }

    -- Insert the new lines
    vim.api.nvim_buf_set_lines(bufnr, line - 1, line, false, new_lines)

    -- Move the cursor to the new line (below the inserted snippet)
    vim.api.nvim_win_set_cursor(0, { line + 1, #indent })
end

vim.api.nvim_create_user_command("UseLingui", insert_snippet_after_cursor, {})

-- 1. Copy this function into a Lua file (e.g., your init.lua or lua/format_markdown.lua).
-- 2. Use visually select lines in Normal mode, then run :lua format_markdown_150().

function M.format_markdown_150()
  -- Get start and end of visual selection
  local start_line = vim.fn.line("'<")
  local end_line   = vim.fn.line("'>")

  -- If the user selected upwards (end < start), swap them
  if start_line > end_line then
    local tmp = start_line
    start_line = end_line
    end_line = tmp
  end

  -- Read in the lines from the buffer
  local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)

  -- Join all text into a single string, separated by spaces
  local text = table.concat(lines, " ")

  -- Wrap words manually at 150 characters
  local wrapped_lines = {}
  local current_line  = ""

  for word in text:gmatch("%S+") do
    -- If adding this word to current_line stays <= 150 chars, do it
    if #current_line + #word + 1 <= 150 then
      if current_line == "" then
        current_line = word
      else
        current_line = current_line .. " " .. word
      end
    else
      -- Otherwise, push the current_line to wrapped_lines and start a new line
      table.insert(wrapped_lines, current_line)
      current_line = word
    end
  end

  -- Add the last line if there's anything in it
  if current_line ~= "" then
    table.insert(wrapped_lines, current_line)
  end

  -- Finally, replace the selected lines in the buffer with the new wrapped lines
  vim.api.nvim_buf_set_lines(0, start_line - 1, end_line, false, wrapped_lines)
end

return M
