-- Tests for hunk-review.health module
local health = require("hunk-review.health")

describe("health module", function()
  describe("check", function()
    it("runs without errors", function()
      -- The health check function calls vim.health functions
      -- We just want to verify it doesn't crash
      local ok = pcall(health.check)
      assert.is_true(ok)
    end)

    it("checks for git executable", function()
      -- Mock vim.health to capture calls
      local health_calls = {}
      local orig_ok = vim.health.ok
      local orig_error = vim.health.error
      local orig_start = vim.health.start
      local orig_warn = vim.health.warn

      vim.health.ok = function(msg) table.insert(health_calls, { type = "ok", msg = msg }) end
      vim.health.error = function(msg) table.insert(health_calls, { type = "error", msg = msg }) end
      vim.health.start = function(msg) table.insert(health_calls, { type = "start", msg = msg }) end
      vim.health.warn = function(msg) table.insert(health_calls, { type = "warn", msg = msg }) end

      health.check()

      -- Restore original functions
      vim.health.ok = orig_ok
      vim.health.error = orig_error
      vim.health.start = orig_start
      vim.health.warn = orig_warn

      -- Verify that health check was started
      local has_start = false
      for _, call in ipairs(health_calls) do
        if call.type == "start" and call.msg == "hunk-review.nvim" then
          has_start = true
          break
        end
      end
      assert.is_true(has_start)

      -- Verify git check was performed
      local has_git_check = false
      for _, call in ipairs(health_calls) do
        if call.msg and call.msg:match("git") then
          has_git_check = true
          break
        end
      end
      assert.is_true(has_git_check)
    end)

    it("checks for snacks.nvim dependency", function()
      local health_calls = {}
      local orig_ok = vim.health.ok
      local orig_error = vim.health.error
      local orig_start = vim.health.start
      local orig_warn = vim.health.warn

      vim.health.ok = function(msg) table.insert(health_calls, { type = "ok", msg = msg }) end
      vim.health.error = function(msg) table.insert(health_calls, { type = "error", msg = msg }) end
      vim.health.start = function(msg) table.insert(health_calls, { type = "start", msg = msg }) end
      vim.health.warn = function(msg) table.insert(health_calls, { type = "warn", msg = msg }) end

      health.check()

      vim.health.ok = orig_ok
      vim.health.error = orig_error
      vim.health.start = orig_start
      vim.health.warn = orig_warn

      -- Verify snacks check was performed
      local has_snacks_check = false
      for _, call in ipairs(health_calls) do
        if call.msg and call.msg:match("snacks") then
          has_snacks_check = true
          break
        end
      end
      assert.is_true(has_snacks_check)
    end)
  end)
end)
