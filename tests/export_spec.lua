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
      assert.are.equal("[]", export.encode_pretty({}))
    end)

    it("encodes empty object", function()
      assert.are.equal("{}", export.encode_pretty(vim.empty_dict()))
    end)

    it("encodes simple array with proper formatting", function()
      local result = export.encode_pretty({ 1, 2, 3 })
      assert.is_not_nil(result:match("%["))
      assert.is_not_nil(result:match("%]"))
      assert.is_not_nil(result:match("1"))
      assert.is_not_nil(result:match("2"))
      assert.is_not_nil(result:match("3"))
    end)

    it("encodes object with proper formatting", function()
      local result = export.encode_pretty({ name = "test", value = 42 })
      assert.is_not_nil(result:match("{"))
      assert.is_not_nil(result:match("}"))
      assert.is_not_nil(result:match("name"))
      assert.is_not_nil(result:match("test"))
      assert.is_not_nil(result:match("value"))
    end)

    it("sorts object keys alphabetically", function()
      local result = export.encode_pretty({ z = 1, a = 2, m = 3 })
      local a_pos = result:find('"a"')
      local m_pos = result:find('"m"')
      local z_pos = result:find('"z"')
      assert.is_true(a_pos < m_pos)
      assert.is_true(m_pos < z_pos)
    end)

    it("encodes nested structures", function()
      local result = export.encode_pretty({ outer = { inner = { 1, 2, 3 } } })
      assert.is_string(result)
      assert.is_not_nil(result:match("outer"))
      assert.is_not_nil(result:match("inner"))
    end)

    it("uses deeper indentation when indent parameter is greater than zero", function()
      local result_0 = export.encode_pretty({ key = "value" }, 0)
      local result_2 = export.encode_pretty({ key = "value" }, 2)
      -- At indent=2 the key line has 6 leading spaces; at indent=0 it has 2
      assert.is_not_nil(result_2:match("\n      \"key\""),
        "indent=2 should produce 6-space indentation for key line")
      assert.is_nil(result_0:match("\n      \"key\""),
        "indent=0 should not produce 6-space indentation")
    end)
  end)

  describe("payload", function()
    it("creates payload structure with required fields", function()
      local result = export.payload({}, {}, "/test/repo")

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

      local blocks = diff.get_change_blocks(hunk_with_comment)
      local comments = { [blocks[1].id] = "Fix this" }

      local result = export.payload({ hunk_with_comment, hunk_without_comment }, comments, "/repo")

      assert.are.equal(1, #result.hunks)
      assert.are.equal("test.lua", result.hunks[1].file)
    end)

    it("includes change blocks with their comments", function()
      local hunk = {
        file_path = "test.lua",
        header = "@@ -1,3 +1,4 @@",
        lines = { " line1", "+line2", "+line3", " line4" },
        parsed = { new_start = 1 },
      }

      local blocks = diff.get_change_blocks(hunk)
      local comments = { [blocks[1].id] = "This looks wrong" }

      local result = export.payload({ hunk }, comments, "/repo")

      assert.are.equal(1, #result.hunks)
      assert.is_table(result.hunks[1].changes)
      assert.are.equal("This looks wrong", result.hunks[1].changes[1].comment)
    end)

    it("includes range comments", function()
      local hunk = {
        file_path = "test.lua",
        header = "@@ -1,3 +1,4 @@",
        lines = { "+line1", "+line2", "+line3" },
        parsed = { new_start = 1 },
      }

      local range_key = diff.make_range_comment_key(hunk, 1, 2)
      local result = export.payload({ hunk }, { [range_key] = "Check these lines" }, "/repo")

      assert.are.equal(1, #result.hunks)
      assert.is_table(result.hunks[1].range_comments)
      assert.are.equal(1, #result.hunks[1].range_comments)
      assert.are.equal("Check these lines", result.hunks[1].range_comments[1].comment)
    end)

    it("omits range_comments field entirely when there are no range comments", function()
      local hunk = {
        file_path = "test.lua",
        header = "@@ -1,2 +1,3 @@",
        lines = { " context", "+new line", " context" },
        parsed = { new_start = 1 },
      }

      local blocks = diff.get_change_blocks(hunk)
      local result = export.payload({ hunk }, { [blocks[1].id] = "Fix this" }, "/repo")

      assert.are.equal(1, #result.hunks)
      assert.is_nil(result.hunks[1].range_comments,
        "range_comments should be nil (omitted) when there are none")
    end)

    it("generates valid ISO8601 timestamp", function()
      local result = export.payload({}, {}, "/repo")
      assert.is_not_nil(result.generated_at:match("%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%dZ"))
    end)
  end)

  describe("clipboard_text", function()
    it("returns nil when no comments exist", function()
      local hunk = {
        file_path = "test.lua",
        lines = { "+new line" },
        parsed = { new_start = 1 },
      }
      assert.is_nil(export.clipboard_text({ hunk }, {}, nil))
    end)

    it("includes custom prompt when provided", function()
      local hunk = { file_path = "test.lua", lines = { "+new line" }, parsed = { new_start = 1 } }
      local blocks = diff.get_change_blocks(hunk)
      local comments = { [blocks[1].id] = "Fix this" }

      local result = export.clipboard_text({ hunk }, comments, "Custom prompt here")

      assert.is_string(result)
      assert.is_not_nil(result:match("Custom prompt here"))
    end)

    it("treats empty string custom_prompt the same as nil", function()
      local hunk = { file_path = "test.lua", lines = { "+new line" }, parsed = { new_start = 1 } }
      local blocks = diff.get_change_blocks(hunk)
      local comments = { [blocks[1].id] = "Fix this" }

      local result_nil = export.clipboard_text({ hunk }, comments, nil)
      local result_empty = export.clipboard_text({ hunk }, comments, "")

      assert.are.equal(result_nil, result_empty,
        "empty string prompt should produce same output as nil prompt")
    end)

    it("formats block comments with file:line and code fence", function()
      local hunk = {
        file_path = "test.lua",
        lines = { "+new line" },
        parsed = { new_start = 5 },
      }

      local blocks = diff.get_change_blocks(hunk)
      local result = export.clipboard_text({ hunk }, { [blocks[1].id] = "Fix this" }, nil)

      assert.is_not_nil(result:match("Fix this"))
      assert.is_not_nil(result:match("test.lua:"))
      assert.is_not_nil(result:match("```"))
      assert.is_not_nil(result:match("%+new line"))
    end)

    it("range comment code fence contains exactly the lines in range (not outside)", function()
      local hunk = {
        file_path = "test.lua",
        lines = { "+line1", "+line2", "+line3" },
        parsed = { new_start = 10 },
      }

      local range_key = diff.make_range_comment_key(hunk, 1, 2)
      local result = export.clipboard_text({ hunk }, { [range_key] = "Review these lines" }, nil)

      assert.is_not_nil(result:match("Review these lines"))
      assert.is_not_nil(result:match("test.lua:"))
      assert.is_not_nil(result:match("```"))
      assert.is_not_nil(result:match("%+line1"), "line1 is in range 1-2, should appear")
      assert.is_not_nil(result:match("%+line2"), "line2 is in range 1-2, should appear")
      assert.is_nil(result:match("%+line3"), "line3 is outside range 1-2, should not appear")
    end)

    it("handles multiple commented blocks", function()
      local hunk = {
        file_path = "test.lua",
        lines = { "+line1", " context", "+line2", " context", "+line3" },
        parsed = { new_start = 1 },
      }

      local blocks = diff.get_change_blocks(hunk)
      local comments = {
        [blocks[1].id] = "Comment 1",
        [blocks[2].id] = "Comment 2",
        [blocks[3].id] = "Comment 3",
      }

      local result = export.clipboard_text({ hunk }, comments, nil)

      assert.is_not_nil(result:match("Comment 1"))
      assert.is_not_nil(result:match("Comment 2"))
      assert.is_not_nil(result:match("Comment 3"))
    end)

    it("excludes blocks without comments", function()
      local hunk = {
        file_path = "test.lua",
        lines = { "+line1", " context", "+line2" },
        parsed = { new_start = 1 },
      }

      local blocks = diff.get_change_blocks(hunk)
      local result = export.clipboard_text({ hunk }, { [blocks[1].id] = "Only this one" }, nil)

      assert.is_string(result)
      assert.is_not_nil(result:match("Only this one"))
      -- line2 belongs to blocks[2] which has no comment; its content should not appear
      assert.is_nil(result:match("%+line2"), "uncommented block's lines should not appear in output")
    end)
  end)
end)
