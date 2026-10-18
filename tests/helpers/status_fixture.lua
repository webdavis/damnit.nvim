local M = {}

local status_lines = require("damnit.render.status_lines")
local status_model = require("damnit.status_model")

local TESTS_DIR = require("helpers.paths").TESTS

function M.read(name)
  local file = assert(io.open(("%s/fixtures/%s"):format(TESTS_DIR, name), "r"))
  local text = file:read("*a")
  file:close()

  return vim.json.decode(text, { luanil = { object = true } })
end

function M.with_only_the_sections(...)
  local full = M.read("full/status.json")
  local kept = { staged = {}, unstaged = {}, conflicts = {}, notices = {}, unpushed = {} }

  for _, name in ipairs({ ... }) do
    kept[name] = full[name]
  end

  return kept
end

local TEN_AM_UTC_ON_THE_TWENTIETH = 1789898400

M.STATE = { store = "~/.local/share/dam/dam.db", now = TEN_AM_UTC_ON_THE_TWENTIETH }

function M.lines_of(status, state)
  return status_lines.lines(status_model.build(status, M.read("full/remote.json")), state or M.STATE)
end

return M
