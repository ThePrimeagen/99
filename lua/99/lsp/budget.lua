local time = require("99.time")

--- @class _99.Lsp.Budget
--- @field max_chars number Maximum character budget
--- @field used_chars number Currently consumed characters
--- @field chars_per_token number Estimation ratio (default 4)
--- @field sections table<string, number> Track chars per section (for stats)
--- @field created_at number Creation timestamp
local Budget = {}
Budget.__index = Budget

--- Create a new budget instance
--- @param max_tokens number Maximum tokens allowed
--- @param chars_per_token number? Characters per token estimate (default 4)
--- @return _99.Lsp.Budget
function Budget.new(max_tokens, chars_per_token)
    chars_per_token = chars_per_token or 4
    local self = setmetatable({
        max_chars = max_tokens * chars_per_token,
        used_chars = 0,
        chars_per_token = chars_per_token,
        sections = {},
        created_at = time.now(),
    }, Budget)
    return self
end

--- Estimate the number of tokens for given text
--- @param text string Text to estimate
--- @return number Estimated token count
function Budget:estimate_tokens(text)
    if not text or text == "" then
        return 0
    end
    return math.ceil(#text / self.chars_per_token)
end

--- Check if text can fit within remaining budget
--- @param text string Text to check
--- @return boolean True if text fits
function Budget:can_fit(text)
    if not text then
        return true
    end
    return (self.used_chars + #text) <= self.max_chars
end

--- Consume budget for a section
--- @param section_name string Name of the section (for tracking)
--- @param text string Text content being consumed
--- @return boolean True if consumed successfully, false if over budget
function Budget:consume(section_name, text)
    if not text or text == "" then
        return true
    end

    local char_count = #text
    if (self.used_chars + char_count) > self.max_chars then
        return false
    end

    self.used_chars = self.used_chars + char_count
    self.sections[section_name] = (self.sections[section_name] or 0)
        + char_count
    return true
end

--- Get remaining character budget
--- @return number Remaining characters
function Budget:remaining()
    return math.max(0, self.max_chars - self.used_chars)
end

--- Get remaining token budget (estimated)
--- @return number Remaining tokens
function Budget:remaining_tokens()
    return math.floor(self:remaining() / self.chars_per_token)
end

--- Get budget usage statistics
--- @return table Stats with used_chars, max_chars, remaining_chars, tokens, sections, utilization
function Budget:stats()
    local max_tokens = math.floor(self.max_chars / self.chars_per_token)
    local used_tokens = self:estimate_tokens(string.rep("x", self.used_chars))
    local remaining_chars = self:remaining()

    return {
        used_chars = self.used_chars,
        max_chars = self.max_chars,
        remaining_chars = remaining_chars,
        used_tokens = used_tokens,
        max_tokens = max_tokens,
        remaining_tokens = self:remaining_tokens(),
        sections = vim.tbl_extend("force", {}, self.sections),
        utilization = self.max_chars > 0 and (self.used_chars / self.max_chars)
            or 0,
    }
end

--- Reset the budget to initial state
function Budget:reset()
    self.used_chars = 0
    self.sections = {}
    self.created_at = time.now()
end

--- Check if budget is exhausted
--- @return boolean True if no budget remaining
function Budget:is_exhausted()
    return self.used_chars >= self.max_chars
end

--- Try to consume text, returning what fits
--- @param section_name string Section name for tracking
--- @param text string Text to consume
--- @return string consumed_text The portion that was consumed
--- @return boolean truncated Whether the text was truncated
function Budget:consume_partial(section_name, text)
    if not text or text == "" then
        return "", false
    end

    local remaining = self:remaining()
    if remaining <= 0 then
        return "", true
    end

    if #text <= remaining then
        self:consume(section_name, text)
        return text, false
    end

    local truncated_text = string.sub(text, 1, remaining)
    self:consume(section_name, truncated_text)
    return truncated_text, true
end

return Budget
