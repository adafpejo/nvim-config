--- @param input string
--- @return string
-- local function strip_code(input)
--   -- Check for triple backticks
--   if input:sub(1, 3) == "```" and input:sub(-3) == "```" then
--     return input:sub(4, -4)
--   -- Check for single backticks
--   elseif input:sub(1, 1) == "`" and input:sub(-1) == "`" then
--     return input:sub(2, -2)
--   else
--     return input
--   end
-- end

local multiline_code_pattern = "^```(.*)```$";
local multiline_line_pattern = "^```(.*)```$";
local one_line_pattern = "(`{1,3}).*(`{1,3})";

function strip_code(str)
    -- Check for triple backticks with optional language specifier
    local lang, code = string.match(str, "^%s*`{1,3}%s*(.-)%s*`{1,3}%s*$")
    if code then
        return code
    end
    -- Check for single backticks
    if str:match("^`.*`$") then
        return str:sub(2, -2)
    end
    -- Return the string as is if no patterns match
    return str
end

-- --- @param input string
-- --- @return string
-- local function strip_code(input)
--     local code = string.match(input, one_line_pattern)
--     if code then
--         return code
--     end

--     return input
--     -- local multiline_code = string.match(input, multiline_code_pattern);
--     -- if multiline_code then
--     --     return multiline_code
--     -- end

--     -- local one_line = string.match(input, multiline_line_pattern);
--     -- if one_line then
--     --     return one_line
--     -- end

--     -- local code = string.match(input, one_line_pattern);
--     -- if code then
--     --     return code
--     -- end

--     -- return input
-- end

return strip_code
