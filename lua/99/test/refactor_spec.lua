-- luacheck: globals describe it assert before_each after_each
local _99 = require("99")
local test_utils = require("99.test.test_utils")
local eq = assert.are.same
local Levels = require("99.logger.level")
local Lsp = require("99.editor.lsp").Lsp

--- Create a real temp file that can be written to
--- @param contents string[]
--- @return string path
local function create_temp_file(contents)
  local path = vim.fn.tempname() .. ".lua"
  vim.fn.writefile(contents, path)
  return path
end

--- Mock Lsp.get_references to return predefined refs
--- @param refs {buffer_index: number, range: LspRange}[]
--- @param buffers table<number, number>
--- @return fun() restore function to unmock
local function mock_lsp_references(refs, buffers)
  local original_get_references = Lsp.get_references

  Lsp.get_references = function(_, cb)
    local resolved_refs = {}
    for _, ref in ipairs(refs) do
      local bufnr = buffers[ref.buffer_index]
      table.insert(resolved_refs, {
        uri = vim.uri_from_bufnr(bufnr),
        range = ref.range,
      })
    end
    vim.schedule(function()
      cb(resolved_refs)
    end)
  end

  return function()
    Lsp.get_references = original_get_references
  end
end

--- @param contents table<number, string[]> buffer number -> file contents
--- @param refs {buffer_index: number, range: LspRange}[]
--- @param cursor_pos {buffer: number, row: number, col: number}
--- @return _99.test.Provider, table<number, number>, fun(), string[]
local function setup_multi_file(contents, refs, cursor_pos)
  local p = test_utils.TestProvider.new()
  _99.setup({
    provider = p,
    logger = {
      error_cache_level = Levels.ERROR,
      type = "print",
    },
  })

  local buffers = {}
  local paths = {}
  for i, file_contents in ipairs(contents) do
    local path = create_temp_file(file_contents)
    table.insert(paths, path)

    local bufnr = vim.fn.bufadd(path)
    vim.fn.bufload(bufnr)
    vim.bo[bufnr].ft = "lua"
    table.insert(test_utils.created_files, bufnr)
    buffers[i] = bufnr
  end

  vim.api.nvim_set_current_buf(buffers[cursor_pos.buffer])
  vim.api.nvim_win_set_cursor(0, { cursor_pos.row, cursor_pos.col })

  local restore_lsp = mock_lsp_references(refs, buffers)

  local function cleanup()
    restore_lsp()
    for _, path in ipairs(paths) do
      vim.fn.delete(path)
    end
  end

  return p, buffers, cleanup, paths
end

--- Read file from disk (after save)
--- @param path string
--- @return string[]
local function read_file(path)
  return vim.fn.readfile(path)
end

describe("refactor", function()
  describe("single file refactoring", function()
    it("renames a function called twice in the same file", function()
      local file_contents = {
        "local function greet(name)",
        '  return "Hello, " .. name',
        "end",
        "",
        "local function main()",
        '  print(greet("Alice"))',
        '  print(greet("Bob"))',
        "end",
      }

      local refs = {
        {
          buffer_index = 1,
          range = {
            start = { line = 5, character = 8 },
            ["end"] = { line = 5, character = 13 },
          },
        },
        {
          buffer_index = 1,
          range = {
            start = { line = 6, character = 8 },
            ["end"] = { line = 6, character = 13 },
          },
        },
      }

      local p, buffers, cleanup, paths = setup_multi_file(
        { file_contents },
        refs,
        { buffer = 1, row = 6, col = 8 }
      )

      _99.refactor({ additional_prompt = "rename greet to sayHello" })
      test_utils.next_frame()

      -- First request (for line 7, processed in reverse order)
      assert.is_not_nil(p.request)
      p:resolve("success", '  print(sayHello("Bob"))')
      test_utils.next_frame()

      -- Second request (for line 6)
      assert.is_not_nil(p.request)
      p:resolve("success", '  print(sayHello("Alice"))')
      test_utils.next_frame()
      test_utils.next_frame() -- Extra frame for save

      local expected = {
        "local function greet(name)",
        '  return "Hello, " .. name',
        "end",
        "",
        "local function main()",
        '  print(sayHello("Alice"))',
        '  print(sayHello("Bob"))',
        "end",
      }
      eq(expected, read_file(paths[1]))
      cleanup()
    end)

    it("handles a single reference", function()
      local file_contents = {
        "local x = 42",
        "print(x)",
      }

      local refs = {
        {
          buffer_index = 1,
          range = {
            start = { line = 1, character = 6 },
            ["end"] = { line = 1, character = 7 },
          },
        },
      }

      local p, _, cleanup, paths = setup_multi_file(
        { file_contents },
        refs,
        { buffer = 1, row = 2, col = 6 }
      )

      _99.refactor({ additional_prompt = "rename x to answer" })
      test_utils.next_frame()

      assert.is_not_nil(p.request)
      p:resolve("success", "print(answer)")
      test_utils.next_frame()
      test_utils.next_frame()

      local expected = {
        "local x = 42",
        "print(answer)",
      }
      eq(expected, read_file(paths[1]))
      cleanup()
    end)
  end)

  describe("multi-file refactoring", function()
    it("renames a function across two files", function()
      local file1 = {
        "local M = {}",
        "",
        "function M.calculate(a, b)",
        "  return a + b",
        "end",
        "",
        "return M",
      }

      local file2 = {
        'local calc = require("calc")',
        "",
        "local function main()",
        "  local result = calc.calculate(1, 2)",
        "  print(result)",
        "end",
      }

      local refs = {
        {
          buffer_index = 1,
          range = {
            start = { line = 2, character = 11 },
            ["end"] = { line = 2, character = 20 },
          },
        },
        {
          buffer_index = 2,
          range = {
            start = { line = 3, character = 17 },
            ["end"] = { line = 3, character = 26 },
          },
        },
      }

      local p, _, cleanup, paths = setup_multi_file(
        { file1, file2 },
        refs,
        { buffer = 1, row = 3, col = 11 }
      )

      _99.refactor({ additional_prompt = "rename calculate to add" })
      test_utils.next_frame()

      -- First request (file2, line 4 - processed in reverse order)
      assert.is_not_nil(p.request)
      p:resolve("success", "  local result = calc.add(1, 2)")
      test_utils.next_frame()

      -- Second request (file1, line 3)
      assert.is_not_nil(p.request)
      p:resolve("success", "function M.add(a, b)")
      test_utils.next_frame()
      test_utils.next_frame()

      local expected_file1 = {
        "local M = {}",
        "",
        "function M.add(a, b)",
        "  return a + b",
        "end",
        "",
        "return M",
      }

      local expected_file2 = {
        'local calc = require("calc")',
        "",
        "local function main()",
        "  local result = calc.add(1, 2)",
        "  print(result)",
        "end",
      }

      eq(expected_file1, read_file(paths[1]))
      eq(expected_file2, read_file(paths[2]))
      cleanup()
    end)

    it("handles three references across two files", function()
      local file1 = {
        "local Logger = {}",
        "",
        "function Logger.log(msg)",
        "  print(msg)",
        "end",
        "",
        "return Logger",
      }

      local file2 = {
        'local Logger = require("logger")',
        "",
        "local function process()",
        '  Logger.log("starting")',
        "  -- do work",
        '  Logger.log("done")',
        "end",
      }

      local refs = {
        {
          buffer_index = 1,
          range = {
            start = { line = 2, character = 16 },
            ["end"] = { line = 2, character = 19 },
          },
        },
        {
          buffer_index = 2,
          range = {
            start = { line = 3, character = 9 },
            ["end"] = { line = 3, character = 12 },
          },
        },
        {
          buffer_index = 2,
          range = {
            start = { line = 5, character = 9 },
            ["end"] = { line = 5, character = 12 },
          },
        },
      }

      local p, _, cleanup, paths = setup_multi_file(
        { file1, file2 },
        refs,
        { buffer = 1, row = 3, col = 16 }
      )

      _99.refactor({ additional_prompt = "rename log to info" })
      test_utils.next_frame()

      -- Process in reverse order: file2 line 6, file2 line 4, file1 line 3
      assert.is_not_nil(p.request)
      p:resolve("success", '  Logger.info("done")')
      test_utils.next_frame()

      assert.is_not_nil(p.request)
      p:resolve("success", '  Logger.info("starting")')
      test_utils.next_frame()

      assert.is_not_nil(p.request)
      p:resolve("success", "function Logger.info(msg)")
      test_utils.next_frame()
      test_utils.next_frame()

      eq('  Logger.info("starting")', read_file(paths[2])[4])
      eq('  Logger.info("done")', read_file(paths[2])[6])
      eq("function Logger.info(msg)", read_file(paths[1])[3])
      cleanup()
    end)
  end)

  describe("error handling", function()
    it("handles no references found", function()
      local file_contents = {
        "local x = 42",
      }

      local p, _, cleanup = setup_multi_file(
        { file_contents },
        {}, -- No refs
        { buffer = 1, row = 1, col = 6 }
      )

      _99.refactor({ additional_prompt = "rename x" })
      test_utils.next_frame()

      -- No request should be made
      assert.is_nil(p.request)
      cleanup()
    end)

    it("handles failed requests gracefully and continues", function()
      local file_contents = {
        "local x = 42",
        "print(x)",
        "print(x)",
      }

      local refs = {
        {
          buffer_index = 1,
          range = {
            start = { line = 1, character = 6 },
            ["end"] = { line = 1, character = 7 },
          },
        },
        {
          buffer_index = 1,
          range = {
            start = { line = 2, character = 6 },
            ["end"] = { line = 2, character = 7 },
          },
        },
      }

      local p, _, cleanup, paths = setup_multi_file(
        { file_contents },
        refs,
        { buffer = 1, row = 2, col = 6 }
      )

      _99.refactor({ additional_prompt = "rename x to y" })
      test_utils.next_frame()

      -- First request (line 3) fails
      assert.is_not_nil(p.request)
      p:resolve("failed", "API error")
      test_utils.next_frame()

      -- Second request (line 2) succeeds
      assert.is_not_nil(p.request)
      p:resolve("success", "print(y)")
      test_utils.next_frame()
      test_utils.next_frame()

      -- Only the successful change should be applied
      local result = read_file(paths[1])
      eq("print(y)", result[2])
      eq("print(x)", result[3]) -- Unchanged due to failure
      cleanup()
    end)
  end)

  describe("edge cases", function()
    it(
      "preserves line numbers when editing multiple lines in same file",
      function()
        local file_contents = {
          "function foo() end",
          "function bar() end",
          "function baz() end",
          "",
          "foo()",
          "bar()",
          "baz()",
        }

        local refs = {
          {
            buffer_index = 1,
            range = {
              start = { line = 4, character = 0 },
              ["end"] = { line = 4, character = 3 },
            },
          },
          {
            buffer_index = 1,
            range = {
              start = { line = 5, character = 0 },
              ["end"] = { line = 5, character = 3 },
            },
          },
          {
            buffer_index = 1,
            range = {
              start = { line = 6, character = 0 },
              ["end"] = { line = 6, character = 3 },
            },
          },
        }

        local p, _, cleanup, paths = setup_multi_file(
          { file_contents },
          refs,
          { buffer = 1, row = 5, col = 0 }
        )

        _99.refactor({ additional_prompt = "add comment before each call" })
        test_utils.next_frame()

        -- Process in reverse: line 7, then 6, then 5
        assert.is_not_nil(p.request)
        p:resolve("success", "-- call baz\nbaz()")
        test_utils.next_frame()

        assert.is_not_nil(p.request)
        p:resolve("success", "-- call bar\nbar()")
        test_utils.next_frame()

        assert.is_not_nil(p.request)
        p:resolve("success", "-- call foo\nfoo()")
        test_utils.next_frame()
        test_utils.next_frame()

        local result = read_file(paths[1])
        -- Each call should have a comment before it
        assert.is_true(vim.tbl_contains(result, "-- call foo"))
        assert.is_true(vim.tbl_contains(result, "-- call bar"))
        assert.is_true(vim.tbl_contains(result, "-- call baz"))
        cleanup()
      end
    )

    it("strips trailing empty lines from response", function()
      local file_contents = {
        "local x = 42",
        "print(x)",
      }

      local refs = {
        {
          buffer_index = 1,
          range = {
            start = { line = 1, character = 6 },
            ["end"] = { line = 1, character = 7 },
          },
        },
      }

      local p, _, cleanup, paths = setup_multi_file(
        { file_contents },
        refs,
        { buffer = 1, row = 2, col = 6 }
      )

      _99.refactor({ additional_prompt = "rename x to y" })
      test_utils.next_frame()

      -- Response with trailing newlines
      assert.is_not_nil(p.request)
      p:resolve("success", "print(y)\n\n\n")
      test_utils.next_frame()
      test_utils.next_frame()

      local expected = {
        "local x = 42",
        "print(y)",
      }
      eq(expected, read_file(paths[1]))
      cleanup()
    end)
  end)
end)
