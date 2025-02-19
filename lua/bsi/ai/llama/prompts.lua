local M = {}

M.prompt_tbl = {
    ["comment"] = "Write comment for provided function, describe parameters and return values. Write comment only as response",
    ["english"] = "Rewrite the following text in better English.\nReturn only rewrited text as response.\n\n",
    ["coder"] = "Omit all phrases and response only code"
}

function M.coder_prompt(prompt, context)
    return string.format("%s %s\n\nCode: \n```%s\n```\n", prompt, M.prompt_tbl["coder"], context)
end

function M.english_prompt(text)
    return string.format("%s\n---\n%s\n", M.prompt_tbl["english"], text)
end

function M.comment_propmpt(text)
    return string.format("%s\n---\n\n```%s\n```\n", M.prompt_tbl["comment"], text)
end

M.prompt_map = {
    ["comment"] = M.comment_propmpt,
    ["english"] = M.english_prompt,
    ["coder"] = M.coder_prompt,
}

return M
