local with_dam = require("helpers.harness").with_dam
local harness = require("helpers.harness")
local app = require("damnit").app()

local fake_process = require("helpers.fake_process")
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

local function full(opts)
  return vim.tbl_extend("keep", opts or {}, { fixtures = harness.fixtures("full") })
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
    local chosen = nil
    local function select(items, opts, on_choice)
      chosen = opts.prompt
      on_choice(items[1], 1)
    end

    with_dam(full({ exit = 4, stderr = REFUSAL_FOR_A_PARENT_WHOSE_CHILD_IS_OPEN, select = select }), function(dam)
      done.send(app, TAXES)
      fake_process.drain()

      local log = fake_process.argv_log(dam.fake)
      assert(log[2] == ("done %s --json"):format(TAXES.oid), vim.inspect(log))
      assert(
        log[3] == ("done %s --force --children keep --json"):format(TAXES.oid),
        "--children keep states the answer the offer promised, and gets through where done.interactive is set: "
          .. vim.inspect(log)
      )
      assert(chosen and chosen:find("4aa6797", 1, true), tostring(chosen))
    end)
  end,

  ["offers every disposition dam takes as a flag, and sends the one chosen"] = function()
    local offered = nil
    local function select(items, opts, on_choice)
      offered = vim.tbl_map(opts.format_item, items)
      on_choice(items[2], 2)
    end

    with_dam(full({ exit = 4, stderr = REFUSAL_FOR_A_PARENT_WHOSE_CHILD_IS_OPEN, select = select }), function(dam)
      done.send(app, TAXES)
      fake_process.drain()

      assert(#offered == 4, vim.inspect(offered))
      assert(offered[4] == "Cancel", vim.inspect(offered))
      local log = fake_process.argv_log(dam.fake)
      assert(log[3] == ("done %s --force --children up --json"):format(TAXES.oid), vim.inspect(log))
    end)
  end,

  ["asks for the group's name before moving the children into it"] = function()
    local function select(items, _, on_choice)
      on_choice(items[3], 3)
    end
    local function input(_, on_answer)
      on_answer("leftovers")
    end

    with_dam(
      full({ exit = 4, stderr = REFUSAL_FOR_A_PARENT_WHOSE_CHILD_IS_OPEN, select = select, input = input }),
      function(dam)
        done.send(app, TAXES)
        fake_process.drain()

        local log = fake_process.argv_log(dam.fake)
        assert(log[3] == ("done %s --force --children into:leftovers --json"):format(TAXES.oid), vim.inspect(log))
      end
    )
  end,

  ["sends nothing when the group's name is left blank"] = function()
    local function select(items, _, on_choice)
      on_choice(items[3], 3)
    end
    local function input(_, on_answer)
      on_answer("  ")
    end

    with_dam(
      full({ exit = 4, stderr = REFUSAL_FOR_A_PARENT_WHOSE_CHILD_IS_OPEN, select = select, input = input }),
      function(dam)
        done.send(app, TAXES)
        fake_process.drain()

        assert(#fake_process.argv_log(dam.fake) == 2, vim.inspect(fake_process.argv_log(dam.fake)))
      end
    )
  end,

  ["sends nothing more when the offer is declined"] = function()
    local function select(items, _, on_choice)
      on_choice(items[#items], #items)
    end

    with_dam(full({ exit = 4, stderr = REFUSAL_FOR_A_PARENT_WHOSE_CHILD_IS_OPEN, select = select }), function(dam)
      done.send(app, TAXES)
      fake_process.drain()

      assert(#fake_process.argv_log(dam.fake) == 2, vim.inspect(fake_process.argv_log(dam.fake)))
    end)
  end,

  ["reports a refusal no force can help, and opens no picker"] = function()
    local offered = false
    local function select(items, _, on_choice)
      offered = true
      on_choice(items[1], 1)
    end

    with_dam(full({ exit = 4, stderr = REFUSAL_FOR_AN_EVENT_NO_FORCE_CAN_HELP, select = select }), function(dam)
      done.send(app, STANDUP)
      fake_process.settle(function()
        return #dam.said > 0
      end)

      assert(not offered, "an event is not blocked, so no force was offered")
      assert(dam.said[1] == "damnit.nvim: a070c36 is an event; events are not completed", vim.inspect(dam.said))
      assert(#fake_process.argv_log(dam.fake) == 2, vim.inspect(fake_process.argv_log(dam.fake)))
    end)
  end,

  ["says what it completed"] = function()
    with_dam(full(), function(dam)
      done.send(app, TAXES)
      fake_process.settle(function()
        return #dam.said > 0
      end)

      assert(dam.said[1] == "damnit.nvim: completed file taxes", vim.inspect(dam.said))
    end)
  end,

  ["reports a recurring task as rolled forward rather than as done"] = function()
    with_dam(full({ fixtures = harness.fixtures("rolled") }), function(dam)
      done.send(app, { oid = "f9ba2bac64c810e11b76102ec45902c2c615c074", subject = "water the plants" })
      fake_process.settle(function()
        return #dam.said > 0
      end)

      assert(dam.said[1] == "damnit.nvim: rolled forward to 2026-10-02", vim.inspect(dam.said))
      for _, line in ipairs(dam.said) do
        assert(not line:find("completed", 1, true), "a rolled forward task was not completed: " .. line)
      end
    end)
  end,
}
