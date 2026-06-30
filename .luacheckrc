-- luacheck configuration for hunk-review.nvim

-- Ignore vim global (provided by Neovim)
globals = {
  "vim",
}

-- Read access to these globals is allowed
read_globals = {
  "vim",
}

-- Exclude test files from certain checks
files["tests/**/*_spec.lua"] = {
  std = "+busted",
  globals = {
    "describe",
    "it",
    "before_each",
    "after_each",
    "pending",
    "assert",
  }
}

-- Ignore line length warnings
max_line_length = false

-- Ignore warnings about unused self
self = false
