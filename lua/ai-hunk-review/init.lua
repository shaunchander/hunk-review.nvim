local M = {}

local api = vim.api

local ns = api.nvim_create_namespace("ai-hunk-review")

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

local function load_hunks()
  local root, root_err = git_root()
  if not root then
    return nil, root_err or "Not inside a Git repository"
  end

  local diff, diff_err = system({
    "git",
    "-C",
    root,
    "diff",
    "--no-color",
    "--no-ext-diff",
    "--unified=3",
    "HEAD",
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

local function close_layout()
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

local function clipboard_text()
  local payload = export_payload()
  return encode_pretty(payload)
end

local function copy_review_to_clipboard()
  local text = clipboard_text()
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

  vim.keymap.set("n", "q", function()
    close_layout()
  end, { buffer = bufnr, silent = true, desc = "Close review layout" })

  vim.keymap.set("n", "r", function()
    M.refresh()
  end, { buffer = bufnr, silent = true, desc = "Refresh review layout" })

  vim.keymap.set("n", "<CR>", function()
    M.select_file()
  end, { buffer = bufnr, silent = true, desc = "Select file" })

  vim.keymap.set("n", "o", function()
    M.select_file()
  end, { buffer = bufnr, silent = true, desc = "Open file in review" })

  vim.keymap.set("n", "/", function()
    M.filter_files()
  end, { buffer = bufnr, silent = true, desc = "Filter files" })

  vim.keymap.set("n", "x", function()
    M.clear_filter()
  end, { buffer = bufnr, silent = true, desc = "Clear file filter" })

  vim.keymap.set("n", "<C-l>", function()
    focus_review()
  end, { buffer = bufnr, silent = true, desc = "Focus review pane" })

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

  vim.keymap.set("n", "q", function()
    close_layout()
  end, { buffer = bufnr, silent = true, desc = "Close review buffer" })

  vim.keymap.set("n", "r", function()
    M.refresh()
  end, { buffer = bufnr, silent = true, desc = "Refresh review buffer" })

  vim.keymap.set("n", "]h", function()
    M.next_hunk()
  end, { buffer = bufnr, silent = true, desc = "Next hunk" })

  vim.keymap.set("n", "[h", function()
    M.prev_hunk()
  end, { buffer = bufnr, silent = true, desc = "Previous hunk" })

  vim.keymap.set("n", "j", function()
    M.next_change()
  end, { buffer = bufnr, silent = true, desc = "Next change" })

  vim.keymap.set("n", "k", function()
    M.prev_change()
  end, { buffer = bufnr, silent = true, desc = "Previous change" })

  vim.keymap.set("n", "<CR>", function()
    M.confirm_review()
  end, { buffer = bufnr, silent = true, desc = "Confirm and copy review" })

  vim.keymap.set("n", "o", function()
    M.jump_to_source()
  end, { buffer = bufnr, silent = true, desc = "Open source" })

  vim.keymap.set("n", "c", function()
    M.add_comment()
  end, { buffer = bufnr, silent = true, desc = "Add change comment" })

  vim.keymap.set("n", "e", function()
    M.export()
  end, { buffer = bufnr, silent = true, desc = "Export review instructions" })

  vim.keymap.set("n", "<C-h>", function()
    focus_explorer()
  end, { buffer = bufnr, silent = true, desc = "Focus explorer pane" })

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

render_explorer = function()
  local bufnr = ensure_explorer_buffer()
  local lines = {}
  local highlights = {}
  local line_map = {}
  local entries = filtered_file_entries()

  table.insert(lines, "Changed Files")
  table.insert(highlights, { line = #lines - 1, group = "Title" })
  local filter_label = vim.trim(state.file_filter or "")
  table.insert(lines, filter_label ~= "" and ("Filter: " .. filter_label) or "Filter: [none]  (/ to set, x to clear)")
  table.insert(highlights, { line = #lines - 1, group = filter_label ~= "" and "Directory" or "Comment" })
  table.insert(lines, "")

  if #entries == 0 then
    table.insert(lines, filter_label ~= "" and "No matching files." or "No hunks found.")
  else
    for _, entry in ipairs(entries) do
      local prefix = entry.file_path == state.selected_file and "> " or "  "
      table.insert(lines, prefix .. file_icon(entry.file_path) .. " " .. entry.file_path)
      line_map[#lines] = { file_path = entry.file_path }
      table.insert(highlights, { line = #lines - 1, group = entry.file_path == state.selected_file and "Directory" or "Normal" })

      table.insert(lines, string.format("    %d hunks  %d change blocks", entry.hunk_count, entry.change_count))
      table.insert(highlights, { line = #lines - 1, group = "Comment" })
    end
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

local function render_review()
  local bufnr = ensure_review_buffer()
  local lines = {}
  local highlights = {}
  local line_map = {}

  table.insert(lines, "AI Hunk Review")
  table.insert(lines, "")

  if #state.hunks == 0 then
    table.insert(lines, "No hunks found in git diff HEAD.")
    table.insert(lines, "")
    table.insert(lines, "Press r to refresh.")
  else
    for hunk_index, hunk in ipairs(state.hunks) do
      local blocks = collect_change_blocks(hunk)
      local block_by_line = {}

      for _, block in ipairs(blocks) do
        for diff_index = block.start, block["end"] do
          block_by_line[diff_index] = block
        end
      end

      table.insert(lines, "  " .. hunk.file_path .. " " .. hunk.header)
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
    api.nvim_buf_add_highlight(bufnr, ns, item.group, item.line, 0, -1)
  end

  vim.bo[bufnr].modifiable = false
  state.line_map = line_map

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
  local diff_state, err = load_hunks()
  if not diff_state then
    notify(err or "Failed to load Git hunks", vim.log.levels.ERROR)
    return
  end

  set_state_from_diff(diff_state)
  render()
end

function M.open()
  M.refresh()
end

function M.select_file()
  local file_path = current_explorer_file()
  if not file_path then
    return
  end

  select_file(file_path)
  render()
  jump_review_to_file(file_path)
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

return M
