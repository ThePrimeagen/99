local RequestStatus = require("99.ops.request_status")
local Mark = require("99.ops.marks")
local geo = require("99.geo")
local make_prompt = require("99.ops.make-prompt")
local CleanUp = require("99.ops.clean-up")

local make_clean_up = CleanUp.make_clean_up
local make_observer = CleanUp.make_observer

local Range = geo.Range
local Point = geo.Point

--- @param context _99.Prompt
--- @param opts? _99.ops.Opts
local function over_range(context, opts)
  opts = opts or {}
  local logger = context.logger:set_area("visual")

  local data = context:visual_data()
  local range = data.range
  
  local ok_top, top_mark = pcall(Mark.mark_above_range, range)
  local ok_bottom, bottom_mark = pcall(Mark.mark_point, range.buffer, range.end_)

  if not ok_top or not ok_bottom or not top_mark:is_valid() or not bottom_mark:is_valid() then
    logger:fatal(
      "Cannot create marks for visual selection. Buffer may have been modified."
    )
    return
  end

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
  local clean_up = make_clean_up(function()
    top_status:stop()
    bottom_status:stop()
  end)

  local system_cmd = context._99.prompts.prompts.visual_selection(range)
  local prompt, refs = make_prompt(context, system_cmd, opts)

  context:add_prompt_content(prompt)
  context:add_references(refs)
  context:add_clean_up(clean_up)

  top_status:start()
  bottom_status:start()
  context:start_request(make_observer(context, {
    on_complete = function(status, response)
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

        if vim.trim(response) == "" then
          print("response was empty, visual replacement aborted")
          logger:debug("response was empty, visual replacement aborted")
          return
        end

        local new_range = Range.from_marks(top_mark, bottom_mark)
        local lines = vim.split(response, "\n")

        --- HACK: i am adding a new line here because above range will add a mark to the line above.
        --- that way this appears to be added to "the same line" as the visual selection was
        --- originally take from
        table.insert(lines, 1, "")

        new_range:replace_text(lines)
        context._99:sync()
      end
    end,
    on_stdout = function(line)
      if display_ai_status then
        top_status:push(line)
      end
    end,
  }))
end

return over_range
