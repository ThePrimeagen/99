local M = {}

local langs = {
    c = {
        names = { body = "compound_statement" },
        log = 'printf("%%p\\n", (void*)&%s);',
    },
    python = {
        names = {},
        log = "print(%s)",
    },
    go = {
        names = {},
        log = 'fmt.Printf("%%+v\\n", %s)',
    },
    ruby = {
        names = { body = "body_statement", block_body = "block_body" },
        log = "puts %s.inspect",
    },
    rust = {
        names = { body = "block" },
        log = 'println!("{:?}", %s);',
    },
    java = {
        names = {},
        log = "System.out.println(%s)",
    },
    lua = {
        names = {},
        log = "vim.inspect(%s)",
    },
    typescript = {
        names = { body = "body" },
    },
}

--- @param lang string
--- @return _99.LanguageOps?
function M.get(lang)
    local cfg = langs[lang]
    if not cfg then
        return nil
    end
    return {
        names = cfg.names,
        log_item = function(item_name)
            if cfg.log then
                return string.format(cfg.log, item_name)
            end
            return item_name
        end,
    }
end

return M
