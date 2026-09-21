-- A task made out of the code in front of you.
--
-- `:Dam capture` takes the subject from a visual selection when there is one
-- and asks for it when there is not, and puts the buffer's location in the
-- task's body. Nothing else is set, so the task lands in `inbox/`, which is
-- where a capture belongs until it is triaged.
--
-- The selection is taken by whole lines. A `TODO` comment is a line of code,
-- and a capture wants the sentence in it rather than the columns it was
-- selected by.

local M = {}

local message = require("damnit.message")

--- The path a capture lands in until somebody triages it.
local INBOX = "inbox/"

--- What a comment starts with in the languages a person writes `TODO` in, and
--- the tail a block comment ends with. Letters are never in this set: a leader
--- is punctuation, and stripping a letter would eat the subject.
local LEADER = '^[%s%-/#;%%%*"]+'
local BLOCK_TAIL = '%s*[%*%-"]+/%s*$'

--- The `TODO` or `FIXME` a comment is marked with, and what a person writes
--- after it before the sentence starts.
local MARKERS = { "[Tt][Oo][Dd][Oo]", "[Ff][Ii][Xx][Mm][Ee]" }
local AFTER_MARKER = "^%s*%b()%s*[:%-]?%s*"

--- Drop a leading `TODO` or `FIXME`, and the `(author)` and punctuation a
--- person puts between it and the sentence.
---
--- The marker only goes when what follows it is not a letter, so a line reading
--- `TODOS are the problem` keeps its first word.
---@param text string
---@return string
local function strip_marker(text)
  for _, marker in ipairs(MARKERS) do
    local rest = text:match("^" .. marker .. "(.*)$")
    if rest and (rest == "" or rest:match("^[^%w]")) then
      return (rest:gsub(AFTER_MARKER, ""):gsub("^%s*[:%-]?%s*", ""))
    end
  end

  return text
end

--- One line of code as the words in it: comment leader, block-comment tail and
--- surrounding space removed.
---@param line string
---@return string
local function words_of(line)
  return (line:gsub(LEADER, ""):gsub(BLOCK_TAIL, ""):gsub("%s+$", ""))
end

--- Several lines of code as one subject.
---
--- A subject is a single line, so the lines are joined with a space and runs of
--- space collapse. The marker goes from the first line that has any words on
--- it, which is where it sits when the comment opens on a fence of its own.
---@param lines string[]
---@return string subject, empty when the lines held no words
function M.content(lines)
  local parts = {}

  for _, line in ipairs(lines) do
    local words = words_of(line)
    if words ~= "" then
      if #parts == 0 then
        words = strip_marker(words)
      end
      if words ~= "" then
        parts[#parts + 1] = words
      end
    end
  end

  return vim.trim((table.concat(parts, " "):gsub("%s+", " ")))
end

--- The `dam new` argv one capture becomes.
---
--- The location is relative and never absolute: a body syncs to a remote and
--- onto a phone.
---@param content string
---@param location damnit.Location?
---@return string[]
function M.args(content, location)
  local args = { "new", content, "--path", INBOX }

  if location then
    vim.list_extend(args, { "--body", require("damnit.location").describe(location) })
  end

  args[#args + 1] = "--json"

  return args
end

--- Create one task, with its location in the body when there is one.
---@param content string
---@param where damnit.Location?
function M.create(content, where)
  if content == "" then
    return message.warn("there is nothing to capture here")
  end

  require("damnit.queue").submit({
    args = M.args(content, where),
    label = "new",
    on_done = function(object, err)
      if err then
        return message.report(err)
      end

      if type(object) ~= "table" or not object.oid then
        return message.warn("dam answered without an object")
      end

      message.say("captured " .. content)
    end,
  })
end

--- Capture the selection, or ask for the subject when there is none.
---
--- With no selection the prompt starts on the current line's own words, so the
--- common case is a keypress and a return, and a buffer holding nothing worth
--- capturing is still a place to type a task from.
---@param range { line1: integer, line2: integer }? the lines a selection covered
function M.capture(range)
  local buf = vim.api.nvim_get_current_buf()
  local first = range and range.line1 or vim.api.nvim_win_get_cursor(0)[1]
  local where = require("damnit.location_edit").of_buffer(buf, first)

  if range then
    return M.create(M.content(vim.api.nvim_buf_get_lines(buf, range.line1 - 1, range.line2, false)), where)
  end

  local line = vim.api.nvim_buf_get_lines(buf, first - 1, first, false)[1] or ""

  vim.ui.input({ prompt = "dam task: ", default = M.content({ line }) }, function(answer)
    if answer == nil or vim.trim(answer) == "" then
      return message.warn("nothing captured")
    end

    M.create(vim.trim(answer), where)
  end)
end

return M
