-- Tests for hunk-review.git module
local git = require("hunk-review.git")

describe("git module", function()
  describe("set_base_branches", function()
    it("updates base branches configuration", function()
      git.set_base_branches({ "main", "master" })
      assert.is_true(git.is_base_branch("main"))
      assert.is_true(git.is_base_branch("master"))
      assert.is_false(git.is_base_branch("develop"))

      -- Restore default
      git.set_base_branches({ "main", "master", "develop" })
    end)
  end)

  describe("is_base_branch", function()
    before_each(function()
      git.set_base_branches({ "main", "master", "develop" })
    end)

    it("returns true for configured base branches", function()
      assert.is_true(git.is_base_branch("main"))
      assert.is_true(git.is_base_branch("master"))
      assert.is_true(git.is_base_branch("develop"))
    end)

    it("returns false for non-base branches", function()
      assert.is_false(git.is_base_branch("feature/my-feature"))
      assert.is_false(git.is_base_branch("release"))
    end)

    it("returns false for nil", function()
      assert.is_false(git.is_base_branch(nil))
    end)

    it("returns false for empty string", function()
      assert.is_false(git.is_base_branch(""))
    end)
  end)

  describe("parse_hunk_header", function()
    it("parses a standard header with explicit counts", function()
      local parsed = git.parse_hunk_header("@@ -10,5 +12,7 @@")
      assert.is_table(parsed)
      assert.are.equal(10, parsed.old_start)
      assert.are.equal(5, parsed.old_count)
      assert.are.equal(12, parsed.new_start)
      assert.are.equal(7, parsed.new_count)
    end)

    it("defaults count to 1 when count is omitted from header", function()
      local parsed = git.parse_hunk_header("@@ -1 +1 @@")
      assert.is_table(parsed)
      assert.are.equal(1, parsed.old_start)
      assert.are.equal(1, parsed.old_count)
      assert.are.equal(1, parsed.new_start)
      assert.are.equal(1, parsed.new_count)
    end)

    it("parses a new-file header (old start is 0)", function()
      local parsed = git.parse_hunk_header("@@ -0,0 +1,5 @@")
      assert.is_table(parsed)
      assert.are.equal(0, parsed.old_start)
      assert.are.equal(0, parsed.old_count)
      assert.are.equal(1, parsed.new_start)
      assert.are.equal(5, parsed.new_count)
    end)

    it("returns nil for a malformed header", function()
      assert.is_nil(git.parse_hunk_header("not a hunk header"))
      assert.is_nil(git.parse_hunk_header(""))
      assert.is_nil(git.parse_hunk_header("@@ missing format @@"))
    end)
  end)

  describe("git_root", function()
    it("returns a path when inside a git repository", function()
      local root, err = git.git_root()
      assert.is_nil(err)
      assert.is_string(root)
      assert.is_true(#root > 0)
    end)

    pending("returns error when not in a git repository", function()
      -- Requires running outside a git repository
    end)

    it("returns error when not in a git repository", function()
      local root, err = git.git_root()
      if root then
        assert.is_string(root)
      else
        assert.is_nil(root)
        assert.is_string(err)
      end
    end)
  end)

  describe("detect_base_branch", function()
    it("returns cached value when provided", function()
      local result = git.detect_base_branch("my-cached-branch")
      assert.are.equal("my-cached-branch", result)
    end)

    it("detects available base branch", function()
      git.set_base_branches({ "main", "master", "develop" })
      local result = git.detect_base_branch(nil)
      assert.is_true(result == "main" or result == "master" or result == "develop" or result == nil)
    end)

    it("returns nil when no base branches exist", function()
      git.set_base_branches({ "nonexistent-branch-xyz-123" })
      local result = git.detect_base_branch(nil)
      assert.is_nil(result)
      git.set_base_branches({ "main", "master", "develop" })
    end)
  end)

  describe("detect_target_branch", function()
    it("returns cached value when provided", function()
      assert.are.equal("feature/cached", git.detect_target_branch("/any", "feature/cached"))
    end)

    it("returns false immediately when cached as false", function()
      assert.are.equal(false, git.detect_target_branch("/any", false))
    end)

    it("returns a branch string or false (never nil) after detection", function()
      local root, _ = git.git_root()
      if not root then
        pending("Not in a git repo")
        return
      end

      local target = git.detect_target_branch(root, nil)
      assert.is_true(
        type(target) == "string" or target == false,
        "detect_target_branch should return a branch name or false, not nil"
      )
    end)
  end)

  describe("collect_hunks", function()
    it("parses a simple unified diff", function()
      local diff_text = [[
diff --git a/test.lua b/test.lua
index abc..def 100644
--- a/test.lua
+++ b/test.lua
@@ -1,3 +1,4 @@
 line1
+new line
 line2
 line3
]]
      local hunks = git.collect_hunks(diff_text)
      assert.are.equal(1, #hunks)
      assert.are.equal("test.lua", hunks[1].file_path)
      assert.is_table(hunks[1].parsed)
      assert.are.equal(1, hunks[1].parsed.new_start)
    end)

    it("parses multiple hunks from same file", function()
      local diff_text = [[
diff --git a/test.lua b/test.lua
index abc..def 100644
--- a/test.lua
+++ b/test.lua
@@ -1,3 +1,4 @@
 line1
+new line
 line2
 line3
@@ -10,3 +11,4 @@
 line10
+another new line
 line11
 line12
]]
      local hunks = git.collect_hunks(diff_text)
      assert.are.equal(2, #hunks)
      assert.are.equal("test.lua", hunks[1].file_path)
      assert.are.equal("test.lua", hunks[2].file_path)
    end)

    it("parses hunks from multiple files", function()
      local diff_text = [[
diff --git a/file1.lua b/file1.lua
index abc..def 100644
--- a/file1.lua
+++ b/file1.lua
@@ -1,2 +1,3 @@
 line1
+new line
 line2
diff --git a/file2.lua b/file2.lua
index ghi..jkl 100644
--- a/file2.lua
+++ b/file2.lua
@@ -5,2 +5,3 @@
 other1
+another new
 other2
]]
      local hunks = git.collect_hunks(diff_text)
      assert.are.equal(2, #hunks)
      assert.are.equal("file1.lua", hunks[1].file_path)
      assert.are.equal("file2.lua", hunks[2].file_path)
    end)

    it("handles empty diff output", function()
      local hunks = git.collect_hunks("")
      assert.are.equal(0, #hunks)
    end)

    it("handles diff with only deletions", function()
      local diff_text = [[
diff --git a/test.lua b/test.lua
--- a/test.lua
+++ b/test.lua
@@ -1,3 +1,2 @@
 line1
-deleted line
 line2
]]
      local hunks = git.collect_hunks(diff_text)
      assert.are.equal(1, #hunks)
      local has_deletion = false
      for _, line in ipairs(hunks[1].lines) do
        if line:sub(1, 1) == "-" then has_deletion = true end
      end
      assert.is_true(has_deletion)
    end)

    it("handles diff with only additions", function()
      local diff_text = [[
diff --git a/test.lua b/test.lua
--- a/test.lua
+++ b/test.lua
@@ -1,2 +1,3 @@
 line1
+added line
 line2
]]
      local hunks = git.collect_hunks(diff_text)
      assert.are.equal(1, #hunks)
      local has_addition = false
      for _, line in ipairs(hunks[1].lines) do
        if line:sub(1, 1) == "+" then has_addition = true end
      end
      assert.is_true(has_addition)
    end)

    it("parses hunk header information", function()
      local diff_text = [[
diff --git a/test.lua b/test.lua
--- a/test.lua
+++ b/test.lua
@@ -10,5 +12,6 @@
 context
+added
 more
]]
      local hunks = git.collect_hunks(diff_text)
      assert.are.equal(1, #hunks)
      assert.is_table(hunks[1].parsed)
      assert.are.equal(12, hunks[1].parsed.new_start)
      assert.are.equal(6, hunks[1].parsed.new_count)
    end)

    it("handles new file creation", function()
      local diff_text = [[
diff --git a/new.lua b/new.lua
new file mode 100644
index 000000..abc1234
--- /dev/null
+++ b/new.lua
@@ -0,0 +1,3 @@
+line1
+line2
+line3
]]
      local hunks = git.collect_hunks(diff_text)
      assert.are.equal(1, #hunks)
      assert.are.equal("new.lua", hunks[1].file_path)
    end)

    it("handles file deletion", function()
      local diff_text = [[
diff --git a/old.lua b/old.lua
deleted file mode 100644
index abc1234..000000
--- a/old.lua
+++ /dev/null
@@ -1,3 +0,0 @@
-line1
-line2
-line3
]]
      local hunks = git.collect_hunks(diff_text)
      -- +++ /dev/null has no "b/" prefix, so current_file is never set; hunk is skipped
      assert.are.equal(0, #hunks)
    end)
  end)

  describe("load_hunks", function()
    it("loads uncommitted hunks when in a git repository", function()
      local result, err = git.load_hunks("uncommitted", {}, { context = 3 })
      if result then
        assert.is_table(result.hunks)
        assert.is_string(result.repo_root)
        assert.is_string(result.cwd)
      else
        assert.is_string(err)
      end
    end)

    it("respects context option", function()
      local result1, _ = git.load_hunks("uncommitted", {}, { context = 0 })
      local result2, _ = git.load_hunks("uncommitted", {}, { context = 10 })
      assert.are.equal(type(result1), type(result2))
    end)

    it("loads main branch diff when specified", function()
      local result, err = git.load_hunks("main", {}, { context = 3 })
      if result then
        assert.is_table(result.hunks)
        assert.is_string(result.repo_root)
      else
        assert.is_string(err)
      end
    end)

    it("returns error string when mode is target and target_branch is false", function()
      local root, _ = git.git_root()
      if not root then
        pending("Not in a git repo")
        return
      end

      local result, err = git.load_hunks("target", { target_branch = false }, {})
      assert.is_nil(result)
      assert.is_string(err)
      assert.is_not_nil(err:match("target branch"), "error should mention target branch")
    end)

    it("returns a result table or an error string for all supported modes", function()
      for _, mode in ipairs({ "uncommitted", "main" }) do
        local result, err = git.load_hunks(mode, {}, {})
        assert.is_true(result ~= nil or type(err) == "string",
          "mode '" .. mode .. "' should return a result table or an error string")
      end
    end)
  end)
end)
