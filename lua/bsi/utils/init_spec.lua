local M = require("bsi.utils.init")

describe("escape_quotes", function()
    it("escapes single quotes", function()
        assert.are.equal(
            "This is a 'test'",
            M.escape_quotes("This is a 'test'")
        )
    end)

    it("escapes double quotes", function()
        assert.are.equal(
            'This is a "test"',
            M.escape_quotes('This is a "test"')
        )
    end)

    it("escapes both single and double quotes", function()
        assert.are.equal(
            'This is a 'test' and a "quote"',
            M.escape_quotes("This is a 'test' and a "quote"")
        )
    end)

    it("returns the same string if no quotes are present", function()
        assert.are.equal("No quotes here", M.escape_quotes("No quotes here"))
    end)

    it("handles an empty string", function()
        assert.are.equal("", M.escape_quotes(""))
    end)

    it("handles an empty string", function()
        assert.are.equal("LLM responseCannot retrieve project language details for ID: %s.", M.escape_quotes("LLM responseCannot retrieve project language details for ID: %s."))
    end)
end)

describe("table_keys", function()
    it("returns the values of the array part of a table", function()
        local tbl = { "a", "b", "c" }
        assert.are.same(tbl, M.table_keys(tbl))
    end)

    it("ignores the hash part of a table", function()
        local tbl = { "a", "b", "c", x = "d", y = "e" }
        assert.are.same({ "a", "b", "c", "x", "y" }, M.table_keys(tbl))
    end)

    it("returns an empty table for an empty table", function()
        assert.are.same({}, M.table_keys({}))
    end)
end)

describe("table_values", function()
    it("returns values from the table using array values as keys", function()
        local tbl = { "one", "two", one = "hello", two = "world" }
        assert.are.same({ "hello", "world" }, M.table_values(tbl))
    end)

    it("returns nil for values if array values are not keys in the table", function()
        local tbl = { "a", "b", "c" }
        assert.are.same({ nil, nil, nil }, M.table_values(tbl))
    end)

    it("returns an empty table for an empty table", function()
        assert.are.same({}, M.table_values({}))
    end)
end)
