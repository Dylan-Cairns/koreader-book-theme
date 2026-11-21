local luaunit = require("luaunit")
local Generate = require("hn_generate")

local TestGenerate = {}

local CANDIDATES = {
    {selector = "div.part", level = 1, page_break = false},
    {selector = "p.calibre7", level = 2, page_break = true},
    {selector = "p.section", level = 3, page_break = false},
}

function TestGenerate:testGroupsByLevelAndEmitsHints()
    local css = Generate.generate(CANDIDATES, {})
    luaunit.assertStrContains(css, "p.calibre7")
    luaunit.assertStrContains(css, "font-size: 1.28rem !important;")
    luaunit.assertStrContains(css, "-cr-hint: toc-level2;")
    luaunit.assertStrContains(css, "page-break-before: always !important;")
    luaunit.assertStrContains(css, "p.calibre7 *")
    luaunit.assertNotStrContains(css, "2026")
end

function TestGenerate:testDeterministicOutput()
    local first = Generate.generate(CANDIDATES, {})
    local second = Generate.generate({
        {selector = "p.section", level = 3},
        {selector = "p.calibre7", level = 2, page_break = true},
        {selector = "div.part", level = 1},
    }, {})
    luaunit.assertEquals(first, second)
end

function TestGenerate:testEmptyInput()
    luaunit.assertNil(Generate.generate({}, {}))
end

function TestGenerate:testHintsCanBeDisabled()
    local css = Generate.generate(CANDIDATES, {toc_hints = false})
    luaunit.assertNotStrContains(css, "-cr-hint")
end

return TestGenerate
