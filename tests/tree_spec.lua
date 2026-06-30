-- Tests for hunk-review.tree module
local tree = require("hunk-review.tree")

describe("tree module", function()
  describe("build_file_tree", function()
    it("builds tree from flat file list", function()
      local entries = {
        { file_path = "file1.lua", additions = 1, deletions = 0, change_count = 1 },
        { file_path = "file2.lua", additions = 2, deletions = 1, change_count = 3 },
      }

      local result = tree.build_file_tree(entries)

      assert.is_table(result)
      assert.is_table(result.files)
      assert.is_table(result.children)
      assert.are.equal(2, #result.files)
    end)

    it("builds nested tree from paths with directories", function()
      local entries = {
        { file_path = "src/main.lua", additions = 1, deletions = 0, change_count = 1 },
        { file_path = "src/utils.lua", additions = 2, deletions = 1, change_count = 3 },
        { file_path = "test/test.lua", additions = 1, deletions = 1, change_count = 2 },
      }

      local result = tree.build_file_tree(entries)

      assert.is_table(result.children.src)
      assert.is_table(result.children.test)
      assert.are.equal(2, #result.children.src.files)
      assert.are.equal(1, #result.children.test.files)
    end)

    it("handles deeply nested paths", function()
      local entries = {
        { file_path = "a/b/c/d/file.lua", additions = 1, deletions = 0, change_count = 1 },
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
        { file_path = "root.lua", additions = 1, deletions = 0, change_count = 1 },
        { file_path = "dir/nested.lua", additions = 2, deletions = 1, change_count = 3 },
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
        files = {
          { file_path = "test.lua", additions = 1, deletions = 0, change_count = 1 }
        },
        children = {}
      }

      local lines = {}
      local highlights = {}
      local line_map = {}

      tree.render_tree_node(node, "", lines, highlights, line_map, 0, {}, nil, {})

      assert.are.equal(1, #lines)
      assert.is_true(lines[1]:match("test.lua") ~= nil)
    end)

    it("renders directories with files", function()
      local node = {
        files = {},
        children = {
          src = {
            files = {
              { file_path = "src/main.lua", additions = 1, deletions = 0, change_count = 1 }
            },
            children = {}
          }
        }
      }

      local lines = {}
      local highlights = {}
      local line_map = {}

      tree.render_tree_node(node, "", lines, highlights, line_map, 0, {}, nil, {})

      -- Should have directory line + file line
      assert.is_true(#lines >= 2)
      assert.is_true(lines[1]:match("src/") ~= nil)
      assert.is_true(lines[2]:match("main.lua") ~= nil)
    end)

    it("marks selected file", function()
      local node = {
        files = {
          { file_path = "test.lua", additions = 1, deletions = 0, change_count = 1 }
        },
        children = {}
      }

      local lines = {}
      local highlights = {}
      local line_map = {}

      tree.render_tree_node(node, "", lines, highlights, line_map, 0, {}, "test.lua", {})

      assert.is_true(lines[1]:match(">") ~= nil)
    end)

    it("respects depth for indentation", function()
      local node = {
        files = {
          { file_path = "test.lua", additions = 1, deletions = 0, change_count = 1 }
        },
        children = {}
      }

      local lines_depth_0 = {}
      local lines_depth_2 = {}

      tree.render_tree_node(node, "", lines_depth_0, {}, {}, 0, {}, nil, {})
      tree.render_tree_node(node, "", lines_depth_2, {}, {}, 2, {}, nil, {})

      -- Depth 2 should have more leading whitespace
      assert.is_true(#lines_depth_2[1] > #lines_depth_0[1])
    end)

    it("collapses directories when specified", function()
      local node = {
        files = {},
        children = {
          src = {
            files = {
              { file_path = "src/main.lua", additions = 1, deletions = 0, change_count = 1 }
            },
            children = {}
          }
        }
      }

      local lines = {}
      local collapsed = { src = true }

      tree.render_tree_node(node, "", lines, {}, {}, 0, collapsed, nil, {})

      -- Should only show directory line, not file
      assert.are.equal(1, #lines)
      assert.is_true(lines[1]:match("src/") ~= nil)
      assert.is_true(lines[1]:match("▸") ~= nil) -- collapsed chevron
    end)

    it("expands directories by default", function()
      local node = {
        files = {},
        children = {
          src = {
            files = {
              { file_path = "src/main.lua", additions = 1, deletions = 0, change_count = 1 }
            },
            children = {}
          }
        }
      }

      local lines = {}

      tree.render_tree_node(node, "", lines, {}, {}, 0, {}, nil, {})

      -- Should show both directory and file
      assert.is_true(#lines > 1)
      assert.is_true(lines[1]:match("▾") ~= nil) -- expanded chevron
    end)

    it("shows file change counts", function()
      local node = {
        files = {
          { file_path = "test.lua", additions = 5, deletions = 3, change_count = 8 }
        },
        children = {}
      }

      local lines = {}

      tree.render_tree_node(node, "", lines, {}, {}, 0, {}, nil, {})

      assert.is_true(lines[1]:match("%+5") ~= nil)
      assert.is_true(lines[1]:match("%-3") ~= nil)
    end)

    it("creates highlight entries", function()
      local node = {
        files = {
          { file_path = "test.lua", additions = 1, deletions = 0, change_count = 1 }
        },
        children = {}
      }

      local highlights = {}

      tree.render_tree_node(node, "", {}, highlights, {}, 0, {}, nil, {})

      -- Should have at least the add/delete highlights
      assert.is_true(#highlights >= 2)
    end)

    it("creates line map entries", function()
      local node = {
        files = {
          { file_path = "test.lua", additions = 1, deletions = 0, change_count = 1 }
        },
        children = {
          src = { files = {}, children = {} }
        }
      }

      local line_map = {}

      tree.render_tree_node(node, "", {}, {}, line_map, 0, {}, nil, {})

      -- Should have entries for both directory and file
      assert.is_true(#vim.tbl_keys(line_map) >= 2)
    end)
  end)

  describe("file_order", function()
    it("returns files in tree order", function()
      local node = {
        files = {
          { file_path = "root.lua" }
        },
        children = {
          src = {
            files = {
              { file_path = "src/main.lua" }
            },
            children = {}
          }
        }
      }

      local order = tree.file_order(node)

      assert.are.equal(2, #order)
      -- Directory files come before root files
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
          z_dir = {
            files = { { file_path = "z_dir/file.lua" } },
            children = {}
          },
          a_dir = {
            files = { { file_path = "a_dir/file.lua" } },
            children = {}
          }
        }
      }

      local order = tree.file_order(node)

      -- Directories are sorted alphabetically
      assert.are.equal("a_dir/file.lua", order[1])
      assert.are.equal("z_dir/file.lua", order[2])
    end)

    it("handles empty tree", function()
      local node = {
        files = {},
        children = {}
      }

      local order = tree.file_order(node)

      assert.are.equal(0, #order)
    end)
  end)
end)
