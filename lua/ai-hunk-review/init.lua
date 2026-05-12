local M = {}

local api = vim.api

local ns = api.nvim_create_namespace("ai-hunk-review")
local syntax_ns = api.nvim_create_namespace("ai-hunk-review-syntax")

local state = {
  layout = nil,
  confirm_bufnr = nil,
  confirm_winid = nil,
  explorer_bufnr = nil,
  explorer_winid = nil,
  review_bufnr = nil,
  review_winid = nil,
  export_bufnr = nil,
  repo_root = nil,
  cwd = nil,
  hunks = {},
  explorer_line_map = {},
  line_map = {},
  comments = {},
  file_filter = "",
  selected_file = nil,
  diff_mode = "uncommitted",
  base_branch = nil,
  peek_winid = nil,
  peek_return_cursor = nil,
  collapsed_dirs = {},
}

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "ai-hunk-review.nvim" })
end

local function get_snacks()
  local ok, snacks = pcall(require, "snacks")
  if ok then
    return snacks
  end
  return nil
end

local function system(cmd, opts)
  local result = vim.system(cmd, vim.tbl_extend("force", { text = true }, opts or {})):wait()
  if result.code ~= 0 then
    return nil, result.stderr
  end
  return result.stdout, nil
end

local function close_confirm_modal()
  if state.confirm_winid and api.nvim_win_is_valid(state.confirm_winid) then
    pcall(api.nvim_win_close, state.confirm_winid, true)
  end
  state.confirm_winid = nil

  if state.confirm_bufnr and api.nvim_buf_is_valid(state.confirm_bufnr) then
    pcall(api.nvim_buf_delete, state.confirm_bufnr, { force = true })
  end
  state.confirm_bufnr = nil
end

local function git_root()
  local root, err = system({ "git", "rev-parse", "--show-toplevel" })
  if not root then
    return nil, err
  end

  return vim.trim(root), nil
end

local function detect_base_branch()
  if state.base_branch then
    return state.base_branch
  end

  for _, branch in ipairs({ "main", "master", "develop" }) do
    local ok = system({ "git", "rev-parse", "--verify", branch })
    if ok then
      state.base_branch = branch
      return branch
    end
  end

  return nil
end

local function make_hunk_id(file_path, header)
  return file_path .. "::" .. header
end

local function make_change_block_id(hunk, start_index, end_index, kind)
  return table.concat({
    make_hunk_id(hunk.file_path, hunk.header),
    tostring(start_index),
    tostring(end_index),
    kind,
  }, "::")
end

local function parse_hunk_header(header)
  local old_start, old_count, new_start, new_count =
    header:match("^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@")

  if not old_start then
    return nil
  end

  return {
    old_start = tonumber(old_start),
    old_count = tonumber(old_count) or 1,
    new_start = tonumber(new_start),
    new_count = tonumber(new_count) or 1,
  }
end

local function collect_hunks(diff_text)
  local hunks = {}
  local current_file = nil
  local current_hunk = nil

  for line in vim.gsplit(diff_text, "\n", { plain = true, trimempty = true }) do
    if vim.startswith(line, "diff --git ") then
      current_file = nil
      current_hunk = nil
    elseif vim.startswith(line, "+++ b/") then
      current_file = line:sub(7)
      current_hunk = nil
    elseif vim.startswith(line, "@@ ") then
      if current_file then
        current_hunk = {
          file_path = current_file,
          header = line,
          parsed = parse_hunk_header(line),
          lines = {},
        }
        table.insert(hunks, current_hunk)
      end
    elseif current_hunk and not vim.startswith(line, "--- ") and not vim.startswith(line, "index ") then
      table.insert(current_hunk.lines, line)
    end
  end

  return hunks
end

local function load_hunks(mode)
  local root, root_err = git_root()
  if not root then
    return nil, root_err or "Not inside a Git repository"
  end

  local diff_target = "HEAD"

  if mode == "full" then
    local base = detect_base_branch()
    if not base then
      return nil, "Could not detect base branch (tried main, master, develop)"
    end

    local merge_base, mb_err = system({ "git", "-C", root, "merge-base", base, "HEAD" })
    if not merge_base then
      return nil, mb_err or "Could not find merge-base"
    end

    diff_target = vim.trim(merge_base)
  end

  local diff, diff_err = system({
    "git",
    "-C",
    root,
    "diff",
    "--no-color",
    "--no-ext-diff",
    "--unified=3",
    diff_target,
    "--",
  })

  if not diff then
    return nil, diff_err
  end

  return {
    repo_root = root,
    cwd = (vim.uv or vim.loop).cwd(),
    hunks = collect_hunks(diff),
  }, nil
end

local function encode_pretty(value, indent)
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
      table.insert(parts, next_prefix .. encode_pretty(item, indent + 1))
    end

    return "[\n" .. table.concat(parts, ",\n") .. "\n" .. prefix .. "]"
  end

  local keys = vim.tbl_keys(value)
  table.sort(keys)

  if vim.tbl_isempty(keys) then
    return "{}"
  end

  for _, key in ipairs(keys) do
    table.insert(parts, next_prefix .. vim.json.encode(key) .. ": " .. encode_pretty(value[key], indent + 1))
  end

  return "{\n" .. table.concat(parts, ",\n") .. "\n" .. prefix .. "}"
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
        current.id = make_change_block_id(hunk, current.start, current["end"], kind)
        table.insert(blocks, current)
      end
      current.id = make_change_block_id(hunk, current.start, current["end"], kind)
    else
      current = nil
    end
  end

  return blocks
end

local current_hunk_at_cursor
local render_explorer
local current_file_entries
local export_payload

local function file_entries()
  local entries = {}
  local by_file = {}

  for hunk_index, hunk in ipairs(state.hunks) do
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
    entry.change_count = entry.change_count + #collect_change_blocks(hunk)
  end

  return entries
end

local function filtered_file_entries()
  local entries = current_file_entries()
  local filter = vim.trim(state.file_filter or "")
  if filter == "" then
    return entries
  end

  local needle = filter:lower()
  return vim.tbl_filter(function(entry)
    return entry.file_path:lower():find(needle, 1, true) ~= nil
  end, entries)
end

current_file_entries = function()
  local entries = file_entries()

  if #entries == 0 then
    state.selected_file = nil
    return entries
  end

  if state.selected_file then
    for _, entry in ipairs(entries) do
      if entry.file_path == state.selected_file then
        return entries
      end
    end
  end

  state.selected_file = entries[1].file_path
  return entries
end

local peek_keymaps = {}

local function clear_peek_keymaps()
  for _, km in ipairs(peek_keymaps) do
    pcall(vim.keymap.del, "n", km.lhs, { buffer = km.buf })
  end
  peek_keymaps = {}
end

local function close_peek()
  clear_peek_keymaps()
  pcall(api.nvim_del_augroup_by_name, "AiHunkReviewPeek")

  if state.peek_winid and api.nvim_win_is_valid(state.peek_winid) then
    pcall(api.nvim_win_close, state.peek_winid, true)
  end
  state.peek_winid = nil

  if state.peek_return_cursor and state.review_winid and api.nvim_win_is_valid(state.review_winid) then
    api.nvim_set_current_win(state.review_winid)
    pcall(api.nvim_win_set_cursor, state.review_winid, state.peek_return_cursor)
  end
  state.peek_return_cursor = nil
end

local function close_layout()
  close_peek()
  close_confirm_modal()

  if state.layout then
    pcall(function()
      state.layout:close({ buf = false })
    end)
    state.layout = nil
  end

  if state.explorer_winid and api.nvim_win_is_valid(state.explorer_winid) then
    pcall(api.nvim_win_close, state.explorer_winid, true)
  end

  if state.review_winid and api.nvim_win_is_valid(state.review_winid) then
    pcall(api.nvim_win_close, state.review_winid, true)
  end

  state.explorer_winid = nil
  state.review_winid = nil
end

local function select_file(file_path)
  if not file_path then
    return
  end

  state.selected_file = file_path
end

local function selected_file_line()
  for line_nr, item in pairs(state.explorer_line_map) do
    if item.file_path == state.selected_file then
      return line_nr
    end
  end

  return nil
end

local function sync_selection_from_review()
  if api.nvim_get_current_buf() ~= state.review_bufnr then
    return
  end

  local hunk = current_hunk_at_cursor()
  if not hunk or hunk.file_path == state.selected_file then
    return
  end

  state.selected_file = hunk.file_path
  render_explorer()
end

local function jump_review_to_file(file_path)
  if not file_path or not (state.review_winid and api.nvim_win_is_valid(state.review_winid)) then
    return
  end

  for line_nr, item in pairs(state.line_map) do
    if item.kind == "hunk_header" and item.hunk and item.hunk.file_path == file_path then
      api.nvim_set_current_win(state.review_winid)
      api.nvim_win_set_cursor(state.review_winid, { line_nr, 0 })
      sync_selection_from_review()
      return
    end
  end
end

local function focus_explorer()
  if state.explorer_winid and api.nvim_win_is_valid(state.explorer_winid) then
    api.nvim_set_current_win(state.explorer_winid)
  end
end

local function focus_review()
  if state.review_winid and api.nvim_win_is_valid(state.review_winid) then
    api.nvim_set_current_win(state.review_winid)
  end
end

local function open_peek()
  close_peek()

  local hunk, item = current_hunk_at_cursor()
  if not hunk or not state.repo_root then
    return
  end

  if state.review_winid and api.nvim_win_is_valid(state.review_winid) then
    state.peek_return_cursor = api.nvim_win_get_cursor(state.review_winid)
  end

  local target = state.repo_root .. "/" .. hunk.file_path

  local width, height, row, col
  if state.review_winid and api.nvim_win_is_valid(state.review_winid) then
    local pos = api.nvim_win_get_position(state.review_winid)
    width = api.nvim_win_get_width(state.review_winid)
    height = api.nvim_win_get_height(state.review_winid)
    row = pos[1]
    col = pos[2]
  else
    width = math.floor(vim.o.columns * 0.68)
    height = math.floor(vim.o.lines * 0.92)
    row = math.floor((vim.o.lines - height) / 2)
    col = vim.o.columns - width - 2
  end

  local bufnr = vim.fn.bufadd(target)
  vim.fn.bufload(bufnr)

  local winid = api.nvim_open_win(bufnr, true, {
    relative = "editor",
    border = "rounded",
    title = " Peek: " .. hunk.file_path .. " (q to close) ",
    title_pos = "center",
    width = math.max(width - 2, 1),
    height = math.max(height - 2, 1),
    row = row,
    col = col,
    zindex = 60,
  })
  state.peek_winid = winid

  vim.wo[winid].number = true
  vim.wo[winid].relativenumber = true
  vim.wo[winid].cursorline = true
  vim.wo[winid].signcolumn = "yes"
  vim.wo[winid].wrap = false

  pcall(api.nvim_win_set_cursor, winid, { item.source_line or 1, 0 })
  vim.cmd("normal! zz")

  vim.keymap.set("n", "q", close_peek, { buffer = bufnr, nowait = true, silent = true, desc = "Close peek" })
  vim.keymap.set("n", "<Esc>", close_peek, { buffer = bufnr, nowait = true, silent = true, desc = "Close peek" })
  peek_keymaps = {
    { lhs = "q", buf = bufnr },
    { lhs = "<Esc>", buf = bufnr },
  }

  local group = api.nvim_create_augroup("AiHunkReviewPeek", { clear = true })
  api.nvim_create_autocmd("WinClosed", {
    group = group,
    pattern = tostring(winid),
    once = true,
    callback = function()
      clear_peek_keymaps()
      state.peek_winid = nil
      if state.peek_return_cursor and state.review_winid and api.nvim_win_is_valid(state.review_winid) then
        api.nvim_set_current_win(state.review_winid)
        pcall(api.nvim_win_set_cursor, state.review_winid, state.peek_return_cursor)
      end
      state.peek_return_cursor = nil
    end,
  })
end

local function apply_explorer_keymaps(bufnr)
  local function map(lhs, fn, desc)
    vim.keymap.set("n", lhs, fn, { buffer = bufnr, nowait = true, silent = true, desc = desc })
  end

  map("q", close_layout, "Close review layout")
  map("r", function() M.refresh() end, "Refresh review layout")
  map("<CR>", function() M.select_file() end, "Select file")
  map("o", function() M.select_file() end, "Open file in review")
  map("/", function() M.filter_files() end, "Filter files")
  map("x", function() M.clear_filter() end, "Clear file filter")
  map("<C-l>", focus_review, "Focus review pane")

  vim.keymap.set("n", "[", function() M.prev_tab() end, { buffer = bufnr, silent = true, desc = "Previous diff tab" })
  vim.keymap.set("n", "]", function() M.next_tab() end, { buffer = bufnr, silent = true, desc = "Next diff tab" })
end

local function apply_review_keymaps(bufnr)
  local function map(lhs, fn, desc)
    vim.keymap.set("n", lhs, fn, { buffer = bufnr, nowait = true, silent = true, desc = desc })
  end

  map("q", close_layout, "Close review buffer")
  map("r", function() M.refresh() end, "Refresh review buffer")
  map("]h", function() M.next_hunk() end, "Next hunk")
  map("[h", function() M.prev_hunk() end, "Previous hunk")
  map("j", function() M.next_change() end, "Next change")
  map("k", function() M.prev_change() end, "Previous change")
  map("<CR>", function() M.confirm_review() end, "Confirm and copy review")
  map("o", function() M.jump_to_source() end, "Open source")
  map("p", open_peek, "Peek source with LSP")
  map("c", function() M.add_comment() end, "Add change comment")
  map("e", function() M.export() end, "Export review instructions")
  map("<C-h>", focus_explorer, "Focus explorer pane")

  vim.keymap.set("n", "[", function() M.prev_tab() end, { buffer = bufnr, silent = true, desc = "Previous diff tab" })
  vim.keymap.set("n", "]", function() M.next_tab() end, { buffer = bufnr, silent = true, desc = "Next diff tab" })
end

local function clipboard_text()
  local sections = {}

  for _, hunk in ipairs(state.hunks) do
    local commented_blocks = {}

    for _, block in ipairs(collect_change_blocks(hunk)) do
      local comment = state.comments[block.id]
      if comment and comment ~= "" then
        table.insert(commented_blocks, {
          comment = comment,
          lines = block.lines,
          line = source_line_for_hunk_offset(hunk, block.start),
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

local function copy_review_to_clipboard()
  local text = clipboard_text()
  if not text then
    notify("No commented blocks to copy", vim.log.levels.WARN)
    return
  end
  vim.fn.setreg("+", text)
  vim.fn.setreg("*", text)
  vim.fn.setreg('"', text)
  notify("Review copied to clipboard")
end

local function open_confirm_modal()
  close_confirm_modal()

  local bufnr = api.nvim_create_buf(false, true)
  state.confirm_bufnr = bufnr
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].modifiable = true
  vim.bo[bufnr].filetype = "aihunkreviewconfirm"

  local lines = {
    "Confirm Review",
    "",
    "Copy the current review payload to your clipboard?",
    "",
    "[y] Yes, copy review",
    "[n] No, continue reviewing",
  }
  api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false

  local width = 48
  local height = #lines
  local row = math.floor((vim.o.lines - height) / 2) - 1
  local col = math.floor((vim.o.columns - width) / 2)

  local winid = api.nvim_open_win(bufnr, true, {
    relative = "editor",
    style = "minimal",
    border = "rounded",
    title = " Review Confirmation ",
    title_pos = "center",
    width = width,
    height = height,
    row = math.max(row, 1),
    col = math.max(col, 0),
    zindex = 120,
  })
  state.confirm_winid = winid
  vim.wo[winid].wrap = false
  vim.wo[winid].cursorline = true

  local function cancel()
    close_confirm_modal()
    focus_review()
  end

  local function confirm()
    copy_review_to_clipboard()
    close_confirm_modal()
    focus_review()
  end

  vim.keymap.set("n", "y", confirm, { buffer = bufnr, silent = true, desc = "Confirm review copy" })
  vim.keymap.set("n", "n", cancel, { buffer = bufnr, silent = true, desc = "Continue reviewing" })
  vim.keymap.set("n", "q", cancel, { buffer = bufnr, silent = true, desc = "Close confirmation" })
  vim.keymap.set("n", "<Esc>", cancel, { buffer = bufnr, silent = true, desc = "Close confirmation" })
  vim.keymap.set("n", "<CR>", confirm, { buffer = bufnr, silent = true, desc = "Confirm review copy" })

  api.nvim_win_set_cursor(winid, { 5, 0 })
end

local function ensure_explorer_buffer()
  if state.explorer_bufnr and api.nvim_buf_is_valid(state.explorer_bufnr) then
    return state.explorer_bufnr
  end

  local bufnr = api.nvim_create_buf(false, true)
  state.explorer_bufnr = bufnr
  api.nvim_buf_set_name(bufnr, "ai-hunk-review://explorer")

  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "hide"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].modifiable = true
  vim.bo[bufnr].filetype = "aihunkreviewexplorer"
  vim.bo[bufnr].buflisted = false

  apply_explorer_keymaps(bufnr)

  return bufnr
end

local function ensure_review_buffer()
  if state.review_bufnr and api.nvim_buf_is_valid(state.review_bufnr) then
    return state.review_bufnr
  end

  local bufnr = api.nvim_create_buf(false, true)
  state.review_bufnr = bufnr
  api.nvim_buf_set_name(bufnr, "ai-hunk-review://review")

  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "hide"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].modifiable = true
  vim.bo[bufnr].filetype = "aihunkreview"
  vim.bo[bufnr].buflisted = false

  apply_review_keymaps(bufnr)

  local group = api.nvim_create_augroup("AiHunkReviewSync", { clear = false })
  api.nvim_create_autocmd("CursorMoved", {
    group = group,
    buffer = bufnr,
    callback = function()
      sync_selection_from_review()
    end,
  })

  return bufnr
end

local function ensure_layout()
  local explorer_bufnr = ensure_explorer_buffer()
  local review_bufnr = ensure_review_buffer()
  local snacks = get_snacks()

  if snacks and snacks.layout and snacks.win then
    if state.layout and state.layout.valid and state.layout:valid() then
      state.layout:show()
      state.layout:update()
    else
      local explorer = snacks.win({
        buf = explorer_bufnr,
        enter = false,
        show = false,
        fixbuf = true,
        border = "none",
        keys = {
          q = function() close_layout() end,
          r = function() M.refresh() end,
          ["<CR>"] = function() M.select_file() end,
          o = function() M.select_file() end,
          ["/"] = function() M.filter_files() end,
          x = function() M.clear_filter() end,
          ["<C-l>"] = function() focus_review() end,
        },
        wo = {
          wrap = false,
          cursorline = true,
          signcolumn = "no",
          number = false,
          relativenumber = false,
          statuscolumn = "",
        },
      })

      local review = snacks.win({
        buf = review_bufnr,
        enter = true,
        show = false,
        fixbuf = true,
        border = "none",
        keys = {
          q = function() close_layout() end,
          r = function() M.refresh() end,
          ["]h"] = function() M.next_hunk() end,
          ["[h"] = function() M.prev_hunk() end,
          j = function() M.next_change() end,
          k = function() M.prev_change() end,
          ["<CR>"] = function() M.confirm_review() end,
          o = function() M.jump_to_source() end,
          p = function() open_peek() end,
          c = function() M.add_comment() end,
          e = function() M.export() end,
          ["<C-h>"] = function() focus_explorer() end,
        },
        wo = {
          wrap = false,
          cursorline = false,
          signcolumn = "no",
          number = false,
          relativenumber = false,
          statuscolumn = "",
        },
      })

      state.layout = snacks.layout.new({
        show = false,
        wins = {
          explorer = explorer,
          review = review,
        },
        layout = {
          box = "horizontal",
          relative = "editor",
          position = "float",
          border = "rounded",
          title = " AI Hunk Review ",
          title_pos = "center",
          backdrop = 60,
          width = 0.96,
          height = 0.92,
          zindex = 50,
          {
            win = "explorer",
            width = 0.28,
            border = "right",
            title = " Files ",
            title_pos = "center",
          },
          {
            win = "review",
            title = " Review ",
            title_pos = "center",
          },
        },
        on_close = function()
          state.layout = nil
          state.explorer_winid = nil
          state.review_winid = nil
        end,
      })
      state.layout:show()
      state.layout:update()
    end

    state.explorer_winid = state.layout.wins.explorer.win
    state.review_winid = state.layout.wins.review.win
    api.nvim_win_set_buf(state.explorer_winid, explorer_bufnr)
    api.nvim_win_set_buf(state.review_winid, review_bufnr)
    api.nvim_set_current_win(state.review_winid)
    return
  end

  if state.explorer_winid and api.nvim_win_is_valid(state.explorer_winid)
    and state.review_winid and api.nvim_win_is_valid(state.review_winid)
  then
    api.nvim_win_set_buf(state.explorer_winid, explorer_bufnr)
    api.nvim_win_set_buf(state.review_winid, review_bufnr)
    vim.wo[state.explorer_winid].wrap = false
    vim.wo[state.review_winid].wrap = false
    return
  end

  local origin_winid = api.nvim_get_current_win()
  api.nvim_win_set_buf(origin_winid, explorer_bufnr)
  state.explorer_winid = origin_winid
  vim.cmd("rightbelow vsplit")
  state.review_winid = api.nvim_get_current_win()
  api.nvim_win_set_buf(state.review_winid, review_bufnr)
  vim.wo[state.explorer_winid].wrap = false
  vim.wo[state.review_winid].wrap = false
  vim.api.nvim_win_set_width(state.explorer_winid, 32)
  api.nvim_set_current_win(state.review_winid)
end

local function find_source_window()
  for _, winid in ipairs(api.nvim_tabpage_list_wins(0)) do
    if winid ~= state.review_winid and winid ~= state.explorer_winid then
      local bufnr = api.nvim_win_get_buf(winid)
      if bufnr ~= state.export_bufnr then
        return winid
      end
    end
  end

  return nil
end

local function current_explorer_file()
  local bufnr = api.nvim_get_current_buf()
  if bufnr ~= state.explorer_bufnr then
    return nil
  end

  local line = api.nvim_win_get_cursor(0)[1]
  local item = state.explorer_line_map[line]
  if not item then
    return nil
  end

  return item.file_path
end

local function file_icon(path)
  local ext = path:match("%.([^.]+)$") or ""
  local by_ext = {
    lua = "",
    ts = "",
    tsx = "",
    js = "",
    jsx = "",
    json = "",
    md = "",
    vim = "",
    yml = "",
    yaml = "",
  }
  return by_ext[ext] or "󰈔"
end

current_hunk_at_cursor = function()
  local bufnr = api.nvim_get_current_buf()
  if bufnr ~= state.review_bufnr then
    return nil
  end

  local line = api.nvim_win_get_cursor(0)[1]
  local item = state.line_map[line]
  if not item then
    return nil
  end

  return item.hunk, item
end

local function current_change_at_cursor()
  local hunk, item = current_hunk_at_cursor()
  if not hunk or not item then
    return nil
  end

  if item.kind == "diff_line" and item.block_id then
    return hunk, item
  end

  if item.kind == "change_comment" and item.block_id then
    return hunk, item
  end

  return nil
end

local function source_line_for_hunk_offset(hunk, diff_index)
  local parsed = hunk.parsed
  if not parsed then
    return 1
  end

  local target = parsed.new_start
  local new_line = parsed.new_start

  for index = 1, math.max(diff_index, 0) do
    local text = hunk.lines[index]
    local prefix = text and text:sub(1, 1) or nil

    if prefix == " " or prefix == "+" then
      target = new_line
      new_line = new_line + 1
    elseif prefix == "-" then
      target = new_line
    end
  end

  return math.max(target, 1)
end

local function build_file_tree(entries)
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

local function render_tree_node(node, dir_path, lines, highlights, line_map, depth)
  local dir_names = vim.tbl_keys(node.children)
  table.sort(dir_names)

  for _, dir_name in ipairs(dir_names) do
    local child = node.children[dir_name]
    local compacted, display_name = compact_dir_path(child, dir_name)
    local full_path = dir_path ~= "" and (dir_path .. "/" .. display_name) or display_name
    local collapsed = state.collapsed_dirs[full_path]
    local indent = string.rep("  ", depth)
    local chevron = collapsed and "▸" or "▾"

    table.insert(lines, indent .. chevron .. "  " .. display_name .. "/")
    table.insert(highlights, { line = #lines - 1, group = "Directory" })
    line_map[#lines] = { dir_path = full_path }

    if not collapsed then
      render_tree_node(compacted, full_path, lines, highlights, line_map, depth + 1)
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
    local selected = entry.file_path == state.selected_file
    local marker = selected and ">" or " "
    local icon = file_icon(entry.file_path)
    local stats = string.format("  %dh %dc", entry.hunk_count, entry.change_count)

    table.insert(lines, indent .. marker .. " " .. icon .. " " .. fname .. stats)
    line_map[#lines] = { file_path = entry.file_path }
    table.insert(highlights, { line = #lines - 1, group = selected and "Directory" or "Normal" })
  end
end

render_explorer = function()
  local bufnr = ensure_explorer_buffer()
  local lines = {}
  local highlights = {}
  local line_map = {}
  local entries = filtered_file_entries()

  local mode_label = state.diff_mode == "full" and "Full Diff" or "Uncommitted"
  table.insert(lines, "Changed Files (" .. mode_label .. ")")
  table.insert(highlights, { line = #lines - 1, group = "Title" })
  local filter_label = vim.trim(state.file_filter or "")
  table.insert(lines, filter_label ~= "" and ("Filter: " .. filter_label) or "Filter: [none]  (/ to set, x to clear)")
  table.insert(highlights, { line = #lines - 1, group = filter_label ~= "" and "Directory" or "Comment" })
  table.insert(lines, "")

  if #entries == 0 then
    table.insert(lines, filter_label ~= "" and "No matching files." or "No hunks found.")
  else
    local tree = build_file_tree(entries)
    render_tree_node(tree, "", lines, highlights, line_map, 0)
  end

  vim.bo[bufnr].modifiable = true
  api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

  for _, item in ipairs(highlights) do
    api.nvim_buf_add_highlight(bufnr, ns, item.group, item.line, 0, -1)
  end

  vim.bo[bufnr].modifiable = false
  state.explorer_line_map = line_map

  local line_nr = selected_file_line()
  if line_nr and state.explorer_winid and api.nvim_win_is_valid(state.explorer_winid) then
    api.nvim_win_set_cursor(state.explorer_winid, { line_nr, 0 })
  end
end

local ts_query_get = vim.treesitter.query.get or vim.treesitter.query.get_query

local function apply_syntax_highlights(bufnr)
  api.nvim_buf_clear_namespace(bufnr, syntax_ns, 0, -1)

  local file_lines = {}
  for line_nr, item in pairs(state.line_map) do
    if item.kind == "diff_line" and item.hunk then
      local fp = item.hunk.file_path
      if not file_lines[fp] then
        file_lines[fp] = {}
      end
      table.insert(file_lines[fp], {
        line_nr = line_nr,
        is_delete = item.change_kind == "delete",
        is_add = item.change_kind == "add",
      })
    end
  end

  for file_path, entries in pairs(file_lines) do
    local ft = vim.filetype.match({ filename = file_path })
    if not ft then
      goto continue
    end

    local lang = ft
    if vim.treesitter.language.get_lang then
      lang = vim.treesitter.language.get_lang(ft) or ft
    end

    table.sort(entries, function(a, b) return a.line_nr < b.line_nr end)

    local new_content, new_map = {}, {}
    local old_content, old_map = {}, {}

    for _, entry in ipairs(entries) do
      local line = api.nvim_buf_get_lines(bufnr, entry.line_nr - 1, entry.line_nr, false)[1] or ""
      local code = line:sub(6)
      if not entry.is_delete then
        table.insert(new_content, code)
        new_map[#new_content] = entry.line_nr
      end
      if not entry.is_add then
        table.insert(old_content, code)
        old_map[#old_content] = entry.line_nr
      end
    end

    local function highlight_content(content, lmap)
      if #content == 0 then
        return
      end

      local tmp = api.nvim_create_buf(false, true)
      api.nvim_buf_set_lines(tmp, 0, -1, false, content)

      local ok, parser = pcall(vim.treesitter.get_parser, tmp, lang)
      if not ok then
        api.nvim_buf_delete(tmp, { force = true })
        return
      end

      parser:parse()

      local trees = parser:trees()
      if not trees or #trees == 0 then
        api.nvim_buf_delete(tmp, { force = true })
        return
      end

      local qok, query = pcall(ts_query_get, lang, "highlights")
      if not qok or not query then
        api.nvim_buf_delete(tmp, { force = true })
        return
      end

      for id, node in query:iter_captures(trees[1]:root(), tmp) do
        local hl = "@" .. query.captures[id]
        local sr, sc, er, ec = node:range()
        for row = sr, er do
          local review_ln = lmap[row + 1]
          if review_ln then
            local cs = (row == sr) and (sc + 5) or 5
            local ce = (row == er) and (ec + 5) or -1
            api.nvim_buf_add_highlight(bufnr, syntax_ns, hl, review_ln - 1, cs, ce)
          end
        end
      end

      api.nvim_buf_delete(tmp, { force = true })
    end

    highlight_content(new_content, new_map)
    highlight_content(old_content, old_map)

    ::continue::
  end
end

local function render_review()
  local bufnr = ensure_review_buffer()
  local lines = {}
  local highlights = {}
  local line_map = {}

  local tab_uncommitted = state.diff_mode == "uncommitted" and "[Uncommitted]" or " Uncommitted "
  local tab_full = state.diff_mode == "full" and "[Full Diff]" or " Full Diff "
  local tab_line = " " .. tab_uncommitted .. "   " .. tab_full
  table.insert(lines, tab_line)
  local tab_row = #lines - 1
  local u_start = 1
  local u_end = u_start + #tab_uncommitted
  local f_start = u_end + 3
  local f_end = f_start + #tab_full
  table.insert(highlights, { line = tab_row, col_start = u_start, col_end = u_end, group = state.diff_mode == "uncommitted" and "Title" or "Comment" })
  table.insert(highlights, { line = tab_row, col_start = f_start, col_end = f_end, group = state.diff_mode == "full" and "Title" or "Comment" })
  table.insert(lines, "")

  if #state.hunks == 0 then
    local empty_msg = state.diff_mode == "full"
      and "No hunks found in merge-base diff."
      or "No hunks found in git diff HEAD."
    table.insert(lines, empty_msg)
    table.insert(lines, "")
    table.insert(lines, "Press r to refresh, [ ] to switch tabs.")
  else
    local prev_file = nil
    for hunk_index, hunk in ipairs(state.hunks) do
      local blocks = collect_change_blocks(hunk)
      local block_by_line = {}

      for _, block in ipairs(blocks) do
        for diff_index = block.start, block["end"] do
          block_by_line[diff_index] = block
        end
      end

      if hunk.file_path ~= prev_file then
        if prev_file then
          table.insert(lines, "")
        end
        local separator = string.rep("─", 60)
        table.insert(lines, separator)
        table.insert(highlights, { line = #lines - 1, group = "Comment" })
        table.insert(lines, "  " .. file_icon(hunk.file_path) .. " " .. hunk.file_path)
        table.insert(highlights, { line = #lines - 1, group = "Statement" })
        line_map[#lines] = {
          kind = "file_header",
          hunk_index = hunk_index,
          hunk = hunk,
          source_line = hunk.parsed and hunk.parsed.new_start or 1,
        }
        table.insert(lines, separator)
        table.insert(highlights, { line = #lines - 1, group = "Comment" })
        table.insert(lines, "")
        prev_file = hunk.file_path
      end

      table.insert(lines, "  " .. hunk.header)
      table.insert(highlights, { line = #lines - 1, group = "Directory" })
      line_map[#lines] = {
        kind = "hunk_header",
        hunk_index = hunk_index,
        hunk = hunk,
        source_line = hunk.parsed and hunk.parsed.new_start or 1,
      }

      for diff_index, diff_line in ipairs(hunk.lines) do
        table.insert(lines, "    " .. diff_line)

        local prefix = diff_line:sub(1, 1)
        local group = "Normal"
        local change_kind = nil
        local block = block_by_line[diff_index]
        if prefix == "+" then
          group = "DiffAdd"
          change_kind = "add"
        elseif prefix == "-" then
          group = "DiffDelete"
          change_kind = "delete"
        elseif prefix == "@" then
          group = "Special"
        end

        table.insert(highlights, { line = #lines - 1, group = group })
        line_map[#lines] = {
          kind = "diff_line",
          hunk_index = hunk_index,
          hunk = hunk,
          diff_index = diff_index,
          source_line = source_line_for_hunk_offset(hunk, diff_index),
          change_kind = change_kind,
          block_id = block and block.id or nil,
          block_start = block and block.start == diff_index or false,
          block_end = block and block["end"] == diff_index or false,
        }

        if block and block["end"] == diff_index then
          local comment = state.comments[block.id] or ""
          if comment ~= "" then
            table.insert(lines, "      Comment: " .. comment)
            table.insert(highlights, { line = #lines - 1, group = "Comment" })
            line_map[#lines] = {
              kind = "change_comment",
              hunk_index = hunk_index,
              hunk = hunk,
              diff_index = block.start,
              source_line = source_line_for_hunk_offset(hunk, diff_index),
              change_kind = block.kind,
              block_id = block.id,
              block_start = false,
              block_end = true,
            }
          end
        end
      end

      table.insert(lines, "")
    end
  end

  vim.bo[bufnr].modifiable = true
  api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

  for _, item in ipairs(highlights) do
    local col_start = item.col_start or 0
    local col_end = item.col_end or -1
    api.nvim_buf_add_highlight(bufnr, ns, item.group, item.line, col_start, col_end)
  end

  vim.bo[bufnr].modifiable = false
  state.line_map = line_map
  apply_syntax_highlights(bufnr)

  if state.review_winid and api.nvim_win_is_valid(state.review_winid) then
    api.nvim_win_set_buf(state.review_winid, bufnr)
  end
end

local function render()
  ensure_layout()
  render_explorer()
  render_review()
end

local function set_state_from_diff(diff_state)
  state.repo_root = diff_state.repo_root
  state.cwd = diff_state.cwd
  state.hunks = diff_state.hunks
end

function M.refresh()
  local diff_state, err = load_hunks(state.diff_mode)
  if not diff_state then
    notify(err or "Failed to load Git hunks", vim.log.levels.ERROR)
    return
  end

  set_state_from_diff(diff_state)
  render()
end

local diff_modes = { "uncommitted", "full" }

local function toggle_diff_mode(direction)
  local current = 1
  for i, mode in ipairs(diff_modes) do
    if mode == state.diff_mode then
      current = i
      break
    end
  end

  current = current + direction
  if current < 1 then
    current = #diff_modes
  elseif current > #diff_modes then
    current = 1
  end

  state.diff_mode = diff_modes[current]
  M.refresh()
end

function M.next_tab()
  toggle_diff_mode(1)
end

function M.prev_tab()
  toggle_diff_mode(-1)
end

function M.open()
  M.refresh()
end

function M.select_file()
  local bufnr = api.nvim_get_current_buf()
  if bufnr ~= state.explorer_bufnr then
    return
  end

  local line = api.nvim_win_get_cursor(0)[1]
  local item = state.explorer_line_map[line]
  if not item then
    return
  end

  if item.dir_path then
    if state.collapsed_dirs[item.dir_path] then
      state.collapsed_dirs[item.dir_path] = nil
    else
      state.collapsed_dirs[item.dir_path] = true
    end
    render_explorer()
    pcall(api.nvim_win_set_cursor, 0, { line, 0 })
    return
  end

  if item.file_path then
    select_file(item.file_path)
    render()
    jump_review_to_file(item.file_path)
  end
end

function M.filter_files()
  vim.ui.input({
    prompt = "File filter: ",
    default = state.file_filter or "",
  }, function(input)
    if input == nil then
      return
    end
    state.file_filter = vim.trim(input)
    render_explorer()
  end)
end

function M.clear_filter()
  state.file_filter = ""
  render_explorer()
end

function M.next_hunk()
  if api.nvim_get_current_buf() ~= state.review_bufnr then
    return
  end

  local cursor_line = api.nvim_win_get_cursor(0)[1]
  local line_count = api.nvim_buf_line_count(state.review_bufnr)
  for line_nr = cursor_line + 1, line_count do
    local item = state.line_map[line_nr]
    if item and item.kind == "hunk_header" then
      api.nvim_win_set_cursor(0, { line_nr, 0 })
      return
    end
  end
end

function M.prev_hunk()
  if api.nvim_get_current_buf() ~= state.review_bufnr then
    return
  end

  local cursor_line = api.nvim_win_get_cursor(0)[1]
  for line_nr = cursor_line - 1, 1, -1 do
    local item = state.line_map[line_nr]
    if item and item.kind == "hunk_header" then
      api.nvim_win_set_cursor(0, { line_nr, 0 })
      return
    end
  end
end

function M.next_change()
  if api.nvim_get_current_buf() ~= state.review_bufnr then
    return
  end

  local cursor_line = api.nvim_win_get_cursor(0)[1]
  local line_count = api.nvim_buf_line_count(state.review_bufnr)
  for line_nr = cursor_line + 1, line_count do
    local item = state.line_map[line_nr]
    if item and item.kind == "diff_line" and item.block_id and item.block_start then
      api.nvim_win_set_cursor(0, { line_nr, 0 })
      return
    end
  end
end

function M.prev_change()
  if api.nvim_get_current_buf() ~= state.review_bufnr then
    return
  end

  local cursor_line = api.nvim_win_get_cursor(0)[1]
  for line_nr = cursor_line - 1, 1, -1 do
    local item = state.line_map[line_nr]
    if item and item.kind == "diff_line" and item.block_id and item.block_start then
      api.nvim_win_set_cursor(0, { line_nr, 0 })
      return
    end
  end
end

function M.jump_to_source()
  local hunk, item = current_hunk_at_cursor()
  if not hunk or not state.repo_root then
    return
  end

  local target = state.repo_root .. "/" .. hunk.file_path
  local source_winid = find_source_window()

  if source_winid then
    api.nvim_set_current_win(source_winid)
    vim.cmd("edit " .. vim.fn.fnameescape(target))
  else
    vim.cmd("leftabove vsplit " .. vim.fn.fnameescape(target))
  end

  api.nvim_win_set_cursor(0, { item.source_line or 1, 0 })

  if state.review_winid and api.nvim_win_is_valid(state.review_winid) then
    api.nvim_set_current_win(state.review_winid)
  end
end

function M.add_comment()
  local hunk, item = current_change_at_cursor()
  if not hunk or not item or not item.block_id then
    return
  end

  local comment_key = item.block_id
  local existing = state.comments[comment_key] or ""
  local label = item.change_kind == "delete" and "deletion" or "addition"

  vim.ui.input({
    prompt = "Comment on " .. label .. " block: ",
    default = existing,
  }, function(input)
    if input == nil then
      return
    end

    state.comments[comment_key] = vim.trim(input)
    render()
  end)
end

export_payload = function()
  local items = {}

  for _, hunk in ipairs(state.hunks) do
    local changes = {}

    for _, block in ipairs(collect_change_blocks(hunk)) do
      table.insert(changes, {
        diff_start = block.start,
        diff_end = block["end"],
        kind = block.kind,
        line = source_line_for_hunk_offset(hunk, block.start),
        lines = block.lines,
        comment = state.comments[block.id] or "",
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
    repo_root = state.repo_root,
    generated_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    instructions = "Review each hunk with its user comment. Propose or apply code changes only when the comment requests an action.",
    hunks = items,
  }
end

local function ensure_export_buffer()
  if state.export_bufnr and api.nvim_buf_is_valid(state.export_bufnr) then
    return state.export_bufnr
  end

  local bufnr = api.nvim_create_buf(false, true)
  state.export_bufnr = bufnr
  api.nvim_buf_set_name(bufnr, "ai-hunk-review://export")
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].filetype = "json"

  return bufnr
end

function M.export()
  if not state.repo_root then
    local diff_state, err = load_hunks()
    if not diff_state then
      notify(err or "Failed to load Git hunks", vim.log.levels.ERROR)
      return
    end
    set_state_from_diff(diff_state)
  end

  local payload = export_payload()
  local pretty = vim.split(encode_pretty(payload), "\n", { plain = true })
  local bufnr = ensure_export_buffer()

  vim.bo[bufnr].modifiable = true
  api.nvim_buf_set_lines(bufnr, 0, -1, false, pretty)
  vim.bo[bufnr].modifiable = false

  vim.cmd("botright vsplit")
  api.nvim_win_set_buf(0, bufnr)
end

function M.confirm_review()
  open_confirm_modal()
end

local keymap_group = api.nvim_create_augroup("AiHunkReviewKeymaps", { clear = true })

api.nvim_create_autocmd("FileType", {
  group = keymap_group,
  pattern = "aihunkreviewexplorer",
  callback = function(args)
    apply_explorer_keymaps(args.buf)
  end,
})

api.nvim_create_autocmd("FileType", {
  group = keymap_group,
  pattern = "aihunkreview",
  callback = function(args)
    apply_review_keymaps(args.buf)
  end,
})

return M
