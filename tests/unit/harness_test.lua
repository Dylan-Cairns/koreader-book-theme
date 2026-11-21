local luaunit = require("luaunit")
local TestHarness = {}

function TestHarness:testCompatibleRuntime()
    luaunit.assertEquals(_VERSION, "Lua 5.1")
    luaunit.assertStrContains(jit.version, "LuaJIT 2.1")
    luaunit.assertEquals(require("ffi").sizeof("void *"), 8)
    local packed = table.pack("one", nil, "three")
    luaunit.assertEquals(packed.n, 3)
    luaunit.assertEquals(table.unpack(packed), "one")
end

function TestHarness:testLinterRejectsInvalidLuaAndUnknownGlobals()
    local luacheck = require("luacheck")
    local report = luacheck.check_strings({"local =", "missing_global()"}, {std = "luajit"})
    luaunit.assertTrue(report.errors > 0)
    luaunit.assertTrue(report.warnings > 0)
end

return TestHarness
