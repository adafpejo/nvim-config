local M = require("bsi.utils.init")

describe("escape_quotes", function()
    it("escapes single quotes", function()
        assert.are.equal(
            "This is a \'test\'",
            M.escape_quotes("This is a 'test'")
        )
    end)

    it("escapes double quotes", function()
        assert.are.equal(
            'This is a \"test\"',
            M.escape_quotes('This is a "test"')
        )
    end)

    it("escapes both single and double quotes", function()
        assert.are.equal(
            'This is a \'test\' and a \"quote\"',
            M.escape_quotes("This is a 'test' and a \"quote\"")
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
