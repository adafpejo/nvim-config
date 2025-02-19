local M = {}

M.co = coroutine

function M.run(fn)
    return M.co.resume(M.co.create(fn))
end

function M.assert_co_status(status, result)
    if not status then
        error("coroutine error: " .. result)
    end
end

function M.resume(co, result)
    vim.schedule(function()
        M.co.resume(co, result)
    end)
end

--- Check coroutine runtime
--- @param co thread
--- @param methodname string
function M.assert_co(co, methodname)
    if not co then
        error(string.format("%s must be called from a coroutine", methodname))
    end
end

return M
