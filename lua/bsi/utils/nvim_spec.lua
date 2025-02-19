local M = require("bsi.utils.nvim")  -- Adjust the module name/path as needed

describe("bsi.utils.nvim", function()
    it("M.trim", function()
        assert.are.same('hello', M.trim("hello     "))
        assert.are.same('hello', M.trim("     hello     "))
        assert.are.same('hello', M.trim("     hello"))
    end)
end)
