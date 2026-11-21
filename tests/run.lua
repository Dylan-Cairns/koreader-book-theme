package.path = table.concat({
    "local/toolchain/luaunit/?.lua",
    "local/toolchain/luacheck/src/?.lua",
    "local/toolchain/luacheck/src/?/init.lua",
    "plugin/book-theme.koplugin/?.lua",
    "plugin/book-theme.koplugin/?/init.lua",
    "tests/?.lua",
    package.path,
}, ";")
local suite = {}
-- Test.ps1 discovers *_test.lua. Each returns a table of LuaUnit test methods.
for index, name in ipairs(arg) do
    suite[#suite + 1] = {"TestFile" .. index, assert(loadfile(name))()}
end
local runner = require("luaunit").LuaUnit.new()
runner:setOutputType("text")
local failures = runner:runSuiteByInstancesNoCmdLineParsing(suite)
assert(runner.result.runCount > 0, "No tests ran")
os.exit(failures)
