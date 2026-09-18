-- `:Todoist`, `:Todoist <view>`, `:Todoist task <id>` and `:Todoist toggle`
--
-- The command lives here rather than behind `setup` so that entering Neovim on
-- it works, which is how the herdr pane and every list view open a task:
-- `nvim +"Todoist task <id>"` in an editor holding nothing else.

if vim.g.loaded_todoist then
  return
end
vim.g.loaded_todoist = true

local USAGE = "usage is :Todoist, :Todoist <view>, :Todoist toggle or :Todoist task <id>"

---@param lead string what has been typed of the argument being completed
---@return string[]
local function complete(lead)
  local candidates = vim.tbl_keys(require("todoist").options.views or {})
  table.insert(candidates, "task")
  table.insert(candidates, "toggle")
  table.sort(candidates)

  return vim.tbl_filter(function(candidate)
    return vim.startswith(candidate, lead)
  end, candidates)
end

vim.api.nvim_create_user_command("Todoist", function(cmd)
  local args = cmd.fargs

  if #args == 0 then
    return require("todoist").open()
  end

  if args[1] == "toggle" then
    if #args ~= 1 then
      return vim.notify("todoist.nvim: " .. USAGE, vim.log.levels.ERROR)
    end

    return require("todoist.sidebar").toggle()
  end

  if args[1] == "task" then
    if #args ~= 2 then
      return vim.notify("todoist.nvim: " .. USAGE, vim.log.levels.ERROR)
    end

    return require("todoist.task_buffer").open(args[2])
  end

  if #args ~= 1 then
    return vim.notify("todoist.nvim: " .. USAGE, vim.log.levels.ERROR)
  end

  require("todoist").open(args[1])
end, {
  nargs = "*",
  complete = complete,
  desc = "Todoist: a list of tasks, a named view, the sidebar, or one task as a buffer",
})
