local M = {}

--- Escapes single and double quotes in a string by prepending a backslash.
--- @param str string: The input string to escape.
--- @return string, number: The string with quotes escaped.
function M.escape_quotes(str)
    return str:gsub("'", "\'"):gsub('"', '\"')
end

function M.has_value(table, val)
    for _, value in ipairs(table) do
        if value == val then
            return true
        end
    end
    return false
end

--- @param t table
--- @return table
function M.table_keys(t)
    local result_table = {}
    for i, k in ipairs(t) do
        result_table[i] = k
    end
    return result_table
end

--- @param t table
--- @return table
function M.table_values(t)
    local result_table = {}
    for i, k in ipairs(t) do
        result_table[i] = t[k]
    end
    return result_table
end

function M.url_encode(str)
  if str then
    str = str:gsub("([^%w%-_.~])", function(c)
      return string.format("%%%02X", string.byte(c))
    end)
  end
  return str
end

return M
