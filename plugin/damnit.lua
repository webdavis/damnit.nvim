-- `:Dam` and its subcommands.
--
-- Declared here rather than behind `setup` so that entering Neovim on one
-- works, which is how a herdr pane and the list buffer open an object:
-- `nvim +"Dam task <oid>"` in an editor holding nothing else.

if vim.g.loaded_damnit then
  return
end
vim.g.loaded_damnit = true

--- The subcommands whose one argument is a view name, so `:Dam <name> <TAB>`
--- completes on the views rather than on the subcommands again.
---@type table<string, boolean>
local TAKES_A_VIEW = { list = true, pick = true }

--- One entry per subcommand. `""` is `:Dam` with no argument.
---@type table<string, fun(args: string[], cmd: table)>
local SUBCOMMANDS = {
  [""] = function()
    require("damnit.window").open()
  end,
  cancel = function()
    require("damnit.queue").cancel()
  end,
  capture = function(_, cmd)
    local selection = cmd.range > 0 and { line1 = cmd.line1, line2 = cmd.line2 } or nil

    require("damnit.capture").capture(selection)
  end,
  done = function()
    require("damnit").completed()
  end,
  list = function(args)
    require("damnit").open(args[1])
  end,
  pick = function(args)
    require("damnit").pick(args[1])
  end,
  task = function(args)
    if #args ~= 1 then
      return require("damnit.message").fail("usage is :Dam task <oid>")
    end

    require("damnit.task_buffer").open(args[1])
  end,
}

---@return string
local function usage()
  local names = {}
  for name in pairs(SUBCOMMANDS) do
    if name ~= "" then
      names[#names + 1] = ":Dam " .. name
    end
  end
  table.sort(names)

  return "usage is :Dam, " .. table.concat(names, ", ")
end

---@param lead string what has been typed of the argument being completed
---@param line string the whole command line so far
---@return string[]
local function complete(lead, line)
  local typed = vim.split(vim.trim(line), "%s+")

  if #typed > 1 and TAKES_A_VIEW[typed[2]] then
    return vim.tbl_filter(function(name)
      return vim.startswith(name, lead)
    end, require("damnit.views").declared())
  end

  local names = {}
  for name in pairs(SUBCOMMANDS) do
    if name ~= "" and vim.startswith(name, lead) then
      names[#names + 1] = name
    end
  end
  table.sort(names)

  return names
end

vim.api.nvim_create_user_command("Dam", function(cmd)
  local args = cmd.fargs
  local run = SUBCOMMANDS[args[1] or ""]

  if not run then
    return require("damnit.message").fail(usage())
  end

  run(vim.list_slice(args, 2), cmd)
end, {
  nargs = "*",
  range = true,
  complete = complete,
  desc = "dam: the staging window, a list, a task, a search, the history, the sidebar or a capture",
})
