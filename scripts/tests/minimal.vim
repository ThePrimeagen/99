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
set rtp^=~/.local/share/nvim/lazy/nvim-treesitter
set rtp^=~/.local/share/nvim/lazy/plenary.nvim

set autoindent
set tabstop=4
set expandtab
set shiftwidth=4
set noswapfile

runtime! plugin/plenary.vim
runtime! plugin/nvim-treesitter.lua

lua <<EOF
-- Always setup nvim-treesitter
local ts = require('nvim-treesitter')
ts.setup()

-- parsers to attempt to install (for user convenience)
local all_parsers = {
  'c', 'cpp', 'go', 'lua', 'php', 'python', 'typescript',
  'javascript', 'java', 'ruby', 'tsx', 'c_sharp', 'vue', 'elixir'
}

-- parsers actually required for tests to run
local required_parsers = { 'lua', 'typescript', 'python' }

local function missing_parsers(parsers)
  local missing = {}
  local buf = vim.api.nvim_create_buf(false, true)
  print('[minimal.vim] Checking for missing parsers...')
  for _, lang in ipairs(parsers) do
    print('[minimal.vim] Checking parser for: ' .. lang)
    local ok, err = pcall(vim.treesitter.get_parser, buf, lang)
    if not ok then
      print('[minimal.vim] Parser NOT found for ' .. lang .. ': ' .. tostring(err))
      table.insert(missing, lang)
    else
      print('[minimal.vim] Parser FOUND for ' .. lang)
    end
  end
  vim.api.nvim_buf_delete(buf, { force = true })
  return missing
end

local function install_with_main_branch_api(parsers)
  -- setup is already done above, just install
  require('nvim-treesitter').install(parsers):wait(300000)
end

-- master branch is deprecated but still widely used
local function install_with_master_branch_api(parsers)
  -- fixes 'pos_delta >= 0' error - https://github.com/nvim-lua/plenary.nvim/issues/52
  vim.cmd('set display=lastline')
  -- make "TSInstall*" available
  vim.cmd('runtime! plugin/nvim-treesitter.vim')
  vim.cmd('TSInstallSync ' .. table.concat(parsers, ' '))
end

local to_install = missing_parsers(all_parsers)
if #to_install > 0 then
  -- Detect which nvim-treesitter API is available (main vs master branch)
  local has_main_api, ts = pcall(require, 'nvim-treesitter')
  has_main_api = has_main_api and type(ts.install) == 'function'

  if has_main_api then
    local ok, err = pcall(install_with_main_branch_api, to_install)
    if not ok then
      print('Tree-sitter install error (main API): ' .. tostring(err))
    end
  else
    local ok, err = pcall(install_with_master_branch_api, to_install)
    if not ok then
      print('Tree-sitter install error (master API): ' .. tostring(err))
    end
  end
end

-- only error if required parsers are still missing
local still_missing = missing_parsers(required_parsers)
if #still_missing > 0 then
  error('Missing required Tree-sitter parsers: ' .. table.concat(still_missing, ', '))
end
EOF
