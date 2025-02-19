local M = require('bsi.utils')

describe("M.table_keys", function()
  it("should extract keys from a table", function()
    local t = {a = 1, b = 2, c = 3}
    local expected_result = {"a", "b", "c"}
    table.sort(expected_result)
    local result = M.table_keys(t)
    table.sort(result)
    assert.are.same(result, expected_result)
  end)

  it("should handle empty tables correctly", function()
    local t = {}
    local expected_result = {}
    assert.are.same(M.table_keys(t), expected_result)
  end)

  it("should handle tables with nil values correctly", function()
    local t = {a = 1, b = nil, c = 3}
    local expected_result = {"a", "c"}
    assert.are.same(M.table_keys(t), expected_result)
  end)
end)

describe("M.table_values", function()
  it("should extract keys from a table", function()
    local t = {a = 1, b = 2, c = 3}
    local expected_result = {1, 2, 3}
    assert.are.same(M.table_values(t), expected_result)
  end)
end)
