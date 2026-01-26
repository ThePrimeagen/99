--- Message encoding helpers for ACP JSON-RPC protocol
local M = {}

--- Build initialize request for ACP protocol
--- @return table JSON-RPC initialize message
function M.initialize_request()
  return {
    jsonrpc = "2.0",
    id = 1,
    method = "initialize",
    params = {
      protocolVersion = 1,
      clientCapabilities = {
        fs = {
          readTextFile = true,
          writeTextFile = true,
        },
        terminal = true,
      },
      clientInfo = {
        name = "99.nvim",
        version = "0.1.0",
      },
    },
  }
end

--- Build session/new request
--- @param cwd string Current working directory
--- @param model string|nil Model ID to use for this session
--- @return table JSON-RPC request
function M.session_new_request(cwd, model)
  local params = {
    cwd = cwd or vim.fn.getcwd(),
    mcpServers = {},
  }

  if model then
    params.modelId = model
    params._meta = {
      modelId = model,
    }
  end

  return {
    jsonrpc = "2.0",
    method = "session/new",
    params = params,
  }
end

--- Build session/set_model request (OpenCode extension)
--- @param session_id string Session identifier
--- @param model_id string Model ID to switch to
--- @return table JSON-RPC request
function M.session_set_model_request(session_id, model_id)
  return {
    jsonrpc = "2.0",
    method = "session/set_model",
    params = {
      sessionId = session_id,
      modelId = model_id,
    },
  }
end

--- Build session/prompt request with content blocks
--- @param session_id string Session identifier
--- @param query string User prompt/query
--- @param context _99.RequestContext Request context with ai_context and tmp_file
--- @return table JSON-RPC request
function M.session_prompt_request(session_id, query, context)
  local content_blocks = {}

  for _, ctx in ipairs(context.ai_context) do
    table.insert(content_blocks, {
      type = "text",
      text = ctx,
    })
  end

  local full_query = query .. "\n\nWrite your response to: " .. context.tmp_file
  table.insert(content_blocks, {
    type = "text",
    text = full_query,
  })

  return {
    jsonrpc = "2.0",
    method = "session/prompt",
    params = {
      sessionId = session_id,
      prompt = content_blocks,
    },
  }
end

--- Build session/cancel notification
--- @param session_id string Session identifier to cancel
--- @return table JSON-RPC notification
function M.session_cancel_notification(session_id)
  return {
    jsonrpc = "2.0",
    method = "session/cancel",
    params = {
      sessionId = session_id,
    },
  }
end

return M
