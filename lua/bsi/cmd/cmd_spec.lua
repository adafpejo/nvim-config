local Cmd = require("bsi.cmd")

describe("cmd.new", function()
  it("returns a Command object", function()
    local cmd = Cmd.new({ "echo", "hello" })
    assert.is_not_nil(cmd)
    assert.is_not_nil(cmd.result)
    assert.is_not_nil(cmd.status)
    assert.is_not_nil(cmd.dispose)
    assert.is_not_nil(cmd.cancel)
  end)

  it("accepts string command", function()
    local cmd = Cmd.new("echo hello")
    assert.is_not_nil(cmd)
    assert.equals("echo", cmd.cmd[1])
  end)

  it("starts with running status", function()
    local cmd = Cmd.new({ "echo", "hello" })
    assert.equals("running", cmd:status())
  end)
end)

describe("cmd:result", function()
  it("returns job data after completion", function()
    local cmd = Cmd.new({ "printf", "hello" })
    local job = cmd:result(3000)
    assert.is_not_nil(job)
    assert.equals("hello", job.stdout)
  end)

  it("returns job with exit code", function()
    local cmd = Cmd.new({ "true" })
    local job = cmd:result(3000)
    assert.equals(0, job.code)
  end)

  it("returns nil on timeout", function()
    local cmd = Cmd.new({ "sleep", "10" })
    local job = cmd:result(500)
    assert.is_nil(job)
  end)

  it("returns nil after dispose", function()
    local cmd = Cmd.new({ "printf", "hello" })
    cmd:dispose()
    local job = cmd:result(100)
    assert.is_nil(job)
  end)
end)

describe("cmd:status", function()
  it("returns running for active command", function()
    local cmd = Cmd.new({ "sleep", "10" })
    assert.equals("running", cmd:status())
  end)

  it("returns done after completion", function()
    local cmd = Cmd.new({ "true" })
    cmd:result(3000)
    assert.equals("done", cmd:status())
  end)

  it("returns failed on non-zero exit", function()
    local cmd = Cmd.new({ "false" })
    cmd:result(3000)
    assert.equals("failed", cmd:status())
  end)

  it("returns disposed after dispose", function()
    local cmd = Cmd.new({ "printf", "hello" })
    cmd:dispose()
    assert.equals("disposed", cmd:status())
  end)
end)

describe("cmd:cancel", function()
  it("marks running command as cancelled", function()
    local cmd = Cmd.new({ "sleep", "10" })
    cmd:cancel()
    assert.equals("cancelled", cmd:status())
  end)

  it("does nothing on finished command", function()
    local cmd = Cmd.new({ "true" })
    cmd:result(3000)
    cmd:cancel()
    assert.equals("done", cmd:status())
  end)

  it("does nothing on disposed command", function()
    local cmd = Cmd.new({ "printf", "hello" })
    cmd:dispose()
    cmd:cancel()
    assert.equals("disposed", cmd:status())
  end)
end)

describe("cmd:dispose", function()
  it("sets status to disposed", function()
    local cmd = Cmd.new({ "printf", "hello" })
    cmd:dispose()
    assert.equals("disposed", cmd:status())
  end)

  it("clears job reference", function()
    local cmd = Cmd.new({ "printf", "hello" })
    cmd:dispose()
    assert.is_nil(cmd:job())
  end)

  it("is idempotent", function()
    local cmd = Cmd.new({ "printf", "hello" })
    cmd:dispose()
    cmd:dispose()
    assert.equals("disposed", cmd:status())
  end)
end)

describe("cmd:job", function()
  it("returns job data", function()
    local cmd = Cmd.new({ "printf", "hello" })
    local job = cmd:job()
    assert.is_not_nil(job)
    assert.equals("running", job.status)
    assert.is_not_nil(job.start_time)
  end)

  it("returns nil after dispose", function()
    local cmd = Cmd.new({ "printf", "hello" })
    cmd:dispose()
    assert.is_nil(cmd:job())
  end)
end)

describe("cmd callbacks", function()
  it("calls on_complete", function()
    local called = false
    Cmd.new({ "true" }, {
      on_complete = function(cmd)
        called = true
        assert.equals("done", cmd:status())
      end,
    })
    vim.wait(3000, function() return called end)
    assert.is_true(called)
  end)

  it("calls on_success when no on_complete", function()
    local called = false
    Cmd.new({ "true" }, {
      on_success = function(cmd)
        called = true
        assert.equals("done", cmd:status())
      end,
    })
    vim.wait(3000, function() return called end)
    assert.is_true(called)
  end)

  it("calls on_error", function()
    local called = false
    Cmd.new({ "false" }, {
      on_error = function(cmd)
        called = true
        assert.equals("failed", cmd:status())
      end,
    })
    vim.wait(3000, function() return called end)
    assert.is_true(called)
  end)

  it("does not call callbacks after dispose", function()
    local called = false
    local cmd = Cmd.new({ "true" }, {
      on_complete = function() called = true end,
      on_success = function() called = true end,
    })
    cmd:dispose()
    vim.wait(1000, function() return called end)
    assert.is_false(called)
  end)
end)

describe("cmd:handle", function()
  it("returns vim.system handle", function()
    local cmd = Cmd.new({ "printf", "hello" })
    local handle = cmd:handle()
    assert.is_not_nil(handle)
    assert.is_not_nil(handle.wait)
  end)

  it("returns nil after dispose", function()
    local cmd = Cmd.new({ "printf", "hello" })
    cmd:dispose()
    assert.is_nil(cmd:handle())
  end)
end)

