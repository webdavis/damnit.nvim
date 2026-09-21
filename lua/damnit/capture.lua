-- A task made out of the code in front of you.
--
-- `:Dam capture` takes the content from a visual selection when there is
-- one and asks for it when there is not, and puts the buffer's location in the
-- task's description. Nothing else is set, so the task lands in Inbox, which is
-- where a capture belongs until it is triaged.
--
-- The selection is taken by whole lines. A `TODO` comment is a line of code, and
-- a capture wants the sentence in it rather than the columns it was selected by.

local M = {}

local client = require("damnit.client")
local location = require("damnit.location")

--- What a comment starts with in the languages a person writes `TODO` in, and
--- the tail a block comment ends with. Letters are never in this set: a leader
--- is punctuation, and stripping a letter would eat the content.
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

--- Several lines of code as one line of task content.
---
--- A task's content is a single line in Todoist, so the lines are joined with a
--- space and runs of space collapse. The marker goes from the first line that
--- has any words on it, which is where it sits when the comment opens on a
--- fence of its own.
---@param lines string[]
---@return string content, empty when the lines held no words
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

---@param message string
---@param level integer?
local function notify(message, level)
  vim.notify("damnit.nvim: " .. message, level or vim.log.levels.INFO)
end

--- Send one task, with its location in the description when there is one.
---@param content string
---@param where damnit.Location?
function M.create(content, where)
  if content == "" then
    return notify("there is nothing to capture here", vim.log.levels.WARN)
  end

  local fields = { content = content }
  if where then
    fields.description = location.describe(where)
  end

  client.create_task(fields, function(task, err)
    if err then
      -- The client has already raised the API's own message.
      return
    end

    if type(task) ~= "table" or not task.id then
      return notify("the API answered without a task", vim.log.levels.WARN)
    end

    notify(("captured %s"):format(content))
  end)
end

--- Capture the selection, or ask for the content when there is none.
---
--- With no selection the prompt starts on the current line's own words, so the
--- common case is a keypress and a return, and a buffer holding nothing worth
--- capturing is still a place to type a task from.
---@param range { line1: integer, line2: integer }? the lines a selection covered
function M.capture(range)
  local buf = vim.api.nvim_get_current_buf()
  local first = range and range.line1 or vim.api.nvim_win_get_cursor(0)[1]
  local where = location.of_buffer(buf, first)

  if range then
    return M.create(M.content(vim.api.nvim_buf_get_lines(buf, range.line1 - 1, range.line2, false)), where)
  end

  local line = vim.api.nvim_buf_get_lines(buf, first - 1, first, false)[1] or ""

  vim.ui.input({ prompt = "Todoist task: ", default = M.content({ line }) }, function(answer)
    if answer == nil or vim.trim(answer) == "" then
      return notify("nothing captured", vim.log.levels.WARN)
    end

    M.create(vim.trim(answer), where)
  end)
end

return M
