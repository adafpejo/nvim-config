local M = {}

---@type table<number, Command>
M._commands = {}
local next_id = 1

---Register a command for tracking
---@param cmd Command
local function register(cmd)
  cmd.id = next_id
  next_id = next_id + 1
  M._commands[cmd.id] = cmd
  return cmd.id
end

---Create and track a new command
---@param cmd table|string
---@param opts? table
---@return Command
function M.new(cmd, opts)
  local command = require("bsi.cmd").new(cmd, opts)
  register(command)
  return command
end

---Get a tracked command by id
---@param id number
---@return Command?
function M.get(id)
  return M._commands[id]
end

---List all tracked commands
---@return table<number, Command>
function M.list()
  return M._commands
end

---Get all commands filtered by status
---@param status string
---@return table<number, Command>
function M.by_status(status)
  local result = {}
  for id, cmd in pairs(M._commands) do
    if cmd:status() == status then
      result[id] = cmd
    end
  end
  return result
end

---Remove a command from tracking
---@param id number
function M.remove(id)
  M._commands[id] = nil
end

---Dispose and remove a command
---@param id number
function M.dispose(id)
  local cmd = M._commands[id]
  if cmd then
    cmd:dispose()
    M._commands[id] = nil
  end
end

---Cleanup all finished commands
function M.cleanup()
  for id, cmd in pairs(M._commands) do
    if cmd:status() ~= "running" then
      M._commands[id] = nil
    end
  end
end

---Cleanup finished commands older than max_age_ms
---@param max_age_ms number
function M.cleanup_old(max_age_ms)
  max_age_ms = max_age_ms or 30000
  local now = vim.uv.now()
  for id, cmd in pairs(M._commands) do
    local job = cmd:job()
    if job.start_time and (now - job.start_time > max_age_ms) and cmd:status() ~= "running" then
      M._commands[id] = nil
    end
  end
end

return M
