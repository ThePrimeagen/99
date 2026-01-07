--- @class _99.Lsp.CacheEntry
--- @field symbols _99.Lsp.Symbol[]? Cached document symbols
--- @field imports _99.Lsp.Import[]? Cached imports
--- @field timestamp number Cache entry creation time (vim.uv.now())
--- @field uri string File URI this entry is for
--- @field ttl number? TTL in milliseconds (nil = session lifetime)
--- @field char_estimate number? Estimated character count for budget

--- @class _99.Lsp.Cache
--- @field entries table<string, _99.Lsp.CacheEntry> URI -> cache entry
--- @field augroup number? Autocmd group ID
--- @field debounce_timers table<string, any> URI -> debounce timer
--- @field debounce_ms number Debounce time for TextChanged
local Cache = {}
Cache.__index = Cache

--- Create a new cache instance
--- @param opts { debounce_ms: number? }? Options
--- @return _99.Lsp.Cache
function Cache.new(opts)
    opts = opts or {}
    local self = setmetatable({
        entries = {},
        augroup = nil,
        debounce_timers = {},
        debounce_ms = opts.debounce_ms or 1000,
    }, Cache)
    return self
end

--- Get a cached entry for a URI
--- @param uri string File URI
--- @return _99.Lsp.CacheEntry?
function Cache:get(uri)
    return self.entries[uri]
end

--- Check if cache has a valid entry for URI
--- @param uri string File URI
--- @return boolean
function Cache:has(uri)
    return self.entries[uri] ~= nil
end

--- Set a cache entry for a URI
--- @param uri string File URI
--- @param entry _99.Lsp.CacheEntry
function Cache:set(uri, entry)
    entry.uri = uri
    entry.timestamp = vim.uv.now()
    self.entries[uri] = entry
end

--- Create and set a cache entry
--- @param uri string File URI
--- @param symbols _99.Lsp.Symbol[]? Document symbols
--- @param imports _99.Lsp.Import[]? Imports
function Cache:store(uri, symbols, imports)
    self:set(uri, {
        symbols = symbols,
        imports = imports,
        timestamp = vim.uv.now(),
        uri = uri,
    })
end

--- Invalidate (remove) a cache entry for a URI
--- @param uri string File URI
function Cache:invalidate(uri)
    self.entries[uri] = nil
    local timer = self.debounce_timers[uri]
    if timer then
        timer:stop()
        timer:close()
        self.debounce_timers[uri] = nil
    end
end

--- Clear all cache entries
function Cache:clear()
    self.entries = {}
    for _, timer in pairs(self.debounce_timers) do
        timer:stop()
        timer:close()
    end
    self.debounce_timers = {}
end

--- Get all cached URIs
--- @return string[]
function Cache:get_uris()
    local uris = {}
    for uri, _ in pairs(self.entries) do
        table.insert(uris, uri)
    end
    return uris
end

--- Get cache statistics
--- @return { count: number, oldest: number?, newest: number? }
function Cache:stats()
    local count = 0
    local oldest
    local newest

    for _, entry in pairs(self.entries) do
        count = count + 1
        if not oldest or entry.timestamp < oldest then
            oldest = entry.timestamp
        end
        if not newest or entry.timestamp > newest then
            newest = entry.timestamp
        end
    end

    return {
        count = count,
        oldest = oldest,
        newest = newest,
    }
end

--- Check if a cache entry has expired based on TTL
--- @param uri string File URI
--- @return boolean True if expired or not found
function Cache:is_expired(uri)
    local entry = self.entries[uri]
    if not entry then
        return true
    end
    if not entry.ttl then
        return false
    end
    return (vim.uv.now() - entry.timestamp) > entry.ttl
end

--- Set a cache entry with explicit TTL
--- @param uri string File URI
--- @param data { symbols: _99.Lsp.Symbol[]?, imports: _99.Lsp.Import[]?, char_estimate: number? } Cache data
--- @param ttl number? TTL in milliseconds (nil = session lifetime)
function Cache:set_with_ttl(uri, data, ttl)
    self:set(uri, {
        symbols = data.symbols,
        imports = data.imports,
        timestamp = vim.uv.now(),
        uri = uri,
        ttl = ttl,
        char_estimate = data.char_estimate,
    })
end

--- Get a cache entry only if valid (not expired)
--- @param uri string File URI
--- @return _99.Lsp.CacheEntry? Entry if valid, nil if expired or not found
function Cache:get_if_valid(uri)
    if self:is_expired(uri) then
        self:invalidate(uri)
        return nil
    end
    return self:get(uri)
end

--- Schedule debounced invalidation for a URI
--- @param uri string File URI
function Cache:schedule_invalidation(uri)
    local existing = self.debounce_timers[uri]
    if existing then
        existing:stop()
        existing:close()
    end

    local timer = vim.uv.new_timer()
    timer:start(
        self.debounce_ms,
        0,
        vim.schedule_wrap(function()
            timer:stop()
            timer:close()
            self:invalidate(uri)
            self.debounce_timers[uri] = nil
        end)
    )

    self.debounce_timers[uri] = timer
end

--- Set up autocmds for cache invalidation
--- Call this once after creating the cache
function Cache:setup_invalidation()
    if self.augroup then
        vim.api.nvim_del_augroup_by_id(self.augroup)
    end

    self.augroup = vim.api.nvim_create_augroup("99LspCache", { clear = true })

    vim.api.nvim_create_autocmd("BufWritePost", {
        group = self.augroup,
        callback = function(args)
            local uri = vim.uri_from_bufnr(args.buf)
            self:invalidate(uri)
        end,
    })

    vim.api.nvim_create_autocmd("TextChanged", {
        group = self.augroup,
        callback = function(args)
            local uri = vim.uri_from_bufnr(args.buf)
            self:schedule_invalidation(uri)
        end,
    })

    vim.api.nvim_create_autocmd("TextChangedI", {
        group = self.augroup,
        callback = function(args)
            local uri = vim.uri_from_bufnr(args.buf)
            self:schedule_invalidation(uri)
        end,
    })

    vim.api.nvim_create_autocmd("BufDelete", {
        group = self.augroup,
        callback = function(args)
            local uri = vim.uri_from_bufnr(args.buf)
            self:invalidate(uri)
        end,
    })
end

--- Tear down autocmds (cleanup)
function Cache:teardown()
    if self.augroup then
        vim.api.nvim_del_augroup_by_id(self.augroup)
        self.augroup = nil
    end

    -- Clear all timers
    for _, timer in pairs(self.debounce_timers) do
        timer:stop()
        timer:close()
    end
    self.debounce_timers = {}
end

--- Get or fetch symbols for a buffer (with caching)
--- @param bufnr number Buffer number
--- @param callback fun(symbols: _99.Lsp.Symbol[]?, from_cache: boolean)
function Cache:get_symbols(bufnr, callback)
    local uri = vim.uri_from_bufnr(bufnr)
    local entry = self:get(uri)

    if entry and entry.symbols then
        callback(entry.symbols, true)
        return
    end

    local symbols_mod = require("99.lsp.symbols")
    symbols_mod.get_document_symbols(bufnr, function(symbols, err)
        if not err and symbols then
            if entry then
                entry.symbols = symbols
                entry.timestamp = vim.uv.now()
            else
                self:store(uri, symbols, nil)
            end
        end
        callback(symbols, false)
    end)
end

--- Get or fetch imports for a buffer (with caching)
--- @param bufnr number Buffer number
--- @param resolve boolean Whether to resolve imports
--- @param callback fun(imports: _99.Lsp.Import[]?, from_cache: boolean)
function Cache:get_imports(bufnr, resolve, callback)
    local uri = vim.uri_from_bufnr(bufnr)
    local entry = self:get(uri)

    if entry and entry.imports then
        callback(entry.imports, true)
        return
    end

    local imports_mod = require("99.lsp.imports")
    imports_mod.get_imports(bufnr, resolve, function(imports)
        if imports then
            if entry then
                entry.imports = imports
                entry.timestamp = vim.uv.now()
            else
                self:store(uri, nil, imports)
            end
        end
        callback(imports, false)
    end)
end

return Cache
