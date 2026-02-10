-- luacheck: globals describe it assert before_each after_each
---@diagnostic disable: undefined-field, need-check-nil
local Files = require("99.extensions.files")
local eq = assert.are.same

describe("files", function()
  local default_exclude = {
    ".env",
    ".env.*",
    "node_modules",
    ".git",
    "dist",
    "build",
    "*.log",
    ".DS_Store",
    "tmp",
    ".cursor",
  }

  before_each(function()
    Files.setup({ enabled = true, exclude = default_exclude }, {})
    Files.set_project_root(vim.uv.cwd())
  end)

  after_each(function()
    Files.set_project_root("")
  end)

  it("discover_files finds known files and excludes .git", function()
    local files = Files.discover_files()
    local paths = {}
    for _, f in ipairs(files) do
      paths[f.path] = f
    end

    -- known fixture files must be present
    assert.is_not_nil(paths["scratch/refresh.lua"])
    assert.is_not_nil(paths["scratch/test.ts"])
    eq("refresh.lua", paths["scratch/refresh.lua"].name)
    eq("test.ts", paths["scratch/test.ts"].name)

    -- .git must be excluded
    for path, _ in pairs(paths) do
      assert.is_nil(
        path:match("^%.git/"),
        "expected .git to be excluded but found: " .. path
      )
    end
  end)

  it("discover_files returns sorted paths", function()
    local files = Files.discover_files()
    for i = 2, #files do
      assert.is_true(
        files[i - 1].path < files[i].path,
        "expected sorted order but "
          .. files[i - 1].path
          .. " >= "
          .. files[i].path
      )
    end
  end)

  it("is_project_file by path and name, rejects invalid", function()
    Files.discover_files()
    eq(true, Files.is_project_file("scratch/refresh.lua"))
    eq(true, Files.is_project_file("refresh.lua"))
    eq(false, Files.is_project_file("nonexistent/file.lua"))
    eq(false, Files.is_project_file(""))
  end)

  it("find_matches fuzzy matches non-contiguous characters", function()
    Files.discover_files()

    -- "rfrsh" should fuzzy match "refresh.lua" (r-f-r-s-h appear in order)
    local matches = Files.find_matches("rfrsh")
    local found = false
    for _, f in ipairs(matches) do
      if f.name == "refresh.lua" then
        found = true
      end
    end
    assert.is_true(found, "expected 'rfrsh' to fuzzy match refresh.lua")

    -- "zzzzz" should match nothing
    local no_matches = Files.find_matches("zzzzz")
    eq(0, #no_matches)
  end)

  it("read_file returns actual file content", function()
    local content = Files.read_file("scratch/refresh.lua")
    assert.is_not_nil(content)
    assert.is_true(#content > 0, "expected non-empty file content")
  end)

  it("read_file returns nil for missing file", function()
    eq(nil, Files.read_file("nonexistent/file.lua"))
  end)

  it("setup excludes configured patterns and keeps others", function()
    Files.setup(
      { enabled = true, exclude = { "scratch", ".git", "node_modules" } },
      {}
    )
    Files.set_project_root(vim.uv.cwd())
    local files = Files.discover_files()

    local has_non_scratch = false
    for _, f in ipairs(files) do
      assert.is_nil(
        f.path:match("^scratch"),
        "expected scratch excluded but found: " .. f.path
      )
      if not f.path:match("^scratch") then
        has_non_scratch = true
      end
    end
    assert.is_true(
      has_non_scratch,
      "expected non-scratch files to still be present"
    )
  end)

  it("setup excludes rule dirs from discovered files", function()
    Files.setup({ enabled = true, exclude = default_exclude }, {
      "scratch/custom_rules",
      "./scratch/custom_rules/",
      "scratch/custom_rules/",
    })
    Files.set_project_root(vim.uv.cwd())
    local files = Files.discover_files()

    for _, f in ipairs(files) do
      assert.is_nil(
        f.path:match("^scratch/custom_rules"),
        "expected rule dir excluded but found: " .. f.path
      )
    end

    -- calling setup again should not break exclusion
    Files.setup({ enabled = true, exclude = default_exclude }, {
      "scratch/custom_rules",
      "./scratch/custom_rules/",
      "scratch/custom_rules/",
    })
    files = Files.discover_files()

    for _, f in ipairs(files) do
      assert.is_nil(
        f.path:match("^scratch/custom_rules"),
        "expected rule dir still excluded after second setup: " .. f.path
      )
    end
  end)

  it("setup preserves base excludes across repeated calls", function()
    -- first call with rule dirs
    Files.setup(
      { enabled = true, exclude = { ".git", "node_modules" } },
      { "scratch/custom_rules" }
    )
    Files.set_project_root(vim.uv.cwd())

    -- second call without rule dirs — base excludes must survive
    Files.setup(
      { enabled = true, exclude = { ".git", "node_modules" } },
      {}
    )
    local files = Files.discover_files()

    for _, f in ipairs(files) do
      assert.is_nil(
        f.path:match("^%.git/"),
        "expected .git still excluded after re-setup: " .. f.path
      )
    end
  end)

  it(
    "completion_provider get_items returns items with correct shape and values",
    function()
      Files.discover_files()
      local provider = Files.completion_provider()

      eq("@", provider.trigger)
      eq("files", provider.name)

      local items = provider.get_items()
      assert.is_true(#items > 0)

      -- find the refresh.lua item specifically and check every field
      local refresh_item = nil
      for _, item in ipairs(items) do
        if item.label == "refresh.lua" then
          refresh_item = item
        end
      end
      assert.is_not_nil(
        refresh_item,
        "expected to find refresh.lua in completion items"
      )
      eq("@scratch/refresh.lua", refresh_item.insertText)
      assert.is_true(
        refresh_item.filterText:match("refresh%.lua") ~= nil,
        "expected filterText to contain filename"
      )
      eq(17, refresh_item.kind) -- LSP CompletionItemKind.Reference
      eq("scratch/refresh.lua", refresh_item.detail)
      eq("markdown", refresh_item.documentation.kind)
    end
  )

  it(
    "completion_provider resolve wraps content in code fence with extension",
    function()
      local provider = Files.completion_provider()
      local content = provider.resolve("scratch/refresh.lua")
      assert.is_not_nil(content)

      assert.is_true(
        content:sub(1, 6) == "```lua",
        "expected code fence to start with ```lua"
      )
      assert.is_true(
        content:sub(-4) == "\n```",
        "expected code fence to end with ```"
      )
      assert.is_true(
        content:match("-- scratch/refresh%.lua") ~= nil,
        "expected path comment in fence"
      )
      local inner = content:match("```lua\n.-\n(.+)\n```$")
      assert.is_not_nil(inner, "expected non-empty content inside code fence")
    end
  )

  it("completion_provider resolve returns nil for missing file", function()
    local provider = Files.completion_provider()
    eq(nil, provider.resolve("does/not/exist.lua"))
  end)

  it("completion_provider resolve works with bare filename", function()
    Files.discover_files()
    local provider = Files.completion_provider()
    local content = provider.resolve("refresh.lua")
    assert.is_not_nil(content, "expected resolve to work with bare filename")
    assert.is_true(
      content:sub(1, 6) == "```lua",
      "expected code fence to start with ```lua"
    )
    assert.is_true(
      content:match("-- scratch/refresh%.lua") ~= nil,
      "expected full relative path in fence comment"
    )
  end)
end)
