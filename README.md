<img width="1083" height="841" alt="Screenshot 2026-05-13 at 4 38 43 PM" src="https://github.com/user-attachments/assets/2f87c2ce-b011-4e77-95e4-4bbec6044071" />

<h1 align="center">🔍 hunk-review.nvim</h1> <p align="center">A lightweight, keyboard-driven code review plugin for Neovim.<br/>Built for reviewing AI-generated code before it hits your codebase.</p>

Coding agents and LLMs can write a lot of code fast — but someone still needs to review it. hunk-review.nvim gives you a focused, distraction-free environment to walk through every change, annotate what needs fixing, and export structured feedback that agents can act on. No context-switching to a browser, no PR UI overhead. Just you, the diff, and your keyboard.

- ✅ two-pane review UI with file explorer + diff viewer
- ✅ inline commenting on change blocks, individual lines, or ranges
- ✅ TreeSitter-powered syntax highlighting in diffs
- ✅ peek into source files without leaving the review
- ✅ structured JSON export for AI agents and downstream tools
- ✅ auto-detects base + target branches with uncommitted / target / main diff modes (stacked-PR aware)

## Getting started

Install with [lazy.nvim](https://github.com/folke/lazy.nvim):
```lua
{
  "shaunchander/hunk-review.nvim",
  opts = {
    -- Optional: prepend a system prompt to the clipboard export so you can
    -- paste directly into an LLM without writing instructions each time.
    -- custom_prompt = "Review these diffs and comments. Suggest targeted fixes only where a comment requests action.",
  },
}
```

Then, open a review session:
```
:HunkReview
```

🎉 You're now reviewing your git diff in a purpose-built two-pane layout. Navigate files on the left, review hunks on the right.

## 📘 Documentation

### How it works

hunk-review.nvim reads your `git diff` and renders it into a navigable, annotatable buffer. You get a file tree on the left and a unified diff view on the right — all keyboard-driven, no mouse needed.

You can add comments to change blocks, cycle between uncommitted / target-branch / main-branch diffs, peek at source files in a floating window, and export your entire review as structured JSON.

### Explorer pane (left)

| Key | Action |
|-----|--------|
| `j` / `k` | Navigate files |
| `<CR>` / `o` | Jump to file's first hunk |
| `<C-l>` | Focus review pane |
| `/` | Filter files by name |
| `x` | Clear filter |
| `[` / `]` | Cycle diff mode (uncommitted → target → main) |
| `C` | Toggle comments sidebar |
| `r` | Refresh |
| `q` | Close |

### Review pane (right)

| Key | Action |
|-----|--------|
| `j` / `k` | Jump to next/previous change block |
| `]h` / `[h` | Jump to next/previous hunk header |
| `<Space>` | Toggle line-by-line mode |
| `c` | Add/edit comment on change block or line |
| `d` | Delete comment on current block |
| `<CR>` | Copy review to clipboard (in visual mode: comment on selected lines) |
| `o` | Jump to source file at current line |
| `p` | Peek source file in floating window |
| `e` | Export JSON review payload |
| `<C-h>` | Focus explorer pane |
| `[` / `]` | Cycle diff mode |
| `C` | Toggle comments sidebar |

Visual mode: select a range and press `c` or `<CR>` to comment on multiple lines.

### Commenting

Add comments to any change block with `c`, or toggle line mode with `<Space>` and comment on individual lines with `c`. Comments persist for the session and are included in exports.

Open the comments sidebar with `C` to see all your comments organized by file. In the sidebar, press `j`/`k` to jump between comments, `<CR>` to jump to the comment's location in the diff, and `d` to delete a comment.

### Diff modes

Cycle diff modes with `[` and `]`:

- **Uncommitted** — `git diff HEAD` (your working changes)
- **Target** — `git diff $(merge-base <target> HEAD)` against the PR/upstream target branch. Only appears when the target branch is **not** the main base (useful for stacked PRs against a parent branch).
- **Main** — `git diff $(merge-base <base> HEAD)` against `main`/`master`/`develop`.

The **main** base branch is auto-detected from `main`, `master`, or `develop` (configurable via `setup()`).

The **target** branch is detected by trying, in order:

1. `gh pr view --json baseRefName` (the actual GitHub PR base — most accurate for stacked PRs)
2. `git rev-parse --abbrev-ref @{upstream}` (upstream tracking branch, with remote prefix stripped)

If neither succeeds, or the detected target equals the main base, the Target tab is hidden.

### Reviewing agent-generated code

hunk-review.nvim is purpose-built for the workflow of reviewing code that coding agents (Claude Code, Copilot, Cursor, Aider, etc.) write on your behalf. Instead of scanning raw diffs in the terminal or jumping between files, you get a structured review pass:

1. **Agent writes code** — let it generate, refactor, or fix across multiple files
2. **`:HunkReview`** — open the review UI and walk through every change
3. **Annotate** — add comments on blocks that need revision, look wrong, or need context
4. **Export** — send structured feedback back to the agent with `e` or copy to clipboard with `<CR>`

The JSON export includes file paths, line numbers, your comments, and the surrounding diff — everything an agent needs to act on your feedback without guessing what you meant.

### Export

Press `e` to generate a structured JSON payload with all hunks, change blocks, and comments. The export is designed for consumption by AI agents or external review tools.

Press `<CR>` (outside line mode) to copy a text-formatted review to your clipboard — grouped by comment with file:line locations and fenced code blocks.

## ⚙️ Configuration

All settings are optional. Call `setup()` to override defaults:

```lua
require("hunk-review").setup({
  -- Branches to try when detecting merge-base for the "Main" diff mode
  base_branches = { "main", "master", "develop" },

  -- Floating layout dimensions (0-1 = percentage of editor)
  layout = {
    width = 0.96,
    height = 0.92,
    explorer_width = 0.28,
  },

  -- Number of context lines in git diff
  diff_context = 3,

  -- Prepend a custom prompt to the clipboard export (<CR> outside line mode).
  -- Useful for pasting directly into an LLM with pre-defined instructions.
  -- When nil (default), only the diff and comments are copied.
  custom_prompt = nil,
})
```

### Health check

Run `:checkhealth hunk-review` to verify your setup (git, snacks.nvim, treesitter parsers).

## Commands

### `:HunkReview`
Open the review buffer. If already open, refreshes with latest diff.

### `:HunkReviewRefresh`
Reload git hunks and re-render the layout.

### `:HunkReviewExport`
Open a buffer with the structured JSON export.

### `:HunkReviewReset`
Clear all comments and reset review state.

## Optional dependency

[snacks.nvim](https://github.com/folke/snacks.nvim) — for an enhanced floating modal layout. Without it, hunk-review falls back to standard Neovim splits.
