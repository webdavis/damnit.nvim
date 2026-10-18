local with_dam = require("helpers.harness").with_dam
local fake_process = require("helpers.fake_process")
local queue_fake = require("helpers.queue_fake")
local queue, entry = queue_fake.queue, queue_fake.entry
local damnit = require("damnit")

return {
  ["frees the lane when setup runs while a call is in flight"] = function()
    with_dam({}, function()
      local answered, err = false, nil
      queue().submit(entry({ "status", "--json" }, {
        on_done = function(_, failure)
          answered, err = true, failure
        end,
      }))

      damnit.setup({})

      fake_process.settle(function()
        return answered
      end)

      assert(
        err ~= nil and err.kind == "cancelled",
        "setup forgets the handshake the call waits on, so the call is cancelled: " .. vim.inspect(err)
      )
      assert(queue().running() == nil, "a lane left running here is one no later call ever gets out of")
    end)
  end,

  ["keeps the running call, its queue and its lane when setup runs mid-call"] = function()
    with_dam({}, function(dam)
      queue().submit(entry({ "status", "--json" }))
      fake_process.drain()

      local peak = 0
      local run = dam.fake.run
      dam.fake.run = function(...)
        local handle = run(...)
        peak = math.max(peak, dam.fake.in_flight)

        return handle
      end

      local order = {}
      local function noting(name)
        return function(_, failure)
          table.insert(order, failure and ("%s: %s"):format(name, failure.message) or name)
        end
      end

      dam.fake.hold = true
      queue().submit(entry({ "status", "--json" }, { label = "a", on_done = noting("a") }))
      queue().submit(entry({ "status", "--json" }, { label = "b", on_done = noting("b") }))

      damnit.setup({})

      assert(queue().running().label == "a", "the call in flight left the header: " .. vim.inspect(queue().running()))
      queue().submit(entry({ "status", "--json" }, { label = "c", on_done = noting("c") }))
      assert(
        queue().running().pending == 2,
        "a call queued before setup was dropped: " .. vim.inspect(queue().running())
      )

      fake_process.drain()

      assert(vim.deep_equal(order, { "a", "b", "c" }), vim.inspect(order))
      assert(peak == 1, "more than one call was in flight at once: " .. peak)
    end)
  end,

  ["runs the queued call when setup lands during the running call's handshake"] = function()
    with_dam({}, function(dam)
      local order = {}
      local function noting(name)
        return function(_, failure)
          table.insert(order, failure and ("%s: %s"):format(name, failure.message) or name)
        end
      end

      dam.fake.hold = true
      queue().submit(entry({ "status", "--json" }, { label = "a", on_done = noting("a") }))
      queue().submit(entry({ "status", "--json" }, { label = "b", on_done = noting("b") }))

      damnit.setup({})
      fake_process.drain()

      assert(vim.deep_equal(order, { "a: the dam call was dropped when the options changed", "b" }), vim.inspect(order))
    end)
  end,
}
