local nvim    = require("bsi.utils.nvim")
local async   = require("bsi.utils.async")
local ide     = require("bsi.utils.ide")
local llama   = require('bsi.ai.llama')
local utils   = require('bsi.utils')
local logger  = require('bsi.logger')
local prompts = require('bsi.ai.llama.prompts')

local Menu    = require("nui.menu")
local event   = require("nui.utils.autocmd").event

local M       = {}

function M.cmd_gsub(str)
    return str:gsub("'", "\\'"):gsub('"', '\\"')
end

--- @param prompt string
--- @param context string
--- @return string
local function buildPopupInfo(prompt, context)
    return "Prompt:\n" .. prompt .. "\n\nContext: \n" .. context
end

function M.ask_llm(instruction)
    nvim.assert_empty_string(instruction, "empty instruction")

    local llm_result = llama.generate_llama(instruction)
    vim.notify_popup(llm_result)
    nvim.assert_empty_string(llm_result, "empty llm_result")

    nvim.save_to_clipboard(llm_result)
    vim.notify_popup("done! past clipboard")
end

function M.ask_english()
    local status, result = async.run(function()
        local visual_selection = nvim.get_visual_selection()
        nvim.assert_empty_string(visual_selection, "empty visual selection")

        local english_prompt = prompts.english_prompt(visual_selection)
        vim.notify_popup(english_prompt, "info", {
            timeout = 100
        })

        M.ask_llm(english_prompt)
    end)
    if not status then
        vim.notify("corutine error: " .. result)
    end
end

function M.ask_coder()
    local status, result = async.run(function()
        local visual_selection = nvim.get_visual_selection()
        local instruction = ide.open_inline_input()

        local coder_prompt = prompts.coder_prompt(instruction, visual_selection)
        vim.notify_popup(coder_prompt, "info", {
            timeout = 100
        })

        M.ask_llm(coder_prompt)
    end)
    if not status then
        vim.notify("corutine error: " .. result)
    end
end

function M.ask_v()
    local status, result = async.run(function()
        local visual_selection = nvim.get_visual_selection()
        local instruction = ide.open_inline_input()

        local coder_prompt = string.format(
            instruction .. "\n" ..
            "---\n" ..
            visual_selection .. "\n"
        )

        vim.notify_popup(coder_prompt, "info", {
            timeout = 100
        })

        M.ask_llm(coder_prompt)
    end)
    if not status then
        vim.notify("corutine error: " .. result)
    end
end

function M.ask()
    local status, result = async.run(function()
        local instruction = ide.open_inline_input()

        vim.notify_popup(string.format("Prompt:\n%s", instruction), "info", {
            timeout = 100
        })

        M.ask_llm(instruction)
    end)
    if not status then
        vim.notify("corutine error: " .. result)
    end
end

local function list_options_picker(visual_selection)
        ai_menu = Menu({
            relative = "cursor",
            position = {
                row = 1,
                col = 0,
            },
            border = {
                style = "rounded",
                text = {
                    top = "[Choose Item]",
                    top_align = "center",
                },
            },
            win_options = {
                winhighlight = "Normal:Normal",
            }
        }, {
            lines = {
                Menu.item("comment"),
                Menu.item("english"),
                Menu.item("coder"),
            },
            max_width = 20,
            keymap = {
                focus_next = { "j", "<Down>", "<Tab>" },
                focus_prev = { "k", "<Up>", "<S-Tab>" },
                close = { "<Esc>", "<C-c>" },
                submit = { "<CR>", "<Space>" },
            },
            on_close = function()
                print("CLOSED")
            end,
            on_submit = function(item)
                local prompt = prompts.prompt_tbl[item.text]

                local status, result = async.run(function()
                    nvim.assert_empty_string(visual_selection, "empty visual selection")
                    vim.notify_popup(buildPopupInfo(prompt, visual_selection), "info", {
                        timeout = 100
                    })

                    M.ask_llm(prompts.prompt_map[item.text](visual_selection))
                end)
                if not status then
                    vim.notify("corutine error: " .. result)
                end
            end,
        })

    ai_menu:on(event.BufLeave, function()
        ai_menu:unmount()
    end)

    ai_menu:mount()
end

vim.keymap.set({ "v" }, "<leader>l", function()
    local visual_selection = nvim.get_visual_selection()
    list_options_picker(visual_selection)
end, { remap = false })

return M
