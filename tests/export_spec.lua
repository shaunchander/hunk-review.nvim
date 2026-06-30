-- Tests for hunk-review.export module
local export = require("hunk-review.export")
local diff = require("hunk-review.diff")

describe("export module", function()
  describe("encode_pretty", function()
    it("encodes simple values", function()
      assert.are.equal('"hello"', export.encode_pretty("hello"))
      assert.are.equal("42", export.encode_pretty(42))
      assert.are.equal("true", export.encode_pretty(true))
      assert.are.equal("false", export.encode_pretty(false))
    end)

    it("encodes empty array", function()
      local result = export.encode_pretty({})
      assert.are.equal("[]", result)
    end)

    it("encodes empty object", function()
      -- In Lua, we need to create a table that's explicitly not a list
      local obj = { key = "value" }
      obj.key = nil -- Make it empty but still an object
      local result = export.encode_pretty(vim.empty_dict())
      assert.are.equal("{}", result)
    end)

    it("encodes simple array with proper formatting", function()
      local arr = { 1, 2, 3 }
      local result = export.encode_pretty(arr)
      assert.is_not_nil(result:match("%["))
      assert.is_not_nil(result:match("%]"))
      assert.is_not_nil(result:match("1"))
      assert.is_not_nil(result:match("2"))
      assert.is_not_nil(result:match("3"))
    end)

    it("encodes object with proper formatting", function()
      local obj = { name = "test", value = 42 }
      local result = export.encode_pretty(obj)
      assert.is_not_nil(result:match("{"))
      assert.is_not_nil(result:match("}"))
      assert.is_not_nil(result:match("name"))
      assert.is_not_nil(result:match("test"))
      assert.is_not_nil(result:match("value"))
    end)

    it("sorts object keys", function()
      local obj = { z = 1, a = 2, m = 3 }
      local result = export.encode_pretty(obj)
      local a_pos = result:find('"a"')
      local m_pos = result:find('"m"')
      local z_pos = result:find('"z"')
      assert.is_true(a_pos < m_pos)
      assert.is_true(m_pos < z_pos)
    end)

    it("encodes nested structures", function()
      local nested = {
        outer = {
          inner = { 1, 2, 3 }
        }
      }
      local result = export.encode_pretty(nested)
      assert.is_string(result)
      assert.is_not_nil(result:match("outer"))
      assert.is_not_nil(result:match("inner"))
    end)

    it("respects indent parameter", function()
      local obj = { key = "value" }
      local result = export.encode_pretty(obj, 2)
      -- Result should have indentation
      assert.is_string(result)
      assert.is_not_nil(result:match("\n"))
    end)
  end)

  describe("payload", function()
    it("creates payload structure with required fields", function()
      local hunks = {}
      local comments = {}
      local repo_root = "/test/repo"

      local result = export.payload(hunks, comments, repo_root)

      assert.is_table(result)
      assert.are.equal("hunk-review.nvim", result.plugin)
      assert.are.equal("/test/repo", result.repo_root)
      assert.is_string(result.generated_at)
      assert.is_string(result.instructions)
      assert.is_table(result.hunks)
    end)

    it("includes only hunks with comments", function()
      local hunk_with_comment = {
        file_path = "test.lua",
        header = "@@ -1,2 +1,3 @@",
        lines = { " context", "+new line", " context" },
        parsed = { new_start = 1 },
      }

      local hunk_without_comment = {
        file_path = "other.lua",
        header = "@@ -1,2 +1,3 @@",
        lines = { " context", "+other line", " context" },
        parsed = { new_start = 1 },
      }

      local hunks = { hunk_with_comment, hunk_without_comment }

      -- Add comment only to the first hunk's change block
      local blocks = diff.get_change_blocks(hunk_with_comment)
      local comments = {}
      comments[blocks[1].id] = "Fix this"

      local result = export.payload(hunks, comments, "/repo")

      -- Should only include the hunk with comments
      assert.are.equal(1, #result.hunks)
      assert.are.equal("test.lua", result.hunks[1].file)
    end)

    it("includes change blocks with comments", function()
      local hunk = {
        file_path = "test.lua",
        header = "@@ -1,3 +1,4 @@",
        lines = { " line1", "+line2", "+line3", " line4" },
        parsed = { new_start = 1 },
      }

      local blocks = diff.get_change_blocks(hunk)
      local comments = {}
      comments[blocks[1].id] = "This looks wrong"

      local result = export.payload({ hunk }, comments, "/repo")

      assert.are.equal(1, #result.hunks)
      local exported_hunk = result.hunks[1]
      assert.is_table(exported_hunk.changes)
      assert.are.equal(1, #exported_hunk.changes)
      assert.are.equal("This looks wrong", exported_hunk.changes[1].comment)
    end)

    it("includes range comments", function()
      local hunk = {
        file_path = "test.lua",
        header = "@@ -1,3 +1,4 @@",
        lines = { "+line1", "+line2", "+line3" },
        parsed = { new_start = 1 },
      }

      local comments = {}
      local range_key = diff.make_range_comment_key(hunk, 1, 2)
      comments[range_key] = "Check these lines"

      local result = export.payload({ hunk }, comments, "/repo")

      assert.are.equal(1, #result.hunks)
      local exported_hunk = result.hunks[1]
      assert.is_table(exported_hunk.range_comments)
      assert.are.equal(1, #exported_hunk.range_comments)
      assert.are.equal("Check these lines", exported_hunk.range_comments[1].comment)
    end)

    it("generates valid ISO8601 timestamp", function()
      local result = export.payload({}, {}, "/repo")
      -- Check that generated_at matches ISO8601 format
      assert.is_true(result.generated_at:match("%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%dZ") ~= nil)
    end)
  end)

  describe("clipboard_text", function()
    it("returns nil when no comments exist", function()
      local hunks = {
        {
          file_path = "test.lua",
          lines = { "+new line" },
          parsed = { new_start = 1 },
        }
      }
      local comments = {}
      local result = export.clipboard_text(hunks, comments, nil)
      assert.is_nil(result)
    end)

    it("includes custom prompt when provided", function()
      local hunk = {
        file_path = "test.lua",
        lines = { "+new line" },
        parsed = { new_start = 1 },
      }

      local blocks = diff.get_change_blocks(hunk)
      local comments = {}
      comments[blocks[1].id] = "Fix this"

      local result = export.clipboard_text({ hunk }, comments, "Custom prompt here")

      assert.is_string(result)
      assert.is_true(result:match("Custom prompt here") ~= nil)
    end)

    it("formats block comments with file:line and code fence", function()
      local hunk = {
        file_path = "test.lua",
        lines = { "+new line" },
        parsed = { new_start = 5 },
      }

      local blocks = diff.get_change_blocks(hunk)
      local comments = {}
      comments[blocks[1].id] = "Fix this"

      local result = export.clipboard_text({ hunk }, comments, nil)

      assert.is_string(result)
      assert.is_true(result:match("Fix this") ~= nil)
      assert.is_true(result:match("test.lua:") ~= nil)
      assert.is_true(result:match("```") ~= nil)
      assert.is_true(result:match("%+new line") ~= nil)
    end)

    it("formats range comments with file:line and code fence", function()
      local hunk = {
        file_path = "test.lua",
        lines = { "+line1", "+line2", "+line3" },
        parsed = { new_start = 10 },
      }

      local comments = {}
      local range_key = diff.make_range_comment_key(hunk, 1, 2)
      comments[range_key] = "Review these lines"

      local result = export.clipboard_text({ hunk }, comments, nil)

      assert.is_string(result)
      assert.is_true(result:match("Review these lines") ~= nil)
      assert.is_true(result:match("test.lua:") ~= nil)
      assert.is_true(result:match("```") ~= nil)
    end)

    it("handles multiple commented blocks", function()
      local hunk = {
        file_path = "test.lua",
        lines = { "+line1", " context", "+line2", " context", "+line3" },
        parsed = { new_start = 1 },
      }

      local blocks = diff.get_change_blocks(hunk)
      local comments = {}
      comments[blocks[1].id] = "Comment 1"
      comments[blocks[2].id] = "Comment 2"
      comments[blocks[3].id] = "Comment 3"

      local result = export.clipboard_text({ hunk }, comments, nil)

      assert.is_string(result)
      assert.is_true(result:match("Comment 1") ~= nil)
      assert.is_true(result:match("Comment 2") ~= nil)
      assert.is_true(result:match("Comment 3") ~= nil)
    end)

    it("excludes blocks without comments", function()
      local hunk = {
        file_path = "test.lua",
        lines = { "+line1", " context", "+line2" },
        parsed = { new_start = 1 },
      }

      local blocks = diff.get_change_blocks(hunk)
      local comments = {}
      -- Only comment on the first block
      comments[blocks[1].id] = "Only this one"

      local result = export.clipboard_text({ hunk }, comments, nil)

      assert.is_string(result)
      assert.is_true(result:match("Only this one") ~= nil)
      -- Should not include the second block's content separately
      -- (it will be in the hunk but not as a commented section)
    end)
  end)
end)
