local TESTS_DIR = arg[0]:match("(.*)/") or "."

local fake_dam = dofile(TESTS_DIR .. "/helpers/fake_dam.lua")
local queue = require("damnit.queue")
local done = require("damnit.done")

local TAXES = { oid = "cfdc36e6c43673b75f02ea89501cba466e96625b", subject = "file taxes" }
local STANDUP = { oid = "a070c369a6dfc382d57988322e453d85d62ef9cf", subject = "standup" }

local REFUSAL_FOR_A_PARENT_WHOSE_CHILD_IS_OPEN = table.concat({
  '{"error": {"kind": "refused", "rule": "blocked", ',
  '"message": "cfdc36e cannot be completed:\\n  child 4aa6797 is open\\n',
  'use --force to complete it anyway, or --force --interactive to decide what happens to them", ',
  '"oids": ["cfdc36e6c43673b75f02ea89501cba466e96625b", "4aa6797253e3610afe61c236650b6ec3f41877ee"]}}',
})

local REFUSAL_FOR_AN_EVENT_NO_FORCE_CAN_HELP = table.concat({
  '{"error": {"kind": "refused", "rule": "not_a_task", ',
  '"message": "a070c36 is an event; events are not completed", ',
  '"oids": ["a070c369a6dfc382d57988322e453d85d62ef9cf"]}}',
})

local function with_dam(run, opts)
  opts = opts or {}

  local fake = fake_dam.install({
    fixtures = opts.fixtures or (TESTS_DIR .. "/fixtures/full"),
    exit = opts.exit,
    stderr = opts.stderr,
  })
  queue.reset()

  local notifications = {}
  local real = vim.notify
  vim.notify = function(text)
    table.insert(notifications, text)
  end

  local ok, err = pcall(run, fake, notifications)

  fake_dam.drain_the_lane_so_no_answer_lands_in_the_next_case()

  vim.notify = real
  queue.reset()
  fake_dam.remove(fake)

  assert(ok, err)
end

return {
  ["reads the blockers dam named in the refusal's oids"] = function()
    local blockers = done.blockers({
      kind = "refused",
      rule = "blocked",
      message = "644351d cannot be completed:\n  child ed990d4 is open\n  child e0edd1e is open",
      oids = {
        "644351da96df4bf6865f321291806cfe2c9d2360",
        "ed990d451d6471dfd80f8cf8165afac7050967a2",
        "e0edd1eb359113fc4db8c69f0d26805f4bcc8e13",
      },
    })

    assert(vim.deep_equal(blockers, { "ed990d4", "e0edd1e" }), vim.inspect(blockers))
  end,

  ["offers to complete it anyway, and sends --force when that is chosen"] = function()
    with_dam(function(fake)
      local chosen = nil
      local real = vim.ui.select
      vim.ui.select = function(items, opts, on_choice)
        chosen = opts.prompt
        on_choice(items[1], 1)
      end

      done.send(TAXES, false)
      pcall(fake_dam.settle, function()
        return #fake_dam.argv_log(fake) >= 3
      end, 2000)
      vim.ui.select = real

      local log = fake_dam.argv_log(fake)
      assert(log[2] == ("done %s --json"):format(TAXES.oid), vim.inspect(log))
      assert(
        log[3] == ("done %s --force --children keep --json"):format(TAXES.oid),
        "--children keep states the answer the offer promised, and gets through where done.interactive is set: "
          .. vim.inspect(log)
      )
      assert(chosen and chosen:find("4aa6797", 1, true), tostring(chosen))
    end, { exit = 4, stderr = REFUSAL_FOR_A_PARENT_WHOSE_CHILD_IS_OPEN })
  end,

  ["sends nothing more when the offer is declined"] = function()
    with_dam(function(fake)
      local real = vim.ui.select
      vim.ui.select = function(items, _, on_choice)
        on_choice(items[#items], #items)
      end

      done.send(TAXES, false)
      pcall(fake_dam.settle, function()
        return #fake_dam.argv_log(fake) >= 3
      end, 200)
      vim.ui.select = real

      assert(#fake_dam.argv_log(fake) == 2, vim.inspect(fake_dam.argv_log(fake)))
    end, { exit = 4, stderr = REFUSAL_FOR_A_PARENT_WHOSE_CHILD_IS_OPEN })
  end,

  ["reports a refusal no force can help, and opens no picker"] = function()
    with_dam(function(fake, notifications)
      local offered = false
      local real = vim.ui.select
      vim.ui.select = function(items, _, on_choice)
        offered = true
        on_choice(items[1], 1)
      end

      done.send(STANDUP, false)
      fake_dam.settle(function()
        return #notifications > 0
      end)
      vim.ui.select = real

      assert(not offered, "an event is not blocked, so no force was offered")
      assert(notifications[1] == "a070c36 is an event; events are not completed", vim.inspect(notifications))
      assert(#fake_dam.argv_log(fake) == 2, vim.inspect(fake_dam.argv_log(fake)))
    end, { exit = 4, stderr = REFUSAL_FOR_AN_EVENT_NO_FORCE_CAN_HELP })
  end,

  ["says what it completed"] = function()
    with_dam(function(_, notifications)
      done.send(TAXES, false)
      fake_dam.settle(function()
        return #notifications > 0
      end)

      assert(notifications[1] == "damnit.nvim: completed file taxes", vim.inspect(notifications))
    end)
  end,

  ["reports a recurring task as rolled forward rather than as done"] = function()
    with_dam(function(_, notifications)
      done.send({ oid = "f9ba2bac64c810e11b76102ec45902c2c615c074", subject = "water the plants" }, false)
      fake_dam.settle(function()
        return #notifications > 0
      end)

      assert(notifications[1] == "damnit.nvim: rolled forward to 2026-10-02", vim.inspect(notifications))
      for _, line in ipairs(notifications) do
        assert(not line:find("completed", 1, true), "a rolled forward task was not completed: " .. line)
      end
    end, { fixtures = TESTS_DIR .. "/fixtures/rolled" })
  end,
}
