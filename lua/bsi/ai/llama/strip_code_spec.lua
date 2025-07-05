local strip_code = require("bsi.ai.llama.strip_code") -- Adjust the module name/path as needed

describe("bsi.ai.llama.strip_code", function()
    it("one string", function()
        local input1 = "`let x = 2;`"
        local expected1 = "let x = 2;"
        local output1 = strip_code(input1)
        assert(output1 == expected1, "Test 1 failed: expected '" .. expected1 .. "', got '" .. output1 .. "'")
    end)

    it("Triple backticks", function()
        local input2 = "```let x = 2;```"
        local expected2 = "let x = 2;"
        local output2 = strip_code(input2)
        assert(output2 == expected2, "Test 2 failed: expected '" .. expected2 .. "', got '" .. output2 .. "'")
    end)

    it("Triple backticks", function()
        local input2 =
        "```javascript\n" ..
        "    let x = 2;\n" ..
        "```"
        local expected2 = "\n    let x = 2;\n"
        local output2 = strip_code(input2)
        assert(output2 == expected2, "Test 2 failed: expected '" .. expected2 .. "', got '" .. output2 .. "'")
    end)

    it("No code fences", function()
        local input3 = "let x = 2;"
        local expected3 = "let x = 2;"
        local output3 = strip_code(input3)
        assert(output3 == expected3, "Test 3 failed: expected '" .. expected3 .. "', got '" .. output3 .. "'")
    end)
end)
