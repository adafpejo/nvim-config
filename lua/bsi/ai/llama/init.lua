local async         = require('bsi.utils.async')
local req           = require('bsi.utils.req')
local strip_code    = require('bsi.ai.llama.strip_code')
local prompts       = require('bsi.ai.llama.prompts')
local logger        = require('bsi.logger')

local M             = {}

local default_url   = "http://localhost:11434/api/generate"
local default_model = "llama3.1"

local function get_llama_res(data)
    return data.response
end

-- Function to filter out <think> blocks from an LLM response string.
-- This removes any content enclosed in <think> and </think> tags,
-- including the tags themselves.
local function filter_think_tags(response)
    -- Use gsub with a pattern to match <think>.*?</think>
    -- The ? makes it non-greedy to handle multiple tags.
    local filtered = response:gsub("<think>.-</think>", "")
    -- Trim any leading/trailing whitespace after removal
    filtered = filtered:match("^%s*(.-)%s*$")
    return filtered
end

-- Function to extract and concatenate code from multiple Markdown code blocks
-- in a given text string. Each block's content (excluding the ``` delimiters
-- and language specifier) is extracted and joined with newlines.
-- Assumes no nested triple backticks.
local function extractAndConcatCode(text)
    local concatenated = {}
    local startPos = 1

    while true do
        -- Find the start of a code block
        local blockStart, blockEnd = text:find("```", startPos)
        if not blockStart then break end

        -- Find the end of the opening ```
        local contentStart = blockEnd + 1

        -- Skip the language specifier line if present
        local langEnd = text:find("\n", contentStart)
        if langEnd then
            contentStart = langEnd + 1
        end

        -- Find the closing ```
        local closeStart, closeEnd = text:find("```", contentStart)
        if not closeStart then break end

        -- Extract the code content (trim trailing newline if present)
        local code = text:sub(contentStart, closeStart - 1)
        code = code:match("(.-)\n?$") or code

        table.insert(concatenated, code)

        -- Move to after this block
        startPos = closeEnd + 1
    end

    -- Concatenate all extracted codes with newlines
    return table.concat(concatenated, "\n")
end

--- Sends a request to the Llama API to rewrite the given prompt in English.
--- @param model string default llama3.1
--- @param prompt string containing your text prompt.
--- @return string
function M.generate(model, prompt, options)
    local co = async.co.running()
    async.assert_co(co, 'coder');

    local payload = {
        model = model or default_model,
        prompt = prompt,
        stream = false,
        options = options
    }

    req.http_post("127.0.0.1", 11434, "/api/generate", payload, function(error, data)
        if error then
            vim.notify(error, vim.log.levels.ERROR)
        end

        local response = filter_think_tags(get_llama_res(data))
        logger:debug("LLM response: " .. response)
        async.co.resume(co, response)
    end)

    return async.co.yield()
end

function M.generate_llama(prompt, options)
    return M.generate('qwen3', prompt, options)
    -- return M.generate('llama3.1', prompt, options)
end

function M.coder(text, visual)
    local prompt = prompts.coder_prompt(text, visual)
    local options = {
        temperature = 0,
        top_p = 0.9,
    }

    return M.generate(default_model, prompt, options)
end

function M.comment(text)
    local prompt = prompts.comment_propmpt(text)
    local options = {
        temperature = 0.7,
        top_p = 0.7,
    }

    return M.generate(default_model, prompt, options)
end

function M.rewrite_text(text)
    local prompt = prompts.english_prompt(text)
    local options = {
        temperature = 0.7,
        top_p = 0.8,
    }

    return M.generate(default_model, prompt, options)
end

return M
