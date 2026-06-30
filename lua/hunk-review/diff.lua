local M = {}

local function hash_changes(lines)
  local h = 5381
  for _, line in ipairs(lines) do
    local prefix = line:sub(1, 1)
    if prefix == "+" or prefix == "-" then
      for i = 1, #line do
        h = ((h * 33) + line:byte(i)) % 2147483647
      end
    end
  end
  return string.format("%x", h)
end

function M.make_hunk_id(file_path, hunk_lines)
  return file_path .. "::" .. hash_changes(hunk_lines)
end

function M.make_range_comment_key(hunk, start_diff_index, end_diff_index)
  return "range::" .. M.make_hunk_id(hunk.file_path, hunk.lines)
    .. "::" .. tostring(start_diff_index) .. "::" .. tostring(end_diff_index)
end

function M.make_line_comment_key(hunk, diff_index)
  return M.make_range_comment_key(hunk, diff_index, diff_index)
end

function M.make_change_block_id(hunk, start_index, end_index, kind)
  return table.concat({
    M.make_hunk_id(hunk.file_path, hunk.lines),
    tostring(start_index),
    tostring(end_index),
    kind,
  }, "::")
end

local function collect_change_blocks(hunk)
  local blocks = {}
  local current = nil

  for diff_index, diff_line in ipairs(hunk.lines) do
    local prefix = diff_line:sub(1, 1)
    local kind = nil
    if prefix == "+" then
      kind = "add"
    elseif prefix == "-" then
      kind = "delete"
    end

    if kind then
      if current and current.kind == kind and current["end"] == diff_index - 1 then
        current["end"] = diff_index
        table.insert(current.lines, diff_line)
      else
        current = {
          kind = kind,
          start = diff_index,
          ["end"] = diff_index,
          lines = { diff_line },
        }
        table.insert(blocks, current)
      end
      current.id = M.make_change_block_id(hunk, current.start, current["end"], kind)
    else
      current = nil
    end
  end

  return blocks
end

function M.get_change_blocks(hunk)
  if not hunk._blocks then
    hunk._blocks = collect_change_blocks(hunk)
  end
  return hunk._blocks
end

local function build_source_line_map(hunk)
  local parsed = hunk.parsed
  if not parsed then
    return {}
  end

  local map = {}
  local target = parsed.new_start
  local new_line = parsed.new_start

  for index, text in ipairs(hunk.lines) do
    local prefix = text:sub(1, 1)
    if prefix == " " or prefix == "+" then
      target = new_line
      new_line = new_line + 1
    elseif prefix == "-" then
      target = new_line
    end
    map[index] = math.max(target, 1)
  end

  return map
end

function M.source_line_for_hunk_offset(hunk, diff_index)
  if not hunk._source_lines then
    hunk._source_lines = build_source_line_map(hunk)
  end
  return hunk._source_lines[diff_index] or 1
end

function M.get_range_comments_for_hunk(hunk, comments)
  local prefix = "range::" .. M.make_hunk_id(hunk.file_path, hunk.lines) .. "::"
  local results = {}

  for key, comment in pairs(comments) do
    if comment ~= "" and key:sub(1, #prefix) == prefix then
      local rest = key:sub(#prefix + 1)
      local s, e = rest:match("^(%d+)::(%d+)$")
      if s then
        local start_idx = tonumber(s)
        local end_idx = tonumber(e)
        table.insert(results, {
          key = key,
          start_idx = start_idx,
          end_idx = end_idx,
          comment = comment,
        })
      end
    end
  end

  -- Sort by start index for consistent ordering
  table.sort(results, function(a, b)
    return a.start_idx < b.start_idx
  end)

  return results
end

function M.file_entries(hunks)
  local entries = {}
  local by_file = {}

  for hunk_index, hunk in ipairs(hunks) do
    local entry = by_file[hunk.file_path]
    if not entry then
      entry = {
        file_path = hunk.file_path,
        hunk_count = 0,
        additions = 0,
        deletions = 0,
        first_hunk_index = hunk_index,
      }
      by_file[hunk.file_path] = entry
      table.insert(entries, entry)
    end

    entry.hunk_count = entry.hunk_count + 1
    for _, line in ipairs(hunk.lines) do
      local prefix = line:sub(1, 1)
      if prefix == "+" then
        entry.additions = entry.additions + 1
      elseif prefix == "-" then
        entry.deletions = entry.deletions + 1
      end
    end
  end

  return entries
end

function M.count_file_comments(file_path, comments)
  local count = 0
  for key, comment in pairs(comments) do
    if comment ~= "" and key:find(file_path, 1, true) then
      count = count + 1
    end
  end
  return count
end

function M.file_icon(path)
  local ext = path:match("%.([^.]+)$") or ""
  local by_ext = {
    lua = "",
    ts = "",
    tsx = "",
    js = "",
    jsx = "",
    json = "",
    md = "",
    vim = "",
    yml = "",
    yaml = "",
  }
  return by_ext[ext] or "󰈔"
end

return M
