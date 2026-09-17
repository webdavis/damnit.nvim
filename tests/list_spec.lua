-- Named views: what `open` does with a name, and what it refuses.
--
-- A name that is not declared is refused before any request, so these cases
-- reach no server and need no double.

-- `--clean -l` sources no plugin directory, so the command this spec drives is
-- loaded by hand. It guards itself, so a second spec doing the same is a no-op.
dofile(((arg[0]:match("(.*)/") or ".") .. "/../plugin/todoist.lua"))

local todoist = require("todoist")

---@param views table<string, string>
---@param run fun()
---@return string[] notifications
local function with_views(views, run)
  todoist.options = vim.tbl_extend("force", todoist.options, { views = views })

  local notifications = {}
  local real_notify = vim.notify
  vim.notify = function(message)
    table.insert(notifications, message)
  end

  local ok, err = pcall(run)

  vim.notify = real_notify
  assert(ok, err)

  return notifications
end

---@param views table<string, string>
---@param name string
---@return string[] notifications
local function open(views, name)
  return with_views(views, function()
    todoist.open(name)
  end)
end

return {
  ["refuses a view it was never given, and says which ones it has"] = function()
    local notifications = open({ today = "today | overdue", work = "#Work" }, "tomorrow")

    assert(#notifications == 1, vim.inspect(notifications))
    assert(notifications[1]:find('no view named "tomorrow"', 1, true), notifications[1])
    assert(notifications[1]:find("declared views are today, work", 1, true), notifications[1])
  end,

  [":Todoist <name> is the same refusal, so the command and the function agree"] = function()
    local notifications = with_views({ today = "today | overdue" }, function()
      vim.cmd("Todoist tomorrow")
    end)

    assert(#notifications == 1, vim.inspect(notifications))
    assert(notifications[1]:find('no view named "tomorrow"', 1, true), notifications[1])
  end,

  ["says so when no views are declared at all"] = function()
    local notifications = open({}, "today")

    assert(#notifications == 1, vim.inspect(notifications))
    assert(notifications[1]:find("no views are declared in setup", 1, true), notifications[1])
  end,
}
