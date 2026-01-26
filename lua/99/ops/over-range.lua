local Request = require("99.request")
local RequestStatus = require("99.ops.request_status")
local Mark = require("99.ops.marks")
local geo = require("99.geo")
local make_clean_up = require("99.ops.clean-up")
local Agents = require("99.extensions.agents")
local Observers = require("99.observers")

local Range = geo.Range
local Point = geo.Point

--- @param context _99.RequestContext
--- @param range _99.Range
--- @param opts? _99.ops.Opts
local function over_range(context, range, opts)
  opts = opts or {}
  local logger = context.logger:set_area("visual")

  local request = Request.new(context)
  local top_mark = Mark.mark_above_range(range)
  local bottom_mark = Mark.mark_point(range.buffer, range.end_)
  context.marks.top_mark = top_mark
  context.marks.bottom_mark = bottom_mark

  logger:debug(
    "visual request start",
    "start",
    Point.from_mark(top_mark),
    "end",
    Point.from_mark(bottom_mark)
  )

  local display_ai_status = context._99.ai_stdout_rows > 1
  local top_status = RequestStatus.new(
    250,
    context._99.ai_stdout_rows or 1,
    "Implementing",
    top_mark
  )
  local bottom_status = RequestStatus.new(250, 1, "Implementing", bottom_mark)
  local clean_up = make_clean_up(context, function()
    top_status:stop()
    bottom_status:stop()
    context:clear_marks()
    request:cancel()
  end)

  local full_prompt = context._99.prompts.prompts.visual_selection(range)
  local additional_prompt = opts.additional_prompt
  if additional_prompt then
    full_prompt =
      context._99.prompts.prompts.prompt(additional_prompt, full_prompt)

    local rules = Agents.find_rules(context._99.rules, additional_prompt)
    context:add_agent_rules(rules)
  end

  local additional_rules = opts.additional_rules
  if additional_rules then
    context:add_agent_rules(additional_rules)
  end

  request:add_prompt_content(full_prompt)
  top_status:start()
  bottom_status:start()
  request:start({
    on_complete = function(status, response)
      vim.schedule(clean_up)
      if status == "cancelled" then
        logger:debug("request cancelled for visual selection, removing marks")
      elseif status == "failed" then
        logger:error(
          "request failed for visual_selection",
          "error response",
          response or "no response provided"
        )
      elseif status == "success" then
        local valid = top_mark:is_valid() and bottom_mark:is_valid()
        if not valid then
          logger:fatal(
            -- luacheck: ignore 631
            "the original visual_selection has been destroyed.  You cannot delete the original visual selection during a request"
          )
          return
        end

        local new_range = Range.from_marks(top_mark, bottom_mark)
        local lines = vim.split(response, "\n")

        --- HACK: i am adding a new line here because above range will add a mark to the line above.
        --- that way this appears to be added to "the same line" as the visual selection was
        --- originally take from
        table.insert(lines, 1, "")

        new_range:replace_text(lines)

        Observers.emit_change({
          context = context,
          start_line = new_range.start.row,
          operation = Observers.Operation.VISUAL,
          prompt = opts.additional_prompt,
        })
      end
    end,
    on_stdout = function(line)
      if display_ai_status then
        top_status:push(line)
      end
    end,
    on_stderr = function(line)
      logger:debug("visual_selection#on_stderr received", "line", line)
    end,
  })
end

return over_range
