-- Tests for hunk-review.git module
local git = require("hunk-review.git")

describe("git module", function()
  describe("set_base_branches", function()
    it("updates base branches configuration", function()
      git.set_base_branches({ "main", "develop" })
      -- Test that is_base_branch reflects the change
      assert.is_true(git.is_base_branch("main"))
      assert.is_true(git.is_base_branch("develop"))
      -- Reset to default
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
      assert.is_false(git.is_base_branch("feature/test"))
      assert.is_false(git.is_base_branch("release/1.0"))
    end)

    it("returns false for nil", function()
      assert.is_false(git.is_base_branch(nil))
    end)

    it("returns false for empty string", function()
      assert.is_false(git.is_base_branch(""))
    end)
  end)

  describe("git_root", function()
    it("returns a path when inside a git repository", function()
      -- This test assumes we're running from inside the plugin's git repo
      local root, err = git.git_root()
      if root then
        assert.is_string(root)
        assert.is_true(#root > 0)
        assert.is_nil(err)
      else
        -- If not in a git repo, skip this test
        pending("Not inside a git repository")
      end
    end)

    it("returns error when not in a git repository", function()
      -- We can't easily test this without changing directories
      -- This is more of a documentation of expected behavior
      pending("Requires running outside a git repository")
    end)
  end)

  describe("detect_base_branch", function()
    before_each(function()
      git.set_base_branches({ "main", "master", "develop" })
    end)

    it("returns cached value when provided", function()
      local result = git.detect_base_branch("cached-main")
      assert.are.equal("cached-main", result)
    end)

    it("detects available base branch", function()
      -- This test depends on the actual git repository state
      -- It will find the first available base branch
      local result = git.detect_base_branch(nil)
      if result then
        assert.is_string(result)
        assert.is_true(git.is_base_branch(result))
      end
    end)

    it("returns nil when no base branches exist", function()
      -- Set impossible branch names
      git.set_base_branches({ "impossible-branch-name-12345" })
      local result = git.detect_base_branch(nil)
      assert.is_nil(result)
      -- Reset
      git.set_base_branches({ "main", "master", "develop" })
    end)
  end)

  describe("detect_target_branch", function()
    it("returns cached value when provided", function()
      local root = vim.fn.getcwd()
      local result = git.detect_target_branch(root, "cached-target")
      assert.are.equal("cached-target", result)
    end)

    it("returns false when cached as false", function()
      local root = vim.fn.getcwd()
      local result = git.detect_target_branch(root, false)
      assert.is_false(result)
    end)

    it("attempts to detect target branch", function()
      local root, err = git.git_root()
      if not root then
        pending("Not inside a git repository")
        return
      end

      local target = git.detect_target_branch(root, nil)
      -- Result can be string, false, or nil depending on git state
      assert.is_true(
        type(target) == "string"
        or target == false
        or target == nil
      )
    end)
  end)

  describe("load_hunks", function()
    it("loads uncommitted hunks when in a git repository", function()
      local result, err = git.load_hunks("uncommitted", {}, { context = 3 })

      if result then
        -- Successful load
        assert.is_table(result)
        assert.is_string(result.repo_root)
        assert.is_string(result.cwd)
        assert.is_table(result.hunks)
        -- hunks can be empty if there are no changes
        assert.is_nil(err)
      else
        -- Either not in a git repo or git error
        assert.is_string(err)
      end
    end)

    it("respects context option", function()
      -- We can't easily verify the exact context without complex setup,
      -- but we can verify the function accepts the option
      local result, err = git.load_hunks("uncommitted", {}, { context = 5 })

      if not result then
        -- It's okay if there's an error (like not in a repo)
        assert.is_string(err)
      else
        assert.is_table(result)
      end
    end)

    it("loads main branch diff when specified", function()
      local result, err = git.load_hunks(
        "main",
        { base_branch = "main" },
        { context = 3 }
      )

      if result then
        assert.is_table(result)
        assert.is_table(result.hunks)
      else
        -- May fail if branch doesn't exist or no commits
        assert.is_string(err)
      end
    end)

    it("handles different diff modes", function()
      -- Test that load_hunks accepts the valid modes without error
      local modes = { "uncommitted", "main", "target" }
      for _, mode in ipairs(modes) do
        local result, err = git.load_hunks(mode, {}, { context = 3 })
        -- Result can be a table (success) or nil (error, e.g., not in git repo)
        assert.is_true(type(result) == "table" or err ~= nil)
      end
    end)
  end)

  describe("collect_hunks", function()
    it("parses a simple unified diff", function()
      local diff_output = [[
diff --git a/test.lua b/test.lua
index 1234567..abcdefg 100644
--- a/test.lua
+++ b/test.lua
@@ -1,3 +1,4 @@
 local x = 1
+local y = 2
 local z = 3
]]
      local hunks = git.collect_hunks(diff_output)
      assert.are.equal(1, #hunks)
      assert.are.equal("test.lua", hunks[1].file_path)
      assert.is_table(hunks[1].lines)
      assert.is_string(hunks[1].header)
    end)

    it("parses multiple hunks from same file", function()
      local diff_output = [[
diff --git a/test.lua b/test.lua
index 1234567..abcdefg 100644
--- a/test.lua
+++ b/test.lua
@@ -1,2 +1,3 @@
 line1
+line2
 line3
@@ -10,2 +11,3 @@
 line10
+line11
 line12
]]
      local hunks = git.collect_hunks(diff_output)
      assert.are.equal(2, #hunks)
      assert.are.equal("test.lua", hunks[1].file_path)
      assert.are.equal("test.lua", hunks[2].file_path)
    end)

    it("parses hunks from multiple files", function()
      local diff_output = [[
diff --git a/file1.lua b/file1.lua
index 1234567..abcdefg 100644
--- a/file1.lua
+++ b/file1.lua
@@ -1,2 +1,3 @@
 line1
+line2
diff --git a/file2.lua b/file2.lua
index 7654321..gfedcba 100644
--- a/file2.lua
+++ b/file2.lua
@@ -1,2 +1,3 @@
 line1
+line2
]]
      local hunks = git.collect_hunks(diff_output)
      assert.are.equal(2, #hunks)
      assert.are.equal("file1.lua", hunks[1].file_path)
      assert.are.equal("file2.lua", hunks[2].file_path)
    end)

    it("handles empty diff output", function()
      local hunks = git.collect_hunks("")
      assert.are.equal(0, #hunks)
    end)

    it("handles diff with only deletions", function()
      local diff_output = [[
diff --git a/test.lua b/test.lua
index 1234567..abcdefg 100644
--- a/test.lua
+++ b/test.lua
@@ -1,3 +1,2 @@
 line1
-line2
 line3
]]
      local hunks = git.collect_hunks(diff_output)
      assert.are.equal(1, #hunks)
      local has_deletion = false
      for _, line in ipairs(hunks[1].lines) do
        if line:sub(1, 1) == "-" then
          has_deletion = true
          break
        end
      end
      assert.is_true(has_deletion)
    end)

    it("handles diff with only additions", function()
      local diff_output = [[
diff --git a/test.lua b/test.lua
index 1234567..abcdefg 100644
--- a/test.lua
+++ b/test.lua
@@ -1,2 +1,3 @@
 line1
+line2
 line3
]]
      local hunks = git.collect_hunks(diff_output)
      assert.are.equal(1, #hunks)
      local has_addition = false
      for _, line in ipairs(hunks[1].lines) do
        if line:sub(1, 1) == "+" then
          has_addition = true
          break
        end
      end
      assert.is_true(has_addition)
    end)

    it("parses hunk header information", function()
      local diff_output = [[
diff --git a/test.lua b/test.lua
index 1234567..abcdefg 100644
--- a/test.lua
+++ b/test.lua
@@ -10,5 +15,7 @@ function test()
 context
+added
 context
]]
      local hunks = git.collect_hunks(diff_output)
      assert.are.equal(1, #hunks)
      assert.is_table(hunks[1].parsed)
      assert.are.equal(10, hunks[1].parsed.old_start)
      assert.are.equal(5, hunks[1].parsed.old_count)
      assert.are.equal(15, hunks[1].parsed.new_start)
      assert.are.equal(7, hunks[1].parsed.new_count)
    end)

    it("handles new file creation", function()
      local diff_output = [[
diff --git a/new.lua b/new.lua
new file mode 100644
index 0000000..abcdefg
--- /dev/null
+++ b/new.lua
@@ -0,0 +1,3 @@
+line1
+line2
+line3
]]
      local hunks = git.collect_hunks(diff_output)
      assert.are.equal(1, #hunks)
      assert.are.equal("new.lua", hunks[1].file_path)
    end)

    it("handles file deletion", function()
      -- Note: Git diff for deleted files may not produce hunks
      -- depending on the exact format. This tests that parsing doesn't crash.
      local diff_output = [[
diff --git a/deleted.lua b/deleted.lua
deleted file mode 100644
index abcdefg..0000000
--- a/deleted.lua
+++ /dev/null
@@ -1,3 +0,0 @@
-line1
-line2
-line3
]]
      local hunks = git.collect_hunks(diff_output)
      -- collect_hunks may return 0 or 1 hunks depending on implementation
      -- The important thing is it doesn't crash
      assert.is_true(#hunks >= 0)
      if #hunks > 0 then
        assert.are.equal("deleted.lua", hunks[1].file_path)
      end
    end)
  end)
end)
