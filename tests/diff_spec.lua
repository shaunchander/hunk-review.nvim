-- Tests for hunk-review.diff module
local diff = require("hunk-review.diff")

describe("diff module", function()
  describe("make_hunk_id", function()
    it("generates consistent IDs for same content", function()
      local lines = { "+foo", "-bar", " baz" }
      local id1 = diff.make_hunk_id("test.lua", lines)
      local id2 = diff.make_hunk_id("test.lua", lines)
      assert.are.equal(id1, id2)
    end)

    it("generates different IDs for different files", function()
      local lines = { "+foo", "-bar" }
      local id1 = diff.make_hunk_id("test1.lua", lines)
      local id2 = diff.make_hunk_id("test2.lua", lines)
      assert.are_not.equal(id1, id2)
    end)

    it("generates different IDs for different content", function()
      local id1 = diff.make_hunk_id("test.lua", { "+foo" })
      local id2 = diff.make_hunk_id("test.lua", { "+bar" })
      assert.are_not.equal(id1, id2)
    end)
  end)

  describe("make_change_block_id", function()
    it("creates unique IDs for change blocks", function()
      local hunk = {
        file_path = "test.lua",
        lines = { "+foo", "+bar" },
      }
      local id = diff.make_change_block_id(hunk, 1, 2, "add")
      assert.is_string(id)
      assert.is_true(#id > 0)
    end)

    it("creates different IDs for different ranges", function()
      local hunk = {
        file_path = "test.lua",
        lines = { "+foo", "+bar", "+baz" },
      }
      local id1 = diff.make_change_block_id(hunk, 1, 2, "add")
      local id2 = diff.make_change_block_id(hunk, 2, 3, "add")
      assert.are_not.equal(id1, id2)
    end)

    it("creates different IDs for different kinds", function()
      local hunk = {
        file_path = "test.lua",
        lines = { "+foo", "+bar" },
      }
      local id1 = diff.make_change_block_id(hunk, 1, 2, "add")
      local id2 = diff.make_change_block_id(hunk, 1, 2, "delete")
      assert.are_not.equal(id1, id2)
    end)
  end)

  describe("make_range_comment_key", function()
    it("creates keys for single-line ranges", function()
      local hunk = {
        file_path = "test.lua",
        lines = { "+foo" },
      }
      local key = diff.make_range_comment_key(hunk, 1, 1)
      assert.is_string(key)
      assert.is_not_nil(key:match("^range::"))
    end)

    it("creates keys for multi-line ranges", function()
      local hunk = {
        file_path = "test.lua",
        lines = { "+foo", "+bar", "+baz" },
      }
      local key = diff.make_range_comment_key(hunk, 1, 3)
      assert.is_string(key)
      assert.is_not_nil(key:match("::1::3$"))
    end)
  end)

  describe("make_line_comment_key", function()
    it("creates a single-line range comment key", function()
      local hunk = {
        file_path = "test.lua",
        lines = { "+foo", "+bar" },
      }
      local line_key = diff.make_line_comment_key(hunk, 2)
      local range_key = diff.make_range_comment_key(hunk, 2, 2)
      assert.are.equal(line_key, range_key)
    end)
  end)

  describe("get_change_blocks", function()
    it("identifies single-line addition blocks", function()
      local hunk = {
        file_path = "test.lua",
        lines = { " context", "+new line", " context" },
      }
      local blocks = diff.get_change_blocks(hunk)
      assert.are.equal(1, #blocks)
      assert.are.equal("add", blocks[1].kind)
      assert.are.equal(2, blocks[1].start)
      assert.are.equal(2, blocks[1]["end"])
    end)

    it("identifies multi-line addition blocks", function()
      local hunk = {
        file_path = "test.lua",
        lines = { "+line1", "+line2", "+line3" },
      }
      local blocks = diff.get_change_blocks(hunk)
      assert.are.equal(1, #blocks)
      assert.are.equal("add", blocks[1].kind)
      assert.are.equal(1, blocks[1].start)
      assert.are.equal(3, blocks[1]["end"])
    end)

    it("identifies single-line deletion blocks", function()
      local hunk = {
        file_path = "test.lua",
        lines = { " context", "-old line", " context" },
      }
      local blocks = diff.get_change_blocks(hunk)
      assert.are.equal(1, #blocks)
      assert.are.equal("delete", blocks[1].kind)
      assert.are.equal(2, blocks[1].start)
      assert.are.equal(2, blocks[1]["end"])
    end)

    it("identifies multiple separate blocks", function()
      local hunk = {
        file_path = "test.lua",
        lines = {
          "+addition1",
          "+addition2",
          " context",
          "-deletion1",
          " context",
          "+addition3",
        },
      }
      local blocks = diff.get_change_blocks(hunk)
      assert.are.equal(3, #blocks)
      assert.are.equal("add", blocks[1].kind)
      assert.are.equal("delete", blocks[2].kind)
      assert.are.equal("add", blocks[3].kind)
    end)

    it("splits additions and deletions even when adjacent", function()
      local hunk = {
        file_path = "test.lua",
        lines = { "-old", "+new" },
      }
      local blocks = diff.get_change_blocks(hunk)
      assert.are.equal(2, #blocks)
      assert.are.equal("delete", blocks[1].kind)
      assert.are.equal("add", blocks[2].kind)
    end)

    it("caches blocks for the same hunk", function()
      local hunk = {
        file_path = "test.lua",
        lines = { "+foo", "+bar" },
      }
      local blocks1 = diff.get_change_blocks(hunk)
      local blocks2 = diff.get_change_blocks(hunk)
      -- Should return the same table reference (cached)
      assert.are.equal(blocks1, blocks2)
    end)
  end)

  describe("source_line_for_hunk_offset", function()
    it("maps context lines correctly", function()
      local hunk = {
        parsed = { new_start = 10 },
        lines = { " context1", " context2" },
      }
      local line = diff.source_line_for_hunk_offset(hunk, 1)
      assert.are.equal(10, line)
      line = diff.source_line_for_hunk_offset(hunk, 2)
      assert.are.equal(11, line)
    end)

    it("maps addition lines correctly", function()
      local hunk = {
        parsed = { new_start = 10 },
        lines = { " context", "+new line", " context" },
      }
      local line = diff.source_line_for_hunk_offset(hunk, 2)
      assert.are.equal(11, line)
    end)

    it("maps deletion lines to the next new line", function()
      local hunk = {
        parsed = { new_start = 10 },
        lines = { " context", "-old line", " context" },
      }
      local line = diff.source_line_for_hunk_offset(hunk, 2)
      assert.are.equal(11, line)
    end)

    it("handles hunks without parsed data", function()
      local hunk = { lines = { "+foo" } }
      local line = diff.source_line_for_hunk_offset(hunk, 1)
      assert.is_number(line)
    end)
  end)

  describe("file_icon", function()
    it("returns a string for any file path", function()
      local icon = diff.file_icon("test.lua")
      assert.is_string(icon)
    end)

    it("handles files without extensions", function()
      local icon = diff.file_icon("Makefile")
      assert.is_string(icon)
    end)

    it("handles paths with directories", function()
      local icon = diff.file_icon("src/components/Button.tsx")
      assert.is_string(icon)
    end)
  end)

  describe("file_entries", function()
    it("extracts unique file entries from hunks", function()
      local hunks = {
        { file_path = "file1.lua", lines = {} },
        { file_path = "file2.lua", lines = {} },
        { file_path = "file1.lua", lines = {} }, -- duplicate
      }
      local entries = diff.file_entries(hunks)
      assert.are.equal(2, #entries)
    end)

    it("includes addition and deletion counts in entries", function()
      local hunks = {
        {
          file_path = "test.lua",
          lines = { "+line1", "+line2", "-line3" },
        },
      }
      local entries = diff.file_entries(hunks)
      assert.are.equal(1, #entries)
      assert.are.equal("test.lua", entries[1].file_path)
      assert.are.equal(2, entries[1].additions)
      assert.are.equal(1, entries[1].deletions)
    end)

    it("returns empty array for no hunks", function()
      local entries = diff.file_entries({})
      assert.are.equal(0, #entries)
    end)
  end)

  describe("get_range_comments_for_hunk", function()
    it("filters comments for specific hunk", function()
      local hunk = {
        file_path = "test.lua",
        lines = { "+foo", "+bar" },
      }
      local other_hunk = {
        file_path = "other.lua",
        lines = { "+baz" },
      }

      local comments = {}
      local key1 = diff.make_range_comment_key(hunk, 1, 1)
      local key2 = diff.make_range_comment_key(other_hunk, 1, 1)
      comments[key1] = "comment on test.lua"
      comments[key2] = "comment on other.lua"

      local result = diff.get_range_comments_for_hunk(hunk, comments)
      assert.are.equal(1, #result)
      assert.are.equal("comment on test.lua", result[1].comment)
    end)

    it("sorts comments by start index", function()
      local hunk = {
        file_path = "test.lua",
        lines = { "+a", "+b", "+c", "+d" },
      }

      local comments = {}
      local key1 = diff.make_range_comment_key(hunk, 3, 3)
      local key2 = diff.make_range_comment_key(hunk, 1, 1)
      comments[key1] = "comment 3"
      comments[key2] = "comment 1"

      local result = diff.get_range_comments_for_hunk(hunk, comments)
      assert.are.equal(2, #result)
      assert.are.equal(1, result[1].start_idx)
      assert.are.equal(3, result[2].start_idx)
    end)

    it("returns empty array when no comments match", function()
      local hunk = {
        file_path = "test.lua",
        lines = { "+foo" },
      }
      local result = diff.get_range_comments_for_hunk(hunk, {})
      assert.are.equal(0, #result)
    end)
  end)
end)
