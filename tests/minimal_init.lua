-- Minimal init for testing
-- This file sets up a minimal Neovim environment for running tests

local M = {}

-- Add project root to runtimepath
local root = vim.fn.fnamemodify(vim.fn.getcwd(), ":p")
vim.opt.rtp:prepend(root)

-- Add plenary to runtimepath (assumes it's installed via package manager)
local plenary_path = vim.fn.stdpath("data") .. "/lazy/plenary.nvim"
if vim.fn.isdirectory(plenary_path) == 1 then
  vim.opt.rtp:append(plenary_path)
end

-- Add snacks.nvim to runtimepath (required dependency)
local snacks_path = vim.fn.stdpath("data") .. "/lazy/snacks.nvim"
if vim.fn.isdirectory(snacks_path) == 1 then
  vim.opt.rtp:append(snacks_path)
end

-- Set up basic vim options for testing
vim.opt.swapfile = false
vim.opt.compatible = false

-- Ensure hunk-review can be loaded
vim.cmd("runtime! plugin/**/*.lua")

return M
