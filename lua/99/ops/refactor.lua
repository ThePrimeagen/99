local Request = require("99.request")
local RequestStatus = require("99.ops.request_status")
local Mark = require("99.ops.marks")
local make_clean_up = require("99.ops.clean-up")
local geo = require("99.geo")
local Range = geo.Range
local Point = geo.Point
local Observers = require("99.observers")
local Lsp = require("99.editor.lsp").Lsp
local utils = require("99.utils")
local Agents = require("99.extensions.agents")

--- Reset context for a new request
--- @param context _99.RequestContext
local function reset_context(context)
  context.ai_context = {}
  context.tmp_file = utils.random_file()
end

--- Load a buffer for a file path
--- @param path string
--- @return number
local function ensure_buffer(path)
  local buffer_number = vim.fn.bufnr(path)
  if buffer_number == -1 then
    buffer_number = vim.fn.bufadd(path)
  end
  if not vim.api.nvim_buf_is_loaded(buffer_number) then
    vim.fn.bufload(buffer_number)
  end
  return buffer_number
end

--- Apply changes to locations and emit observer events
--- @param locations {buffer: number, path: string, range: _99.Range}[]
--- @param results table<number, string>
--- @param context _99.RequestContext
--- @param opts _99.ops.Opts
--- @param logger _99.Logger
--- @return table<number, boolean> changed_buffers
local function apply_changes(locations, results, context, opts, logger)
  local changed_buffers = {}
  for i = #locations, 1, -1 do
    local loc = locations[i]
    local response = results[i]
    if response then
      local lines = vim.split(response, "\n")
      while #lines > 0 and lines[#lines] == "" do
        table.remove(lines)
      end
      loc.range:replace_text(lines)
      changed_buffers[loc.buffer] = true
      logger:debug(
        "applied change",
        "path",
        loc.path,
        "line",
        loc.range.start.row
      )

      Observers.emit_change({
        context = context,
        buffer = loc.buffer,
        start_line = loc.range.start.row,
        operation = Observers.Operation.REFACTOR,
        prompt = opts.additional_prompt,
      })
    end
  end
  return changed_buffers
end

--- Save all modified buffers
--- @param changed_buffers table<number, boolean>
--- @param logger _99.Logger
local function save_changed_buffers(changed_buffers, logger)
  for buffer_number, _ in pairs(changed_buffers) do
    if
      vim.api.nvim_buf_is_valid(buffer_number)
      and vim.bo[buffer_number].modified
    then
      vim.api.nvim_buf_call(buffer_number, function()
        vim.cmd("silent write")
      end)
      logger:debug("saved buffer", "buffer_number", buffer_number)
    end
  end
end

--- Build a configured request for a single location
--- @param loc {buffer: number, path: string, range: _99.Range}
--- @param context _99.RequestContext
--- @param opts _99.ops.Opts
--- @return _99.Request
local function build_request(loc, context, opts)
  reset_context(context)
  local request = Request.new(context)

  local prompt = context._99.prompts.prompts.refactor(
    loc.path,
    loc.range.start.row,
    loc.range:to_text(),
    opts.additional_prompt or ""
  )

  if opts.additional_prompt then
    local rules = Agents.find_rules(context._99.rules, opts.additional_prompt)
    context:add_agent_rules(rules)
  end

  if opts.additional_rules then
    context:add_agent_rules(opts.additional_rules)
  end

  request:add_prompt_content(prompt)
  return request
end

--- Convert LSP references to ranges we can work with
--- Expands each reference to include the full line for better context
--- @param refs {uri: string, range: LspRange}[]
--- @return {buffer: number, path: string, range: _99.Range}[]
local function refs_to_ranges(refs)
  local ranges = {}
  for _, ref in ipairs(refs) do
    local path = vim.uri_to_fname(ref.uri)
    local buffer_number = ensure_buffer(path)
    local line_num = ref.range.start.line + 1

    local line_content = vim.api.nvim_buf_get_lines(
      buffer_number,
      line_num - 1,
      line_num,
      false
    )[1] or ""
    local line_len = #line_content

    table.insert(ranges, {
      buffer = buffer_number,
      path = path,
      range = Range:new(
        buffer_number,
        Point:new(line_num, 1),
        Point:new(line_num, line_len + 1)
      ),
    })
  end
  return ranges
end

--- @param context _99.RequestContext
--- @param opts _99.ops.Opts
local function refactor(context, opts)
  opts = opts or {}
  local logger = context.logger:set_area("refactor")
  local buffer = context.buffer

  Lsp.get_references(buffer, function(refs)
    if #refs == 0 then
      logger:warn("no references found")
      return
    end

    local locations = refs_to_ranges(refs)
    logger:debug("found references", "count", #locations)

    local status_mark = Mark.mark_above_range(locations[1].range)
    local request_status = RequestStatus.new(
      250,
      context._99.ai_stdout_rows,
      "Refactoring",
      status_mark
    )
    request_status:start()

    local completed = 0
    local total = #locations
    local results = {} -- Store results indexed by location
    local active_requests = {} -- Track active requests for cancellation

    local clean_up = make_clean_up(context, function()
      -- Cancel all active requests
      for _, req in pairs(active_requests) do
        req:cancel()
      end
      request_status:stop()
      status_mark:delete()
    end)

    -- Called when all requests complete
    local function on_all_complete()
      -- Apply changes in reverse order to prevent line number shifts
      local changed_buffers =
        apply_changes(locations, results, context, opts, logger)
      save_changed_buffers(changed_buffers, logger)
      vim.schedule(clean_up)
      logger:debug("refactor complete", "total", total)
    end

    -- Launch all requests in parallel
    for index, loc in ipairs(locations) do
      -- Each request needs its own context copy for tmp_file
      local request = build_request(loc, context, opts)
      active_requests[index] = request

      request:start({
        on_stdout = function(line)
          request_status:push(line)
        end,
        on_stderr = function(line)
          logger:debug("refactor#on_stderr", "index", index, "line", line)
        end,
        on_complete = function(status, response)
          completed = completed + 1
          active_requests[index] = nil
          request_status:push(string.format("Done %d/%d", completed, total))

          if status == "success" then
            results[index] = response
            logger:debug("got response for location", "index", index)
          elseif status == "cancelled" then
            logger:debug("refactor was cancelled", "index", index)
          else
            logger:warn(
              "failed to process location",
              "index",
              index,
              "status",
              status
            )
          end

          -- Check if all requests are done
          if completed >= total then
            on_all_complete()
          end
        end,
      })
    end

    logger:debug("launched parallel requests", "count", total)
  end)
end

return refactor
