local M = {}

local base_branches = { "main", "master", "develop" }

function M.set_base_branches(branches)
  base_branches = branches
end

local function system(cmd, opts)
  local result = vim.system(cmd, vim.tbl_extend("force", { text = true }, opts or {})):wait()
  if result.code ~= 0 then
    return nil, result.stderr
  end
  return result.stdout, nil
end

-- `git diff` exits 1 when differences exist; treat 0 and 1 both as success.
local function system_diff(cmd, opts)
  local result = vim.system(cmd, vim.tbl_extend("force", { text = true }, opts or {})):wait()
  if result.code ~= 0 and result.code ~= 1 then
    return nil, result.stderr
  end
  return result.stdout or "", nil
end

local function collect_untracked_diff(root, context)
  local listing = system({ "git", "-C", root, "ls-files", "--others", "--exclude-standard", "-z" })
  if not listing or listing == "" then
    return ""
  end

  local pieces = {}
  for file in vim.gsplit(listing, "\0", { plain = true, trimempty = true }) do
    local diff = system_diff({
      "git", "-C", root,
      "diff", "--no-color", "--no-ext-diff", "--no-index",
      "--unified=" .. context,
      "--", "/dev/null", file,
    })
    if diff and diff ~= "" then
      table.insert(pieces, diff)
    end
  end
  return table.concat(pieces, "\n")
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

  for _, branch in ipairs(base_branches) do
    local ok = system({ "git", "rev-parse", "--verify", branch })
    if ok then
      return branch
    end
  end

  return nil
end

function M.is_base_branch(branch)
  if not branch then
    return false
  end
  for _, b in ipairs(base_branches) do
    if b == branch then
      return true
    end
  end
  return false
end

-- Returns the target branch name, or `false` when detection has run and found
-- nothing. `nil` means "never tried" so callers can distinguish a cache miss
-- from a confirmed-absent result and skip repeating expensive lookups.
function M.detect_target_branch(root, cached)
  if cached ~= nil then
    return cached
  end

  local gh_out = system({ "gh", "pr", "view", "--json", "baseRefName", "-q", ".baseRefName" }, { cwd = root })
  if gh_out then
    local branch = vim.trim(gh_out)
    if branch ~= "" then
      return branch
    end
  end

  local upstream = system({ "git", "-C", root, "rev-parse", "--abbrev-ref", "@{upstream}" })
  if upstream then
    local trimmed = vim.trim(upstream)
    local stripped = trimmed:match("^[^/]+/(.+)$")
    if stripped and stripped ~= "" then
      return stripped
    end
  end

  return false
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

function M.load_hunks(mode, ctx, opts)
  local root, root_err = M.git_root()
  if not root then
    return nil, root_err or "Not inside a Git repository"
  end

  ctx = ctx or {}
  local base_branch = M.detect_base_branch(ctx.base_branch)
  local target_branch = M.detect_target_branch(root, ctx.target_branch)

  local diff_target = "HEAD"

  if mode == "target" then
    if not target_branch then
      return nil, "Could not detect target branch (no gh PR and no upstream tracking branch)"
    end
    local merge_base, mb_err = system({ "git", "-C", root, "merge-base", target_branch, "HEAD" })
    if not merge_base then
      return nil, mb_err or ("Could not find merge-base with " .. target_branch)
    end
    diff_target = vim.trim(merge_base)
  elseif mode == "main" or mode == "full" then
    if not base_branch then
      return nil, "Could not detect base branch (tried " .. table.concat(base_branches, ", ") .. ")"
    end
    local merge_base, mb_err = system({ "git", "-C", root, "merge-base", base_branch, "HEAD" })
    if not merge_base then
      return nil, mb_err or "Could not find merge-base"
    end
    diff_target = vim.trim(merge_base)
  end

  local context = opts and opts.context or 3
  local diff, diff_err = system({
    "git", "-C", root,
    "diff", "--no-color", "--no-ext-diff", "--unified=" .. context,
    diff_target, "--",
  })

  if not diff then
    return nil, diff_err
  end

  if mode == "uncommitted" then
    local untracked = collect_untracked_diff(root, context)
    if untracked ~= "" then
      diff = (diff ~= "" and (diff .. "\n") or "") .. untracked
    end
  end

  return {
    repo_root = root,
    cwd = (vim.uv or vim.loop).cwd(),
    hunks = M.collect_hunks(diff),
    base_branch = base_branch,
    target_branch = target_branch,
  }, nil
end

return M
