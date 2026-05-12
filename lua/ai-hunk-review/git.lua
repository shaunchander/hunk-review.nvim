local M = {}

local function system(cmd, opts)
  local result = vim.system(cmd, vim.tbl_extend("force", { text = true }, opts or {})):wait()
  if result.code ~= 0 then
    return nil, result.stderr
  end
  return result.stdout, nil
end

function M.git_root()
  local root, err = system({ "git", "rev-parse", "--show-toplevel" })
  if not root then
    return nil, err
  end
  return vim.trim(root), nil
end

function M.detect_base_branch(cached)
  if cached then
    return cached
  end

  for _, branch in ipairs({ "main", "master", "develop" }) do
    local ok = system({ "git", "rev-parse", "--verify", branch })
    if ok then
      return branch
    end
  end

  return nil
end

function M.parse_hunk_header(header)
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

function M.collect_hunks(diff_text)
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
          parsed = M.parse_hunk_header(line),
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

function M.load_hunks(mode, cached_base_branch)
  local root, root_err = M.git_root()
  if not root then
    return nil, root_err or "Not inside a Git repository"
  end

  local diff_target = "HEAD"
  local base_branch = cached_base_branch

  if mode == "full" then
    base_branch = M.detect_base_branch(cached_base_branch)
    if not base_branch then
      return nil, "Could not detect base branch (tried main, master, develop)"
    end

    local merge_base, mb_err = system({ "git", "-C", root, "merge-base", base_branch, "HEAD" })
    if not merge_base then
      return nil, mb_err or "Could not find merge-base"
    end

    diff_target = vim.trim(merge_base)
  end

  local diff, diff_err = system({
    "git", "-C", root,
    "diff", "--no-color", "--no-ext-diff", "--unified=3",
    diff_target, "--",
  })

  if not diff then
    return nil, diff_err
  end

  return {
    repo_root = root,
    cwd = (vim.uv or vim.loop).cwd(),
    hunks = M.collect_hunks(diff),
    base_branch = base_branch,
  }, nil
end

return M
