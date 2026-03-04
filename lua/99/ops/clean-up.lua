local M = {}

--- @alias _99.Providers.on_complete fun(status: _99.Prompt.EndingState, response: string): nil
--- @class _99.Providers.PartialObserver
--- @field on_complete _99.Providers.on_complete
--- @field on_stdout? fun(line: string): nil
--- @field on_stderr? fun(line: string): nil
--- @field on_start? fun(): nil

--- @param context _99.Prompt
--- @param obs_or_fn _99.Providers.PartialObserver | _99.Providers.on_complete
--- @return _99.Providers.Observer
M.make_observer = function(context, obs_or_fn)
  --- @type _99.Providers.PartialObserver
  local obs = type(obs_or_fn) == "table" and obs_or_fn
    or {
      on_complete = obs_or_fn,
    }
  return {
    on_start = function()
      if obs.on_start then
        obs.on_start()
      end
    end,
    on_complete = function(status, res)
      pcall(obs.on_complete, status, res)
      if status == "failed" then
        vim.notify(
          "99: provider failed\n" .. (res or "unknown error"),
          vim.log.levels.ERROR
        )
      end
      vim.schedule(function()
        context:stop()
        context._99:sync()
      end)
    end,
    on_stderr = function(line)
      if obs.on_stderr then
        obs.on_stderr(line)
      end
    end,
    on_stdout = function(line)
      if obs.on_stdout then
        obs.on_stdout(line)
      end
    end,
  } --[[@as _99.Providers.Observer ]]
end

---@param clean_up_fn fun(): nil
---@return fun(): nil
M.make_clean_up = function(clean_up_fn)
  local called = false
  local function clean_up()
    if called then
      return
    end
    called = true
    clean_up_fn()
  end
  return clean_up
end

return M
