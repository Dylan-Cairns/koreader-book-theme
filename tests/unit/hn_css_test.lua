local luaunit = require("luaunit")
local Html = require("hn_html")
local Css = require("hn_css")

local TestCss = {}

local STYLE = [[
p { font-size: 1em; font-weight: normal; }
.calibre7 { font-size: 1.4em; font-weight: bold; text-align: center; }
p.calibre7 { font-size: 1.6em !important; }
#ch1 { page-break-before: always; }
@media screen { .calibre7 { letter-spacing: 0.1em; } }
.x:hover { font-size: 9em; }
]]

local function element(html)
    local doc = Html.parse(html)
    for _, candidate in ipairs(doc.elements) do
        if candidate.tag == "p" then return candidate end
    end
end

function TestCss:testSpecificityAndImportant()
    local rules = Css.parse(STYLE)
    local values = Css.compute(element('<p class="calibre7" id="ch1">x</p>'), rules)
    luaunit.assertEquals(values["font-size"], "1.6em")
    luaunit.assertEquals(values["font-weight"], "bold")
    luaunit.assertEquals(values["text-align"], "center")
    luaunit.assertEquals(values["page-break-before"], "always")
    luaunit.assertEquals(values["letter-spacing"], "0.1em")
end

function TestCss:testInlineStyleWins()
    local rules = Css.parse(STYLE)
    local values = Css.compute(
        element('<p class="calibre7" style="font-size:2em; font-weight:normal">x</p>'), rules)
    luaunit.assertEquals(values["font-size"], "2em")
    luaunit.assertEquals(values["font-weight"], "normal")
end

function TestCss:testPseudoSelectorsAreIgnored()
    local rules = Css.parse(STYLE)
    for _, rule in ipairs(rules) do
        luaunit.assertNotStrContains(rule.tag or "", "hover")
    end
end

function TestCss:testValueHelpers()
    luaunit.assertEquals(Css.font_size_ratio("1.4em"), 1.4)
    luaunit.assertEquals(Css.font_size_ratio("120%"), 1.2)
    luaunit.assertEquals(Css.font_size_ratio("large"), 1.2)
    luaunit.assertEquals(Css.font_size_ratio("24px"), 1.5)
    luaunit.assertNil(Css.font_size_ratio("12"))
    luaunit.assertTrue(Css.is_bold("bold"))
    luaunit.assertTrue(Css.is_bold("700"))
    luaunit.assertFalse(Css.is_bold("500"))
    luaunit.assertTrue(Css.is_centered("center"))
    luaunit.assertTrue(Css.page_break_before("always"))
    luaunit.assertFalse(Css.page_break_before("avoid"))
    luaunit.assertEquals(Css.margin_top("1.5em"), 1.5)
end

return TestCss
