-- `:Dam`, `:Dam <view>`, `:Dam completed`, `:Dam task <id>` and
-- `:Dam toggle`
--
-- The command lives here rather than behind `setup` so that entering Neovim on
-- it works, which is how the herdr pane and every list view open a task:
-- `nvim +"Todoist task <id>"` in an editor holding nothing else.

if vim.g.loaded_damnit then
  return
end
vim.g.loaded_damnit = true

local USAGE = "usage is :Dam, :Dam <view>, :Dam completed, :Dam toggle,"
  .. " :Dam capture, :Dam pick [<view>] or :Dam task <id>"

---@param lead string what has been typed of the argument being completed
---@return string[]
local function complete(lead)
  local candidates = vim.tbl_keys(require("damnit").options.views or {})
  table.insert(candidates, "capture")
  table.insert(candidates, "completed")
  table.insert(candidates, "pick")
  table.insert(candidates, "task")
  table.insert(candidates, "toggle")
  table.sort(candidates)

  return vim.tbl_filter(function(candidate)
    return vim.startswith(candidate, lead)
  end, candidates)
end

vim.api.nvim_create_user_command("Dam", function(cmd)
  local args = cmd.fargs

  if #args == 0 then
    return require("damnit").open()
  end

  if args[1] == "toggle" then
    if #args ~= 1 then
      return vim.notify("damnit.nvim: " .. USAGE, vim.log.levels.ERROR)
    end

    return require("damnit.sidebar").toggle()
  end

  if args[1] == "completed" then
    if #args ~= 1 then
      return vim.notify("damnit.nvim: " .. USAGE, vim.log.levels.ERROR)
    end

    return require("damnit.completed").open()
  end

  if args[1] == "capture" then
    if #args ~= 1 then
      return vim.notify("damnit.nvim: " .. USAGE, vim.log.levels.ERROR)
    end

    -- `range` is 0 unless the command was given one, which is how a capture
    -- from visual mode is told apart from a capture on the cursor's line.
    local selection = cmd.range > 0 and { line1 = cmd.line1, line2 = cmd.line2 } or nil

    return require("damnit.capture").capture(selection)
  end

  if args[1] == "pick" then
    if #args > 2 then
      return vim.notify("damnit.nvim: " .. USAGE, vim.log.levels.ERROR)
    end

    return require("damnit").pick(args[2])
  end

  if args[1] == "task" then
    if #args ~= 2 then
      return vim.notify("damnit.nvim: " .. USAGE, vim.log.levels.ERROR)
    end

    return require("damnit.task_buffer").open(args[2])
  end

  if #args ~= 1 then
    return vim.notify("damnit.nvim: " .. USAGE, vim.log.levels.ERROR)
  end

  require("damnit").open(args[1])
end, {
  nargs = "*",
  range = true,
  complete = complete,
  desc = "dam: a list of tasks, a named view, the completed history, the sidebar, a capture, a search, or one task",
})
