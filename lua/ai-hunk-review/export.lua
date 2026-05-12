local diff = require("ai-hunk-review.diff")

local M = {}

function M.encode_pretty(value, indent)
  indent = indent or 0
  local prefix = string.rep("  ", indent)
  local next_prefix = string.rep("  ", indent + 1)

  if type(value) ~= "table" then
    return vim.json.encode(value)
  end

  local is_array = vim.islist(value)
  local parts = {}

  if is_array then
    if vim.tbl_isempty(value) then
      return "[]"
    end

    for _, item in ipairs(value) do
      table.insert(parts, next_prefix .. M.encode_pretty(item, indent + 1))
    end

    return "[\n" .. table.concat(parts, ",\n") .. "\n" .. prefix .. "]"
  end

  local keys = vim.tbl_keys(value)
  table.sort(keys)

  if vim.tbl_isempty(keys) then
    return "{}"
  end

  for _, key in ipairs(keys) do
    table.insert(parts, next_prefix .. vim.json.encode(key) .. ": " .. M.encode_pretty(value[key], indent + 1))
  end

  return "{\n" .. table.concat(parts, ",\n") .. "\n" .. prefix .. "}"
end

function M.payload(hunks, comments, repo_root)
  local items = {}

  for _, hunk in ipairs(hunks) do
    local changes = {}

    for _, block in ipairs(diff.get_change_blocks(hunk)) do
      table.insert(changes, {
        diff_start = block.start,
        diff_end = block["end"],
        kind = block.kind,
        line = diff.source_line_for_hunk_offset(hunk, block.start),
        lines = block.lines,
        comment = comments[block.id] or "",
      })
    end

    table.insert(items, {
      file = hunk.file_path,
      header = hunk.header,
      line = hunk.parsed and hunk.parsed.new_start or 1,
      diff = hunk.lines,
      changes = changes,
    })
  end

  return {
    plugin = "ai-hunk-review.nvim",
    repo_root = repo_root,
    generated_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    instructions = "Review each hunk with its user comment. Propose or apply code changes only when the comment requests an action.",
    hunks = items,
  }
end

function M.clipboard_text(hunks, comments)
  local sections = {}

  for _, hunk in ipairs(hunks) do
    local commented_blocks = {}

    for _, block in ipairs(diff.get_change_blocks(hunk)) do
      local comment = comments[block.id]
      if comment and comment ~= "" then
        table.insert(commented_blocks, {
          comment = comment,
          lines = block.lines,
          line = diff.source_line_for_hunk_offset(hunk, block.start),
        })
      end
    end

    if #commented_blocks > 0 then
      for _, cb in ipairs(commented_blocks) do
        table.insert(sections, cb.comment)
        table.insert(sections, hunk.file_path .. ":" .. cb.line)
        table.insert(sections, "```")
        for _, line in ipairs(cb.lines) do
          table.insert(sections, line)
        end
        table.insert(sections, "```")
        table.insert(sections, "")
      end
    end
  end

  if #sections == 0 then
    return nil
  end

  return table.concat(sections, "\n")
end

return M
