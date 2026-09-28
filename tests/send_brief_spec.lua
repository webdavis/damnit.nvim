local TESTS_DIR = arg[0]:match("(.*)/") or "."

local hand_off = dofile(TESTS_DIR .. "/helpers/hand_off.lua")
local send = require("damnit.send")

return {
  ["writes dam's own fields, and leaves out what the object has none of"] = function()
    local brief = send.brief(hand_off.FULL, "start with the receipts")

    assert(brief:find("dam task: file taxes", 1, true), brief)
    assert(brief:find("oid: 78b8950", 1, true), "seven characters, which is what an agent types")
    assert(not brief:find("78b8950b027", 1, true), "never the whole forty")
    assert(brief:find("path: home/finances/", 1, true), brief)
    assert(brief:find("due: 2026-09-20", 1, true), brief)
    assert(brief:find("priority: p1", 1, true), brief)
    assert(brief:find("labels: home, slow", 1, true), brief)
    assert(brief:find("receipts are in the drawer", 1, true), brief)
    assert(brief:find("note: start with the receipts", 1, true), brief)
  end,

  ["leaves out a field the object has nothing for"] = function()
    local brief = send.brief({ oid = hand_off.OID, subject = "x", path = "inbox/" }, nil)

    assert(not brief:find("due:", 1, true), brief)
    assert(not brief:find("labels:", 1, true), brief)
    assert(not brief:find("priority:", 1, true), brief)
    assert(not brief:find("note:", 1, true), brief)
  end,

  ["leaves the priority off an object at dam's least urgent"] = function()
    local brief = send.brief({ oid = hand_off.OID, subject = "x", path = "inbox/", task = { priority = 4 } }, nil)

    assert(not brief:find("priority:", 1, true), brief)
  end,

  ["names the store the window's header names"] = function()
    local brief = send.brief({ oid = hand_off.OID, subject = "x", path = "inbox/" }, nil)
    local store = require("damnit.window").store_display(require("damnit.queue").key())

    assert(brief:find("store: " .. store, 1, true), brief)
  end,

  ["a paste terminator inside the brief cannot end the frame early"] = function()
    local framed = send.pasted("before" .. hand_off.PASTE_END .. "after")

    assert(framed == hand_off.PASTE_START .. "beforeafter" .. hand_off.PASTE_END, vim.inspect(framed))
  end,
}
