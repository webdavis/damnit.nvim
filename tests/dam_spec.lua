-- The dam boundary: the argv it builds, the JSON it decodes, and the error
-- table it makes of every exit code.

local fake_dam = dofile((arg[0]:match("(.*)/") or ".") .. "/helpers/fake_dam.lua")
local dam = require("damnit.dam")
local damnit = require("damnit")

---@param opts table? passed to fake_dam.install
---@param args string[]
---@return table? data
---@return damnit.Error? err
---@return string[] argv_log
local function call(opts, args)
  local fake = fake_dam.install(opts)

  local answered, data, err = false, nil, nil
  dam.call(args, nil, function(value, failure)
    answered, data, err = true, value, failure
  end)

  fake_dam.settle(function()
    return answered
  end)

  local log = fake_dam.argv_log(fake)
  fake_dam.remove(fake)

  return data, err, log
end

return {
  ["builds an argv with no store flags when neither option is set"] = function()
    damnit.options.store, damnit.options.config = nil, nil

    assert(vim.deep_equal(dam.argv({ "status", "--json" }), { "dam", "status", "--json" }))
  end,

  ["passes --store and --config through as global flags, before the subcommand"] = function()
    damnit.options.store, damnit.options.config = "/store/dam.db", "/config/dam.toml"

    local argv = dam.argv({ "status", "--json" })
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
    local data, err, log = call(nil, { "status", "--json" })

    assert(err == nil, err and err.message)
    assert(type(data) == "table" and vim.islist(data.staged), vim.inspect(data))
    assert(log[#log] == "status --json", vim.inspect(log))
  end,

  ["calls exit 1 an error and strips dam's own prefix off the line"] = function()
    local _, err = call({ exit = 1, stderr = "dam: storage: the store is locked" }, { "add", "78b8950", "--json" })

    assert(err.kind == "error", err.kind)
    assert(err.code == 1, tostring(err.code))
    assert(err.message == "storage: the store is locked", err.message)
    assert(err.plugin == nil, "dam wrote this message, so it takes no prefix")
  end,

  ["reads a refusal out of dam's error document, rule and oids included"] = function()
    -- dam writes a header, one indented line per blocker, then its advice.
    local blocked = "98d8780 cannot be completed:\n  child a9db854 is open\n"
      .. "use --force to complete it anyway, or --force --interactive to decide what happens to them"
    local document = vim.json.encode({
      error = {
        kind = "refused",
        rule = "blocked",
        message = blocked,
        oids = { "98d878013fb0e026d37170e7ceed6707192ae99a", "a9db854060d1943ef9eb9f6d7a8ac0b1ace45d77" },
      },
    })
    local _, err = call({ exit = 4, stderr = document }, { "done", "98d8780", "--json" })

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
    local _, err = call({ exit = 1, stderr = document }, { "push", "--json" })

    assert(err.kind == "credential", err.kind)
    assert(err.rule == nil, tostring(err.rule))
    assert(err.message == "no credential for todoist", err.message)
  end,

  ["carries standard error that is not a document as the message it is"] = function()
    local usage = "error: unrecognized subcommand 'dpne'\n\nUsage: dam <COMMAND>"
    local _, err = call({ exit = 2, stderr = usage }, { "dpne", "--json" })

    assert(err.kind == "usage", err.kind)
    assert(err.code == 2, tostring(err.code))
    assert(err.rule == nil, "clap wrote this, so there is no rule")
    assert(err.message == usage, vim.inspect(err.message))
  end,

  ["says which call failed when dam failed and wrote nothing at all"] = function()
    local _, err = call({ exit = 1 }, { "status", "--json" })

    assert(err.kind == "error", err.kind)
    assert(err.message == "a dam call failed with exit 1 and said nothing", err.message)
    assert(err.plugin == true, "the plugin wrote this one")
  end,

  ["calls exit 3 cancelled"] = function()
    local _, err = call({ exit = 3, stderr = "dam: cancelled" }, { "push", "--json" })

    assert(err.kind == "cancelled", err.kind)
    assert(err.code == 3, tostring(err.code))
  end,

  ["calls an undecodable answer on a clean exit malformed rather than raising"] = function()
    local fake = fake_dam.install()
    vim.env.DAMNIT_TEST_FIXTURES = fake.dir

    local file = assert(io.open(fake.dir .. "/status.json", "w"))
    file:write("not json at all\n")
    file:close()

    local answered, err = false, nil
    dam.call({ "status", "--json" }, nil, function(_, failure)
      answered, err = true, failure
    end)

    fake_dam.settle(function()
      return answered
    end)
    fake_dam.remove(fake)

    assert(err.kind == "malformed", vim.inspect(err))
    assert(err.plugin == true, "the plugin wrote this one")
  end,

  ["reports a dam that is not on PATH instead of raising"] = function()
    local saved = vim.env.PATH
    vim.env.PATH = "/nonexistent-for-this-spec"
    dam.forget()

    local answered, err = false, nil
    local ok = pcall(dam.call, { "status", "--json" }, nil, function(_, failure)
      answered, err = true, failure
    end)

    fake_dam.settle(function()
      return answered
    end)

    vim.env.PATH = saved
    dam.forget()

    assert(ok, "a missing binary must not raise out of dam.call")
    assert(err.kind == "missing", vim.inspect(err))
    assert(err.message:find("cargo install damnit", 1, true), err.message)
  end,
}
