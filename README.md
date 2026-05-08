# ai-hunk-review.nvim

`ai-hunk-review.nvim` is a small Neovim plugin that opens a two-pane review UI for the current `git diff HEAD`. In LazyVim with `snacks.nvim` available, it opens as a fullscreen-ish floating modal similar to LazyGit. The left pane is a file explorer for changed files, and the right pane is a synthetic hunk review buffer showing all hunks across files. As you move through the review pane, the active file is highlighted in the explorer. It is designed for lightweight review passes where you want to move through hunks, annotate them, jump back to source, and export structured instructions for a local AI agent.

## Commands

- `:AIReview` opens or refreshes the review buffer.
- `:AIReviewRefresh` reloads the current Git hunks.
- `:AIReviewExport` opens a JSON export buffer with the current hunk data and comments.

Each hunk header also includes its file path inline so the source file stays visible while scrolling.

If `snacks.nvim` is unavailable, the plugin falls back to the previous split-window layout.

## Explorer Pane

- `j` and `k` use normal cursor movement to browse changed files.
- `<CR>` or `o` jumps the reviewer pane to the first hunk for the current file and focuses it.
- `<C-l>` focuses the review pane.
- `/` opens a filter prompt for narrowing the file list.
- `x` clears the current file filter.
- `r` refreshes the review layout.
- `q` closes the two-pane layout.

## Review Pane

- `j` jumps to the next contiguous change block (`+++` or `---` runs).
- `k` jumps to the previous contiguous change block (`+++` or `---` runs).
- `<C-h>` focuses the explorer pane.
- `<CR>` opens a confirmation modal to copy the current review to your clipboard.
- `[h` jumps to the previous hunk.
- `]h` jumps to the next hunk.
- `o` jumps to the source file near the selected diff line.
- `c` adds or edits a comment for the current addition or deletion block.
- `e` exports the current review payload.
- `r` refreshes the review buffer.
- `q` closes the review buffer.

## Installation

With `lazy.nvim`:

```lua
{
  dir = "/path/to/ai-hunk-review.nvim",
}
```

## Notes

- The MVP reads from `git diff HEAD`, so it focuses on tracked changes relative to `HEAD`.
- Comments are kept in memory for the current Neovim session and keyed per contiguous change block.
