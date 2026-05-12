local M = {}

function M.make_hunk_id(file_path, header)
  return file_path .. "::" .. header
end

function M.make_change_block_id(hunk, start_index, end_index, kind)
  return table.concat({
    M.make_hunk_id(hunk.file_path, hunk.header),
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

function M.file_entries(hunks)
  local entries = {}
  local by_file = {}

  for hunk_index, hunk in ipairs(hunks) do
    local entry = by_file[hunk.file_path]
    if not entry then
      entry = {
        file_path = hunk.file_path,
        hunk_count = 0,
        change_count = 0,
        first_hunk_index = hunk_index,
      }
      by_file[hunk.file_path] = entry
      table.insert(entries, entry)
    end

    entry.hunk_count = entry.hunk_count + 1
    entry.change_count = entry.change_count + #M.get_change_blocks(hunk)
  end

  return entries
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
