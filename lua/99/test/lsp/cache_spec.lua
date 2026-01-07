-- luacheck: globals describe it assert before_each after_each
local Cache = require("99.lsp.cache")
local eq = assert.are.same

describe("Cache", function()
    local cache

    before_each(function()
        cache = Cache.new()
    end)

    after_each(function()
        cache:teardown()
    end)

    describe("new", function()
        it("should create cache with default debounce", function()
            local c = Cache.new()
            eq(1000, c.debounce_ms)
            eq({}, c.entries)
            c:teardown()
        end)

        it("should create cache with custom debounce", function()
            local c = Cache.new({ debounce_ms = 500 })
            eq(500, c.debounce_ms)
            c:teardown()
        end)
    end)

    describe("get/set", function()
        it("should store and retrieve entries", function()
            local entry = {
                symbols = { { name = "foo" } },
                imports = nil,
                timestamp = 12345,
                uri = "file:///test.lua",
            }
            cache:set("file:///test.lua", entry)
            local retrieved = cache:get("file:///test.lua")
            eq("foo", retrieved.symbols[1].name)
        end)

        it("should return nil for missing entries", function()
            eq(nil, cache:get("file:///nonexistent.lua"))
        end)
    end)

    describe("has", function()
        it("should return true for existing entries", function()
            cache:set("file:///test.lua", { uri = "file:///test.lua" })
            assert.is_true(cache:has("file:///test.lua"))
        end)

        it("should return false for missing entries", function()
            assert.is_false(cache:has("file:///nonexistent.lua"))
        end)
    end)

    describe("store", function()
        it("should create entry with symbols and imports", function()
            local symbols = { { name = "sym1" } }
            local imports = { { module = "mod1" } }
            cache:store("file:///test.lua", symbols, imports)

            local entry = cache:get("file:///test.lua")
            eq("sym1", entry.symbols[1].name)
            eq("mod1", entry.imports[1].module)
            assert.is_not_nil(entry.timestamp)
        end)
    end)

    describe("invalidate", function()
        it("should remove entry", function()
            cache:set("file:///test.lua", { uri = "file:///test.lua" })
            cache:invalidate("file:///test.lua")
            eq(nil, cache:get("file:///test.lua"))
        end)
    end)

    describe("clear", function()
        it("should remove all entries", function()
            cache:set("file:///a.lua", { uri = "file:///a.lua" })
            cache:set("file:///b.lua", { uri = "file:///b.lua" })
            cache:clear()
            eq({}, cache.entries)
        end)
    end)

    describe("get_uris", function()
        it("should return all cached URIs", function()
            cache:set("file:///a.lua", { uri = "file:///a.lua" })
            cache:set("file:///b.lua", { uri = "file:///b.lua" })
            local uris = cache:get_uris()
            eq(2, #uris)
        end)
    end)

    describe("stats", function()
        it("should return cache statistics", function()
            cache:set("file:///a.lua", {
                uri = "file:///a.lua",
                timestamp = 100,
            })
            cache:set("file:///b.lua", {
                uri = "file:///b.lua",
                timestamp = 200,
            })
            local stats = cache:stats()
            eq(2, stats.count)
            eq(100, stats.oldest)
            eq(200, stats.newest)
        end)

        it("should handle empty cache", function()
            local stats = cache:stats()
            eq(0, stats.count)
            eq(nil, stats.oldest)
            eq(nil, stats.newest)
        end)
    end)

    describe("TTL support", function()
        describe("is_expired", function()
            it("should return true for missing entries", function()
                assert.is_true(cache:is_expired("file:///nonexistent.lua"))
            end)

            it("should return false for entries without TTL", function()
                cache:set("file:///test.lua", {
                    uri = "file:///test.lua",
                    timestamp = vim.uv.now(),
                })
                assert.is_false(cache:is_expired("file:///test.lua"))
            end)

            it("should return false for non-expired entries with TTL", function()
                cache:set("file:///test.lua", {
                    uri = "file:///test.lua",
                    timestamp = vim.uv.now(),
                    ttl = 60000,
                })
                assert.is_false(cache:is_expired("file:///test.lua"))
            end)

            it("should return true for expired entries", function()
                cache:set("file:///test.lua", {
                    uri = "file:///test.lua",
                    timestamp = vim.uv.now() - 10000,
                    ttl = 5000,
                })
                assert.is_true(cache:is_expired("file:///test.lua"))
            end)
        end)

        describe("set_with_ttl", function()
            it("should set entry with TTL", function()
                cache:set_with_ttl(
                    "file:///test.lua",
                    { symbols = { { name = "foo" } } },
                    30000
                )
                local entry = cache:get("file:///test.lua")
                eq(30000, entry.ttl)
                eq("foo", entry.symbols[1].name)
            end)

            it("should set entry with char_estimate", function()
                cache:set_with_ttl(
                    "file:///test.lua",
                    { symbols = {}, char_estimate = 500 },
                    nil
                )
                local entry = cache:get("file:///test.lua")
                eq(500, entry.char_estimate)
            end)

            it("should allow nil TTL for session lifetime", function()
                cache:set_with_ttl("file:///test.lua", { symbols = {} }, nil)
                local entry = cache:get("file:///test.lua")
                eq(nil, entry.ttl)
                assert.is_false(cache:is_expired("file:///test.lua"))
            end)
        end)

        describe("get_if_valid", function()
            it("should return entry if not expired", function()
                cache:set("file:///test.lua", {
                    uri = "file:///test.lua",
                    timestamp = vim.uv.now(),
                    ttl = 60000,
                })
                local entry = cache:get_if_valid("file:///test.lua")
                assert.is_not_nil(entry)
            end)

            it("should return nil and invalidate if expired", function()
                cache:set("file:///test.lua", {
                    uri = "file:///test.lua",
                    timestamp = vim.uv.now() - 10000,
                    ttl = 5000,
                })
                local entry = cache:get_if_valid("file:///test.lua")
                eq(nil, entry)
                assert.is_false(cache:has("file:///test.lua"))
            end)

            it("should return nil for missing entries", function()
                eq(nil, cache:get_if_valid("file:///nonexistent.lua"))
            end)
        end)
    end)
end)
