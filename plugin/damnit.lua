-- `:Dam` and its subcommands.
--
-- Declared here rather than behind `setup` so that entering Neovim on one
-- works, which is how a herdr pane and the list buffer open an object:
-- `nvim +"Dam task <oid>"` in an editor holding nothing else.

if vim.g.loaded_damnit then
  return
end
vim.g.loaded_damnit = true

--- One entry per subcommand. `""` is `:Dam` with no argument.
---@type table<string, fun(args: string[], cmd: table)>
local SUBCOMMANDS = {
  [""] = function()
    require("damnit.window").open()
  end,
  cancel = function()
    require("damnit.queue").cancel()
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

---@param lead string
---@return string[]
local function complete(lead)
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
    return vim.notify("damnit.nvim: " .. usage(), vim.log.levels.ERROR)
  end

  run(vim.list_slice(args, 2), cmd)
end, {
  nargs = "*",
  range = true,
  complete = complete,
  desc = "dam: the staging window, a list, a task, a search, the history, the sidebar or a capture",
})
