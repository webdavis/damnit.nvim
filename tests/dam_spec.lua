local with_dam = require("helpers.harness").with_dam
local fake_process = require("helpers.fake_process")

local function client()
  return require("damnit").app().dam
end

local damnit = require("damnit")

local function answered_by_a_fake(fake_opts, args)
  local answered, data, err = false, nil, nil

  local sent = with_dam(fake_opts or {}, function()
    client().call(args, nil, function(value, failure)
      answered, data, err = true, value, failure
    end)

    fake_process.settle(function()
      return answered
    end)
  end).sent

  return data, err, sent
end

return {
  ["builds an argv with no store flags when neither option is set"] = function()
    damnit.options.store, damnit.options.config = nil, nil

    assert(vim.deep_equal(client().argv({ "status", "--json" }), { "dam", "status", "--json" }))
  end,

  ["passes --store and --config through as global flags, before the subcommand"] = function()
    damnit.options.store, damnit.options.config = "/store/dam.db", "/config/dam.toml"

    local argv = client().argv({ "status", "--json" })
    damnit.options.store, damnit.options.config = nil, nil

    assert(
      vim.deep_equal(argv, {
        "dam",
        "--store",
        "/store/dam.db",
        "--config",
        "/config/dam.toml",
        "status",
        "--json",
      }),
      vim.inspect(argv)
    )
  end,

  ["decodes the JSON dam printed on a clean exit"] = function()
    local data, err, log = answered_by_a_fake(nil, { "status", "--json" })

    assert(err == nil, err and err.message)
    assert(type(data) == "table" and vim.islist(data.staged), vim.inspect(data))
    assert(log[#log] == "status --json", vim.inspect(log))
  end,

  ["calls exit 1 an error and strips dam's own prefix off the line"] = function()
    local _, err = answered_by_a_fake(
      { exit = 1, stderr = "dam: storage: the store is locked" },
      { "add", "78b8950", "--json" }
    )

    assert(err.kind == "error", err.kind)
    assert(err.code == 1, tostring(err.code))
    assert(err.message == "storage: the store is locked", err.message)
    assert(err.plugin == nil, "dam wrote this message, so it takes no prefix")
  end,

  ["reads a refusal out of dam's error document, rule and oids included"] = function()
    local header = "98d8780 cannot be completed:\n"
    local one_indented_line_per_blocker = "  child a9db854 is open\n"
    local advice = "use --force to complete it anyway, or --force --interactive to decide what happens to them"
    local blocked = header .. one_indented_line_per_blocker .. advice
    local document = vim.json.encode({
      error = {
        kind = "refused",
        rule = "blocked",
        message = blocked,
        oids = { "98d878013fb0e026d37170e7ceed6707192ae99a", "a9db854060d1943ef9eb9f6d7a8ac0b1ace45d77" },
      },
    })
    local _, err = answered_by_a_fake({ exit = 4, stderr = document }, { "done", "98d8780", "--json" })

    assert(err.kind == "refused", err.kind)
    assert(err.code == 4, tostring(err.code))
    assert(err.rule == "blocked", tostring(err.rule))
    assert(err.message == blocked, vim.inspect(err.message))
    assert(#err.oids == 2 and err.oids[2]:sub(1, 7) == "a9db854", vim.inspect(err.oids))
    assert(err.plugin == nil, "dam wrote this message, so it takes no prefix")
  end,

  ["takes dam's own kind for a failure that is not a rule"] = function()
    local document = vim.json.encode({
      error = { kind = "credential", rule = vim.NIL, message = "no credential for todoist", oids = {} },
    })
    local _, err = answered_by_a_fake({ exit = 1, stderr = document }, { "push", "--json" })

    assert(err.kind == "credential", err.kind)
    assert(err.rule == nil, tostring(err.rule))
    assert(err.message == "no credential for todoist", err.message)
  end,

  ["carries standard error that is not a document as the message it is"] = function()
    local usage = "error: unrecognized subcommand 'dpne'\n\nUsage: dam <COMMAND>"
    local _, err = answered_by_a_fake({ exit = 2, stderr = usage }, { "dpne", "--json" })

    assert(err.kind == "usage", err.kind)
    assert(err.code == 2, tostring(err.code))
    assert(err.rule == nil, "clap wrote this, so there is no rule")
    assert(err.message == usage, vim.inspect(err.message))
  end,

  ["says which call failed when dam failed and wrote nothing at all"] = function()
    local _, err = answered_by_a_fake({ exit = 1 }, { "status", "--json" })

    assert(err.kind == "error", err.kind)
    assert(err.message == "a dam call failed with exit 1 and said nothing", err.message)
    assert(err.plugin == true, "the plugin wrote this one")
  end,

  ["calls exit 3 cancelled"] = function()
    local _, err = answered_by_a_fake({ exit = 3, stderr = "dam: cancelled" }, { "push", "--json" })

    assert(err.kind == "cancelled", err.kind)
    assert(err.code == 3, tostring(err.code))
  end,

  ["calls an undecodable answer on a clean exit malformed rather than raising"] = function()
    with_dam({ stdout = "not json at all\n" }, function()
      local answered, err = false, nil
      client().call({ "status", "--json" }, nil, function(_, failure)
        answered, err = true, failure
      end)

      fake_process.settle(function()
        return answered
      end)

      assert(err.kind == "malformed", vim.inspect(err))
      assert(err.plugin == true, "the plugin wrote this one")
    end)
  end,

  ["reports a dam that is not on PATH instead of raising"] = function()
    local saved = vim.env.PATH
    vim.env.PATH = "/nonexistent-for-this-spec"
    require("damnit").setup({})

    local answered, err = false, nil
    local ok = pcall(client().call, { "status", "--json" }, nil, function(_, failure)
      answered, err = true, failure
    end)

    assert(
      vim.wait(1000, function()
        return answered
      end),
      "the missing dam never answered"
    )

    vim.env.PATH = saved
    require("damnit").setup({})

    assert(ok, "a missing binary must not raise out of dam.call")
    assert(err.kind == "missing", vim.inspect(err))
    assert(err.message:find("cargo install damnit", 1, true), err.message)
  end,
}
