--- @param input string
--- @return string
local function strip_code(input)
  -- Check for triple backticks
  if input:sub(1, 3) == "```" and input:sub(-3) == "```" then
    return input:sub(4, -4)
  -- Check for single backticks
  elseif input:sub(1, 1) == "`" and input:sub(-1) == "`" then
    return input:sub(2, -2)
  else
    return input
  end
end

return strip_code
