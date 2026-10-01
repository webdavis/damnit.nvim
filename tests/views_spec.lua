local TESTS_DIR = arg[0]:match("(.*)/") or "."

dofile(TESTS_DIR .. "/../plugin/damnit.lua")

local fake_dam = dofile(TESTS_DIR .. "/helpers/fake_dam.lua")
local queue = require("damnit.queue")
local views = require("damnit.views")
local damnit = require("damnit")

local function with_views(declared, run)
  local fake = fake_dam.install({ fixtures = TESTS_DIR .. "/fixtures/full" })
  queue.reset()
  views.reset()
  damnit.options.views = declared

  local notifications = {}
  local real = vim.notify
  vim.notify = function(text)
    table.insert(notifications, text)
  end

  local ok, err = pcall(run, notifications, fake)

  fake_dam.drain_the_lane_so_no_answer_lands_in_the_next_case()

  vim.notify = real
  damnit.options.views = {}
  views.reset()
  queue.reset()
  fake_dam.remove(fake)

  assert(ok, err)
end

local function resolved(name)
  local spec, answered = nil, false

  views.resolve_then(name, function(found)
    spec, answered = found, true
  end)
  fake_dam.settle(function()
    return answered or queue.running() == nil
  end)

  return spec
end

local function times_sent(fake, argv)
  return #vim.tbl_filter(function(line)
    return line == argv
  end, fake_dam.argv_log(fake))
end

return {
  ["means every open task when it is given no name"] = function()
    local spec = views.resolve(nil)

    assert(spec.title == "all open tasks", spec.title)
    assert(spec.query == nil, tostring(spec.query))
    assert(vim.deep_equal(views.query_args(spec), { "ls", "--json" }), vim.inspect(views.query_args(spec)))
  end,

  ["sends the declared query rather than the name, and asks dam nothing first"] = function()
    with_views({ today = "due:today | overdue" }, function(_, fake)
      local spec = resolved("today")

      assert(spec.query == "due:today | overdue", spec.query)
      assert(vim.deep_equal(views.query_args(spec), { "ls", "due:today | overdue", "--json" }))
      assert(times_sent(fake, "filter list --json") == 0, vim.inspect(fake_dam.argv_log(fake)))
    end)
  end,

  ["reads dam's saved filters once per session and hands one of them to dam by name"] = function()
    with_views({}, function(_, fake)
      views.load()
      local spec = resolved("inbox")

      assert(spec and spec.title == "inbox" and spec.query == "inbox", vim.inspect(spec))

      resolved("today")
      fake_dam.drain_the_lane_so_no_answer_lands_in_the_next_case()
      assert(times_sent(fake, "filter list --json") == 1, vim.inspect(fake_dam.argv_log(fake)))
    end)
  end,

  ["refuses a name in neither source before any ls, naming both sources"] = function()
    with_views({ work = "path:work/" }, function(notifications, fake)
      assert(resolved("tomorrow") == nil, "a name in neither source is refused")

      assert(times_sent(fake, "filter list --json") == 1, vim.inspect(fake_dam.argv_log(fake)))
      for _, line in ipairs(fake_dam.argv_log(fake)) do
        assert(not vim.startswith(line, "ls "), "a refused name cost an ls: " .. line)
      end
      assert(#notifications == 1, vim.inspect(notifications))
      assert(notifications[1]:find('no view named "tomorrow"', 1, true), notifications[1])
      assert(notifications[1]:find("declared views are work", 1, true), notifications[1])
      assert(notifications[1]:find("dam's saved filters are inbox, today", 1, true), notifications[1])
    end)
  end,

  ["says so when nothing is declared at all"] = function()
    with_views({}, function(notifications)
      resolved("tomorrow")

      assert(notifications[1]:find("no views are declared in setup", 1, true), notifications[1])
    end)
  end,

  [":Dam list completes the declared views at once, and dam's saved filters once they are read"] = function()
    with_views({ work = "path:work/" }, function(_, fake)
      assert(vim.deep_equal(vim.fn.getcompletion("Dam list ", "cmdline"), { "work" }))

      fake_dam.settle(function()
        return #vim.fn.getcompletion("Dam list ", "cmdline") == 3
      end)
      assert(vim.deep_equal(vim.fn.getcompletion("Dam pick t", "cmdline"), { "today" }))
      assert(times_sent(fake, "filter list --json") == 1, "each Tab while the list was read asked again")
    end)
  end,

  ["offers both sources for completion, once each, with the declared name winning"] = function()
    with_views({ today = "due:today", work = "path:work/" }, function()
      resolved("inbox")

      assert(vim.deep_equal(views.known(), { "inbox", "today", "work" }), vim.inspect(views.known()))
      assert(resolved("today").query == "due:today", "the declared view wins a collision")
    end)
  end,
}
