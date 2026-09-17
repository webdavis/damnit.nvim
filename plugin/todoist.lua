-- `:Todoist task <id>`
--
-- The command lives here rather than behind `setup` so that entering Neovim on
-- it works, which is how the herdr pane and every list view open a task:
-- `nvim +"Todoist task <id>"` in an editor holding nothing else.

if vim.g.loaded_todoist then
  return
end
vim.g.loaded_todoist = true

local USAGE = "usage is :Todoist task <id>"

vim.api.nvim_create_user_command("Todoist", function(cmd)
  if #cmd.fargs ~= 2 or cmd.fargs[1] ~= "task" then
    return vim.notify("todoist.nvim: " .. USAGE, vim.log.levels.ERROR)
  end

  require("todoist.task_buffer").open(cmd.fargs[2])
end, { nargs = "*", desc = "Todoist: open one task as a buffer" })
