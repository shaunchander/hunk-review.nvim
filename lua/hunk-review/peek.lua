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
  -- Clear file-view annotations before restoring the review buffer
  if state.review_winid and api.nvim_win_is_valid(state.review_winid) then
    local cur_bufnr = api.nvim_win_get_buf(state.review_winid)
    if state.review_bufnr and cur_bufnr ~= state.review_bufnr then
      local view_ns = api.nvim_create_namespace("hunk-review-fileview")
      pcall(api.nvim_buf_clear_namespace, cur_bufnr, view_ns, 0, -1)
    end
  end

  clear_keymaps()
  pcall(api.nvim_del_augroup_by_name, "HunkReviewPeek")

  -- Restore review buffer to the review window
  if state.review_winid and api.nvim_win_is_valid(state.review_winid) then
    if state.review_bufnr and api.nvim_buf_is_valid(state.review_bufnr) then
      api.nvim_win_set_buf(state.review_winid, state.review_bufnr)
    end

    -- Restore window options
    if state.peek_saved_winopts then
      for opt, val in pairs(state.peek_saved_winopts) do
        vim.wo[state.review_winid][opt] = val
      end
    end

    if state.peek_return_cursor then
      api.nvim_set_current_win(state.review_winid)
      pcall(api.nvim_win_set_cursor, state.review_winid, state.peek_return_cursor)
    end
  end

  state.peek_return_cursor = nil
  state.peek_saved_winopts = nil
end

function M.open(state, hunk, item)
  M.close(state)

  if not hunk or not state.repo_root then
    return
  end

  if not state.review_winid or not api.nvim_win_is_valid(state.review_winid) then
    return
  end

  if not state.review_bufnr or not api.nvim_buf_is_valid(state.review_bufnr) then
    return
  end

  -- Save cursor position to return to
  state.peek_return_cursor = api.nvim_win_get_cursor(state.review_winid)

  -- Save window options before modifying
  state.peek_saved_winopts = {
    number = vim.wo[state.review_winid].number,
    relativenumber = vim.wo[state.review_winid].relativenumber,
    cursorline = vim.wo[state.review_winid].cursorline,
    signcolumn = vim.wo[state.review_winid].signcolumn,
    wrap = vim.wo[state.review_winid].wrap,
  }

  local target = state.repo_root .. "/" .. hunk.file_path

  -- Load the buffer
  local bufnr = vim.fn.bufadd(target)
  vim.fn.bufload(bufnr)

  -- Replace the review window buffer with the source file
  api.nvim_set_current_win(state.review_winid)
  api.nvim_win_set_buf(state.review_winid, bufnr)

  -- Configure window options for a better peek experience
  vim.wo[state.review_winid].number = true
  vim.wo[state.review_winid].relativenumber = true
  vim.wo[state.review_winid].cursorline = true
  vim.wo[state.review_winid].signcolumn = "yes"
  vim.wo[state.review_winid].wrap = false

  -- Jump to the relevant line
  pcall(api.nvim_win_set_cursor, state.review_winid, { item.source_line or 1, 0 })
  vim.cmd("normal! zz")

  -- Set up keymaps for closing peek (returns to review buffer)
  local function close() M.close(state) end

  vim.keymap.set("n", "q", close, { buffer = bufnr, nowait = true, silent = true, desc = "Return to diff view (hunk-review)" })
  vim.keymap.set("n", "<Esc>", close, { buffer = bufnr, nowait = true, silent = true, desc = "Return to diff view (hunk-review)" })
  keymaps = {
    { lhs = "q", buf = bufnr },
    { lhs = "<Esc>", buf = bufnr },
  }
end

return M
