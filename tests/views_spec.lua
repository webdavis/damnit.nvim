local app = require("damnit").app()
local TESTS_DIR = require("helpers.paths").TESTS

dofile(TESTS_DIR .. "/../plugin/damnit.lua")

local fake_process = require("helpers.fake_process")
local function queue()
  return require("damnit").app().queue
end
local views = require("damnit.views")
local damnit = require("damnit")
local said = require("helpers.said")

local function with_views(declared, run)
  local fake = fake_process.install({ fixtures = TESTS_DIR .. "/fixtures/full" })
  views.reset()
  damnit.options.views = declared

  local notifications = fake.said

  local ok, err = pcall(run, notifications, fake)

  fake_process.drain()

  damnit.options.views = {}
  views.reset()
  fake_process.remove(fake)

  assert(ok, err)
end

local function resolved(name)
  local spec, answered = nil, false

  views.resolve_then(app, name, function(found)
    spec, answered = found, true
  end)
  fake_process.settle(function()
    return answered or queue().running() == nil
  end)

  return spec
end

local function times_sent(fake, argv)
  return #vim.tbl_filter(function(line)
    return line == argv
  end, fake_process.argv_log(fake))
end

return {
  ["means every open task when it is given no name, and asks dam for no finished one"] = function()
    local spec = views.resolve(app, nil)

    assert(spec.title == "all open tasks", spec.title)
    assert(spec.query == nil, tostring(spec.query))
    assert(vim.deep_equal(views.query_args(spec), { "ls", "!done", "--json" }), vim.inspect(views.query_args(spec)))
  end,

  ["sends the declared query rather than the name, and asks dam nothing first"] = function()
    with_views({ today = "due:today | overdue" }, function(_, fake)
      local spec = resolved("today")

      assert(spec.query == "due:today | overdue", spec.query)
      assert(vim.deep_equal(views.query_args(spec), { "ls", "due:today | overdue", "--json" }))
      assert(times_sent(fake, "filter list --json") == 0, vim.inspect(fake_process.argv_log(fake)))
    end)
  end,

  ["reads dam's saved filters once per session and hands one of them to dam by name"] = function()
    with_views({}, function(_, fake)
      views.load(app)
      local spec = resolved("inbox")

      assert(spec and spec.title == "inbox" and spec.query == "inbox", vim.inspect(spec))

      resolved("today")
      fake_process.drain()
      assert(times_sent(fake, "filter list --json") == 1, vim.inspect(fake_process.argv_log(fake)))
    end)
  end,

  ["reads dam's saved filters again once setup points at another store"] = function()
    with_views({}, function(_, fake)
      resolved("inbox")
      damnit.setup({ store = "/store/other.db" })
      resolved("inbox")
      damnit.options.store = nil

      local filter_lists = vim.tbl_filter(function(line)
        return vim.endswith(line, "filter list --json")
      end, fake_process.argv_log(fake))
      assert(#filter_lists == 2, vim.inspect(fake_process.argv_log(fake)))
    end)
  end,

  ["refuses a name in neither source before any ls, naming both sources"] = function()
    with_views({ work = "path:work/" }, function(notifications, fake)
      assert(resolved("tomorrow") == nil, "a name in neither source is refused")

      assert(times_sent(fake, "filter list --json") == 1, vim.inspect(fake_process.argv_log(fake)))
      for _, line in ipairs(fake_process.argv_log(fake)) do
        assert(not vim.startswith(line, "ls "), "a refused name cost an ls: " .. line)
      end
      assert(#notifications == 1, vim.inspect(notifications))
      assert(
        said.whole(
          notifications[1],
          'damnit.nvim: there is no view named "tomorrow"; declared views are work; '
            .. "dam's saved filters are inbox, today"
        ),
        notifications[1]
      )
    end)
  end,

  ["says so when nothing is declared at all"] = function()
    with_views({}, function(notifications)
      resolved("tomorrow")

      assert(
        said.whole(
          notifications[1],
          'damnit.nvim: there is no view named "tomorrow"; no views are declared in setup; '
            .. "dam's saved filters are inbox, today"
        ),
        notifications[1]
      )
    end)
  end,

  [":Dam list completes the declared views at once, and dam's saved filters once they are read"] = function()
    with_views({ work = "path:work/" }, function(_, fake)
      assert(vim.deep_equal(vim.fn.getcompletion("Dam list ", "cmdline"), { "work" }))

      fake_process.settle(function()
        return #vim.fn.getcompletion("Dam list ", "cmdline") == 3
      end)
      assert(vim.deep_equal(vim.fn.getcompletion("Dam pick t", "cmdline"), { "today" }))
      assert(times_sent(fake, "filter list --json") == 1, "each Tab while the list was read asked again")
    end)
  end,

  ["offers both sources for completion, once each, with the declared name winning"] = function()
    with_views({ today = "due:today", work = "path:work/" }, function()
      resolved("inbox")

      assert(vim.deep_equal(views.known(app), { "inbox", "today", "work" }), vim.inspect(views.known(app)))
      assert(resolved("today").query == "due:today", "the declared view wins a collision")
    end)
  end,
}
