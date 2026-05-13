local M = {}

local api = vim.api
local git = require("hunk-review.git")
local diff = require("hunk-review.diff")
local tree = require("hunk-review.tree")
local peek = require("hunk-review.peek")
local syntax = require("hunk-review.syntax")
local export = require("hunk-review.export")
local comments_sidebar = require("hunk-review.comments")

local ns = api.nvim_create_namespace("hunk-review")
local ns_linemode = api.nvim_create_namespace("hunk-review-linemode")

local defaults = {
  base_branches = { "main", "master", "develop" },
  layout = {
    width = 0.96,
    height = 0.92,
    explorer_width = 0.28,
  },
  diff_context = 3,
}

local config = vim.deepcopy(defaults)

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
  line_mode = false,
  comments_winid = nil,
  comments_sidebar_open = false,
}

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "hunk-review.nvim" })
end

local function get_snacks()
  local ok, snacks = pcall(require, "snacks")
  if ok then
    return snacks
  end
  return nil
end

-- Forward declarations for mutual references
local render_explorer
local render

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

local function close_layout()
  peek.close(state)
  comments_sidebar.close(state)
  close_confirm_modal()

  local explorer_win = state.explorer_winid
  local review_win = state.review_winid
  local explorer_buf = state.explorer_bufnr
  local review_buf = state.review_bufnr

  if state.layout then
    pcall(function()
      state.layout:close({ buf = false })
    end)
    state.layout = nil
  end

  for _, winid in ipairs({ explorer_win, review_win }) do
    if winid and api.nvim_win_is_valid(winid) then
      pcall(api.nvim_win_close, winid, true)
    end
  end

  for _, bufnr in ipairs({ explorer_buf, review_buf }) do
    if bufnr and api.nvim_buf_is_valid(bufnr) then
      pcall(api.nvim_buf_delete, bufnr, { force = true })
    end
  end

  state.explorer_winid = nil
  state.review_winid = nil
  state.explorer_bufnr = nil
  state.review_bufnr = nil
  state.line_mode = false
  syntax.clear_cache()
end

local function current_file_entries()
  local entries = diff.file_entries(state.hunks)

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

local function selected_file_line()
  for line_nr, item in pairs(state.explorer_line_map) do
    if item.file_path == state.selected_file then
      return line_nr
    end
  end
  return nil
end

local function current_hunk_at_cursor()
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

local function update_line_mode_indicator()
  if not state.review_bufnr or not api.nvim_buf_is_valid(state.review_bufnr) then
    return
  end
  api.nvim_buf_clear_namespace(state.review_bufnr, ns_linemode, 0, -1)
  if not state.line_mode then
    return
  end
  if not state.review_winid or not api.nvim_win_is_valid(state.review_winid) then
    return
  end
  local cursor_line = api.nvim_win_get_cursor(state.review_winid)[1]
  local item = state.line_map[cursor_line]
  if item and item.kind == "diff_line" then
    api.nvim_buf_set_extmark(state.review_bufnr, ns_linemode, cursor_line - 1, 0, {
      virt_text = { { "  > ", "WarningMsg" } },
      virt_text_pos = "overlay",
    })
  end
end

local function enter_line_mode()
  if api.nvim_get_current_buf() ~= state.review_bufnr then
    return
  end
  local cursor_line = api.nvim_win_get_cursor(0)[1]
  local item = state.line_map[cursor_line]

  if item and item.kind == "hunk_header" then
    local line_count = api.nvim_buf_line_count(state.review_bufnr)
    for line_nr = cursor_line + 1, line_count do
      local next_item = state.line_map[line_nr]
      if next_item and next_item.kind == "diff_line" then
        api.nvim_win_set_cursor(0, { line_nr, 0 })
        item = next_item
        break
      elseif next_item and next_item.kind == "hunk_header" then
        break
      end
    end
  end

  if not item or item.kind ~= "diff_line" then
    return
  end

  state.line_mode = true
  if state.review_winid and api.nvim_win_is_valid(state.review_winid) then
    vim.wo[state.review_winid].cursorline = true
  end
  update_line_mode_indicator()
end

local function exit_line_mode()
  state.line_mode = false
  if state.review_winid and api.nvim_win_is_valid(state.review_winid) then
    vim.wo[state.review_winid].cursorline = false
  end
  update_line_mode_indicator()
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

-- Keymap application (single authority — called from FileType autocmds only)

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
  map("C", function() comments_sidebar.toggle(state) end, "Toggle comments sidebar")

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
  map("<Space>", function()
    if state.line_mode then exit_line_mode() else enter_line_mode() end
  end, "Toggle line-by-line mode")
  map("<Esc>", function()
    if state.line_mode then exit_line_mode() end
  end, "Exit line-by-line mode")
  map("<CR>", function()
    if state.line_mode then M.add_line_comment() else M.confirm_review() end
  end, "Confirm review / Line comment")
  map("o", function() M.jump_to_source() end, "Open source")
  map("p", function() peek.open(state, current_hunk_at_cursor()) end, "Peek source with LSP")
  map("c", function()
    if state.line_mode then M.add_line_comment() else M.add_comment() end
  end, "Add comment")
  map("d", function() M.delete_comment() end, "Delete comment")
  map("e", function() M.export() end, "Export review instructions")
  map("C", function() comments_sidebar.toggle(state) end, "Toggle comments sidebar")
  map("<C-h>", focus_explorer, "Focus explorer pane")

  vim.keymap.set("n", "[", function() M.prev_tab() end, { buffer = bufnr, silent = true, desc = "Previous diff tab" })
  vim.keymap.set("n", "]", function() M.next_tab() end, { buffer = bufnr, silent = true, desc = "Next diff tab" })

  vim.keymap.set("x", "c", function() M.add_range_comment() end, { buffer = bufnr, nowait = true, silent = true, desc = "Comment on selected lines" })
  vim.keymap.set("x", "<CR>", function() M.add_range_comment() end, { buffer = bufnr, nowait = true, silent = true, desc = "Comment on selected lines" })
end

-- Buffer creation (keymaps applied via FileType autocmd, not here)

local function ensure_explorer_buffer()
  if state.explorer_bufnr and api.nvim_buf_is_valid(state.explorer_bufnr) then
    return state.explorer_bufnr
  end

  local bufnr = api.nvim_create_buf(false, true)
  state.explorer_bufnr = bufnr
  api.nvim_buf_set_name(bufnr, "hunk-review://explorer")

  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "hide"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].modifiable = true
  vim.bo[bufnr].filetype = "hunkreviewexplorer"
  vim.bo[bufnr].buflisted = false

  return bufnr
end

local function ensure_review_buffer()
  if state.review_bufnr and api.nvim_buf_is_valid(state.review_bufnr) then
    return state.review_bufnr
  end

  local bufnr = api.nvim_create_buf(false, true)
  state.review_bufnr = bufnr
  api.nvim_buf_set_name(bufnr, "hunk-review://review")

  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "hide"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].modifiable = true
  vim.bo[bufnr].filetype = "hunkreview"
  vim.bo[bufnr].buflisted = false

  local group = api.nvim_create_augroup("HunkReviewSync", { clear = false })
  api.nvim_create_autocmd("CursorMoved", {
    group = group,
    buffer = bufnr,
    callback = function()
      sync_selection_from_review()
      if state.line_mode then
        update_line_mode_indicator()
      end
    end,
  })

  return bufnr
end

-- Layout

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
        wo = {
          wrap = false,
          cursorline = false,
          signcolumn = "no",
          number = false,
          relativenumber = false,
          statuscolumn = "",
          scrolloff = 999,
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
          title = " Hunk Review ",
          title_pos = "center",
          backdrop = 60,
          width = config.layout.width,
          height = config.layout.height,
          zindex = 50,
          {
            win = "explorer",
            width = config.layout.explorer_width,
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

  -- Fallback: split layout without snacks
  if state.explorer_winid and api.nvim_win_is_valid(state.explorer_winid)
    and state.review_winid and api.nvim_win_is_valid(state.review_winid)
  then
    api.nvim_win_set_buf(state.explorer_winid, explorer_bufnr)
    api.nvim_win_set_buf(state.review_winid, review_bufnr)
    vim.wo[state.explorer_winid].wrap = false
    vim.wo[state.review_winid].wrap = false
    vim.wo[state.review_winid].scrolloff = 999
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
  vim.wo[state.review_winid].scrolloff = 999
  vim.api.nvim_win_set_width(state.explorer_winid, 32)
  api.nvim_set_current_win(state.review_winid)
end

-- Clipboard / confirm modal

local function copy_review_to_clipboard()
  local text = export.clipboard_text(state.hunks, state.comments)
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
  vim.bo[bufnr].filetype = "hunkreviewconfirm"

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

-- Rendering

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
    local file_tree = tree.build_file_tree(entries)
    tree.render_tree_node(file_tree, "", lines, highlights, line_map, 0, state.collapsed_dirs, state.selected_file, state.comments)
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
  state.explorer_line_map = line_map

  local line_nr = selected_file_line()
  if line_nr and state.explorer_winid and api.nvim_win_is_valid(state.explorer_winid) then
    api.nvim_win_set_cursor(state.explorer_winid, { line_nr, 0 })
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
    local entries = diff.file_entries(state.hunks)
    local file_tree = tree.build_file_tree(entries)
    local file_order = tree.file_order(file_tree)
    local order_map = {}
    for i, fp in ipairs(file_order) do
      order_map[fp] = i
    end

    local sorted_hunks = vim.list_slice(state.hunks, 1, #state.hunks)
    table.sort(sorted_hunks, function(a, b)
      local oa = order_map[a.file_path] or 9999
      local ob = order_map[b.file_path] or 9999
      if oa ~= ob then return oa < ob end
      return (a.parsed and a.parsed.new_start or 0) < (b.parsed and b.parsed.new_start or 0)
    end)

    local prev_file = nil
    for hunk_index, hunk in ipairs(sorted_hunks) do
      local blocks = diff.get_change_blocks(hunk)
      local block_by_line = {}

      for _, block in ipairs(blocks) do
        for diff_index = block.start, block["end"] do
          block_by_line[diff_index] = block
        end
      end

      local range_comments = diff.get_range_comments_for_hunk(hunk, state.comments)
      local range_ends = {}
      for _, rc in ipairs(range_comments) do
        if not range_ends[rc.end_idx] then
          range_ends[rc.end_idx] = {}
        end
        table.insert(range_ends[rc.end_idx], rc)
      end

      if hunk.file_path ~= prev_file then
        if prev_file then
          table.insert(lines, "")
        end
        local separator = string.rep("─", 60)
        table.insert(lines, separator)
        table.insert(highlights, { line = #lines - 1, group = "Comment" })
        table.insert(lines, "  " .. diff.file_icon(hunk.file_path) .. " " .. hunk.file_path)
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
          source_line = diff.source_line_for_hunk_offset(hunk, diff_index),
          change_kind = change_kind,
          block_id = block and block.id or nil,
          block_start = block and block.start == diff_index or false,
          block_end = block and block["end"] == diff_index or false,
        }

        local ending_ranges = range_ends[diff_index]
        if ending_ranges then
          for _, rc in ipairs(ending_ranges) do
            local label = rc.start_idx == rc.end_idx
              and "      Comment: "
              or ("      Comment (L" .. rc.start_idx .. "-" .. rc.end_idx .. "): ")
            table.insert(lines, label .. rc.comment)
            table.insert(highlights, { line = #lines - 1, group = "Comment" })
            line_map[#lines] = {
              kind = "range_comment",
              hunk_index = hunk_index,
              hunk = hunk,
              diff_index = diff_index,
              source_line = diff.source_line_for_hunk_offset(hunk, diff_index),
              change_kind = change_kind,
              range_key = rc.key,
              range_start = rc.start_idx,
              range_end = rc.end_idx,
            }
          end
        end

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
              source_line = diff.source_line_for_hunk_offset(hunk, diff_index),
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
  syntax.apply(bufnr, line_map)

  if state.review_winid and api.nvim_win_is_valid(state.review_winid) then
    api.nvim_win_set_buf(state.review_winid, bufnr)
  end

  if state.line_mode then
    update_line_mode_indicator()
  end
end

render = function()
  ensure_layout()
  render_explorer()
  render_review()
end

-- State management

local function set_state_from_diff(diff_state)
  local repo_changed = state.repo_root and state.repo_root ~= diff_state.repo_root

  state.repo_root = diff_state.repo_root
  state.cwd = diff_state.cwd
  state.hunks = diff_state.hunks
  state.base_branch = diff_state.base_branch or state.base_branch

  if repo_changed then
    state.comments = {}
    state.collapsed_dirs = {}
    state.selected_file = nil
    state.file_filter = ""
  end
end

-- Public API

function M.refresh()
  local diff_state, err = git.load_hunks(state.diff_mode, state.base_branch, { context = config.diff_context })
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
    state.selected_file = item.file_path
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

  if state.line_mode then
    for line_nr = cursor_line + 1, line_count do
      local item = state.line_map[line_nr]
      if item and item.kind == "diff_line" then
        api.nvim_win_set_cursor(0, { line_nr, 0 })
        return
      end
    end
    return
  end

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

  if state.line_mode then
    for line_nr = cursor_line - 1, 1, -1 do
      local item = state.line_map[line_nr]
      if item and item.kind == "diff_line" then
        api.nvim_win_set_cursor(0, { line_nr, 0 })
        return
      end
    end
    return
  end

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
    comments_sidebar.refresh(state)
  end)
end

function M.add_line_comment()
  if api.nvim_get_current_buf() ~= state.review_bufnr then
    return
  end

  local cursor_line = api.nvim_win_get_cursor(0)[1]
  local item = state.line_map[cursor_line]
  if not item or item.kind ~= "diff_line" then
    return
  end

  local comment_key = diff.make_line_comment_key(item.hunk, item.diff_index)
  local existing = state.comments[comment_key] or ""

  vim.ui.input({
    prompt = "Comment on line: ",
    default = existing,
  }, function(input)
    if input == nil then return end
    state.comments[comment_key] = vim.trim(input)
    local save_hunk = item.hunk
    local save_diff_index = item.diff_index
    render()
    comments_sidebar.refresh(state)
    for line_nr, mapped in pairs(state.line_map) do
      if mapped.kind == "diff_line" and mapped.hunk == save_hunk and mapped.diff_index == save_diff_index then
        pcall(api.nvim_win_set_cursor, 0, { line_nr, 0 })
        break
      end
    end
  end)
end

function M.add_range_comment()
  if api.nvim_get_current_buf() ~= state.review_bufnr then
    return
  end

  local v_start = vim.fn.getpos("v")[2]
  local v_end = vim.fn.getpos(".")[2]
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)

  if v_start > v_end then
    v_start, v_end = v_end, v_start
  end

  local first_item, last_item
  local hunk
  for line_nr = v_start, v_end do
    local item = state.line_map[line_nr]
    if item and item.kind == "diff_line" then
      if not first_item then
        first_item = item
        hunk = item.hunk
      end
      if item.hunk == hunk then
        last_item = item
      end
    end
  end

  if not first_item or not last_item or not hunk then
    return
  end

  local comment_key = diff.make_range_comment_key(hunk, first_item.diff_index, last_item.diff_index)
  local existing = state.comments[comment_key] or ""
  local line_count = last_item.diff_index - first_item.diff_index + 1
  local prompt_label = line_count == 1 and "Comment on line: " or ("Comment on " .. line_count .. " lines: ")

  vim.ui.input({
    prompt = prompt_label,
    default = existing,
  }, function(input)
    if input == nil then return end
    state.comments[comment_key] = vim.trim(input)
    local save_diff_index = first_item.diff_index
    render()
    comments_sidebar.refresh(state)
    for line_nr, mapped in pairs(state.line_map) do
      if mapped.kind == "diff_line" and mapped.hunk == hunk and mapped.diff_index == save_diff_index then
        pcall(api.nvim_win_set_cursor, 0, { line_nr, 0 })
        break
      end
    end
  end)
end

function M.delete_comment()
  if api.nvim_get_current_buf() ~= state.review_bufnr then
    return
  end

  local cursor_line = api.nvim_win_get_cursor(0)[1]
  local item = state.line_map[cursor_line]
  if not item then return end

  local key
  if item.kind == "change_comment" and item.block_id then
    key = item.block_id
  elseif item.kind == "range_comment" and item.range_key then
    key = item.range_key
  elseif item.kind == "diff_line" and item.hunk and item.diff_index then
    local line_key = diff.make_line_comment_key(item.hunk, item.diff_index)
    local has_line = state.comments[line_key] and state.comments[line_key] ~= ""
    local has_block = item.block_id and state.comments[item.block_id] and state.comments[item.block_id] ~= ""

    if state.line_mode and has_line then
      key = line_key
    elseif not state.line_mode and has_block then
      key = item.block_id
    elseif has_line then
      key = line_key
    elseif has_block then
      key = item.block_id
    else
      for k, comment in pairs(state.comments) do
        if comment ~= "" and k:match("^range::") then
          local s, e = k:match("::(%d+)::(%d+)$")
          if s and tonumber(s) <= item.diff_index and tonumber(e) >= item.diff_index then
            key = k
            break
          end
        end
      end
    end
  end

  if not key or not state.comments[key] or state.comments[key] == "" then
    return
  end

  state.comments[key] = nil
  render()
  comments_sidebar.refresh(state)
end

function M.export()
  if not state.repo_root then
    local diff_state, err = git.load_hunks(state.diff_mode, state.base_branch, { context = config.diff_context })
    if not diff_state then
      notify(err or "Failed to load Git hunks", vim.log.levels.ERROR)
      return
    end
    set_state_from_diff(diff_state)
  end

  local payload = export.payload(state.hunks, state.comments, state.repo_root)
  local pretty = vim.split(export.encode_pretty(payload), "\n", { plain = true })

  local bufnr
  if state.export_bufnr and api.nvim_buf_is_valid(state.export_bufnr) then
    bufnr = state.export_bufnr
  else
    bufnr = api.nvim_create_buf(false, true)
    state.export_bufnr = bufnr
    api.nvim_buf_set_name(bufnr, "hunk-review://export")
    vim.bo[bufnr].buftype = "nofile"
    vim.bo[bufnr].bufhidden = "wipe"
    vim.bo[bufnr].swapfile = false
    vim.bo[bufnr].filetype = "json"

    api.nvim_create_autocmd("BufWipeout", {
      buffer = bufnr,
      once = true,
      callback = function()
        state.export_bufnr = nil
      end,
    })
  end

  vim.bo[bufnr].modifiable = true
  api.nvim_buf_set_lines(bufnr, 0, -1, false, pretty)
  vim.bo[bufnr].modifiable = false

  vim.cmd("botright vsplit")
  api.nvim_win_set_buf(0, bufnr)
end

function M.confirm_review()
  open_confirm_modal()
end

function M.reset()
  comments_sidebar.close(state)
  state.comments = {}
  state.collapsed_dirs = {}
  state.file_filter = ""
  state.selected_file = nil
  state.line_mode = false

  if state.review_bufnr and api.nvim_buf_is_valid(state.review_bufnr) then
    render()
  end

  notify("Review reset")
end

-- FileType autocmds as single keymap authority
local keymap_group = api.nvim_create_augroup("HunkReviewKeymaps", { clear = true })

api.nvim_create_autocmd("FileType", {
  group = keymap_group,
  pattern = "hunkreviewexplorer",
  callback = function(args)
    apply_explorer_keymaps(args.buf)
  end,
})

api.nvim_create_autocmd("FileType", {
  group = keymap_group,
  pattern = "hunkreview",
  callback = function(args)
    apply_review_keymaps(args.buf)
  end,
})

function M.setup(opts)
  config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  git.set_base_branches(config.base_branches)
end

return M
