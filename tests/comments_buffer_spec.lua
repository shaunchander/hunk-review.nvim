-- Tests that the comment system does not create scratch buffers.
-- Comments are stored in-memory only (state.comments table)
-- and rendered as virtual text extmarks, never as buffer lines.
local diff = require("hunk-review.diff")

local function count_scratch_bufs()
  local count = 0
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf)
      and vim.api.nvim_buf_get_name(buf) == "" then
      count = count + 1
    end
  end
  return count
end

local function make_test_hunk(file_path, lines)
  return {
    file_path = file_path or "test.lua",
    header = "@@ -1,3 +1,5 @@",
    parsed = { new_start = 1 },
    lines = lines or { " context", "+added line", "-removed line", "+another add", " context" },
  }
end

describe("comment buffer safety", function()
  describe("comment key generation", function()
    it("creates no scratch buffers", function()
      local before = count_scratch_bufs()
      local hunk = make_test_hunk()

      for _ = 1, 50 do
        diff.make_hunk_id(hunk.file_path, hunk.lines)
        diff.make_line_comment_key(hunk, 1)
        diff.make_line_comment_key(hunk, 2)
        diff.make_range_comment_key(hunk, 1, 3)
        diff.make_change_block_id(hunk, 1, 2, "add")
        diff.make_change_block_id(hunk, 3, 3, "delete")
      end

      assert.are.equal(before, count_scratch_bufs(),
        "comment key generation should not create buffers")
    end)
  end)

  describe("change block detection", function()
    it("creates no scratch buffers", function()
      local before = count_scratch_bufs()

      for i = 1, 20 do
        local hunk = make_test_hunk("file_" .. i .. ".lua")
        diff.get_change_blocks(hunk)
      end

      assert.are.equal(before, count_scratch_bufs(),
        "change block detection should not create buffers")
    end)
  end)

  describe("in-memory comment storage", function()
    it("storing and querying comments creates no scratch buffers", function()
      local before = count_scratch_bufs()
      local comments = {}
      local hunk = make_test_hunk()

      for i = 1, 20 do
        local key = diff.make_line_comment_key(hunk, 2)
        comments[key] = "line comment iteration " .. i

        local range_key = diff.make_range_comment_key(hunk, 2, 4)
        comments[range_key] = "range comment iteration " .. i

        local blocks = diff.get_change_blocks(hunk)
        for _, block in ipairs(blocks) do
          comments[block.id] = "block comment " .. i
        end

        diff.get_range_comments_for_hunk(hunk, comments)
      end

      assert.are.equal(before, count_scratch_bufs(),
        "comment storage and querying should not create buffers")
    end)

    it("handles multiple hunks across files without buffers", function()
      local before = count_scratch_bufs()
      local comments = {}

      local hunks = {
        make_test_hunk("src/init.lua", { "+new", " ctx", "-old" }),
        make_test_hunk("src/util.lua", { "+a", "+b", "+c" }),
        make_test_hunk("README.md", { "-removed", "+replaced" }),
      }

      for _, hunk in ipairs(hunks) do
        local blocks = diff.get_change_blocks(hunk)
        for _, block in ipairs(blocks) do
          comments[block.id] = "comment on " .. hunk.file_path
        end
        diff.get_range_comments_for_hunk(hunk, comments)
        diff.source_line_for_hunk_offset(hunk, 1)
      end

      diff.file_entries(hunks)

      for _, hunk in ipairs(hunks) do
        diff.count_file_comments(hunk.file_path, comments)
      end

      assert.are.equal(before, count_scratch_bufs(),
        "full comment pipeline across files should not create buffers")
    end)
  end)

  describe("comment extmark rendering", function()
    it("renders comments as virt_lines extmarks without creating buffers", function()
      local ns = vim.api.nvim_create_namespace("hunk-review-comments")
      local bufnr = vim.api.nvim_create_buf(false, true)

      -- Simulate diff content in a buffer
      local diff_lines = {
        "  @@ -1,3 +1,5 @@",
        "    context",
        "    +added line",
        "    -removed line",
        "    +another add",
        "    context",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, diff_lines)

      local before = count_scratch_bufs()

      -- Place extmarks (simulating render_comment_extmarks behavior)
      for i = 1, 10 do
        vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
        vim.api.nvim_buf_set_extmark(bufnr, ns, 2, 0, {
          virt_lines = { { { "      Comment: test " .. i, "Comment" } } },
        })
        vim.api.nvim_buf_set_extmark(bufnr, ns, 4, 0, {
          virt_lines = { { { "      Comment: another " .. i, "Comment" } } },
        })
      end

      assert.are.equal(before, count_scratch_bufs(),
        "extmark-based comments should not create any buffers")

      -- Verify extmarks exist
      local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
      assert.are.equal(2, #marks, "should have exactly 2 comment extmarks")

      -- Verify clearing and re-placing doesn't leak
      vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
      local marks_after_clear = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
      assert.are.equal(0, #marks_after_clear, "clearing should remove all extmarks")

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("repeated clear-and-place cycles create zero buffers", function()
      local ns = vim.api.nvim_create_namespace("hunk-review-comments")
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "line1", "line2", "line3" })

      local before = count_scratch_bufs()

      -- Simulate 50 comment add/edit/delete cycles
      for i = 1, 50 do
        vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
        vim.api.nvim_buf_set_extmark(bufnr, ns, 0, 0, {
          virt_lines = { { { "comment " .. i, "Comment" } } },
        })
      end

      assert.are.equal(before, count_scratch_bufs(),
        "50 extmark cycles should create zero new buffers")

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("comment deletion", function()
    it("removing comments creates no buffers", function()
      local before = count_scratch_bufs()
      local comments = {}
      local hunk = make_test_hunk()

      local keys = {}
      for i = 1, 10 do
        local key = diff.make_line_comment_key(hunk, 2)
        comments[key] = "comment " .. i
        table.insert(keys, key)

        local rk = diff.make_range_comment_key(hunk, 2, 4)
        comments[rk] = "range " .. i
        table.insert(keys, rk)
      end

      for _, key in ipairs(keys) do
        comments[key] = nil
      end

      assert.are.equal(before, count_scratch_bufs(),
        "comment deletion should not create buffers")
    end)
  end)
end)
