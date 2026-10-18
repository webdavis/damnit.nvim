local highlights = require("damnit.render.highlights")
local render = require("damnit.render")
local scratch = require("damnit.scratch")
local status_fixture = require("helpers.status_fixture")

local fixture = status_fixture.read
local full_status_with_only_the_sections = status_fixture.with_only_the_sections
local lines_of = status_fixture.lines_of

return {
  ["marks the verb, the oid and the path with their own groups"] = function()
    local lines = lines_of(full_status_with_only_the_sections("unstaged"))

    local change = nil
    for _, line in ipairs(lines) do
      if line.kind == "change" then
        change = line
        break
      end
    end

    local groups = vim.tbl_map(function(mark)
      return mark.group
    end, change.marks)

    assert(vim.tbl_contains(groups, "DamOpChanged"), vim.inspect(groups))
    assert(vim.tbl_contains(groups, "DamOid"), vim.inspect(groups))
    assert(vim.tbl_contains(groups, "DamPath"), vim.inspect(groups))
    assert(change.oid == "badb4903b653809e591c31118004e07de7c8183c", tostring(change.oid))
  end,

  ["records every drawn row's kind, oid and section"] = function()
    local lines = lines_of(fixture("full/status.json"))
    local buf = vim.api.nvim_create_buf(false, true)
    render.draw(buf, lines)

    assert(#scratch.rows(buf) == #lines, ("%d rows for %d lines"):format(#scratch.rows(buf), #lines))

    for index, line in ipairs(lines) do
      local row = scratch.row(buf, index)
      assert(row.kind == line.kind, ("line %d kind %s"):format(index, tostring(row.kind)))
      assert(row.oid == line.oid, ("line %d oid %s"):format(index, tostring(row.oid)))
      assert(row.section == line.section, ("line %d section %s"):format(index, tostring(row.section)))
    end

    vim.api.nvim_buf_delete(buf, { force = true })
  end,

  ["names the section every entry and heading belongs to"] = function()
    local lines = lines_of(fixture("full/status.json"))
    local seen = {}

    for _, line in ipairs(lines) do
      if line.section then
        seen[line.section] = (seen[line.section] or 0) + 1
      end
    end

    local heading = 1
    local heading_plus_its_entries = {
      conflicts = heading + 1,
      working = heading + 2,
      staged = heading + 1,
      unpushed = heading + 2,
      notices = heading + 5,
    }
    assert(vim.deep_equal(seen, heading_plus_its_entries), vim.inspect(seen))
  end,

  ["links every group to a standard one and writes no colour"] = function()
    for group, target in pairs(highlights.HIGHLIGHTS) do
      assert(type(target) == "string" and target ~= "", group)
    end

    highlights.define()

    local defined = vim.api.nvim_get_hl(0, { name = "DamOverdue", link = true })
    assert(defined.link == "ErrorMsg", vim.inspect(defined))
  end,
}
