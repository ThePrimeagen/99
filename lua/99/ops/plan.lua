local Window = require("99.window")
local geo = require("99.geo")
local Point = geo.Point

--- @class _99.Plan
--- @field diff string[]
--- @field new_text string[]
--- @field old_text string[]
--- @field file_path string
--- @field start_row number
--- @field start_col number
--- @field end_row number
--- @field end_col number

--- @class _99.PlanResult
--- @field approved boolean

local Plan = {}

--- @param old_text string[]
--- @param new_text string[]
--- @return string[]
local function build_diff(old_text, new_text)
  local diff = {}
  table.insert(diff, "--- Original")
  for _, line in ipairs(old_text) do
    table.insert(diff, "-" .. line)
  end
  table.insert(diff, "+++ New")
  for _, line in ipairs(new_text) do
    table.insert(diff, "+" .. line)
  end
  return diff
end

--- @param context _99.RequestContext
--- @param new_text string[]
--- @param range geo.Range
--- @return _99.Plan | nil
function Plan.new(context, new_text, range)
  local buffer = context.buffer
  if not buffer then
    return nil
  end

  local start = range.start
  local end_ = range["end"]

  local old_text = vim.api.nvim_buf_get_lines(
    buffer,
    start.row,
    end_.row,
    false
  )

  return {
    diff = build_diff(old_text, new_text),
    new_text = new_text,
    old_text = old_text,
    file_path = context.full_path,
    start_row = start.row,
    start_col = start.col,
    end_row = end_.row,
    end_col = end_.col,
  }
end

--- @param plan _99.Plan
--- @param cb fun(approved: boolean): nil
function Plan.show_and_confirm(plan, cb)
  local msg = { "Apply changes?", "", "File: " .. plan.file_path, "" }
  for _, line in ipairs(plan.diff) do
    table.insert(msg, line)
  end
  table.insert(msg, "")
  table.insert(msg, "[y]es to apply, [n]o to cancel")

  Window.display_centered_message(msg, function(answer)
    if answer and answer:lower():sub(1, 1) == "y" then
      cb(true)
    else
      cb(false)
    end
  end)
end

--- @param plan _99.Plan
function Plan.apply(plan)
  local buffer = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(
    buffer,
    plan.start_row,
    plan.end_row,
    false,
    plan.new_text
  )
end

return Plan
