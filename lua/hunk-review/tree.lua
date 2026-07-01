local diff = require("hunk-review.diff")

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

function M.render_tree_node(node, dir_path, lines, highlights, line_map, depth, collapsed_dirs, selected_file, comments)
  local dir_names = vim.tbl_keys(node.children)
  table.sort(dir_names)

  for _, dir_name in ipairs(dir_names) do
    local child = node.children[dir_name]
    local compacted, display_name = compact_dir_path(child, dir_name)
    local full_path = dir_path ~= "" and (dir_path .. "/" .. display_name) or display_name
    local collapsed = collapsed_dirs[full_path]
    local indent = string.rep("  ", depth)
    local chevron = collapsed and "▸" or "▾"
    local dir_icon, dir_icon_hl = diff.file_icon(display_name, "directory")

    local line_text = indent .. chevron .. " " .. dir_icon .. " " .. display_name .. "/"
    table.insert(lines, line_text)
    local row = #lines - 1

    -- Highlight the directory icon with its specific highlight group
    if dir_icon_hl then
      local icon_start = #indent + #chevron + 1
      table.insert(highlights, { line = row, col_start = icon_start, col_end = icon_start + #dir_icon, group = dir_icon_hl })
    end
    -- Highlight the directory name
    table.insert(highlights, { line = row, col_start = #indent + #chevron + 1 + #dir_icon + 1, col_end = -1, group = "Directory" })
    line_map[#lines] = { dir_path = full_path }

    if not collapsed then
      M.render_tree_node(compacted, full_path, lines, highlights, line_map, depth + 1, collapsed_dirs, selected_file, comments)
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
    local icon, icon_hl = diff.file_icon(entry.file_path)

    local prefix = indent .. marker .. " " .. icon .. " " .. fname
    local add_str = "  +" .. entry.additions
    local del_str = " -" .. entry.deletions

    local line_text = prefix .. add_str .. del_str
    local row = #lines

    local comment_count = comments and diff.count_file_comments(entry.file_path, comments) or 0
    if comment_count > 0 then
      local comment_str = "  " .. comment_count .. "c"
      line_text = line_text .. comment_str
    end

    table.insert(lines, line_text)
    line_map[#lines] = { file_path = entry.file_path }

    -- Highlight file icon with its specific color
    if icon_hl then
      local icon_start = #indent + #marker + 1
      table.insert(highlights, { line = row, col_start = icon_start, col_end = icon_start + #icon, group = icon_hl })
    end

    -- Highlight selection
    if selected then
      table.insert(highlights, { line = row, col_start = 0, col_end = #prefix, group = "Directory" })
    end

    -- Highlight change counts
    table.insert(highlights, { line = row, col_start = #prefix, col_end = #prefix + #add_str, group = "DiffAdd" })
    table.insert(highlights, { line = row, col_start = #prefix + #add_str, col_end = #prefix + #add_str + #del_str, group = "DiffDelete" })

    -- Highlight comment count
    if comment_count > 0 then
      table.insert(highlights, { line = row, col_start = #prefix + #add_str + #del_str, col_end = -1, group = "Comment" })
    end
  end
end

function M.file_order(node)
  local order = {}

  local dir_names = vim.tbl_keys(node.children)
  table.sort(dir_names)

  for _, dir_name in ipairs(dir_names) do
    local child = node.children[dir_name]
    local compacted = compact_dir_path(child, dir_name)
    for _, file_path in ipairs(M.file_order(compacted)) do
      table.insert(order, file_path)
    end
  end

  local sorted_files = vim.tbl_values(node.files)
  table.sort(sorted_files, function(a, b)
    local a_name = a.file_path:match("[^/]+$")
    local b_name = b.file_path:match("[^/]+$")
    return a_name < b_name
  end)

  for _, entry in ipairs(sorted_files) do
    table.insert(order, entry.file_path)
  end

  return order
end

return M
