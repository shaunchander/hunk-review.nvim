local M = {}

function M.check()
  vim.health.start("hunk-review.nvim")

  local git_ok = vim.fn.executable("git") == 1
  if git_ok then
    vim.health.ok("git is installed")
  else
    vim.health.error("git is not installed or not in PATH")
  end

  local root = vim.system({ "git", "rev-parse", "--show-toplevel" }, { text = true }):wait()
  if root.code == 0 then
    vim.health.ok("inside a git repository: " .. vim.trim(root.stdout))
  else
    vim.health.warn("not inside a git repository (run from a git project to use hunk-review)")
  end

  local snacks_ok = pcall(require, "snacks")
  if snacks_ok then
    vim.health.ok("snacks.nvim is available (required for comments picker)")
  else
    vim.health.error("snacks.nvim not found (required dependency)")
  end

  local parsers_ok, parsers = pcall(require, "nvim-treesitter.parsers")
  if parsers_ok then
    local common = { "lua", "python", "javascript", "typescript", "go", "rust" }
    local installed = {}
    local missing = {}
    for _, lang in ipairs(common) do
      if parsers.has_parser(lang) then
        table.insert(installed, lang)
      else
        table.insert(missing, lang)
      end
    end
    if #installed > 0 then
      vim.health.ok("treesitter parsers installed: " .. table.concat(installed, ", "))
    end
    if #missing > 0 then
      vim.health.info("treesitter parsers not installed (syntax highlighting unavailable): " .. table.concat(missing, ", "))
    end
  else
    vim.health.info("nvim-treesitter not found (syntax highlighting in diff view disabled)")
  end
end

return M
