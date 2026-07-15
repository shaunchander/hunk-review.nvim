-- Tests for the comments sidebar (Shift+C / C key behavior).
local diff = require("hunk-review.diff")
local comments = require("hunk-review.comments")

local function make_hunk(file_path, lines)
  return {
    file_path = file_path or "test.lua",
    header = "@@ -1,3 +1,5 @@",
    parsed = { new_start = 10 },
    lines = lines or { " ctx", "+added", "-removed", "+another", " ctx" },
  }
end

local function make_state(hunks, comment_table)
  return {
    hunks = hunks or {},
    comments = comment_table or {},
    review_winid = nil,
    line_map = {},
    comments_sidebar_open = false,
  }
end

describe("comments sidebar", function()
  describe("M.close", function()
    it("clears comments_sidebar_open flag", function()
      local state = make_state()
      state.comments_sidebar_open = true
      comments.close(state)
      assert.is_false(state.comments_sidebar_open)
    end)

    it("is safe to call when sidebar was never opened", function()
      local state = make_state()
      assert.has_no_error(function()
        comments.close(state)
      end)
    end)
  end)

  describe("M.open with no comments", function()
    it("notifies and returns without creating buffers", function()
      local before = #vim.api.nvim_list_bufs()
      local state = make_state()

      local notified = false
      local orig_notify = vim.notify
      vim.notify = function(msg, level, opts)
        if msg:find("No comments") then notified = true end
      end

      comments.open(state)

      vim.notify = orig_notify

      assert.is_true(notified, "should notify when no comments exist")
      assert.are.equal(before, #vim.api.nvim_list_bufs())
    end)
  end)

  describe("M.open when snacks is unavailable", function()
    it("notifies user that snacks is not available", function()
      local hunk = make_hunk()
      local blocks = diff.get_change_blocks(hunk)
      local state = make_state({ hunk })
      state.comments[blocks[1].id] = "test comment"

      local notified_msg = nil
      local orig_notify = vim.notify
      vim.notify = function(msg, ...) notified_msg = msg end

      local real_require = _G.require
      _G.require = function(name)
        if name == "snacks" then error("snacks not available") end
        return real_require(name)
      end

      pcall(comments.open, state)

      _G.require = real_require
      vim.notify = orig_notify

      assert.is_not_nil(notified_msg, "should have sent a notification")
      assert.is_not_nil(notified_msg:match("snacks"), "notification should mention snacks")
    end)
  end)

  describe("M.toggle", function()
    it("does not crash when state has no hunks", function()
      local state = make_state()
      assert.has_no_error(function()
        comments.toggle(state)
      end)
    end)

    it("does not crash when snacks is not available", function()
      local hunk = make_hunk()
      local state = make_state({ hunk })
      local blocks = diff.get_change_blocks(hunk)
      state.comments[blocks[1].id] = "test comment"

      local real_require = _G.require
      _G.require = function(name)
        if name == "snacks" then error("snacks not available") end
        return real_require(name)
      end

      local ok = pcall(comments.toggle, state)
      _G.require = real_require

      assert.is_true(ok, "toggle should not raise when snacks is unavailable")
    end)
  end)

  describe("picker item data model", function()
    -- build_picker_items is a local function inside comments.lua.
    -- These tests verify that the data model it consumes (block ids, range comment
    -- keys, source line mapping) is correct — i.e. that the picker would receive
    -- the right data if snacks were available.

    it("block comment is retrievable via the block id key", function()
      local hunk = make_hunk("src/foo.lua", { "+line1", "+line2" })
      local blocks = diff.get_change_blocks(hunk)
      assert.is_true(#blocks >= 1)

      local state = make_state({ hunk })
      state.comments[blocks[1].id] = "my block comment"

      assert.are.equal("my block comment", state.comments[blocks[1].id])

      local source_line = diff.source_line_for_hunk_offset(hunk, blocks[1].start)
      assert.is_number(source_line)
      assert.is_true(source_line >= 1)
    end)

    it("range comment is retrievable via get_range_comments_for_hunk", function()
      local hunk = make_hunk("src/foo.lua", { "+line1", "+line2", "+line3" })
      local range_key = diff.make_range_comment_key(hunk, 1, 3)
      local state = make_state({ hunk })
      state.comments[range_key] = "range comment"

      local rc_list = diff.get_range_comments_for_hunk(hunk, state.comments)
      assert.are.equal(1, #rc_list)
      assert.are.equal("range comment", rc_list[1].comment)
      assert.are.equal(1, rc_list[1].start_idx)
      assert.are.equal(3, rc_list[1].end_idx)
    end)

    it("comments from two different hunks in the same file have distinct keys", function()
      local hunk1 = make_hunk("src/foo.lua", { "+line1" })
      local hunk2 = {
        file_path = "src/foo.lua",
        header = "@@ -20,2 +20,3 @@",
        parsed = { new_start = 20 },
        lines = { " ctx", "+added", " ctx" },
      }

      local blocks1 = diff.get_change_blocks(hunk1)
      local blocks2 = diff.get_change_blocks(hunk2)
      local state = make_state({ hunk1, hunk2 })
      state.comments[blocks1[1].id] = "comment on hunk1"
      state.comments[blocks2[1].id] = "comment on hunk2"

      assert.are.equal("comment on hunk1", state.comments[blocks1[1].id])
      assert.are.equal("comment on hunk2", state.comments[blocks2[1].id])
      assert.are_not.equal(blocks1[1].id, blocks2[1].id,
        "different hunks produce different block ids")
    end)

    it("empty comment string is not included (excluded by get_range_comments_for_hunk)", function()
      local hunk = make_hunk("src/foo.lua", { "+line1" })
      local range_key = diff.make_range_comment_key(hunk, 1, 1)
      local state = make_state({ hunk })
      state.comments[range_key] = ""

      local rc_list = diff.get_range_comments_for_hunk(hunk, state.comments)
      assert.are.equal(0, #rc_list, "empty string comments should be excluded from picker items")
    end)
  end)
end)
