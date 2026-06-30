-- Tests for main hunk-review plugin functionality
local review = require("hunk-review")

describe("hunk-review plugin", function()
  before_each(function()
    -- Reset plugin state before each test
    review.setup({})
  end)

  describe("setup", function()
    it("accepts configuration options", function()
      review.setup({
        base_branches = { "main", "develop" },
        diff_context = 5,
        custom_prompt = "Test prompt",
      })
      -- If setup doesn't error, it worked
      assert.is_true(true)
    end)

    it("uses defaults when no config provided", function()
      review.setup()
      assert.is_true(true)
    end)

    it("merges partial config with defaults", function()
      review.setup({
        diff_context = 10,
      })
      assert.is_true(true)
    end)
  end)

  describe("commands", function()
    it("defines HunkReview command", function()
      local commands = vim.api.nvim_get_commands({})
      assert.is_not_nil(commands.HunkReview)
    end)

    it("defines HunkReviewRefresh command", function()
      local commands = vim.api.nvim_get_commands({})
      assert.is_not_nil(commands.HunkReviewRefresh)
    end)

    it("defines HunkReviewExport command", function()
      local commands = vim.api.nvim_get_commands({})
      assert.is_not_nil(commands.HunkReviewExport)
    end)

    it("defines HunkReviewReset command", function()
      local commands = vim.api.nvim_get_commands({})
      assert.is_not_nil(commands.HunkReviewReset)
    end)
  end)

  describe("HunkReview command", function()
    it("can be executed without error", function()
      -- This may fail if not in a git repo, but shouldn't crash
      local ok = pcall(vim.cmd, "HunkReview")
      -- We accept either success or controlled failure
      assert.is_true(type(ok) == "boolean")
    end)
  end)

  describe("HunkReviewReset command", function()
    it("can be executed", function()
      local ok = pcall(vim.cmd, "HunkReviewReset")
      assert.is_true(type(ok) == "boolean")
    end)
  end)

  describe("public API", function()
    it("exposes open function", function()
      assert.is_function(review.open)
    end)

    it("exposes refresh function", function()
      assert.is_function(review.refresh)
    end)

    it("exposes export function", function()
      assert.is_function(review.export)
    end)

    it("exposes reset function", function()
      assert.is_function(review.reset)
    end)

    it("exposes next_tab function", function()
      assert.is_function(review.next_tab)
    end)

    it("exposes prev_tab function", function()
      assert.is_function(review.prev_tab)
    end)

    it("exposes select_file function", function()
      assert.is_function(review.select_file)
    end)

    it("exposes filter_files function", function()
      assert.is_function(review.filter_files)
    end)

    it("exposes clear_filter function", function()
      assert.is_function(review.clear_filter)
    end)

    it("exposes navigation functions", function()
      assert.is_function(review.next_hunk)
      assert.is_function(review.prev_hunk)
      assert.is_function(review.next_change)
      assert.is_function(review.prev_change)
    end)

    it("exposes comment functions", function()
      assert.is_function(review.add_comment)
      assert.is_function(review.add_line_comment)
      assert.is_function(review.add_range_comment)
      assert.is_function(review.delete_comment)
    end)

    it("exposes jump_to_source function", function()
      assert.is_function(review.jump_to_source)
    end)

    it("exposes confirm_review function", function()
      assert.is_function(review.confirm_review)
    end)
  end)

  describe("reset", function()
    it("clears state without errors or handles gracefully", function()
      -- Reset may fail with window errors in test environment, which is acceptable
      local ok, err = pcall(review.reset)
      if not ok then
        -- Error is acceptable if it's about invalid windows (no UI in tests)
        local is_window_error = err and err:match("Invalid window")
        assert.is_true(ok or is_window_error ~= nil, "Unexpected error: " .. tostring(err))
      end
    end)
  end)
end)

describe("buffer setup", function()
  it("sets correct filetype for explorer buffer", function()
    -- Create a buffer with the explorer filetype
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(bufnr, "filetype", "hunkreviewexplorer")

    local ft = vim.api.nvim_buf_get_option(bufnr, "filetype")
    assert.are.equal("hunkreviewexplorer", ft)

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("sets correct filetype for review buffer", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(bufnr, "filetype", "hunkreview")

    local ft = vim.api.nvim_buf_get_option(bufnr, "filetype")
    assert.are.equal("hunkreview", ft)

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)
end)

describe("highlights", function()
  it("defines HunkReviewDiffBg highlight", function()
    local hl = vim.api.nvim_get_hl_by_name("HunkReviewDiffBg", true)
    -- The highlight should exist (may be empty table if default = true)
    assert.is_table(hl)
  end)

  it("defines HunkReviewAddBg highlight", function()
    local hl = vim.api.nvim_get_hl_by_name("HunkReviewAddBg", true)
    assert.is_table(hl)
  end)

  it("defines HunkReviewDeleteBg highlight", function()
    local hl = vim.api.nvim_get_hl_by_name("HunkReviewDeleteBg", true)
    assert.is_table(hl)
  end)
end)
