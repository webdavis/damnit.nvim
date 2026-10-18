local M = {}

local ask = require("damnit.health.ask")
local dam = require("damnit.dam")
local store_reports = require("damnit.health.store_reports")
local verbs = require("damnit.dam.verbs")

local call = ask.call

local function nothing_to_speak_to(err)
  return err and (err.kind == "missing" or err.kind == "unsupported")
end

local function report_version_and_store(app)
  local finished, data, err = call(app, verbs.ls(nil, true))

  if not finished then
    vim.health.error(("dam did not answer within %d seconds"):format(ask.DEADLINE_MS / 1000))

    return false
  end

  if nothing_to_speak_to(err) then
    vim.health.error(err.message)

    return false
  end

  local range = ("the supported range is >=%s <%s"):format(dam.MIN_VERSION, dam.MAX_VERSION)

  if app.dam.version then
    local first_dam_on_path = vim.fn.exepath("dam")
    vim.health.ok(("dam %s at %s, and %s"):format(app.dam.version, first_dam_on_path, range))
  else
    vim.health.warn(("dam --version printed something that is not a version, and %s"):format(range))
  end

  if err then
    vim.health.error(("the store did not answer: %s"):format(err.message))
  else
    local object_count = type(data.objects) == "table" and #data.objects or 0
    vim.health.ok(("the store answers, and holds %d objects"):format(object_count))
  end

  return true
end

local function report_paths(app)
  for _, flag in ipairs({ "store", "config" }) do
    local named = app.options[flag]
    local variable = "DAM_" .. flag:upper()
    local from_env = vim.env[variable]

    if type(named) == "string" and named ~= "" then
      vim.health.ok(("the %s is %s, from setup"):format(flag, named))
    elseif type(from_env) == "string" and from_env ~= "" then
      vim.health.ok(("the %s is %s, from %s"):format(flag, from_env, variable))
    else
      vim.health.ok(("the %s is dam's own, which no --%s overrides"):format(flag, flag))
    end
  end
end

function M.check()
  local app = require("damnit").app()
  vim.health.start("damnit.nvim")

  if not report_version_and_store(app) then
    return
  end

  report_paths(app)
  store_reports.remotes(app)
  store_reports.filters(app)
  store_reports.conflicts(app)
  store_reports.views(app)
end

return M
