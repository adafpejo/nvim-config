local jsonkv = require("bsi.jsonkv")

describe("bsi.jsonkv", function()
  local saved_plus
  local saved_unnamed

  before_each(function()
    saved_plus = vim.fn.getreg("+")
    saved_unnamed = vim.fn.getreg('"')
  end)

  after_each(function()
    vim.fn.setreg("+", saved_plus)
    vim.fn.setreg('"', saved_unnamed)
  end)

  it("flattens nested objects, arrays, null, and empty containers", function()
    local text = [[
{
  "name": "ada",
  "nested": {"count": 2, "ok": true},
  "tags": ["a", "b"],
  "n": null,
  "empty": {},
  "arr": [],
  "a.b": 1,
  "weird key": "x"
}
]]
    local flat, err = jsonkv.flatten_text(text)
    assert.is_nil(err)
    assert.are.same([[
["a.b"] = 1
arr = []
empty = {}
n = null
name = "ada"
nested.count = 2
nested.ok = true
tags[0] = "a"
tags[1] = "b"
["weird key"] = "x"]], flat)
  end)

  it("keeps a comment-looking string and skips real comments", function()
    local text = [[
{
  // keep
  "b": 1,
  /* c */ "a": "/* stay */"
}
]]
    local flat, err = jsonkv.flatten_text(text)
    assert.is_nil(err)
    assert.are.same('a = "/* stay */"\nb = 1', flat)
  end)

  it("quotes keys that need escaping", function()
    local flat, err = jsonkv.flatten_text('{"quote\\"key": "v"}')
    assert.is_nil(err)
    assert.are.same('["quote\\"key"] = "v"', flat)
  end)

  it("emits root scalars and empty roots without a key", function()
    assert.are.same("42", jsonkv.flatten_text("42"))
    assert.are.same('"hi"', jsonkv.flatten_text('"hi"'))
    assert.are.same("null", jsonkv.flatten_text("null"))
    assert.are.same("true", jsonkv.flatten_text("true"))
    assert.are.same("{}", jsonkv.flatten_text("{}"))
    assert.are.same("[]", jsonkv.flatten_text("[]"))
  end)

  it("uses 0-based indexes through nested arrays", function()
    local flat = jsonkv.flatten_text('[{"name":"a"}, null]')
    assert.are.same('[0].name = "a"\n[1] = null', flat)
  end)

  it("rejects empty and invalid JSON", function()
    local flat, err = jsonkv.flatten_text("   \n")
    assert.is_nil(flat)
    assert.are.same("empty JSON", err)

    flat, err = jsonkv.flatten_text("{")
    assert.is_nil(flat)
    assert.truthy(err)
  end)

  it("copies a range to the paste registers and leaves the buffer", function()
    local buf = vim.api.nvim_create_buf(false, true)
    local original = { '{"only": 1}', '{"skip": 2}' }
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, original)
    vim.api.nvim_set_current_buf(buf)

    local flat = jsonkv.command({ range = 2, line1 = 1, line2 = 1 })
    assert.are.same("only = 1", flat)
    assert.are.same("only = 1", vim.fn.getreg("+"))
    assert.are.same("only = 1", vim.fn.getreg('"'))
    assert.are.same(original, vim.api.nvim_buf_get_lines(buf, 0, -1, false))

    local whole = jsonkv.command({ range = 0 })
    assert.is_nil(whole)
    assert.are.same(original, vim.api.nvim_buf_get_lines(buf, 0, -1, false))

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "{", '  "a": 1,', '  "b": false', "}" })
    whole = jsonkv.command({})
    assert.are.same("a = 1\nb = false", whole)
    assert.are.same("a = 1\nb = false", vim.fn.getreg("+"))
  end)
end)
