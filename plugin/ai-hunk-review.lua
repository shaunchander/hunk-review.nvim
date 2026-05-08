if vim.g.loaded_ai_hunk_review then
  return
end

vim.g.loaded_ai_hunk_review = 1

local review = require("ai-hunk-review")

vim.api.nvim_create_user_command("AIReview", function()
  review.open()
end, {
  desc = "Open the AI hunk review buffer",
})

vim.api.nvim_create_user_command("AIReviewRefresh", function()
  review.refresh()
end, {
  desc = "Refresh the AI hunk review buffer",
})

vim.api.nvim_create_user_command("AIReviewExport", function()
  review.export()
end, {
  desc = "Export structured AI review instructions",
})
