local Prompt = require("99.prompt")

--- @class _99.State.Tracking.Serialized
--- @field requests _99.Prompt.Serialized[]

--- @class _99.State.Tracking.Config.Options.Counts
--- @field vibe number | nil
--- @field search number | nil
--- @field tutorial number | nil
--- @field visual number | nil
---
--- @class _99.State.Tracking.Config.Options
--- @field serialize_counts _99.State.Tracking.Config.Options.Counts | nil

--- @class _99.State.Tracking.Config
--- @field serialize_counts table<_99.Prompt.Operation, number>

--- @class _99.State.Tracking
--- @docs base
--- @field history _99.Prompt[]
--- @field id_to_request table<number, _99.Prompt>
--- @field setup fun(opts: _99.State.Tracking.Config.Options): nil
local Tracking = {}
Tracking.__index = Tracking

--- @param _99 _99.State
--- @param previous_state _99.State.Tracking.Serialized | nil
--- @return _99.State.Tracking
function Tracking.new(_99, previous_state)
  local tracking = setmetatable({}, Tracking) --[[ @as _99.State.Tracking]]

  tracking.history = {}
  tracking.id_to_request = {}

  if not previous_state then
    return tracking
  end

  local serialized_requests = previous_state.requests or {}
  -- Serialized requests are newest-first for display/storage limits; history is
  -- oldest-first so reverse scans and index tie-breaks remain deterministic.
  for i = #serialized_requests, 1, -1 do
    local d = serialized_requests[i]
    local prompt = Prompt.deserialize(_99, d)
    table.insert(tracking.history, prompt)
    tracking.id_to_request[prompt.xid] = prompt
  end

  return tracking
end

--- @param context _99.Prompt
function Tracking:track(context)
  assert(context:valid(), "context is not valid")
  table.insert(self.history, context)
  self.id_to_request[context.xid] = context
end

--- @return number
function Tracking:completed()
  local count = 0
  for _, entry in ipairs(self.history) do
    if entry:is_completed() or entry:is_cancelled() then
      count = count + 1
    end
  end
  return count
end

function Tracking:clear_history()
  local keep = {}
  for _, entry in ipairs(self.history) do
    if entry.state == "requesting" then
      table.insert(keep, entry)
    else
      self.id_to_request[entry.xid] = nil
    end
  end
  self.history = keep
end

function Tracking:stop_all_requests()
  for _, r in pairs(self:active()) do
    r:stop()
  end
end

--- @return _99.Prompt[]
function Tracking:active()
  local out = {}
  for _, r in ipairs(self.history) do
    if r.state == "requesting" then
      table.insert(out, r)
    end
  end
  return out
end

function Tracking:active_count()
  local count = 0
  for _, r in ipairs(self.history) do
    if r.state == "requesting" then
      count = count + 1
    end
  end
  return count
end

--- @param type "search" | "visual" | "tutorial" | "vibe"
--- @return _99.Prompt[]
function Tracking:request_by_type(type)
  local out = {} --[[ @as _99.Prompt[] ]]
  for _, r in ipairs(self.history) do
    if r.operation == type then
      table.insert(out, r)
    end
  end
  return out
end

--- @return _99.Prompt[]
function Tracking:successful()
  local requests = {}
  for i = #self.history, 1, -1 do
    local request = self.history[i]
    if request.state == "success" then
      table.insert(requests, request)
    end
  end
  return requests
end

--- @param prompt _99.Prompt
--- @return number
local function order_value(prompt)
  return prompt.completed_at or prompt.started_at or 0
end

--- @param candidate _99.Prompt
--- @param candidate_index number
--- @param current _99.Prompt | nil
--- @param current_index number
--- @return boolean
local function is_newer(candidate, candidate_index, current, current_index)
  if not current then
    return true
  end

  local candidate_value = order_value(candidate)
  local current_value = order_value(current)
  if candidate_value ~= current_value then
    return candidate_value > current_value
  end

  return candidate_index > current_index
end

--- Helper to sort newest first while preserving history index as a tie breaker.
--- @param history_index_by_request table<_99.Prompt, number>
--- @return fun(a: _99.Prompt, b: _99.Prompt): boolean
local function newest_first(history_index_by_request)
  return function(a, b)
    local a_value = order_value(a)
    local b_value = order_value(b)
    if a_value ~= b_value then
      return a_value > b_value
    end

    return (history_index_by_request[a] or 0)
      > (history_index_by_request[b] or 0)
  end
end

--- @param type _99.Prompt.Operation | nil
--- @return _99.Prompt | nil
function Tracking:latest_successful(type)
  local latest = nil
  local latest_index = 0

  for i, request in ipairs(self.history) do
    if
      request.state == "success" and (not type or request.operation == type)
    then
      if is_newer(request, i, latest, latest_index) then
        latest = request
        latest_index = i
      end
    end
  end

  return latest
end

--- @return _99.State.Tracking.Serialized
function Tracking:serialize()
  local sc = Tracking.__config.serialize_count

  -- First, dedupe by session_id, keeping only the newest prompt per session
  -- Use completion time (completed_at or started_at) for determining "newest"
  --- @type table<string, _99.Prompt>
  local latest_by_session_id = {}
  --- @type table<_99.Prompt, number>
  local history_index_by_request = {}
  for i, r in ipairs(self.history) do
    history_index_by_request[r] = i
    if r.state == "success" then
      local session_id = r.session_id or tostring(r.xid)
      local existing = latest_by_session_id[session_id]
      local existing_index = existing and history_index_by_request[existing]
        or 0
      if is_newer(r, i, existing, existing_index) then
        latest_by_session_id[session_id] = r
      end
    end
  end

  --- @type table<_99.Prompt.Operation, _99.Prompt[]>
  local all_requests = {}
  for _, r in pairs(latest_by_session_id) do
    local op = r.operation
    local max = sc[op] or 0
    if max > 0 then
      all_requests[op] = all_requests[op] or {}
      table.insert(all_requests[op], r)
    end
  end

  for op, _ in pairs(sc) do
    all_requests[op] = all_requests[op] or {}
    local r = all_requests[op]
    table.sort(r, newest_first(history_index_by_request))
  end

  --- @type _99.Prompt[]
  local requests = {}
  for op, max in pairs(sc) do
    local count = 0
    for _, request in ipairs(all_requests[op] or {}) do
      if count >= max then
        break
      end
      table.insert(requests, request)
      count = count + 1
    end
  end

  table.sort(requests, newest_first(history_index_by_request))
  local serialized = {}
  for _, r in ipairs(requests) do
    table.insert(serialized, r:serialize())
  end

  return {
    requests = serialized,
  }
end

Tracking.__config = {
  serialize_count = {
    vibe = 1,
    search = 1,
    tutorial = 3,
    visual = 0,
  },
}

--- @param opts _99.State.Tracking.Config.Options
function Tracking.setup(opts)
  local config = Tracking.__config
  local opts_sa = opts.serialize_counts
  if opts_sa then
    local sa = config.serialize_count
    if opts_sa.vibe ~= nil then
      sa.vibe = opts_sa.vibe
    end
    if opts_sa.search ~= nil then
      sa.search = opts_sa.search
    end
    if opts_sa.tutorial ~= nil then
      sa.tutorial = opts_sa.tutorial
    end
    if opts_sa.visual ~= nil then
      sa.visual = opts_sa.visual
    end
  end
end

--- @param requests _99.Prompt[]
--- @return string[]
function Tracking.to_selectable_list(requests)
  local str_requests = {}
  for i, r in ipairs(requests) do
    table.insert(str_requests, string.format("%d: %s", i, r:summary()))
  end
  return str_requests
end

return Tracking
