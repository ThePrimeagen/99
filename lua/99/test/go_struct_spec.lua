---@module "plenary.busted"
local test_utils = require("99.test.test_utils")
---@diagnostic disable-next-line: undefined-field
local eq = assert.are.same

describe("go 99-struct query", function()
  it("should capture struct names and fields", function()
    local go_content = {
      "package main",
      "",
      "type Person struct {",
      "    Name string",
      "    Age int",
      "}",
      "",
      "type MyStruct struct {",
      "    Field string",
      "    Count int",
      "}",
    }

    local buffer = test_utils.create_file(go_content, "go")
    local parser = vim.treesitter.get_parser(buffer, "go")
    assert(parser, "Parser should not be nil")

    local tree = parser:parse()[1]
    local root = tree:root()

    local ok, query = pcall(vim.treesitter.query.get, "go", "99-struct")
    assert(ok and query, "Failed to load query")

    local structs = {}
    local current_struct = nil

    for id, node in query:iter_captures(root, buffer, 0, -1) do
      local name = query.captures[id]
      local text = vim.treesitter.get_node_text(node, buffer)

      if name == "struct.name" then
        current_struct = { name = text, fields = {} }
        table.insert(structs, current_struct)
      elseif name == "field.name" and current_struct then
        table.insert(current_struct.fields, { name = text })
      elseif name == "field.type" and current_struct then
        current_struct.fields[#current_struct.fields].type = text
      end
    end

    local expected_structs = {
      {
        name = "Person",
        fields = {
          { name = "Name", type = "string" },
          { name = "Age", type = "int" },
        },
      },
      {
        name = "MyStruct",
        fields = {
          { name = "Field", type = "string" },
          { name = "Count", type = "int" },
        },
      },
    }

    eq(expected_structs, structs)
  end)
end)
