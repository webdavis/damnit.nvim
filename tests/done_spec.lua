-- Completing a task, and what happens when dam refuses because something under
-- it is still open.

local TESTS_DIR = arg[0]:match("(.*)/") or "."

local fake_dam = dofile(TESTS_DIR .. "/helpers/fake_dam.lua")
local queue = require("damnit.queue")
local done = require("damnit.done")

local TAXES = { oid = "cfdc36e6c43673b75f02ea89501cba466e96625b", subject = "file taxes" }

--- dam's own refusal for a parent whose child is open, captured from
--- `dam done <oid> --json` against a store in a temporary directory.
local BLOCKED = table.concat({
  '{"error": {"kind": "refused", "rule": "blocked", ',
  '"message": "cfdc36e cannot be completed:\\n  child 4aa6797 is open\\n',
  'use --force to complete it anyway, or --force --interactive to decide what happens to them", ',
  '"oids": ["cfdc36e6c43673b75f02ea89501cba466e96625b", "4aa6797253e3610afe61c236650b6ec3f41877ee"]}}',
})

---@param run fun(fake: damnit.FakeDam, notifications: string[])
---@param opts { fixtures: string?, exit: integer?, stderr: string? }?
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

  -- A call still in flight answers after the teardown and lands its message in
  -- the next case, so the lane is drained before the fake is taken away.
  pcall(fake_dam.settle, function()
    return queue.running() == nil
  end, 2000)

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

  ["recognises the rule for a question no machine format can answer"] = function()
    local said = done.interactive_refusal({ kind = "refused", rule = "needs_an_answer" }, TAXES.oid)

    assert(
      said
        == "dam is configured to ask what happens to the children; "
          .. "run dam done cfdc36e --force --interactive in a terminal",
      tostring(said)
    )
    assert(done.interactive_refusal({ kind = "refused", rule = "blocked" }, TAXES.oid) == nil)
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
      assert(log[3] == ("done %s --force --json"):format(TAXES.oid), vim.inspect(log))
      assert(chosen and chosen:find("4aa6797", 1, true), tostring(chosen))
    end, { exit = 4, stderr = BLOCKED })
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
    end, { exit = 4, stderr = BLOCKED })
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
