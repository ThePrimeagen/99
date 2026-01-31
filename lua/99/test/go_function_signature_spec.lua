---@module "plenary.busted"
local test_utils = require("99.test.test_utils")
---@diagnostic disable-next-line: undefined-field
local eq = assert.are.same

describe("go 99-function-signature query", function()
  it("should capture function signatures", function()
    local go_content = {
      "package main",
      "",
      "func main() {",
      '    fmt.Println("Hello, world!")',
      "}",
      "",
      "func add(a int, b int) int {",
      "    return a + b",
      "}",
      "",
      "type MyStruct struct {",
      "    Field string",
      "}",
      "",
      "func (ms MyStruct) GetField() string {",
      "    return ms.Field",
      "}",
      "",
      "func (ms *MyStruct) SetField(value string) {",
      "    ms.Field = value",
      "}",
    }

    local buffer = test_utils.create_file(go_content, "go")
    local parser = vim.treesitter.get_parser(buffer, "go")
    assert(parser, "Parser should not be nil")

    local tree = parser:parse()[1]
    local root = tree:root()

    local ok, query =
      pcall(vim.treesitter.query.get, "go", "99-function-signature")
    assert(ok and query, "Failed to load query")

    local actual_signatures = {}
    for id, node in query:iter_captures(root, buffer, 0, -1) do
      if query.captures[id] == "signature" then
        local text = vim.treesitter.get_node_text(node, buffer)
        -- strip body
        text = text:gsub("%s*{.*$", "")
        text = vim.trim(text)
        table.insert(actual_signatures, text)
      end
    end

    local expected_signatures = {
      "func main()",
      "func add(a int, b int) int",
      "func (ms MyStruct) GetField() string",
      "func (ms *MyStruct) SetField(value string)",
    }

    eq(expected_signatures, actual_signatures)
  end)
end)
