local api = vim.api

local M = {}

local syntax_ns = api.nvim_create_namespace("ai-hunk-review-syntax")
local ts_query_get = vim.treesitter.query.get or vim.treesitter.query.get_query

function M.apply(bufnr, line_map)
  api.nvim_buf_clear_namespace(bufnr, syntax_ns, 0, -1)

  local file_lines = {}
  for line_nr, item in pairs(line_map) do
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

return M
