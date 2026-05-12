local diff = require("ai-hunk-review.diff")

local M = {}

function M.build_file_tree(entries)
  local root = { children = {}, files = {} }

  for _, entry in ipairs(entries) do
    local parts = {}
    for part in entry.file_path:gmatch("[^/]+") do
      table.insert(parts, part)
    end

    if #parts == 1 then
      table.insert(root.files, entry)
    else
      local node = root
      for i = 1, #parts - 1 do
        local dir = parts[i]
        if not node.children[dir] then
          node.children[dir] = { children = {}, files = {} }
        end
        node = node.children[dir]
      end
      table.insert(node.files, entry)
    end
  end

  return root
end

local function compact_dir_path(node, name)
  local child_names = vim.tbl_keys(node.children)
  if #child_names == 1 and #node.files == 0 then
    local child_name = child_names[1]
    local merged = name .. "/" .. child_name
    return compact_dir_path(node.children[child_name], merged)
  end
  return node, name
end

function M.render_tree_node(node, dir_path, lines, highlights, line_map, depth, collapsed_dirs, selected_file)
  local dir_names = vim.tbl_keys(node.children)
  table.sort(dir_names)

  for _, dir_name in ipairs(dir_names) do
    local child = node.children[dir_name]
    local compacted, display_name = compact_dir_path(child, dir_name)
    local full_path = dir_path ~= "" and (dir_path .. "/" .. display_name) or display_name
    local collapsed = collapsed_dirs[full_path]
    local indent = string.rep("  ", depth)
    local chevron = collapsed and "▸" or "▾"

    table.insert(lines, indent .. chevron .. "  " .. display_name .. "/")
    table.insert(highlights, { line = #lines - 1, group = "Directory" })
    line_map[#lines] = { dir_path = full_path }

    if not collapsed then
      M.render_tree_node(compacted, full_path, lines, highlights, line_map, depth + 1, collapsed_dirs, selected_file)
    end
  end

  local sorted_files = vim.tbl_values(node.files)
  table.sort(sorted_files, function(a, b)
    local a_name = a.file_path:match("[^/]+$")
    local b_name = b.file_path:match("[^/]+$")
    return a_name < b_name
  end)

  for _, entry in ipairs(sorted_files) do
    local fname = entry.file_path:match("[^/]+$")
    local indent = string.rep("  ", depth)
    local selected = entry.file_path == selected_file
    local marker = selected and ">" or " "
    local icon = diff.file_icon(entry.file_path)
    local stats = string.format("  %dh %dc", entry.hunk_count, entry.change_count)

    table.insert(lines, indent .. marker .. " " .. icon .. " " .. fname .. stats)
    line_map[#lines] = { file_path = entry.file_path }
    table.insert(highlights, { line = #lines - 1, group = selected and "Directory" or "Normal" })
  end
end

return M
