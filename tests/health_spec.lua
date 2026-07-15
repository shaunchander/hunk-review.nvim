-- Tests for hunk-review.health module
local health = require("hunk-review.health")

local function capture_health_calls()
  local calls = {}
  local orig = {
    ok = vim.health.ok,
    error = vim.health.error,
    warn = vim.health.warn,
    info = vim.health.info,
    start = vim.health.start,
  }

  vim.health.ok = function(msg) table.insert(calls, { type = "ok", msg = msg }) end
  vim.health.error = function(msg) table.insert(calls, { type = "error", msg = msg }) end
  vim.health.warn = function(msg) table.insert(calls, { type = "warn", msg = msg }) end
  vim.health.info = function(msg) table.insert(calls, { type = "info", msg = msg }) end
  vim.health.start = function(msg) table.insert(calls, { type = "start", msg = msg }) end

  health.check()

  vim.health.ok = orig.ok
  vim.health.error = orig.error
  vim.health.warn = orig.warn
  vim.health.info = orig.info
  vim.health.start = orig.start

  return calls
end

local function find_call(calls, predicate)
  for _, call in ipairs(calls) do
    if predicate(call) then return call end
  end
  return nil
end

describe("health module", function()
  describe("check", function()
    it("runs without errors", function()
      local ok = pcall(health.check)
      assert.is_true(ok)
    end)

    it("starts with the plugin name as section header", function()
      local calls = capture_health_calls()
      local start_call = find_call(calls, function(c)
        return c.type == "start" and c.msg == "hunk-review.nvim"
      end)
      assert.is_not_nil(start_call, "health check must begin with vim.health.start('hunk-review.nvim')")
    end)

    it("reports git as ok when git is installed", function()
      -- git is expected to be available in the test environment
      local calls = capture_health_calls()
      local git_call = find_call(calls, function(c)
        return c.msg and c.msg:match("git")
      end)
      assert.is_not_nil(git_call, "health check must report on git")

      -- In a test environment git is installed, so the call type should be "ok"
      if vim.fn.executable("git") == 1 then
        assert.are.equal("ok", git_call.type,
          "git is installed in this environment; health check should report ok, not error")
      else
        assert.are.equal("error", git_call.type,
          "git is not installed; health check should report error")
      end
    end)

    it("reports snacks as error when snacks is not installed", function()
      local snacks_available = pcall(require, "snacks")
      local calls = capture_health_calls()

      local snacks_call = find_call(calls, function(c)
        return c.msg and c.msg:match("snacks")
      end)
      assert.is_not_nil(snacks_call, "health check must report on snacks.nvim")

      if snacks_available then
        assert.are.equal("ok", snacks_call.type,
          "snacks is installed; health check should report ok")
      else
        assert.are.equal("error", snacks_call.type,
          "snacks is not installed; health check should report error, not warn or ok")
      end
    end)

    it("reports git repository status", function()
      local calls = capture_health_calls()
      -- Should have either an ok (inside repo) or a warn (outside repo) for the repo check
      local repo_call = find_call(calls, function(c)
        return c.msg and (c.msg:match("git repository") or c.msg:match("inside a git"))
      end)
      assert.is_not_nil(repo_call, "health check should report on git repository status")
      assert.is_true(
        repo_call.type == "ok" or repo_call.type == "warn",
        "repo check should be ok (inside repo) or warn (outside), never error"
      )
    end)
  end)
end)
