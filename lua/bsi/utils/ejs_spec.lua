local ejs = require("bsi.utils.ejs")

describe("bsi.utils.ejs", function()
  it("should render simple variables", function()
    local template = "Hello <%= name %>!"
    local result = ejs.render(template, { name = "World" })
    assert.are.equal("Hello World!", result)
  end)

  it("should support lua code blocks", function()
    local template = "Items: <% for _, item in ipairs(items) do %><%= item %>,<% end %>"
    local result = ejs.render(template, { items = { "apple", "banana" } })
    assert.are.equal("Items: apple,banana,", result)
  end)

  it("should escape html by default with <%%= %%>", function()
    local template = "Tag: <%= tag %>"
    local result = ejs.render(template, { tag = "<div>" })
    assert.are.equal("Tag: &lt;div&gt;", result)
  end)

  it("should NOT escape html with <%- %>", function()
    local template = "Tag: <%- tag %>"
    local result = ejs.render(template, { tag = "<div>" })
    assert.are.equal("Tag: <div>", result)
  end)
end)
