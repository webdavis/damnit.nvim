local fake_process = dofile((arg[0]:match("(.*)/") or ".") .. "/helpers/fake_process.lua")
local queue_fake = dofile((arg[0]:match("(.*)/") or ".") .. "/helpers/queue_fake.lua")
local queue, with_fake, entry = queue_fake.queue, queue_fake.with_fake, queue_fake.entry
local damnit = require("damnit")

return {
  ["runs one entry at a time and holds the rest"] = function()
    with_fake(function()
      queue().submit(entry({ "status", "--json" }))
      queue().submit(entry({ "status", "--json" }))

      local running = queue().running()
      assert(running ~= nil, "the first entry starts as soon as it is submitted")
      assert(running.pending == 1, tostring(running.pending))
    end)
  end,

  ["hides a background entry from the display and still reports it as running"] = function()
    with_fake(function()
      queue().submit(entry({ "ls", "--json" }, { label = "ls", background = true }))

      local running = queue().running()
      local foreground = queue().foreground()

      assert(
        running ~= nil and running.background == true,
        "a background read still holds the lane: " .. vim.inspect(running)
      )
      assert(
        foreground == nil,
        "nothing is said about a background read where a person is reading: " .. vim.inspect(foreground)
      )
    end)
  end,

  ["reports a call somebody asked for as the one worth showing"] = function()
    with_fake(function()
      queue().submit(entry({ "push", "--json" }, { label = "push fake" }))

      local foreground = queue().foreground()

      assert(foreground ~= nil, "a foreground entry is what the header and the statusline draw")
      assert(foreground.label == "push fake", foreground.label)
      assert(foreground.background == nil, vim.inspect(foreground))
    end)
  end,

  ["refuses a second push and names the one already running"] = function()
    with_fake(function(fake, notifications)
      assert(queue().submit(entry({ "push", "--json" }, { label = "push todoist", verb = "push", network = true })))

      local second =
        queue().submit(entry({ "push", "--json" }, { label = "push todoist", verb = "push", network = true }))

      assert(second == false, "the second push must be refused rather than queued")
      assert(#notifications == 1, vim.inspect(notifications))
      assert(notifications[1] == "damnit.nvim: push todoist is already running; C-c cancels it", notifications[1])

      fake_process.settle(function()
        return queue().running() == nil
      end)

      local pushes = 0
      for _, line in ipairs(fake_process.argv_log(fake)) do
        if line == "push --json" then
          pushes = pushes + 1
        end
      end
      assert(pushes == 1, vim.inspect(fake_process.argv_log(fake)))
    end)
  end,

  ["tells a pull that a push is what is in the way"] = function()
    with_fake(function(_, notifications)
      queue().submit(entry({ "push", "--json" }, { label = "push todoist", verb = "push", network = true }))
      queue().submit(entry({ "pull", "--json" }, { label = "pull todoist", verb = "pull", network = true }))

      assert(notifications[1] == "damnit.nvim: push todoist is running; C-c cancels it, then pull", notifications[1])
    end)
  end,

  ["queues a local call behind a running network one"] = function()
    with_fake(function()
      queue().submit(entry({ "push", "--json" }, { label = "push todoist", verb = "push", network = true }))

      assert(queue().submit(entry({ "status", "--json" })), "a local call queues rather than being refused")
      assert(queue().running().pending == 1, vim.inspect(queue().running()))
    end)
  end,

  ["keeps a second store's lane independent of the first"] = function()
    with_fake(function(fake)
      damnit.setup({ store = "/store/one.db" })
      queue().submit(entry({ "status", "--json" }))
      fake_process.drain()

      fake.hold = true
      queue().submit(entry({ "status", "--json" }))

      damnit.setup({ store = "/store/two.db" })
      queue().submit(entry({ "status", "--json" }))

      assert(queue().running("/store/one.db") ~= nil, "the first store is still running")
      assert(queue().running("/store/two.db") ~= nil, "the second store did not wait on the first")
    end)
  end,

  ["says nothing is running when there is nothing to cancel"] = function()
    with_fake(function(_, notifications)
      assert(queue().cancel() == false)
      assert(notifications[1] == "damnit.nvim: nothing is running", notifications[1])
    end)
  end,
}
