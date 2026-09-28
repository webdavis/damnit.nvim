local M = {}

local message = require("damnit.message")

local INBOX = "inbox/"

local COMMENT_LEADER_PUNCTUATION = '^[%s%-/#;%%%*"]+'
local BLOCK_COMMENT_TAIL = '%s*[%*%-"]+/%s*$'

local TODO_MARKERS = { "[Tt][Oo][Dd][Oo]", "[Ff][Ii][Xx][Mm][Ee]" }
local ATTRIBUTION_AFTER_MARKER = "^%s*%b()%s*[:%-]?%s*"

local function marker_stands_alone(rest)
  return rest == "" or rest:match("^[^%w]") ~= nil
end

local function strip_marker(text)
  for _, marker in ipairs(TODO_MARKERS) do
    local rest = text:match("^" .. marker .. "(.*)$")
    if rest and marker_stands_alone(rest) then
      return (rest:gsub(ATTRIBUTION_AFTER_MARKER, ""):gsub("^%s*[:%-]?%s*", ""))
    end
  end

  return text
end

local function words_of(line)
  return (line:gsub(COMMENT_LEADER_PUNCTUATION, ""):gsub(BLOCK_COMMENT_TAIL, ""):gsub("%s+$", ""))
end

local function as_one_line(parts)
  return vim.trim((table.concat(parts, " "):gsub("%s+", " ")))
end

function M.content(lines)
  local parts = {}

  for _, line in ipairs(lines) do
    local words = words_of(line)
    if words ~= "" then
      local marker_may_lead = #parts == 0
      if marker_may_lead then
        words = strip_marker(words)
      end
      if words ~= "" then
        parts[#parts + 1] = words
      end
    end
  end

  return as_one_line(parts)
end

function M.args(content, location)
  local args = { "new", content, "--path", INBOX }

  if location then
    vim.list_extend(args, { "--body", require("damnit.location").describe(location) })
  end

  args[#args + 1] = "--json"

  return args
end

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

function M.capture(range)
  local buf = vim.api.nvim_get_current_buf()
  local first = range and range.line1 or vim.api.nvim_win_get_cursor(0)[1]
  local where = require("damnit.location_edit").of_buffer(buf, first)

  if range then
    return M.create(M.content(vim.api.nvim_buf_get_lines(buf, range.line1 - 1, range.line2, false)), where)
  end

  local line = vim.api.nvim_buf_get_lines(buf, first - 1, first, false)[1] or ""

  local current_line_words = M.content({ line })

  vim.ui.input({ prompt = "dam task: ", default = current_line_words }, function(answer)
    if answer == nil or vim.trim(answer) == "" then
      return message.warn("nothing captured")
    end

    M.create(vim.trim(answer), where)
  end)
end

return M
