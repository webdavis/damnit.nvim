-- :checkhealth damnit, which reports where dam is, what it holds and which of
-- the declared views it will run.
--
-- Nothing here reports anything about a credential, because nothing here reads
-- one: dam resolves its own and never hands one back.

local fake_dam = dofile((arg[0]:match("(.*)/") or ".") .. "/helpers/fake_dam.lua")
local health = require("damnit.health")

local TESTS_DIR = arg[0]:match("(.*)/") or "."

--- dam's own refusal document, which is what it writes on standard error under
--- `--json` when it will not answer.
local REFUSAL =
  '{"error": {"kind": "refused", "rule": "bad_query", "message": "\\"nonsense\\" is not a declared category", "oids": []}}'

---@param run fun(): nil
---@return { level: string, text: string }[]
local function report(run)
  local lines = {}
  local real = { ok = vim.health.ok, warn = vim.health.warn, error = vim.health.error, start = vim.health.start }

  for _, level in ipairs({ "ok", "warn", "error", "start" }) do
    vim.health[level] = function(text)
      table.insert(lines, { level = level, text = tostring(text) })
    end
  end

  local outcome, err = pcall(run)

  for _, level in ipairs({ "ok", "warn", "error", "start" }) do
    vim.health[level] = real[level]
  end

  assert(outcome, err)

  return lines
end

---@param lines { level: string, text: string }[]
---@param level string
---@param needle string
---@return boolean
local function said(lines, level, needle)
  for _, line in ipairs(lines) do
    if line.level == level and line.text:find(needle, 1, true) then
      return true
    end
  end

  return false
end

return {
  ["reports dam, its version, the supported range and what the store holds"] = function()
    local fake = fake_dam.install({ fixtures = TESTS_DIR .. "/fixtures/full" })
    local lines = report(health.check)
    fake_dam.remove(fake)

    assert(said(lines, "ok", "dam 0.2.0"), vim.inspect(lines))
    assert(said(lines, "ok", ">=0.2.0 <0.3.0"), vim.inspect(lines))

    -- Which dam answered, not just that one did: a machine can carry a
    -- cargo-installed dam and a Homebrew one, and the report is where you find
    -- out which is on PATH first.
    assert(said(lines, "ok", fake.dir .. "/dam"), vim.inspect(lines))
    assert(said(lines, "ok", "4 objects"), "the object count comes off the same ls")
    assert(said(lines, "ok", "the remote fake speaks through the fake helper at fake::"), vim.inspect(lines))

    -- A remote with stale set makes a read pull before it answers, which is
    -- the one configuration the poller's --no-pull is there for, so the report
    -- says which remotes carry it.
    assert(said(lines, "ok", "the remote flaky speaks through the flaky helper at flaky::"), vim.inspect(lines))
    assert(said(lines, "ok", "narrowed to work/"), vim.inspect(lines))
    assert(said(lines, "ok", "stale after 1s, so a read may pull it first"), vim.inspect(lines))
    assert(said(lines, "ok", "today"), "dam's own saved filters are named")

    for _, line in ipairs(lines) do
      assert(not line.text:lower():find("token", 1, true), "the health check never sees a credential")
      assert(not line.text:lower():find("credential", 1, true), "the health check never sees a credential")
    end
  end,

  ["errors with the install line when dam is not on PATH"] = function()
    local saved = vim.env.PATH
    vim.env.PATH = "/nonexistent-for-this-spec"
    require("damnit.dam").forget()

    local lines = report(health.check)

    vim.env.PATH = saved
    require("damnit.dam").forget()

    assert(said(lines, "error", "cargo install damnit"), vim.inspect(lines))
    assert(#lines == 2, "nothing is asked of a dam that is not there")
  end,

  ["refuses a dam outside the supported range and says which one it found"] = function()
    local fake = fake_dam.install({ fixtures = TESTS_DIR .. "/fixtures/full", version = "0.1.0" })
    local lines = report(health.check)
    fake_dam.remove(fake)

    assert(said(lines, "error", "dam 0.1.0 is outside the supported range"), vim.inspect(lines))
    assert(#lines == 2, "nothing is asked of a dam this plugin will not speak to")
  end,

  ["warns with the count when the store holds a conflict"] = function()
    local fake = fake_dam.install({ fixtures = TESTS_DIR .. "/fixtures/full" })
    local lines = report(health.check)
    fake_dam.remove(fake)

    -- full/status.json carries one, and co and ct are what settle it.
    assert(said(lines, "warn", "1 object is in conflict"), vim.inspect(lines))
  end,

  ["names the store and the config the plugin passes, and where each came from"] = function()
    local fake = fake_dam.install({ fixtures = TESTS_DIR .. "/fixtures/full" })
    require("damnit").setup({ store = "/somewhere/dam.db", config = "/somewhere/config.toml" })

    local lines = report(health.check)

    require("damnit").options.store = nil
    require("damnit").options.config = nil
    fake_dam.remove(fake)

    -- dam prints neither path, so the honest report is what it was told.
    assert(said(lines, "ok", "/somewhere/dam.db"), vim.inspect(lines))
    assert(said(lines, "ok", "/somewhere/config.toml"), vim.inspect(lines))
    assert(said(lines, "ok", "from setup"), vim.inspect(lines))
  end,

  ["says dam resolves the store and the config itself when no option names one"] = function()
    local fake = fake_dam.install({ fixtures = TESTS_DIR .. "/fixtures/full" })
    local lines = report(health.check)
    fake_dam.remove(fake)

    assert(said(lines, "ok", "the store is dam's own"), vim.inspect(lines))
    assert(said(lines, "ok", "the config is dam's own"), vim.inspect(lines))
  end,

  ["errors naming each declared view dam refuses, and carries dam's own words"] = function()
    local fake =
      fake_dam.install({ fixtures = TESTS_DIR .. "/fixtures/full", stderr = REFUSAL, exit = 4, version = "0.2.0" })
    require("damnit").setup({ views = { broken = "nonsense:zzz" } })

    local lines = report(health.check)

    require("damnit").options.views = {}
    fake_dam.remove(fake)

    assert(said(lines, "error", "broken"), vim.inspect(lines))
    assert(said(lines, "error", '"nonsense" is not a declared category'), "dam's own line is carried verbatim")
    assert(said(lines, "error", "the store did not answer"), "the same refusal reaches the store check")
  end,

  ["reports every declared view dam runs"] = function()
    local fake = fake_dam.install({ fixtures = TESTS_DIR .. "/fixtures/full" })
    require("damnit").setup({ views = { mine = "path:work" } })

    local lines = report(health.check)

    require("damnit").options.views = {}
    fake_dam.remove(fake)

    assert(said(lines, "ok", 'the view mine runs "path:work"'), vim.inspect(lines))
  end,
}
