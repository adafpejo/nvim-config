local M = {}
M.__index = M

---@class AsyncJob
---@field id number
---@field cmd table
---@field status "running" | "done" | "failed" | "cancelled"
---@field code number?
---@field stdout string
---@field stderr string
---@field start_time number
---@field end_time number?
---@field duration number?

---@class Command
---@field id number
---@field cmd table
---@field _job AsyncJob
---@field _handle vim.SystemHandle?
---@field _disposed boolean
---@field _opts table

---Create a new command
---@param cmd table|string
---@param opts? table
---@return Command
function M.new(cmd, opts)
  opts = opts or {}
  local cmd_table = type(cmd) == "string" and vim.split(cmd, "%s+") or cmd

  local job = {
    id = 0,
    cmd = cmd_table,
    status = "running",
    stdout = "",
    stderr = "",
    start_time = vim.uv.hrtime(),
    duration = 0,
  }

  local self = setmetatable({
    id = 0,
    cmd = cmd_table,
    _job = job,
    _handle = nil,
    _disposed = false,
    _opts = opts,
  }, M)

  local handle = vim.system(cmd_table, {
    cwd = opts.cwd or vim.fn.getcwd(),
    env = opts.env,
    text = true,
    stdout = function(_, data)
      if data then
        self._job.stdout = self._job.stdout .. data
      end
      if opts.stdout then
        opts.stdout(self, data)
      end
    end,
    stderr = function(_, data)
      if data then
        self._job.stderr = self._job.stderr .. data
      end
      if opts.stderr then
        opts.stderr(self, data)
      end
    end,
  }, function(obj)
    if not self._job or self._disposed then
      return
    end

    self._job.end_time = vim.uv.hrtime()
    self._job.duration = (self._job.end_time - self._job.start_time) / 1e9
    self._job.code = obj.code
    if self._job.status ~= "cancelled" then
      self._job.status = obj.code == 0 and "done" or "failed"
    end

    vim.schedule(function()
      if self._disposed or not self._job then
        return
      end

      if opts.on_complete then
        opts.on_complete(self)
      elseif self._job.status == "done" and opts.on_success then
        opts.on_success(self)
      elseif self._job.status == "failed" and opts.on_error then
        opts.on_error(self)
      end
    end)
  end)

  self._handle = handle
  return self
end

---Wait for command to finish and return result (alias for :result)
---@param timeout_ms number? timeout in milliseconds (default: 60000)
---@return AsyncJob|nil
function M:wait(timeout_ms)
  return self:result(timeout_ms)
end

---Wait for command to finish and return result
---@param timeout_ms number? timeout in milliseconds (default: 60000)
---@return AsyncJob|nil
function M:result(timeout_ms)
  if self._disposed then
    return nil
  end
  timeout_ms = timeout_ms or 60000
  vim.wait(timeout_ms, function()
    return self._job and self._job.status ~= "running"
  end, 30)
  if not self._job or self._job.status == "running" then
    return nil
  end
  return self._job
end

---@return "running" | "done" | "failed" | "cancelled" | "disposed"
function M:status()
  if self._disposed then
    return "disposed"
  end
  return self._job and self._job.status or "disposed"
end

---@return vim.SystemHandle?
function M:handle()
  return self._disposed and nil or self._handle
end

---@return AsyncJob?
function M:job()
  return self._disposed and nil or self._job
end

function M:cancel()
  if self._disposed then
    return
  end
  if self._job and self._job.status == "running" then
    self._job.status = "cancelled"
    vim.notify("Command cancelled: " .. table.concat(self.cmd, " "), vim.log.levels.WARN)
  end
  if self._handle then
    pcall(function() self._handle:kill(9) end)
  end
end

function M:dispose()
  if self._disposed then return end
  self._disposed = true

  if self._handle then
    pcall(function() self._handle:kill(9) end)
    self._handle = nil
  end

  self._job = nil
end

return M
