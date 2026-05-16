# bsi/cmd

A robust asynchronous command execution wrapper for Neovim using `vim.system()`.

Provides a clean OOP interface for running shell commands with callbacks, waiting, cancellation, and resource management.

## Installation / Setup

The module is part of the `bsi` library:

```lua
local Cmd = require("bsi.cmd")
local CmdManager = require("bsi.cmd.manager")
```

## Basic Usage

### Create and run a command

```lua
-- Using table (recommended)
local cmd = Cmd.new({ "echo", "Hello World" })

-- Using string
local cmd = Cmd.new("ls -la")
```

### Wait for completion (synchronous style)

```lua
local job = cmd:wait()           -- or cmd:result()
if job then
  print("Status:", job.status)
  print("Output:", job.stdout)
  print("Exit code:", job.code)
  print("Duration:", job.duration, "seconds")
end
```

### Check status

```lua
print(cmd:status())  -- "running", "done", "failed", "cancelled", or "disposed"
```

### Using with manager (recommended for long-running or many commands)

```lua
local Manager = require("bsi.cmd.manager")

local cmd = Manager.new({ "sleep", "2" })
print("Command ID:", cmd.id)

-- Later
local tracked = Manager.get(cmd.id)
Manager.cleanup()           -- remove finished commands
Manager.cleanup_old(30000)  -- remove commands older than 30s
```

## Callbacks

```lua
Cmd.new({ "git", "status" }, {
  on_complete = function(cmd)
    print("Command finished with status:", cmd:status())
    local job = cmd:job()
    if job.stdout then
      print("Output:", job.stdout)
    end
  end,

  on_success = function(cmd)
    print("Success! Output:", cmd:job().stdout)
  end,

  on_error = function(cmd)
    print("Failed with code:", cmd:job().code)
    print("Error:", cmd:job().stderr)
  end,

  stdout = function(cmd, data)
    vim.notify("STDOUT: " .. (data or ""))
  end,
})
```

## API

### Command methods

| Method | Description |
|--------|-------------|
| `cmd:result(timeout_ms)` | Waits and returns `AsyncJob` or `nil` on timeout |
| `cmd:wait(timeout_ms)` | Alias for `:result()` |
| `cmd:status()` | Returns current status |
| `cmd:job()` | Returns the job data table |
| `cmd:handle()` | Returns raw `vim.SystemHandle` |
| `cmd:cancel()` | Marks as cancelled and kills process |
| `cmd:dispose()` | Cleans up resources (call when done) |

### Manager methods

| Method | Description |
|--------|-------------|
| `Manager.new(...)` | Creates + tracks a command |
| `Manager.get(id)` | Get command by ID |
| `Manager.list()` | All tracked commands |
| `Manager.by_status(status)` | Filter by status |
| `Manager.cleanup()` | Remove all finished commands |
| `Manager.dispose(id)` | Dispose and remove |
| `Manager.cleanup_old(ms)` | Cleanup old finished commands |

### AsyncJob fields

- `id`, `cmd`, `status`, `code`, `stdout`, `stderr`, `start_time`, `duration`

## Best Practices

1. Always call `cmd:dispose()` when finished (especially with callbacks)
2. Use `Manager` for anything non-trivial
3. Prefer table form of command over string
4. Use `:wait()` with reasonable timeout
5. Check `cmd:status()` before accessing job data

## Examples

See:
- `lua/bsi/cmd/cmd_spec.lua`
- `lua/bsi/cmd/manager_spec.lua`
- `lua/bsi/git/init.lua` (real usage example)

---

**Note**: This module was recently fixed for critical bugs (missing `:wait()`, callback handling, disposal races, and ID tracking).
