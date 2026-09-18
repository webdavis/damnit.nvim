-- The completed-task walk: which request reads the next page, what has been
-- collected so far, where the walk stops, and what all of that looks like as
-- lines.
--
-- Everything here is state and pure functions over the pages handed to it: no
-- buffer, no request, no notification. That is what makes the paging boundary
-- and the ordering testable without a window or a network.
--
-- The endpoint reads a window of at most three months, so a history longer than
-- that is several windows walked back one at a time. `since` is inclusive and
-- `until` is exclusive, which is why the first window ends at the start of
-- tomorrow: today's completions have to be inside it.

local M = {}

--- Days in one window. Ninety is inside the API's three-month cap for any three
--- consecutive months, including three that each hold 31 days.
local WINDOW_DAYS = 90

--- How many windows the walk reads. The endpoint has no floor of its own, so
--- the bottom of the list is a stated depth the buffer can name rather than an
--- unbounded string of requests.
local WINDOWS = 12

local SECONDS_PER_DAY = 86400

---@param value any
---@return string
local function text(value)
  if value == nil or value == vim.NIL then
    return ""
  end

  return tostring(value)
end

--- A moment as the ISO 8601 timestamp the endpoint reads, in UTC.
---@param at integer seconds since the Unix epoch
---@return string
local function timestamp(at)
  return os.date("!%Y-%m-%dT%H:%M:%SZ", at)
end

---@param at integer seconds since the Unix epoch
---@return string
local function date(at)
  return os.date("!%Y-%m-%d", at)
end

--- The date part of a completion timestamp, which is what a line shows. A task
--- the API completed with no time keeps the column and shows nothing in it, so
--- the dates below it still line up.
---@param task table
---@return string
function M.completion_date(task)
  return text(task.completed_at):sub(1, 10)
end

--- One completed task as one line: when it was finished, then what it was.
---
--- The list is flat and ordered by completion, so the date leads. A completed
--- task is read for when it was done rather than for where it was filed.
---@param task table
---@return string
function M.task_line(task)
  return ("%-10s  %s"):format(M.completion_date(task), text(task.content))
end

--- Newest first, and within one completion time the higher id first, so two
--- tasks finished the same day have one order rather than whichever the sort
--- happened to leave them in.
---@param left table
---@param right table
---@return boolean
local function newest_first(left, right)
  local at, other = text(left.completed_at), text(right.completed_at)
  if at ~= other then
    return at > other
  end

  return text(left.id) > text(right.id)
end

---@class todoist.CompletedRequest
---@field since string ISO 8601, inclusive
---@field until_ string ISO 8601, exclusive
---@field cursor string? the previous page's cursor, within the same window

local History = {}
History.__index = History

--- A walk starting at the newest window.
---@param now integer? seconds since the Unix epoch, defaulting to the clock
---@return table history
function M.new(now)
  local at = now or os.time()

  -- The start of tomorrow in UTC: `until` is exclusive, so anything earlier
  -- would leave today's completions out of the first window.
  local ends_at = at - (at % SECONDS_PER_DAY) + SECONDS_PER_DAY

  return setmetatable({
    collected = {},
    by_id = {},
    ends_at = ends_at,
    starts_at = ends_at - WINDOW_DAYS * SECONDS_PER_DAY,
    floor_at = ends_at - WINDOW_DAYS * WINDOWS * SECONDS_PER_DAY,
    cursor = nil,
    is_spent = false,
  }, History)
end

--- The request that reads the next page, or nil once the walk has read as deep
--- as it goes.
---@return todoist.CompletedRequest?
function History:request()
  if self.is_spent then
    return nil
  end

  return { since = timestamp(self.starts_at), until_ = timestamp(self.ends_at), cursor = self.cursor }
end

--- Step back to the window before the one just read.
function History:step_back()
  self.cursor = nil
  self.ends_at = self.starts_at
  self.starts_at = math.max(self.ends_at - WINDOW_DAYS * SECONDS_PER_DAY, self.floor_at)
  self.is_spent = self.ends_at <= self.floor_at
end

--- Take one page: keep its tasks, and move the walk to whatever reads the page
--- after it.
---
--- A cursor the walk has already used steps back instead, so an endpoint
--- repeating itself cannot hold the walk on one window.
---@param page table as the endpoint answered, `items` and `next_cursor`
function History:accept(page)
  for _, task in ipairs(page.items or {}) do
    local id = text(task.id)
    if not self.by_id[id] then
      self.by_id[id] = true
      table.insert(self.collected, task)
    end
  end

  -- The whole collection is sorted rather than appended to: an earlier window
  -- is older than the one before it, but the endpoint promises no order inside
  -- one window.
  table.sort(self.collected, newest_first)

  local cursor = page.next_cursor
  if type(cursor) == "string" and cursor ~= "" and cursor ~= self.cursor then
    self.cursor = cursor
  else
    self:step_back()
  end
end

---@return boolean spent whether the walk has read as deep as it goes
function History:spent()
  return self.is_spent
end

---@return integer
function History:len()
  return #self.collected
end

--- Drop a task, which is what reopening one does: it is no longer completed, so
--- it leaves this list at once rather than waiting for a refresh.
---@param id string
function History:forget(id)
  self.collected = vim.tbl_filter(function(task)
    return text(task.id) ~= id
  end, self.collected)
  self.by_id[id] = nil
end

--- The line under the list: how much of the history is on screen, and, at the
--- bottom, the day the walk stopped at.
---@return string
function History:footer()
  local count = ("%d completed tasks."):format(#self.collected)

  if self.is_spent then
    return ("%s Read back to %s, which is as far as the API goes."):format(count, date(self.floor_at))
  end

  return ("%s Move to the last line for more."):format(count)
end

--- The whole screen as lines, plus the task each line holds.
---
--- The id table is the only way a line maps back to a task: nothing parses an id
--- out of display text, so `u` keeps working however the line is written.
---@param status string? what to say instead of the footer, while a page is out
---@return string[] lines
---@return table<integer, string> task id by line number
function History:render(status)
  local lines = { "Todoist: completed", "" }
  local ids = {}

  for _, task in ipairs(self.collected) do
    lines[#lines + 1] = M.task_line(task)
    ids[#lines] = text(task.id)
  end

  if #self.collected == 0 and not status then
    lines[#lines + 1] = "No completed tasks."
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = status or self:footer()

  return lines, ids
end

return M
