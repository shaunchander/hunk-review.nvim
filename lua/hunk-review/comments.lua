local api = vim.api
local diff = require("hunk-review.diff")

local M = {}

local function build_picker_items(state)
  local items = {}

  for _, hunk in ipairs(state.hunks) do
    -- Block comments
    for _, block in ipairs(diff.get_change_blocks(hunk)) do
      local comment = state.comments[block.id]
      if comment and comment ~= "" then
        local source_line = diff.source_line_for_hunk_offset(hunk, block.start)
        local preview_lines = {}
        for i = 1, math.min(3, #block.lines) do
          table.insert(preview_lines, block.lines[i])
        end

        table.insert(items, {
          text = hunk.file_path .. ":" .. source_line .. " - " .. comment,
          file = hunk.file_path,
          line = source_line,
          comment = comment,
          comment_key = block.id,
          hunk = hunk,
          diff_index = block.start,
          preview = table.concat(preview_lines, "\n"),
        })
      end
    end

    -- Range/line comments
    for _, rc in ipairs(diff.get_range_comments_for_hunk(hunk, state.comments)) do
      local start_line = diff.source_line_for_hunk_offset(hunk, rc.start_idx)
      local end_line = rc.start_idx ~= rc.end_idx
        and diff.source_line_for_hunk_offset(hunk, rc.end_idx)
        or nil

      local loc = end_line and (start_line .. "-" .. end_line) or tostring(start_line)
      local preview_lines = {}
      for di = rc.start_idx, math.min(rc.end_idx, rc.start_idx + 2) do
        if hunk.lines[di] then
          table.insert(preview_lines, hunk.lines[di])
        end
      end

      table.insert(items, {
        text = hunk.file_path .. ":" .. loc .. " - " .. rc.comment,
        file = hunk.file_path,
        line = start_line,
        comment = rc.comment,
        comment_key = rc.key,
        hunk = hunk,
        diff_index = rc.start_idx,
        preview = table.concat(preview_lines, "\n"),
      })
    end
  end

  return items
end

function M.close(state)
  -- Snacks picker handles its own lifecycle, nothing to clean up
  state.comments_sidebar_open = false
end

function M.open(state)
  local ok, snacks = pcall(require, "snacks")
  if not ok then
    vim.notify("snacks.nvim not available", vim.log.levels.WARN, { title = "hunk-review" })
    return
  end

  local items = build_picker_items(state)

  if #items == 0 then
    vim.notify("No comments yet. Press 'c' on a change block to add one.", vim.log.levels.INFO, { title = "hunk-review" })
    return
  end

  state.comments_sidebar_open = true

  snacks.picker.pick({
    prompt = "Comments",
    format = "file",
    items = items,
    preview = function(item, ctx)
      if not item then return end
      return {
        text = item.preview,
        ft = "diff",
      }
    end,
    confirm = function(item)
      if not item then return end

      -- Jump to the comment in the diff view
      if not state.review_winid or not api.nvim_win_is_valid(state.review_winid) then
        return
      end

      for line_nr, mapped in pairs(state.line_map) do
        if mapped.hunk == item.hunk and mapped.diff_index == item.diff_index and mapped.kind == "diff_line" then
          api.nvim_set_current_win(state.review_winid)
          api.nvim_win_set_cursor(state.review_winid, { line_nr, 0 })
          return
        end
      end
    end,
    actions = {
      delete = function(item)
        if item and item.comment_key then
          state.comments[item.comment_key] = nil
          -- Refresh the picker with updated items
          M.open(state)
        end
      end,
    },
    win = {
      input = {
        keys = {
          ["<C-d>"] = { "delete", mode = { "n", "i" } },
        },
      },
    },
  })

  state.comments_sidebar_open = false
end

function M.toggle(state)
  -- Since snacks picker doesn't maintain state, just open it
  M.open(state)
end

function M.refresh(state)
  -- Only refresh if currently open (which won't be the case with pickers)
  -- This is a no-op for snacks pickers
end

return M
