local M = {}

function M.next_frame()
    local next = false
    vim.schedule(function()
        next = true
    end)

    vim.wait(1000, function()
        return next
    end)
end

M.created_files = {}

--- @class _99.test.ProviderRequest
--- @field query string
--- @field request _99.Request
--- @field observer _99.ProviderObserver?
--- @field logger _99.Logger

--- @class _99.test.Provider : _99.Provider
--- @field request _99.test.ProviderRequest?
local TestProvider = {}
TestProvider.__index = TestProvider

function TestProvider.new()
    return setmetatable({}, TestProvider)
end

--- @param query string
---@param request _99.Request
---@param observer _99.ProviderObserver?
function TestProvider:make_request(query, request, observer)
    local logger = request.context.logger:set_area("TestProvider")
    logger:debug("make_request", "tmp_file", request.context.tmp_file)
    self.request = {
        query = query,
        request = request,
        observer = observer,
        logger = logger,
    }
end

--- @param status _99.Request.ResponseState
--- @param result string
function TestProvider:resolve(status, result)
    assert(self.request, "you cannot call resolve until make_request is called")
    local obs = self.request.observer
    if obs then
        --- to match the behavior expected from the OpenCodeProvider
        if self.request.request:is_cancelled() then
            obs.on_complete("cancelled", result)
        else
            obs.on_complete(status, result)
        end
    end
    self.request = nil
end

--- @param line string
function TestProvider:stdout(line)
    assert(self.request, "you cannot call stdout until make_request is called")
    local obs = self.request.observer
    if obs then
        obs.on_stdout(line)
    end
end

--- @param line string
function TestProvider:stderr(line)
    assert(self.request, "you cannot call stderr until make_request is called")
    local obs = self.request.observer
    if obs then
        obs.on_stderr(line)
    end
end

M.TestProvider = TestProvider

function M.clean_files()
    for _, bufnr in ipairs(M.created_files) do
        vim.api.nvim_buf_delete(bufnr, { force = true })
    end
    M.created_files = {}
end

---@param contents string[]
---@param file_type string?
---@param row number?
---@param col number?
function M.create_file(contents, file_type, row, col)
    assert(type(contents) == "table", "contents must be a table of strings")
    file_type = file_type or "lua"
    local bufnr = vim.api.nvim_create_buf(false, false)

    vim.api.nvim_set_current_buf(bufnr)
    vim.bo[bufnr].ft = file_type
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, contents)
    vim.api.nvim_win_set_cursor(0, { row or 1, col or 0 })

    table.insert(M.created_files, bufnr)
    return bufnr
end

--- Assert that the request query contains expected content in a specific XML section
--- @param query string
--- @param section string  -- e.g., "FunctionDocumentation"
--- @param expected_content string
function M.assert_section_contains(query, section, expected_content)
    local pattern = "<" .. section .. ">(.-)</" .. section .. ">"
    local content = query:match(pattern)
    assert(content ~= nil, "Section <" .. section .. "> not found in query")
    assert(
        content:find(expected_content, 1, true) ~= nil,
        "Expected '"
            .. expected_content
            .. "' in <"
            .. section
            .. ">, got: "
            .. content
    )
end

--- Assert that a section exists in the query
--- @param query string
--- @param section string
function M.assert_section_exists(query, section)
    local pattern = "<" .. section .. ">"
    assert(query:match(pattern) ~= nil, "Section <" .. section .. "> not found")
end

--- Assert that a section does NOT exist in the query
--- @param query string
--- @param section string
function M.assert_section_not_exists(query, section)
    local pattern = "<" .. section .. ">"
    assert(
        query:match(pattern) == nil,
        "Section <" .. section .. "> should not exist"
    )
end

return M
