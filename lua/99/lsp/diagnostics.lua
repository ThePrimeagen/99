local M = {}

local geo = require("99.geo")
local Point = geo.Point

--- @class _99.Lsp.Diagnostic
--- @field bufnr number Buffer number
--- @field lnum number Starting line (0-based)
--- @field end_lnum number? Ending line (0-based)
--- @field col number Starting column (0-based)
--- @field end_col number? Ending column (0-based)
--- @field severity number 1=ERROR, 2=WARN, 3=INFO, 4=HINT
--- @field message string Diagnostic message
--- @field source string? Source of diagnostic (e.g., "lua_ls")
--- @field code string|number? Diagnostic code

--- Severity level names
M.severity = vim.diagnostic.severity

--- @type table<number, string>
M.severity_names = {
    [vim.diagnostic.severity.ERROR] = "ERROR",
    [vim.diagnostic.severity.WARN] = "WARN",
    [vim.diagnostic.severity.INFO] = "INFO",
    [vim.diagnostic.severity.HINT] = "HINT",
}

--- Get diagnostics for a buffer
--- @param bufnr number Buffer number
--- @return _99.Lsp.Diagnostic[]
function M.get_diagnostics(bufnr)
    return vim.diagnostic.get(bufnr)
end

--- Filter diagnostics by minimum severity
--- @param diags _99.Lsp.Diagnostic[] Diagnostics to filter
--- @param min_severity number Minimum severity level (1=ERROR is most severe)
--- @return _99.Lsp.Diagnostic[] Filtered diagnostics
function M.filter_by_severity(diags, min_severity)
    local result = {}
    for _, diag in ipairs(diags) do
        if diag.severity <= min_severity then
            table.insert(result, diag)
        end
    end
    return result
end

--- Filter diagnostics to those within a range
--- @param diags _99.Lsp.Diagnostic[] Diagnostics to filter
--- @param range _99.Range Range to filter by
--- @return _99.Lsp.Diagnostic[] Filtered diagnostics
function M.filter_by_range(diags, range)
    local result = {}
    for _, diag in ipairs(diags) do
        local diag_point = Point:from_lsp_position(diag.lnum, diag.col)
        if range:contains(diag_point) then
            table.insert(result, diag)
        end
    end
    return result
end

--- Convert diagnostic position to Point
--- @param diag _99.Lsp.Diagnostic
--- @return _99.Point
function M.convert_to_point(diag)
    return Point:from_lsp_position(diag.lnum, diag.col)
end

--- Format a single diagnostic
--- @param diag _99.Lsp.Diagnostic
--- @return string Formatted diagnostic
function M.format_diagnostic(diag)
    local severity_name = M.severity_names[diag.severity] or "UNKNOWN"
    local location = string.format("%d:%d", diag.lnum + 1, diag.col + 1)

    local parts = { severity_name, location, diag.message }

    if diag.source then
        table.insert(parts, 1, "[" .. diag.source .. "]")
    end

    if diag.code then
        table.insert(parts, "(" .. tostring(diag.code) .. ")")
    end

    return table.concat(parts, " ")
end

--- Format multiple diagnostics
--- @param diags _99.Lsp.Diagnostic[]
--- @return string Formatted diagnostics
function M.format_diagnostics(diags)
    if not diags or #diags == 0 then
        return ""
    end

    local lines = {}
    for _, diag in ipairs(diags) do
        table.insert(lines, M.format_diagnostic(diag))
    end
    return table.concat(lines, "\n")
end

--- Get diagnostics for a buffer filtered by severity and optionally range
--- @param bufnr number Buffer number
--- @param opts { min_severity: number?, range: _99.Range? }? Options
--- @return _99.Lsp.Diagnostic[]
function M.get_filtered_diagnostics(bufnr, opts)
    opts = opts or {}
    local diags = M.get_diagnostics(bufnr)

    if opts.min_severity then
        diags = M.filter_by_severity(diags, opts.min_severity)
    end

    if opts.range then
        diags = M.filter_by_range(diags, opts.range)
    end

    return diags
end

--- Get only errors and warnings (most relevant for context)
--- @param bufnr number Buffer number
--- @param range _99.Range? Optional range to filter
--- @return _99.Lsp.Diagnostic[]
function M.get_errors_and_warnings(bufnr, range)
    return M.get_filtered_diagnostics(bufnr, {
        min_severity = vim.diagnostic.severity.WARN,
        range = range,
    })
end

--- Format diagnostics for context output
--- @param diags _99.Lsp.Diagnostic[]
--- @return string
function M.format_for_context(diags)
    if not diags or #diags == 0 then
        return ""
    end

    local parts = { "## Diagnostics" }
    for _, diag in ipairs(diags) do
        table.insert(parts, "- " .. M.format_diagnostic(diag))
    end
    return table.concat(parts, "\n")
end

--- Group diagnostics by severity
--- @param diags _99.Lsp.Diagnostic[]
--- @return table<number, _99.Lsp.Diagnostic[]> Grouped by severity
function M.group_by_severity(diags)
    local groups = {}
    for _, diag in ipairs(diags) do
        local sev = diag.severity
        if not groups[sev] then
            groups[sev] = {}
        end
        table.insert(groups[sev], diag)
    end
    return groups
end

--- Get diagnostic counts by severity
--- @param diags _99.Lsp.Diagnostic[]
--- @return { errors: number, warnings: number, info: number, hints: number }
function M.get_counts(diags)
    local counts = { errors = 0, warnings = 0, info = 0, hints = 0 }
    for _, diag in ipairs(diags) do
        if diag.severity == vim.diagnostic.severity.ERROR then
            counts.errors = counts.errors + 1
        elseif diag.severity == vim.diagnostic.severity.WARN then
            counts.warnings = counts.warnings + 1
        elseif diag.severity == vim.diagnostic.severity.INFO then
            counts.info = counts.info + 1
        elseif diag.severity == vim.diagnostic.severity.HINT then
            counts.hints = counts.hints + 1
        end
    end
    return counts
end

return M
