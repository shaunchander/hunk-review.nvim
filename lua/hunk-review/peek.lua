local api = vim.api

local M = {}

local keymaps = {}

local function clear_keymaps()
  for _, km in ipairs(keymaps) do
    pcall(vim.keymap.del, "n", km.lhs, { buffer = km.buf })
  end
  keymaps = {}
end

function M.close(state)
  clear_keymaps()
  pcall(api.nvim_del_augroup_by_name, "HunkReviewPeek")

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

function M.open(state, hunk, item)
  M.close(state)

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

  local function close() M.close(state) end

  vim.keymap.set("n", "q", close, { buffer = bufnr, nowait = true, silent = true, desc = "Close peek" })
  vim.keymap.set("n", "<Esc>", close, { buffer = bufnr, nowait = true, silent = true, desc = "Close peek" })
  keymaps = {
    { lhs = "q", buf = bufnr },
    { lhs = "<Esc>", buf = bufnr },
  }

  local group = api.nvim_create_augroup("HunkReviewPeek", { clear = true })
  api.nvim_create_autocmd("WinClosed", {
    group = group,
    pattern = tostring(winid),
    once = true,
    callback = function()
      clear_keymaps()
      state.peek_winid = nil
      if state.peek_return_cursor and state.review_winid and api.nvim_win_is_valid(state.review_winid) then
        api.nvim_set_current_win(state.review_winid)
        pcall(api.nvim_win_set_cursor, state.review_winid, state.peek_return_cursor)
      end
      state.peek_return_cursor = nil
    end,
  })
end

return M
