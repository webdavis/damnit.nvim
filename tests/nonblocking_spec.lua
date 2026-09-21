-- The requirement that prompted the whole design: nothing in this plugin takes
-- the editor hostage while dam runs.

local fake_dam = dofile((arg[0]:match("(.*)/") or ".") .. "/helpers/fake_dam.lua")
local queue = require("damnit.queue")

return {
  ["returns at once and leaves the loop turning while dam runs"] = function()
    local fake = fake_dam.install({ sleep = "0.4" })
    queue.reset()

    local ticks = 0
    local observer = vim.uv.new_timer()
    observer:start(0, 20, function()
      ticks = ticks + 1
    end)

    local answered = false
    local began = vim.uv.hrtime()
    queue.submit({
      args = { "push", "--json" },
      label = "push todoist",
      verb = "push",
      network = true,
      on_done = function()
        answered = true
      end,
    })
    local submit_ms = (vim.uv.hrtime() - began) / 1e6

    fake_dam.settle(function()
      return answered
    end, 3000)

    observer:stop()
    observer:close()
    local log = fake_dam.argv_log(fake)
    fake_dam.remove(fake)
    queue.reset()

    assert(submit_ms < 100, ("submit took %.1fms, so something waited"):format(submit_ms))
    -- A blocking implementation produces zero ticks. The floor is generous on
    -- purpose: a ceiling around a real spawn is what reddens a build on a slow
    -- runner.
    assert(ticks >= 5, ("the loop ticked %d times while dam ran"):format(ticks))
    assert(log[#log] == "push --json", vim.inspect(log))
  end,

  ["cancels with SIGINT, which dam answers with exit 3"] = function()
    local fake = fake_dam.install({ sleep = "5" })
    queue.reset()
    local grace = queue.GRACE_MS
    queue.GRACE_MS = 20

    local answered, err = false, nil
    queue.submit({
      args = { "push", "--json" },
      label = "push todoist",
      verb = "push",
      network = true,
      on_done = function(_, failure)
        answered, err = true, failure
      end,
    })

    -- The handshake spawns first, so the push is the second recorded argv.
    fake_dam.settle(function()
      return #fake_dam.argv_log(fake) >= 2
    end)

    assert(queue.cancel())

    fake_dam.settle(function()
      return answered
    end)

    queue.GRACE_MS = grace
    fake_dam.remove(fake)
    queue.reset()

    assert(err ~= nil and err.kind == "cancelled", vim.inspect(err))
    assert(err.code == 3, tostring(err.code))
    assert(queue.running() == nil, "the lane is empty once the cancelled entry exits")
  end,

  ["drops the pending entries when the running one is cancelled"] = function()
    local fake = fake_dam.install({ sleep = "5" })
    queue.reset()
    local grace = queue.GRACE_MS
    queue.GRACE_MS = 20

    local ran = 0
    queue.submit({
      args = { "push", "--json" },
      label = "push todoist",
      verb = "push",
      network = true,
      on_done = function()
        ran = ran + 1
      end,
    })
    queue.submit({ args = { "status", "--json" }, label = "status" })
    queue.submit({ args = { "status", "--json" }, label = "status" })

    fake_dam.settle(function()
      return #fake_dam.argv_log(fake) >= 2
    end)

    assert(queue.running().pending == 2, vim.inspect(queue.running()))
    queue.cancel()

    fake_dam.settle(function()
      return queue.running() == nil
    end)

    queue.GRACE_MS = grace
    local log = fake_dam.argv_log(fake)
    fake_dam.remove(fake)
    queue.reset()

    assert(ran == 1, "the cancelled entry is still answered")
    for _, line in ipairs(log) do
      assert(line ~= "status --json", "a dropped entry must never spawn: " .. vim.inspect(log))
    end
  end,
}
