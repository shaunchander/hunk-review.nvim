local api = vim.api
local diff = require("hunk-review.diff")

local M = {}

local ns = api.nvim_create_namespace("hunk-review-comments")

local function build_entries(state)
  local entries = {}
  local by_file = {}

  for _, hunk in ipairs(state.hunks) do
    for _, block in ipairs(diff.get_change_blocks(hunk)) do
      local comment = state.comments[block.id]
      if comment and comment ~= "" then
        if not by_file[hunk.file_path] then
          by_file[hunk.file_path] = {}
        end
        table.insert(by_file[hunk.file_path], {
          comment = comment,
          comment_key = block.id,
          source_line = diff.source_line_for_hunk_offset(hunk, block.start),
          end_source_line = nil,
          context_lines = block.lines,
          hunk = hunk,
          diff_index = block.start,
        })
      end
    end

    for _, rc in ipairs(diff.get_range_comments_for_hunk(hunk, state.comments)) do
      if not by_file[hunk.file_path] then
        by_file[hunk.file_path] = {}
      end
      local context = {}
      for di = rc.start_idx, rc.end_idx do
        if hunk.lines[di] then
          table.insert(context, hunk.lines[di])
        end
      end
      local start_line = diff.source_line_for_hunk_offset(hunk, rc.start_idx)
      local end_line = rc.start_idx ~= rc.end_idx
        and diff.source_line_for_hunk_offset(hunk, rc.end_idx)
        or nil
      table.insert(by_file[hunk.file_path], {
        comment = rc.comment,
        comment_key = rc.key,
        source_line = start_line,
        end_source_line = end_line,
        context_lines = context,
        hunk = hunk,
        diff_index = rc.start_idx,
      })
    end
  end

  local file_paths = vim.tbl_keys(by_file)
  table.sort(file_paths)
  for _, fp in ipairs(file_paths) do
    table.insert(entries, { file_path = fp, comments = by_file[fp] })
  end

  return entries
end

local function render_sidebar(state)
  local entries = build_entries(state)

  local total = 0
  for _, entry in ipairs(entries) do
    total = total + #entry.comments
  end

  local lines = {}
  local highlights = {}
  local line_map = {}

  table.insert(lines, " Comments (" .. total .. ")")
  table.insert(highlights, { line = #lines - 1, group = "Title" })
  table.insert(lines, "")

  if total == 0 then
    table.insert(lines, "No comments yet.")
    table.insert(highlights, { line = #lines - 1, group = "Comment" })
    table.insert(lines, "")
    table.insert(lines, "Press c on a change block to add one.")
    table.insert(highlights, { line = #lines - 1, group = "Comment" })
    return lines, highlights, line_map
  end

  for _, entry in ipairs(entries) do
    local separator = string.rep("─", 40)
    table.insert(lines, separator)
    table.insert(highlights, { line = #lines - 1, group = "Comment" })
    table.insert(lines, "  " .. diff.file_icon(entry.file_path) .. " " .. entry.file_path)
    table.insert(highlights, { line = #lines - 1, group = "Statement" })
    table.insert(lines, separator)
    table.insert(highlights, { line = #lines - 1, group = "Comment" })
    table.insert(lines, "")

    for _, c in ipairs(entry.comments) do
      local loc
      if c.end_source_line then
        loc = "L" .. c.source_line .. "-L" .. c.end_source_line
      else
        loc = "L" .. c.source_line
      end

      table.insert(lines, "  " .. loc .. ": " .. c.comment)
      table.insert(highlights, { line = #lines - 1, group = "Directory" })
      line_map[#lines] = { hunk = c.hunk, diff_index = c.diff_index, comment_key = c.comment_key }

      local max_context = 3
      for i, ctx_line in ipairs(c.context_lines) do
        if i > max_context then
          table.insert(lines, "    ...")
          table.insert(highlights, { line = #lines - 1, group = "Comment" })
          break
        end
        table.insert(lines, "    " .. ctx_line)
        local prefix = ctx_line:sub(1, 1)
        local group = "Normal"
        if prefix == "+" then group = "DiffAdd"
        elseif prefix == "-" then group = "DiffDelete"
        end
        table.insert(highlights, { line = #lines - 1, group = group })
      end

      table.insert(lines, "")
    end
  end

  return lines, highlights, line_map
end

function M.close(state)
  if state.comments_winid and api.nvim_win_is_valid(state.comments_winid) then
    pcall(api.nvim_win_close, state.comments_winid, true)
  end
  state.comments_winid = nil
  state.comments_sidebar_open = false
end

function M.open(state)
  M.close(state)

  local lines, highlights, line_map = render_sidebar(state)

  local bufnr = api.nvim_create_buf(false, true)
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].buflisted = false

  api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  for _, hl in ipairs(highlights) do
    local col_start = hl.col_start or 0
    local col_end = hl.col_end
    local opts = { hl_group = hl.group, priority = 100 }
    if col_end and col_end >= 0 then
      opts.end_col = col_end
    else
      local line_text = api.nvim_buf_get_lines(bufnr, hl.line, hl.line + 1, false)[1] or ""
      opts.end_col = #line_text
    end
    api.nvim_buf_set_extmark(bufnr, ns, hl.line, col_start, opts)
  end
  vim.bo[bufnr].modifiable = false

  local width, height, row, col
  if state.review_winid and api.nvim_win_is_valid(state.review_winid) then
    local pos = api.nvim_win_get_position(state.review_winid)
    local review_width = api.nvim_win_get_width(state.review_winid)
    width = math.floor(review_width * 0.45)
    height = api.nvim_win_get_height(state.review_winid)
    row = pos[1]
    col = pos[2] + review_width - width
  else
    width = math.floor(vim.o.columns * 0.4)
    height = math.floor(vim.o.lines * 0.8)
    row = math.floor((vim.o.lines - height) / 2)
    col = vim.o.columns - width - 2
  end

  local winid = api.nvim_open_win(bufnr, true, {
    relative = "editor",
    border = "rounded",
    title = " Comments ",
    title_pos = "center",
    width = math.max(width - 2, 1),
    height = math.max(height - 2, 1),
    row = row,
    col = col,
    zindex = 60,
  })
  state.comments_winid = winid
  state.comments_sidebar_open = true

  vim.wo[winid].wrap = true
  vim.wo[winid].cursorline = true
  vim.wo[winid].signcolumn = "no"
  vim.wo[winid].number = false
  vim.wo[winid].relativenumber = false
  vim.wo[winid].statuscolumn = ""

  local function close() M.close(state) end

  local function jump_to_comment()
    local cursor_line = api.nvim_win_get_cursor(winid)[1]
    local entry = line_map[cursor_line]
    if not entry then return end

    M.close(state)

    if not state.review_winid or not api.nvim_win_is_valid(state.review_winid) then
      return
    end

    for line_nr, item in pairs(state.line_map) do
      if item.hunk == entry.hunk and item.diff_index == entry.diff_index and item.kind == "diff_line" then
        api.nvim_set_current_win(state.review_winid)
        api.nvim_win_set_cursor(state.review_winid, { line_nr, 0 })
        return
      end
    end
  end

  local function next_comment()
    local cursor_line = api.nvim_win_get_cursor(winid)[1]
    local line_count = api.nvim_buf_line_count(bufnr)
    for ln = cursor_line + 1, line_count do
      if line_map[ln] then
        api.nvim_win_set_cursor(winid, { ln, 0 })
        return
      end
    end
  end

  local function prev_comment()
    local cursor_line = api.nvim_win_get_cursor(winid)[1]
    for ln = cursor_line - 1, 1, -1 do
      if line_map[ln] then
        api.nvim_win_set_cursor(winid, { ln, 0 })
        return
      end
    end
  end

  local function delete_comment()
    local cursor_line = api.nvim_win_get_cursor(winid)[1]
    local entry = line_map[cursor_line]
    if not entry or not entry.comment_key then return end
    state.comments[entry.comment_key] = nil
    M.refresh(state)
  end

  vim.keymap.set("n", "j", next_comment, { buffer = bufnr, nowait = true, silent = true })
  vim.keymap.set("n", "k", prev_comment, { buffer = bufnr, nowait = true, silent = true })
  vim.keymap.set("n", "d", delete_comment, { buffer = bufnr, nowait = true, silent = true })
  vim.keymap.set("n", "q", close, { buffer = bufnr, nowait = true, silent = true })
  vim.keymap.set("n", "<Esc>", close, { buffer = bufnr, nowait = true, silent = true })
  vim.keymap.set("n", "C", close, { buffer = bufnr, nowait = true, silent = true })
  vim.keymap.set("n", "<CR>", jump_to_comment, { buffer = bufnr, nowait = true, silent = true })

  local group = api.nvim_create_augroup("HunkReviewComments", { clear = true })
  api.nvim_create_autocmd("WinClosed", {
    group = group,
    pattern = tostring(winid),
    once = true,
    callback = function()
      state.comments_winid = nil
      state.comments_sidebar_open = false
    end,
  })
end

function M.toggle(state)
  if state.comments_sidebar_open then
    M.close(state)
  else
    M.open(state)
  end
end

function M.refresh(state)
  if not state.comments_sidebar_open then return end
  M.open(state)
end

return M
