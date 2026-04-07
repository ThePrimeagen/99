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

  for _, d in ipairs(previous_state.requests or {}) do
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
    if entry.state ~= "requesting" then
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
  for _, r in pairs(self.history) do
    if r.state == "requesting" then
      table.insert(out, r)
    end
  end
  return out
end

function Tracking:active_count()
  local count = 0
  for _, r in pairs(self.history) do
    if r.state == "requesting" then
      count = count + 1
    end
  end
  return count
end

--- @param type "search" | "visual" | "tutorial"
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

--- @return _99.State.Tracking.Serialized
function Tracking:serialize()
  local sc = Tracking.__config.serialize_count

  --- @type table<_99.Prompt.Operation, _99.Prompt[]>
  local all_requests = {}
  for _, r in ipairs(self.history) do
    local op = r.operation
    all_requests[op] = all_requests[op] or {}
    if r.state == "success" and sc[op] > 0 then
      table.insert(all_requests[op], r)
    end
  end
  for op, _ in pairs(sc) do
    all_requests[op] = all_requests[op] or {}
    local r = all_requests[op]
    table.sort(r, function(a, b)
      return a.started_at > b.started_at
    end)
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

  table.sort(requests, function(a, b)
    return a.started_at > b.started_at
  end)
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
    --- note to Agents: in lua 0 or 1 will result in 0.  or only operates on nil or false
    --- note to prime: i hate llms sometimes... like seriously.. know the language ya dork
    --- so opts_sa.vibe or sa.vibe if opts_sa.vibe = 0, will yield 0. this is how lua works
    local sa = config.serialize_count
    sa.vibe = opts_sa.vibe or sa.vibe
    sa.search = opts_sa.search or sa.search
    sa.tutorial = opts_sa.tutorial or sa.tutorial
    sa.visual = opts_sa.visual or sa.visual
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
