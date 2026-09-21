-- The queue: one dam per store at a time, a refused second network call, and
-- what cancelling drops.

local fake_dam = dofile((arg[0]:match("(.*)/") or ".") .. "/helpers/fake_dam.lua")
local queue = require("damnit.queue")
local damnit = require("damnit")

---@param run fun(fake: damnit.FakeDam, notifications: string[])
---@param opts table?
local function with_fake(run, opts)
  local fake = fake_dam.install(opts)
  queue.reset()

  local notifications = {}
  local real = vim.notify
  vim.notify = function(text)
    table.insert(notifications, text)
  end

  local ok, err = pcall(run, fake, notifications)

  vim.notify = real
  queue.reset()
  fake_dam.remove(fake)
  damnit.options.store = nil

  assert(ok, err)
end

---@param args string[]
---@param extra table?
---@return table entry
local function entry(args, extra)
  return vim.tbl_extend("force", { args = args, label = table.concat(args, " ") }, extra or {})
end

return {
  ["runs one entry at a time and holds the rest"] = function()
    with_fake(function()
      queue.submit(entry({ "status", "--json" }))
      queue.submit(entry({ "status", "--json" }))

      local running = queue.running()
      assert(running ~= nil, "the first entry starts as soon as it is submitted")
      assert(running.pending == 1, tostring(running.pending))
    end, { sleep = "0.3" })
  end,

  ["refuses a second push and names the one already running"] = function()
    with_fake(function(fake, notifications)
      assert(queue.submit(entry({ "push", "--json" }, { label = "push todoist", verb = "push", network = true })))

      local second =
        queue.submit(entry({ "push", "--json" }, { label = "push todoist", verb = "push", network = true }))

      assert(second == false, "the second push must be refused rather than queued")
      assert(#notifications == 1, vim.inspect(notifications))
      assert(notifications[1] == "damnit.nvim: push todoist is already running; C-c cancels it", notifications[1])

      fake_dam.settle(function()
        return queue.running() == nil
      end, 3000)

      local pushes = 0
      for _, line in ipairs(fake_dam.argv_log(fake)) do
        if line == "push --json" then
          pushes = pushes + 1
        end
      end
      assert(pushes == 1, vim.inspect(fake_dam.argv_log(fake)))
    end, { sleep = "0.2" })
  end,

  ["tells a pull that a push is what is in the way"] = function()
    with_fake(function(_, notifications)
      queue.submit(entry({ "push", "--json" }, { label = "push todoist", verb = "push", network = true }))
      queue.submit(entry({ "pull", "--json" }, { label = "pull todoist", verb = "pull", network = true }))

      assert(notifications[1] == "damnit.nvim: push todoist is running; C-c cancels it, then pull", notifications[1])
    end, { sleep = "0.2" })
  end,

  ["queues a local call behind a running network one"] = function()
    with_fake(function()
      queue.submit(entry({ "push", "--json" }, { label = "push todoist", verb = "push", network = true }))

      assert(queue.submit(entry({ "status", "--json" })), "a local call queues rather than being refused")
      assert(queue.running().pending == 1, vim.inspect(queue.running()))
    end, { sleep = "0.2" })
  end,

  ["keeps a second store's lane independent of the first"] = function()
    with_fake(function()
      damnit.options.store = "/store/one.db"
      queue.submit(entry({ "status", "--json" }))

      damnit.options.store = "/store/two.db"
      queue.submit(entry({ "status", "--json" }))

      assert(queue.running("/store/one.db") ~= nil, "the first store is still running")
      assert(queue.running("/store/two.db") ~= nil, "the second store did not wait on the first")
    end, { sleep = "0.3" })
  end,

  ["says nothing is running when there is nothing to cancel"] = function()
    with_fake(function(_, notifications)
      assert(queue.cancel() == false)
      assert(notifications[1] == "damnit.nvim: nothing is running", notifications[1])
    end)
  end,
}
