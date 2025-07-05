local logger = require('bsi.logger')

local M = {}

-- Function to break a flat table into a 2D table of pairs
local function break_table_to_2d(inputTable)
    local result = {}
    local pair = {}
    local pairIndex = 1

    for i, value in ipairs(inputTable) do
        pair[pairIndex] = value
        pairIndex = pairIndex + 1

        if pairIndex > 2 then
            table.insert(result, pair)
            pair = {}
            pairIndex = 1
        end
    end

    if pairIndex > 1 then
        table.insert(result, pair)
    end

    return result
end

local function read_chunked_response(headers, response_body)
    local fullBody = ""

    local chunks = break_table_to_2d(vim.split(response_body, "\r\n"))

    for _, subTable in ipairs(chunks) do
        local chunkSize = tonumber(subTable[1], 16)
        local chunkData = subTable[2]

        if chunkSize == 0 then
            break -- Zero-length chunk indicates end of body
        end

        fullBody = fullBody .. chunkData
    end

    -- Step 8: Return the full reassembled body
    return fullBody
end

local function read_single_response(headers, response_body)
    local body = ""
    local content_length = headers["content-length"]
    content_length = tonumber(content_length)
    if content_length then
        body = response_body:sub(1, content_length)
    elseif logger then
        -- Log warning instead of error; proceed with full bo
        logger:warn("Invalid Content-Length: " .. headers["content-length"])
    end

    return body
end

--- Extracts the HTTP response body and metadata from a raw HTTP message.
--- @param buf string: The full HTTP response (headers and body).
--- @return string|nil: The extracted body, or nil if parsing fails.
--- @return string|nil: Error message if parsing fails, nil otherwise.
--- @return number|nil: HTTP status code, or nil if invalid.
local function decode_http(buf)
    -- Find the end of headers
    local header_end = buf:find("\r\n\r\n")
    if not header_end then
        return nil, "No header-body separator found"
    end

    local headers_str = buf:sub(1, header_end - 1)
    local body = buf:sub(header_end + 4)

    -- Split headers and extract status line
    local lines = vim.split(headers_str, "\r\n")
    if #lines == 0 then
        return nil, "No headers found"
    end

    local status_line = lines[1]
    local status_code = tonumber(status_line:match("HTTP/%d%.%d (%d+)"))
    if not status_code then
        return nil, "Invalid status line: " .. status_line
    end

    -- Parse headers into a table
    local headers = {}
    for i = 2, #lines do
        local line = lines[i]
        local key, value = line:match("^([^:]+):%s*(.*)$")
        if key and value then
            headers[key:lower()] = value
        end
    end

    local chunked = headers['transfer-encoding'] == 'chunked'
    if chunked then
        logger:debug("read_chunked_response...")
        body = read_chunked_response(headers, body)
    else
        logger:debug("read_single_response...")
        body = read_single_response(headers, body)
    end

    return body, nil, status_code
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

--- Performs an HTTP POST request using vim.loop.
--- @param host string: e.g., "example.com"
--- @param port number: e.g., 80
--- @param path string: e.g., "/api/endpoint"
--- @param json table: Data to send as JSON.
--- @param callback function: Called with (err, response) when done.
function M.http_post(host, port, path, json, callback)
    local uv = vim.loop
    local client = uv.new_tcp()
    local buffer = "" -- Accumulate response data

    -- Validate inputs
    if type(json) ~= "table" then
        callback("json parameter must be a table", nil)
        return
    end
    if not path:match("^/") then
        path = "/" .. path -- Ensure path starts with a slash
    end

    local function read_message()
        client:read_start(function(err, data)
            if err then
                callback("Read error: " .. err, nil)
                client:close()
                return
            end
            if data then
                buffer = buffer .. data
            else
                logger:debug(buffer)
                -- Connection closed; process the full response
                local body, decode_err, status_code = decode_http(buffer)
                logger:debug("Body: \n" .. body)
                if decode_err then
                    callback(decode_err, nil)
                elseif status_code ~= 200 then
                    callback("HTTP error: Status " .. status_code, nil)
                else
                    local ok, decoded = pcall(vim.json.decode, body)
                    if ok then
                        callback(nil, decoded)
                    else
                        callback("JSON decode error: " .. decoded, nil)
                    end
                end
                client:close()
            end
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
            "\r\n" ..
            "%s",
            path, host, #data, data
        )
        logger:debug(request)
        client:write(request, function(err)
            if err then
                callback("Write error: " .. err, nil)
                client:close()
            end
        end)
    end

    client:connect(host, port, function(err)
        if err then
            callback("Connection error: " .. err, nil)
            client:close()
        else
            read_message()
            send_message()
        end
    end)
end

return M
