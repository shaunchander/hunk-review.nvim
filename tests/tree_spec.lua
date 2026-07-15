-- Tests for hunk-review.tree module
local tree = require("hunk-review.tree")
local diff = require("hunk-review.diff")

describe("tree module", function()
  describe("build_file_tree", function()
    it("builds tree from flat file list", function()
      local entries = {
        { file_path = "file1.lua", additions = 1, deletions = 0 },
        { file_path = "file2.lua", additions = 2, deletions = 1 },
      }

      local result = tree.build_file_tree(entries)

      assert.is_table(result)
      assert.is_table(result.files)
      assert.is_table(result.children)
      assert.are.equal(2, #result.files)
    end)

    it("builds nested tree from paths with directories", function()
      local entries = {
        { file_path = "src/main.lua", additions = 1, deletions = 0 },
        { file_path = "src/utils.lua", additions = 2, deletions = 1 },
        { file_path = "test/test.lua", additions = 1, deletions = 1 },
      }

      local result = tree.build_file_tree(entries)

      assert.is_table(result.children.src)
      assert.is_table(result.children.test)
      assert.are.equal(2, #result.children.src.files)
      assert.are.equal(1, #result.children.test.files)
    end)

    it("handles deeply nested paths", function()
      local entries = {
        { file_path = "a/b/c/d/file.lua", additions = 1, deletions = 0 },
      }

      local result = tree.build_file_tree(entries)

      assert.is_table(result.children.a)
      assert.is_table(result.children.a.children.b)
      assert.is_table(result.children.a.children.b.children.c)
      assert.is_table(result.children.a.children.b.children.c.children.d)
      assert.are.equal(1, #result.children.a.children.b.children.c.children.d.files)
    end)

    it("handles mixed root and nested files", function()
      local entries = {
        { file_path = "root.lua", additions = 1, deletions = 0 },
        { file_path = "dir/nested.lua", additions = 2, deletions = 1 },
      }

      local result = tree.build_file_tree(entries)

      assert.are.equal(1, #result.files)
      assert.is_table(result.children.dir)
      assert.are.equal(1, #result.children.dir.files)
    end)

    it("handles empty entries", function()
      local result = tree.build_file_tree({})

      assert.is_table(result)
      assert.is_table(result.files)
      assert.is_table(result.children)
      assert.are.equal(0, #result.files)
      assert.are.equal(0, #vim.tbl_keys(result.children))
    end)
  end)

  describe("render_tree_node", function()
    it("renders root files", function()
      local node = {
        files = { { file_path = "test.lua", additions = 1, deletions = 0 } },
        children = {}
      }

      local lines = {}
      tree.render_tree_node(node, "", lines, {}, {}, 0, {}, nil, {})

      assert.are.equal(1, #lines)
      assert.is_not_nil(lines[1]:match("test.lua"))
    end)

    it("renders directories with files", function()
      local node = {
        files = {},
        children = {
          src = {
            files = { { file_path = "src/main.lua", additions = 1, deletions = 0 } },
            children = {}
          }
        }
      }

      local lines = {}
      tree.render_tree_node(node, "", lines, {}, {}, 0, {}, nil, {})

      assert.is_true(#lines >= 2)
      assert.is_not_nil(lines[1]:match("src/"))
      assert.is_not_nil(lines[2]:match("main.lua"))
    end)

    it("marks selected file with > indicator", function()
      local node = {
        files = { { file_path = "test.lua", additions = 1, deletions = 0 } },
        children = {}
      }

      local lines = {}
      tree.render_tree_node(node, "", lines, {}, {}, 0, {}, "test.lua", {})

      assert.is_not_nil(lines[1]:match(">"))
    end)

    it("non-selected file shows space in place of > indicator", function()
      local node = {
        files = { { file_path = "test.lua", additions = 1, deletions = 0 } },
        children = {}
      }

      local lines = {}
      tree.render_tree_node(node, "", lines, {}, {}, 0, {}, "other.lua", {})

      -- The marker should be a space, not >
      assert.is_nil(lines[1]:match(">"))
    end)

    it("respects depth for indentation", function()
      local node = {
        files = { { file_path = "test.lua", additions = 1, deletions = 0 } },
        children = {}
      }

      local lines_depth_0 = {}
      local lines_depth_2 = {}

      tree.render_tree_node(node, "", lines_depth_0, {}, {}, 0, {}, nil, {})
      tree.render_tree_node(node, "", lines_depth_2, {}, {}, 2, {}, nil, {})

      assert.is_true(#lines_depth_2[1] > #lines_depth_0[1])
    end)

    it("collapses directories when specified", function()
      local node = {
        files = {},
        children = {
          src = {
            files = { { file_path = "src/main.lua", additions = 1, deletions = 0 } },
            children = {}
          }
        }
      }

      local lines = {}
      tree.render_tree_node(node, "", lines, {}, {}, 0, { src = true }, nil, {})

      assert.are.equal(1, #lines)
      assert.is_not_nil(lines[1]:match("src/"))
      assert.is_not_nil(lines[1]:match("▸"))
    end)

    it("expands directories by default", function()
      local node = {
        files = {},
        children = {
          src = {
            files = { { file_path = "src/main.lua", additions = 1, deletions = 0 } },
            children = {}
          }
        }
      }

      local lines = {}
      tree.render_tree_node(node, "", lines, {}, {}, 0, {}, nil, {})

      assert.is_true(#lines > 1)
      assert.is_not_nil(lines[1]:match("▾"))
    end)

    it("shows file change counts", function()
      local node = {
        files = { { file_path = "test.lua", additions = 5, deletions = 3 } },
        children = {}
      }

      local lines = {}
      tree.render_tree_node(node, "", lines, {}, {}, 0, {}, nil, {})

      assert.is_not_nil(lines[1]:match("%+5"))
      assert.is_not_nil(lines[1]:match("%-3"))
    end)

    it("line_map entries have file_path for files and dir_path for directories", function()
      local node = {
        files = { { file_path = "root.lua", additions = 1, deletions = 0 } },
        children = {
          src = {
            files = { { file_path = "src/main.lua", additions = 0, deletions = 1 } },
            children = {}
          }
        }
      }

      local line_map = {}
      tree.render_tree_node(node, "", {}, {}, line_map, 0, {}, nil, {})

      local has_dir_entry = false
      local has_file_entry = false
      for _, entry in pairs(line_map) do
        if entry.dir_path then has_dir_entry = true end
        if entry.file_path then has_file_entry = true end
      end

      assert.is_true(has_dir_entry, "directory entries must have a dir_path key")
      assert.is_true(has_file_entry, "file entries must have a file_path key")
    end)

    it("shows comment count indicator when file has comments", function()
      local hunk = { file_path = "test.lua", lines = { "+foo" } }
      local key = diff.make_range_comment_key(hunk, 1, 1)
      local test_comments = { [key] = "a comment" }

      local node = {
        files = { { file_path = "test.lua", additions = 1, deletions = 0 } },
        children = {}
      }

      local lines = {}
      tree.render_tree_node(node, "", lines, {}, {}, 0, {}, nil, test_comments)

      assert.is_not_nil(lines[1]:match("1c"), "comment count indicator should appear in file line")
    end)

    it("does not show comment indicator when file has no comments", function()
      local node = {
        files = { { file_path = "test.lua", additions = 1, deletions = 0 } },
        children = {}
      }

      local lines = {}
      tree.render_tree_node(node, "", lines, {}, {}, 0, {}, nil, {})

      assert.is_nil(lines[1]:match("%dc"), "no comment indicator when there are no comments")
    end)
  end)

  describe("compact_dir_path (via render_tree_node)", function()
    it("merges a single-child directory with no files into one display line", function()
      -- src/ has no files and exactly one child (components/), so compact_dir_path
      -- merges them: the display line shows "src/components/" not two separate lines.
      local node = {
        files = {},
        children = {
          src = {
            files = {},
            children = {
              components = {
                files = { { file_path = "src/components/Button.lua", additions = 2, deletions = 0 } },
                children = {}
              }
            }
          }
        }
      }

      local lines = {}
      tree.render_tree_node(node, "", lines, {}, {}, 0, {}, nil, {})

      -- Should produce exactly 2 lines: the compacted dir line + the file line
      assert.are.equal(2, #lines, "single-child compaction should collapse src/ + components/ into one line")
      assert.is_not_nil(lines[1]:match("src/components/"),
        "compacted dir line should show merged path 'src/components/'")
      assert.is_not_nil(lines[2]:match("Button.lua"),
        "file should render under the compacted directory")
    end)

    it("does not compact a directory that has files at its own level", function()
      -- src/ has a file AND a child; compact_dir_path should NOT merge them
      local node = {
        files = {},
        children = {
          src = {
            files = { { file_path = "src/root_file.lua", additions = 1, deletions = 0 } },
            children = {
              sub = {
                files = { { file_path = "src/sub/file.lua", additions = 1, deletions = 0 } },
                children = {}
              }
            }
          }
        }
      }

      local lines = {}
      tree.render_tree_node(node, "", lines, {}, {}, 0, {}, nil, {})

      -- src/ should appear as its own line (not merged with sub/)
      assert.is_not_nil(lines[1]:match("^▾"), "src/ should be a normal expandable directory")
      -- The line should just say "src/", not "src/sub/"
      assert.is_nil(lines[1]:match("src/sub/"), "non-compactable dir should not show merged path")
    end)
  end)

  describe("file_order", function()
    it("returns files in tree order", function()
      local node = {
        files = { { file_path = "root.lua" } },
        children = {
          src = {
            files = { { file_path = "src/main.lua" } },
            children = {}
          }
        }
      }

      local order = tree.file_order(node)

      assert.are.equal(2, #order)
      assert.are.equal("src/main.lua", order[1])
      assert.are.equal("root.lua", order[2])
    end)

    it("sorts files alphabetically within each level", function()
      local node = {
        files = {
          { file_path = "z.lua" },
          { file_path = "a.lua" },
          { file_path = "m.lua" }
        },
        children = {}
      }

      local order = tree.file_order(node)

      assert.are.equal(3, #order)
      assert.are.equal("a.lua", order[1])
      assert.are.equal("m.lua", order[2])
      assert.are.equal("z.lua", order[3])
    end)

    it("handles nested directories in order", function()
      local node = {
        files = {},
        children = {
          z_dir = { files = { { file_path = "z_dir/file.lua" } }, children = {} },
          a_dir = { files = { { file_path = "a_dir/file.lua" } }, children = {} }
        }
      }

      local order = tree.file_order(node)

      assert.are.equal("a_dir/file.lua", order[1])
      assert.are.equal("z_dir/file.lua", order[2])
    end)

    it("handles empty tree", function()
      local order = tree.file_order({ files = {}, children = {} })
      assert.are.equal(0, #order)
    end)
  end)
end)
