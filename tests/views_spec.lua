-- Resolving a view name against the two sources, and what a name in neither
-- costs.

local views = require("damnit.views")
local damnit = require("damnit")

---@param declared table<string, string>
---@param run fun(notifications: string[])
local function with_views(declared, run)
  views.reset()
  damnit.options.views = declared

  local notifications = {}
  local real = vim.notify
  vim.notify = function(text)
    table.insert(notifications, text)
  end

  local ok, err = pcall(run, notifications)

  vim.notify = real
  damnit.options.views = {}
  views.reset()

  assert(ok, err)
end

return {
  ["means every open task when it is given no name"] = function()
    local spec = views.resolve(nil)

    assert(spec.title == "all open tasks", spec.title)
    assert(spec.query == nil, tostring(spec.query))
    assert(vim.deep_equal(views.query_args(spec), { "ls", "--json" }), vim.inspect(views.query_args(spec)))
  end,

  ["sends the declared query rather than the name"] = function()
    with_views({ today = "due:today | overdue" }, function()
      local spec = views.resolve("today")

      assert(spec.query == "due:today | overdue", spec.query)
      assert(spec.probing == nil, "a declared view is not a probe")
      assert(vim.deep_equal(views.query_args(spec), { "ls", "due:today | overdue", "--json" }))
    end)
  end,

  ["hands an undeclared name to dam as a bare word, once"] = function()
    with_views({ today = "due:today" }, function()
      local spec = views.resolve("work")

      assert(spec.query == "work", spec.query)
      assert(spec.probing == true, "an undeclared name is a probe of dam's saved filters")
    end)
  end,

  ["refuses the name before any call once dam has refused it too"] = function()
    with_views({ today = "due:today", work = "path:work/" }, function(notifications)
      views.forget_filter("tomorrow")

      assert(views.resolve("tomorrow") == nil, "a name in neither source is refused")
      assert(#notifications == 1, vim.inspect(notifications))
      assert(notifications[1]:find('no view named "tomorrow"', 1, true), notifications[1])
      assert(notifications[1]:find("declared views are today, work", 1, true), notifications[1])
    end)
  end,

  ["says so when nothing is declared at all"] = function()
    with_views({}, function(notifications)
      views.forget_filter("today")
      views.resolve("today")

      assert(notifications[1]:find("no views are declared in setup", 1, true), notifications[1])
    end)
  end,
}
