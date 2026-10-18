local TESTS = debug.getinfo(1, "S").source:match("^@(.*)/helpers/paths%.lua$")

return { TESTS = TESTS }
