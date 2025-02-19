local logger = require('bsi.logger')
local http = require('http')

local M = {}

--- Extracts the HTTP response body from a raw HTTP message.
--- @param buf string: The full HTTP response (headers and body).
--- @return string|nil: The extracted body, or nil if no body is found.
local function decode_http(buf)
    -- Split the raw response into lines.
    local lines = vim.split(buf, "\r\n")
    local header_end_line = nil
    local content_length = nil
    local header_prefix = "content-length:"

    -- Iterate over lines to locate headers and the blank line separator.
    for i, line in ipairs(lines) do
        if line == "" then
            header_end_line = i
            break
        end

        -- Look for the Content-Length header.
        local lower_line = line:lower()
        if lower_line:sub(1, #header_prefix) == header_prefix then
            local len_str = vim.trim(lower_line:sub(#header_prefix + 1))
            content_length = tonumber(len_str)
            if not content_length then
                error("failed to parse content-length header: " .. len_str)
            end
        end
    end

    -- If no header/body separator was found, return nil.
    if not header_end_line then
        return nil
    end

    -- Concatenate the lines after the header separator to form the body.
    local body_lines = vim.list_slice(lines, header_end_line + 1)
    local body = table.concat(body_lines, "\n")

    -- If a Content-Length header was provided, slice the body accordingly.
    if content_length then
        body = body:sub(1, content_length)
    end

    return body
end

-- function M.http_post(host, port, path, json, callback)
--     http.post(host, path, port, json, true, function(err, response)
--       if err then
--         print("Error:", err)
--         return
--       end
--       print(vim.inspect(response))
--       callback(response.body)
--     end)
-- end

--- Perform an HTTP POST request.
--- @param host string       e.g. "example.com"
--- @param port number       e.g. 80
--- @param path string       e.g. "/api/endpoint"
--- @param json table
--- @param callback function (err, response) - called when done
function M.http_post(host, port, path, json, callback)
    local uv = vim.loop
    local client = uv.new_tcp()

    local function read_message()
        client:read_start(function(err, data)
            if err then
                -- TODO: logging
                return
            end
            logger:debug(vim.inspect("" .. data))
            local msg = decode_http("" .. data)
            logger:debug(vim.inspect(msg))
            local ok, d = pcall(vim.json.decode, msg)
            if not ok then
                error("decode failed: " .. vim.inspect(data))
            end

            vim.schedule_wrap(callback)(d)
            client:close()
        end)
    end

    local function send_message()
        local data = vim.json.encode(json)
        local request = string.format(
            "POST %s HTTP/1.1\r\n" ..
            "Host: %s\r\n" ..
            "Content-Type: application/json\r\n" ..
            "Content-Length: %d\r\n" ..
            "Connection: close\r\n" ..
            "\r\n" .. -- data break
            "%s",
            path, host, #data, data
        )
        client:write(request)
    end

    -- Connect to the resolved address and port
    client:connect(host, port, function(e)
        if not e then
            read_message()
            vim.schedule(send_message)
        else
            -- TODO: make better
            error("could not connect")
        end
    end)
end

return M
