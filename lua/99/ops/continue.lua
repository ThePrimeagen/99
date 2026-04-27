local Prompt = require("99.prompt")

local M = {}

--- Default number of recent turns to include in continuation prompt
local DEFAULT_CONTINUE_HISTORY_LIMIT = 3

--- Mapping of supported operations to their context creators and dispatch functions
--- @type table<
---   _99.Prompt.Operation,
---   {create: fun(state: _99.State): _99.Prompt, dispatch: fun(ops: table, context: _99.Prompt, opts: table): nil}
--- >
local OPERATION_MAP = {
  vibe = {
    create = function(state)
      return Prompt.vibe(state)
    end,
    dispatch = function(ops, context, opts)
      ops.vibe(context, opts)
    end,
  },
  search = {
    create = function(state)
      return Prompt.search(state)
    end,
    dispatch = function(ops, context, opts)
      ops.search(context, opts)
    end,
  },
  tutorial = {
    create = function(state)
      return Prompt.tutorial(state)
    end,
    dispatch = function(ops, context, opts)
      ops.tutorial(context, opts)
    end,
  },
  visual = {
    create = function(state)
      return Prompt.visual(state)
    end,
    dispatch = function(ops, context, opts)
      ops.over_range(context, opts)
    end,
  },
}

--- @param state _99.State
--- @param source _99.Prompt
--- @param follow_up string
--- @param op_config table
--- @return _99.Prompt
local function create_context_for_source(state, source, follow_up, op_config)
  local context = op_config.create(state)
  context.session_id = source.session_id
  context.turns = vim.deepcopy(source.turns or {})
  context.user_prompt = follow_up
  return context
end

--- @param state _99.State
--- @param source _99.Prompt
--- @param follow_up string
--- @return string
local function build_follow_up_prompt(state, source, follow_up)
  local turns = source:recent_turns(DEFAULT_CONTINUE_HISTORY_LIMIT)
  return state.prompts.prompts.continue_chat(source.operation, turns, follow_up)
end

--- @param state _99.State
--- @param ops table
--- @param source _99.Prompt
--- @param opts _99.ops.ContinueOpts
--- @return _99.TraceID | nil
function M.run(state, ops, source, opts)
  if not source then
    vim.notify("99.continue requires a source prompt", vim.log.levels.WARN)
    return nil
  end

  opts = opts or {}
  local follow_up = opts.additional_prompt
  if not follow_up or follow_up == "" then
    vim.notify("99.continue requires a follow-up prompt", vim.log.levels.WARN)
    return nil
  end

  if not source.turns or #source.turns == 0 then
    vim.notify(
      "99.continue could not find conversation turns",
      vim.log.levels.WARN
    )
    return nil
  end

  -- Visual continuation requires a fresh visual selection
  if source.operation == "visual" then
    local mode = vim.fn.mode()
    if mode ~= "v" and mode ~= "V" and mode ~= "\22" then
      vim.notify(
        "99.continue visual requests require a fresh visual selection",
        vim.log.levels.WARN
      )
      return nil
    end
  end

  local op_config = OPERATION_MAP[source.operation]
  if not op_config then
    vim.notify(
      "99.continue does not support operation: " .. tostring(source.operation),
      vim.log.levels.WARN
    )
    return nil
  end

  local context = create_context_for_source(state, source, follow_up, op_config)

  local continuation_prompt = build_follow_up_prompt(state, source, follow_up)
  local continued_opts = vim.tbl_extend("force", opts, {
    additional_prompt = continuation_prompt,
  })

  op_config.dispatch(ops, context, continued_opts)

  return context.xid
end

return M
