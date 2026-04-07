--- TODO: I need to refactor a lot of this file
--- it really sucks
local Agents = require("99.extensions.agents")
local Point = require("99.geo").Point

local BASE = 100
local LEGEND = 200

--- @class _99.window.Module
--- @field active_windows _99.window.Window[]
local M = {
  active_windows = {},
}

local nsid = vim.api.nvim_create_namespace("99.window.error")
local legend_nsid = vim.api.nvim_create_namespace("99.window.legend")
local win_valid = vim.api.nvim_win_is_valid
local buf_valid = vim.api.nvim_buf_is_valid

--- @class _99.window.Config
--- @field width number
--- @field height number
--- @field row number?
--- @field col number?
--- @field anchor string?
--- @field border nil | string | string[]
--- @field zindex number?
--- @field relative string?
--- @field title string

--- @class _99.window.Window
--- @field config _99.window.Config
--- @field win_id number
--- @field buf_id number
--- @field type "capture_input" | "status"

--- @class _99.window.SplitWindow
--- @field win number
--- @field buffer number

--- @param lines string[]
--- @return string[]
local function ensure_no_new_lines(lines)
  local display_lines = {}
  for _, line in ipairs(lines) do
    local split_lines = vim.split(line, "\n")
    for _, clean_line in ipairs(split_lines) do
      table.insert(display_lines, clean_line)
    end
  end
  return display_lines
end

--- @return number
--- @return number
local function get_ui_dimensions()
  local ui = vim.api.nvim_list_uis()[1]
  return ui.width, ui.height
end

--- @return _99.window.Config
local function create_window_top_config()
  local width, _ = get_ui_dimensions()
  return {
    width = width - 2,
    height = 3,
    anchor = "NE",
    border = "rounded",
  }
end

--- @param zindex number
--- @param title string
--- @return _99.window.Config
local function create_transparent_top_right_config(zindex, title)
  local width, _ = get_ui_dimensions()
  return {
    width = math.floor(width / 3),
    height = 3,
    col = width,
    anchor = "NE",
    border = nil,
    zindex = zindex,
    title = title,
  }
end

--- @return _99.window.Config
local function create_window_full_screen()
  local width, height = get_ui_dimensions()
  return {
    width = width - 2,
    height = height - 2,
    anchor = "NE",
    border = "rounded",
  }
end

--- @param win _99.window.Window
---@param offset_bottom number | nil
--- @return _99.window.Config
---@diagnostic disable-next-line
local function create_window_inside(win, offset_bottom)
  local config = win.config
  offset_bottom = offset_bottom or 0
  return {
    width = config.width - 2,
    height = 1,
    row = config.row + config.height - offset_bottom,
    col = config.col + 1,
    anchor = config.anchor,
  }
end

--- @return _99.window.Config
local function create_centered_window()
  local width, height = get_ui_dimensions()
  local win_width = math.floor(width * 2 / 3)
  local win_height = math.floor(height / 3)
  return {
    width = win_width,
    height = win_height,
    row = math.floor((height - win_height) / 2),
    col = math.floor((width - win_width) / 2),
    border = "rounded",
  }
end

--- @param config _99.window.Config
--- @param title string?
local function full_config(config, title)
  return {
    relative = config.relative or "editor",
    width = config.width,
    height = config.height,
    row = config.row or 0,
    col = config.col or 0,
    anchor = config.anchor,
    style = "minimal",
    border = config.border,
    title = title or config.title,
    title_pos = "center",
    zindex = config.zindex or 1,
  }
end

--- @param config _99.window.Config
--- @param title string
--- @param enter boolean
--- @return _99.window.Window
local function create_floating_window(config, title, enter)
  local buf_id = vim.api.nvim_create_buf(false, true)
  local win_id =
    vim.api.nvim_open_win(buf_id, enter, full_config(config, title))
  local window = {
    config = config,
    win_id = win_id,
    buf_id = buf_id,
  }
  vim.wo[win_id].wrap = true

  table.insert(M.active_windows, window)
  return window
end

--- @param window _99.window.Window
local function highlight_error(window)
  local line_count = vim.api.nvim_buf_line_count(window.buf_id)

  if line_count > 0 then
    vim.api.nvim_buf_set_extmark(window.buf_id, nsid, 0, 0, {
      end_row = 1,
      hl_group = "Normal",
      hl_eol = true,
    })
  end

  if line_count > 1 then
    vim.api.nvim_buf_set_extmark(window.buf_id, nsid, 1, 0, {
      end_row = line_count,
      hl_group = "ErrorMsg",
      hl_eol = true,
    })
  end
end

--- @param error_text string
--- @return _99.window.Window
function M.display_error(error_text)
  local window =
    create_floating_window(create_window_top_config(), " 99 Error ", false)
  local lines = vim.split(error_text, "\n")

  table.insert(lines, 1, "")
  table.insert(
    lines,
    1,
    "99: Fatal operational error encountered (error logs may have more in-depth information)"
  )

  vim.api.nvim_buf_set_lines(window.buf_id, 0, -1, false, lines)
  highlight_error(window)
  return window
end

--- @param window _99.window.Window
local function window_close(window)
  if win_valid(window.win_id) then
    vim.api.nvim_win_close(window.win_id, true)
  end
  if buf_valid(window.buf_id) then
    vim.api.nvim_buf_delete(window.buf_id, { force = true })
  end
end

--- @param window _99.window.Window
--- @return boolean
function M.valid(window)
  return win_valid(window.win_id) and buf_valid(window.buf_id)
end

--- @param text string
function M.display_cancellation_message(text)
  local config = create_transparent_top_right_config(100, " 99 Cancelled ")
  local window = create_floating_window(config, " 99 Cancelled ", false)
  local lines = vim.split(text, "\n")

  vim.api.nvim_buf_set_lines(window.buf_id, 0, -1, false, lines)

  vim.api.nvim_buf_set_extmark(window.buf_id, nsid, 0, 0, {
    end_row = vim.api.nvim_buf_line_count(window.buf_id),
    hl_group = "WarningMsg",
    hl_eol = true,
  })

  vim.defer_fn(function()
    if win_valid(window.win_id) then
      M.clear_active_popups()
    end
  end, 5000)

  return window
end

--- TODO: i dont like how the other interfaces have text being passed in
--- but this one is lines.  probably need to revisit this
--- @param lines string[]
function M.display_full_screen_message(lines)
  --- TODO: i really dislike that i am closing and opening windows
  --- i think it would be better to perserve the one that is already open
  --- but i just want this to work and then later... ohh much later, ill fix
  --- this basic nonsense
  M.clear_active_popups()
  local window =
    create_floating_window(create_window_full_screen(), " 99 ", true)
  local display_lines = ensure_no_new_lines(lines)
  vim.api.nvim_buf_set_lines(window.buf_id, 0, -1, false, display_lines)
end

--- @return _99.window.Window
--- @return _99.window.Config
function M.create_centered_window()
  M.clear_active_popups()
  local config = create_centered_window()
  local window = create_floating_window(config, " 99 ", true)
  return window, config
end

--- @param message string[]
function M.display_centered_message(message)
  M.clear_active_popups()
  local config = create_centered_window()
  local window = create_floating_window(config, " 99 ", true)
  local display_lines = ensure_no_new_lines(message)

  vim.api.nvim_buf_set_lines(window.buf_id, 0, -1, false, display_lines)

  return window
end

--- @param win _99.window.Window
--- @param name string
local function set_defaul_win_options(win, name)
  vim.api.nvim_buf_set_name(win.buf_id, name)
  vim.wo[win.win_id].number = true
  vim.bo[win.buf_id].filetype = "99"
  vim.bo[win.buf_id].buftype = "acwrite"
  vim.bo[win.buf_id].bufhidden = "wipe"
  vim.bo[win.buf_id].swapfile = false
end

--- @param win _99.window.Window
--- @param rules _99.Agents.Rules?
--- @param group any
local function highlight_rules_found(win, rules, group)
  if rules == nil then
    return
  end

  local rule_nsid = vim.api.nvim_create_namespace("99.window.rules")
  local function check_and_highlight_rules()
    if not win_valid(win.win_id) then
      return
    end

    vim.api.nvim_buf_clear_namespace(win.buf_id, rule_nsid, 0, -1)

    local lines = vim.api.nvim_buf_get_lines(win.buf_id, 0, -1, false)
    local buffer_text = table.concat(lines, "\n")
    local rules_and_names = Agents.by_name(rules, buffer_text)
    local found_rules = rules_and_names.rules
    if not found_rules or vim.tbl_isempty(found_rules) then
      return
    end

    local rule_names = rules_and_names.names
    for line_num, line in ipairs(lines) do
      for _, rule_name in ipairs(rule_names) do
        local start_col = 0
        while true do
          local found_start, found_end =
            string.find(line, rule_name, start_col + 1, true)
          if not found_start then
            break
          end

          -- Highlight the matched rule
          vim.api.nvim_buf_set_extmark(
            win.buf_id,
            rule_nsid,
            line_num - 1,
            found_start - 1,
            {
              end_col = found_end,
              hl_group = "Search",
            }
          )

          start_col = found_end --[[ @as number ]]
        end
      end
    end
  end

  vim.api.nvim_create_autocmd("InsertLeave", {
    group = group,
    buffer = win.buf_id,
    callback = function()
      check_and_highlight_rules()
    end,
  })

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = group,
    buffer = win.buf_id,
    callback = function()
      check_and_highlight_rules()
    end,
  })
end

--- @alias _99.window.KeyMap table<string, string>
--- @class _99.window.CaptureInputOpts
--- @field cb fun(success: boolean, result: string): nil
--- @field on_load? fun(): nil
--- @field content? string[]
--- @field rules? _99.Agents.Rules
--- @field keymap? _99.window.KeyMap

--- @param keymap _99.window.KeyMap
--- @param width number
--- @return string[]
local function keymap_lines(keymap, width)
  local keys = vim.tbl_keys(keymap)
  table.sort(keys)

  local lines = { "" }
  for _, key in ipairs(keys) do
    local current = lines[#lines]
    local legend = string.format("%s=%s", key, keymap[key])
    if #current + #legend + 1 > width then
      table.insert(lines, legend)
    else
      lines[#lines] = string.format("%s %s", current, legend)
    end
  end

  return lines
end

--- @param win _99.window.Window
--- @param keymap _99.window.KeyMap
local function create_window_legend(win, keymap)
  local lines = keymap_lines(keymap, win.config.width - 2)
  local keyoffset = #lines
  local keymap_config = create_window_inside(win, keyoffset - 1)
  keymap_config.height = keyoffset
  keymap_config.zindex = LEGEND

  local keymap_win = create_floating_window(keymap_config, "", false)
  vim.bo[keymap_win.buf_id].buftype = "nofile"
  vim.bo[keymap_win.buf_id].bufhidden = "wipe"
  vim.bo[keymap_win.buf_id].swapfile = false
  vim.bo[keymap_win.buf_id].modifiable = true
  vim.bo[keymap_win.buf_id].readonly = false
  vim.api.nvim_buf_set_lines(keymap_win.buf_id, 0, -1, false, lines)

  vim.api.nvim_buf_clear_namespace(keymap_win.buf_id, legend_nsid, 0, -1)
  for line_num, line in ipairs(lines) do
    local start_col = 1
    while true do
      local found_start, found_end = string.find(line, "%S+=%S+", start_col)
      if not found_start then
        break
      end

      local legend = string.sub(line, found_start, found_end)
      local separator = string.find(legend, "=", 1, true)
      if separator and separator > 1 and separator < #legend then
        local key_start = found_start - 1
        local key_end = found_start + separator - 2
        local value_start = found_start + separator - 1

        vim.api.nvim_buf_set_extmark(
          keymap_win.buf_id,
          legend_nsid,
          line_num - 1,
          key_start,
          {
            end_col = key_end,
            hl_group = "WarningMsg",
          }
        )

        vim.api.nvim_buf_set_extmark(
          keymap_win.buf_id,
          legend_nsid,
          line_num - 1,
          value_start,
          {
            end_col = found_end,
            hl_group = "Comment",
          }
        )
      end

      start_col = found_end + 1
    end
  end

  vim.bo[keymap_win.buf_id].modifiable = false
  vim.bo[keymap_win.buf_id].readonly = true

  -- one for the border, one for the extra space, and then keymap count
  vim.wo[win.win_id].scrolloff = keyoffset + 2
end

--- @param name string
--- @param opts _99.window.CaptureInputOpts
function M.capture_input(name, opts)
  M.clear_active_popups()

  local config = create_centered_window()
  local win =
    create_floating_window(config, string.format(" 99 %s ", name), true)
  win.type = "capture_input"

  set_defaul_win_options(win, "99-prompt")
  vim.api.nvim_set_current_win(win.win_id)

  opts.keymap = opts.keymap or {}
  opts.keymap.q = "cancel"
  create_window_legend(win, opts.keymap)

  local group = vim.api.nvim_create_augroup(
    "99_present_prompt_" .. win.buf_id,
    { clear = true }
  )

  highlight_rules_found(win, opts.rules, group)
  vim.api.nvim_create_autocmd("BufLeave", {
    group = group,
    buffer = win.buf_id,
    callback = function()
      if win_valid(win.win_id) then
        vim.api.nvim_set_current_win(win.win_id)
      else
        M.clear_active_popups()
      end
    end,
  })

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    group = group,
    buffer = win.buf_id,
    callback = function()
      if not win_valid(win.win_id) then
        return
      end
      local lines = vim.api.nvim_buf_get_lines(win.buf_id, 0, -1, false)
      local result = table.concat(lines, "\n")
      M.clear_active_popups()
      opts.cb(true, result)
    end,
  })

  vim.api.nvim_create_autocmd("BufUnload", {
    group = group,
    buffer = win.buf_id,
    callback = function()
      if not win_valid(win.win_id) then
        return
      end
      vim.api.nvim_del_augroup_by_id(group)
    end,
  })

  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    pattern = tostring(win.win_id),
    callback = function()
      if not win_valid(win.win_id) then
        return
      end
      M.clear_active_popups()
      opts.cb(false, "")
    end,
  })

  vim.keymap.set("n", "q", function()
    M.clear_active_popups()
    opts.cb(false, "")
  end, { buffer = win.buf_id, nowait = true })

  if opts.on_load then
    vim.schedule(opts.on_load)
  end

  if opts.content then
    vim.api.nvim_buf_set_lines(
      win.buf_id,
      0,
      -1,
      false,
      ensure_no_new_lines(opts.content)
    )
  end

  return win
end

--- @param name string
--- @param opts _99.window.CaptureInputOpts
function M.capture_select_input(name, opts)
  local win
  win = M.capture_input(name, {
    content = opts.content,
    rules = opts.rules,
    keymap = opts.keymap,
    cb = function(success, result)
      if not success then
        opts.cb(false, result)
      end
    end,
    on_load = function()
      vim.bo[win.buf_id].modifiable = false
      vim.bo[win.buf_id].readonly = true
      if opts.on_load then
        opts.on_load()
      end
    end,
  })

  vim.keymap.set("n", "<CR>", function()
    if not win_valid(win.win_id) then
      return
    end

    local point = Point:from_cursor()
    local line = point:line(win.buf_id)
    M.clear_active_popups()
    opts.cb(true, line or "")
  end, { buffer = win.buf_id, nowait = true })
end

function M.clear_active_popups()
  for _, window in ipairs(M.active_windows) do
    window_close(window)
  end
  M.active_windows = {}
end

--- @return _99.window.Window
function M.status_window()
  M.clear_active_popups()
  local config = create_transparent_top_right_config(100, " 99 - Status ")
  local window = create_floating_window(config, " 99 - Status ", false)
  window.type = "status"
  return window
end

--- @param win _99.window.Window
--- @param width number
--- @param height number
function M.resize(win, width, height)
  if win.config.height == height then
    return
  end
  assert(M.is_active_window(win), "you cannot pass in an inactive window")
  win.config.height = height
  win.config.width = width
  vim.api.nvim_win_set_config(win.win_id, full_config(win.config))
end

--- @return boolean
function M.has_active_windows()
  return #M.active_windows > 0
end

--- @return boolean
function M.has_active_status_window()
  local has = false
  for _, w in ipairs(M.active_windows) do
    if w.type == "status" then
      has = true
      break
    end
  end
  return has
end

--- @return boolean
function M.has_active_window()
  for _, w in ipairs(M.active_windows) do
    if
      w.type == "capture_input"
      and win_valid(w.win_id)
      and buf_valid(w.buf_id)
    then
      return true
    end
  end
  return false
end

function M.refresh_active_windows()
  --- @type _99.window.Window[]
  local actives = {}
  for _, w in ipairs(M.active_windows) do
    if M.valid(w) then
      table.insert(actives, w)
    end
  end
  M.active_windows = actives
end

--- @param win _99.window.Window
--- @return boolean
function M.is_active_window(win)
  for _, active_win in ipairs(M.active_windows) do
    if active_win.win_id == win.win_id then
      return true
    end
  end
  return false
end

--- @param win _99.window.Window
function M.close(win)
  if not M.valid(win) then
    return
  end
  window_close(win)
  for i, active_win in ipairs(M.active_windows) do
    if active_win.win_id == win.win_id then
      table.remove(M.active_windows, i)
      break
    end
  end
end

--- @class _99.window.SplitWindowOpts
--- @field split_direction "vertical" | "horizontal"
--- @field window_opts table<string, any>
--- @field filetype string | nil

--- @param content string[]
---@param buffer number | nil
---@param opts _99.window.SplitWindowOpts | nil
--- @return _99.window.SplitWindow
function M.create_split(content, buffer, opts)
  opts = opts or { split_direction = "vertical" }
  opts.window_opts = opts.window_opts or {}
  opts.split_direction = opts.split_direction or "vertical"
  opts.filetype = opts.filetype or "markdown"

  local split_direction = opts.split_direction
  assert(
    split_direction == "vertical" or split_direction == "horizontal",
    "unknown split direction: "
      .. vim.inspect(split_direction)
      .. " : must be horizontal or vertical"
  )

  if split_direction == "horizontal" then
    vim.cmd("split")
  else
    vim.cmd("vsplit")
  end

  local win_id = vim.api.nvim_get_current_win()
  local buf_id = buffer
  if not buf_id or not buf_valid(buf_id) then
    buf_id = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_buf_set_lines(
      buf_id,
      0,
      -1,
      false,
      ensure_no_new_lines(content)
    )
  end

  vim.api.nvim_win_set_buf(win_id, buf_id)
  vim.bo[buf_id].filetype = opts.filetype
  for option, value in pairs(opts.window_opts) do
    vim.wo[win_id][option] = value
  end
  return {
    win = win_id,
    buffer = buf_id,
  }
end
return M
