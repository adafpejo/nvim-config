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

    req.http_post("localhost", 11434, "/api/generate", payload, function(error, data)
        local response = get_llama_res(data)
        logger:debug("LLM response: " .. response)
        async.co.resume(co, response)
    end)

    return async.co.yield()
end

function M.generate_llama(prompt, options)
    return M.generate('llama3.1', prompt, options)
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
