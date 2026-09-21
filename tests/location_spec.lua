-- The location a body holds, as text.
--
-- A body is text a person can edit on their phone, so every answer here is
-- either a location or nil. Nothing here reaches an editor or a task store:
-- following a location is `location_edit`, and its cases live beside it.

local location = require("damnit.location")

return {
  ["reads a repository, a path and a line out of a body"] = function()
    local parsed = location.parse("damnit.nvim lua/damnit/list.lua:42")

    assert(parsed, "no location parsed")
    assert(parsed.repo == "damnit.nvim", vim.inspect(parsed))
    assert(parsed.path == "lua/damnit/list.lua", vim.inspect(parsed))
    assert(parsed.line == 42, vim.inspect(parsed))
  end,

  ["reads a path and a line with no repository in front of them"] = function()
    local parsed = location.parse("thing.lua:7")

    assert(parsed, "no location parsed")
    assert(parsed.repo == nil, vim.inspect(parsed))
    assert(parsed.path == "thing.lua", vim.inspect(parsed))
    assert(parsed.line == 7, vim.inspect(parsed))
  end,

  ["finds the location under a note somebody typed above it"] = function()
    local parsed = location.parse("ask about this first\n\ndamnit.nvim lua/damnit/list.lua:3\n")

    assert(parsed and parsed.line == 3, vim.inspect(parsed))
  end,

  ["a body with no location at all parses to nothing"] = function()
    assert(location.parse("buy milk") == nil, "a sentence parsed as a location")
    assert(location.parse("") == nil, "an empty body parsed as a location")
    assert(location.parse(nil) == nil, "no body parsed as a location")
    assert(location.parse("lua/thing.lua:no-line") == nil, "a body with no line number parsed")
    assert(location.parse("lua/thing.lua:0") == nil, "line zero parsed")
    assert(location.parse("Isaiah 40:31") == nil, "a bible verse parsed as a location")
  end,

  ["a body carrying a note above the location still parses back to it"] = function()
    local where = { repo = "damnit.nvim", path = "lua/damnit/list.lua", line = 42 }
    local body = "ask about this first\n\n" .. location.describe(where)
    local parsed = location.parse(body)

    assert(parsed and vim.deep_equal(parsed, where), vim.inspect(parsed))
  end,

  ["what a location is written as is what parses back"] = function()
    local written = location.describe({ repo = "damnit.nvim", path = "lua/damnit/list.lua", line = 42 })
    local parsed = location.parse(written)

    assert(written == "damnit.nvim lua/damnit/list.lua:42", written)
    assert(parsed and parsed.path == "lua/damnit/list.lua" and parsed.line == 42, vim.inspect(parsed))
  end,
}
