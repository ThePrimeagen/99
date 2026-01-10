" covers all package managers i am willing to cover
set rtp+=.
set rtp+=../plenary.nvim
set rtp+=../nvim-treesitter
set rtp+=~/.vim/plugged/plenary.nvim
set rtp+=~/.vim/plugged/nvim-treesitter
set rtp+=~/.local/share/nvim/site/pack/packer/start/plenary.nvim
set rtp+=~/.local/share/nvim/site/pack/packer/start/nvim-treesitter
set rtp+=~/.local/share/lunarvim/site/pack/packer/start/plenary.nvim
set rtp+=~/.local/share/lunarvim/site/pack/packer/start/nvim-treesitter
set rtp+=~/.local/share/nvim/lazy/plenary.nvim
set rtp+=~/.local/share/nvim/lazy/nvim-treesitter

set autoindent
set tabstop=4
set expandtab
set shiftwidth=4
set noswapfile

runtime! plugin/plenary.vim
runtime! plugin/nvim-treesitter.lua

lua <<EOF
vim.opt.rtp:append(vim.fn.stdpath('data') .. '/site')

-- so far, only lua and typescript parser are used in the test
local required_parsers = { "lua", "typescript" }

local function missing_parsers(parsers)
  local missing = {}
  local buf = vim.api.nvim_create_buf(false, true) -- false: no list, true: scratch buffer
  for _, lang in ipairs(parsers) do
    local ok = pcall(vim.treesitter.get_parser, buf, lang)
    if not ok then
      table.insert(missing, lang)
    end
  end
  vim.api.nvim_buf_delete(buf, { force = true })
  return missing
end

local to_install = missing_parsers(required_parsers)
if #to_install > 0 then
  error(
    "Missing Tree-sitter parsers: "
      .. table.concat(to_install, ", ")
      .. "\nInstall them with: TSInstall " .. table.concat(to_install, " ")
  )
end
EOF
