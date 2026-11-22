local luaunit = require("luaunit")
local Generate = require("hn_generate")
local Theme = require("hn_theme")
local Helpers = require("helpers")

local TestGenerate = {}

local CANDIDATES = {
    {selector = "div.part", level = 1, page_break = false},
    {selector = "p.calibre7", level = 2, page_break = true},
    {selector = "p.section", level = 3, page_break = false},
}

local function generate(candidates, theme, options)
    options = options or {}
    options.theme = theme or Theme.defaults()
    return Generate.generate(candidates, options)
end

-- Return the first rule block whose selector list starts with `selector`.
local function block(css, selector)
    local start = css:find("\n" .. selector, 1, true)
    if not start then return nil end
    local brace = css:find("{", start, true)
    if not brace then return nil end
    local finish = css:find("}", brace, true)
    return css:sub(start, finish)
end

function TestGenerate:testBaseStylesheetWithoutCandidates()
    local css = generate({})
    luaunit.assertNotNil(css)
    luaunit.assertStrContains(css, "/* book-theme v2: per-book typography; theme ")
    luaunit.assertStrContains(css, 'font-family: "EB Garamond" !important;')
    luaunit.assertStrContains(css, "font-weight: normal !important;")
    luaunit.assertStrContains(css, "*, *::before, *::after {")
    luaunit.assertStrContains(css, "font-family: inherit !important;")
    luaunit.assertStrContains(css, "pre, code, kbd, samp, tt {")
    luaunit.assertStrContains(css, "font-family: monospace !important;")
    luaunit.assertStrContains(css, "p, li, dd, dt, blockquote {")
    luaunit.assertStrContains(css, "line-height: inherit !important;")
    luaunit.assertNotStrContains(css, "-cr-hint")
end

function TestGenerate:testRealHeadingsAlwaysThemed()
    local css = generate({})
    local h1 = block(css, "h1")
    luaunit.assertNotNil(h1)
    luaunit.assertStrContains(h1, 'font-family: "Alegreya Sans" !important;')
    luaunit.assertStrContains(h1, "font-weight: bold !important;")
    luaunit.assertStrContains(h1, "font-size: 1.45rem !important;")
    luaunit.assertStrContains(h1, "text-indent: 0 !important;")
    luaunit.assertStrContains(h1, "hyphens: none !important;")
    luaunit.assertStrContains(h1, "page-break-after: avoid !important;")
    luaunit.assertStrContains(h1, "text-transform: none !important;")

    luaunit.assertStrContains(block(css, "h2"), "font-size: 1.30rem !important;")
    luaunit.assertStrContains(block(css, "h3"), "font-size: 1.15rem !important;")
    local minor = block(css, "h4,\nh5,\nh6")
    luaunit.assertNotNil(minor)
    luaunit.assertStrContains(minor, "font-size: 0.95rem !important;")
    luaunit.assertStrContains(minor, "text-transform: uppercase !important;")
    luaunit.assertStrContains(minor, "letter-spacing: 0.05em !important;")

    -- A publisher span inside a real heading must not keep its own metrics.
    local reset = block(css, "h1 *")
    luaunit.assertNotNil(reset)
    luaunit.assertStrContains(reset, "font-size: inherit !important;")
    luaunit.assertStrContains(css, "h4 *,\nh5 *,\nh6 * {")
end

function TestGenerate:testBaseBlockquoteUsesQuoteRole()
    local css = generate({})
    local quote = block(css, "blockquote")
    luaunit.assertNotNil(quote)
    luaunit.assertStrContains(quote, 'font-family: "EB Garamond" !important;')
    luaunit.assertStrContains(quote, "font-style: italic !important;")
    luaunit.assertNotStrContains(quote, "font-size:")
end

function TestGenerate:testPseudoHeadingsGetHintsAndSortedSelectors()
    local css = generate({
        {selector = "p.zeta", level = 2},
        {selector = "div.part", level = 1, page_break = false},
        {selector = "p.alpha", level = 2},
        {selector = "p.section", level = 3},
    })
    luaunit.assertStrContains(css, "-cr-hint: toc-level1;")
    luaunit.assertStrContains(css, "-cr-hint: toc-level2;")
    luaunit.assertStrContains(css, "-cr-hint: toc-level3;")
    luaunit.assertStrContains(css, "p.alpha,\np.zeta {")
    luaunit.assertStrContains(css, "p.alpha *")
    local pseudo = block(css, "p.alpha")
    luaunit.assertStrContains(pseudo, "font-size: 1.30rem !important;")
    luaunit.assertStrContains(pseudo, "-cr-hint: toc-level2;")
end

function TestGenerate:testHintsOnlyOnPseudoHeadings()
    local css = generate(CANDIDATES)
    local h2 = block(css, "h2")
    luaunit.assertNotStrContains(h2, "-cr-hint")
    luaunit.assertStrContains(css, "-cr-hint: toc-level2;")
end

function TestGenerate:testTocHintsFollowTheme()
    local theme = Theme.defaults()
    theme.toc_hints = false
    local css = generate(CANDIDATES, theme)
    luaunit.assertNotStrContains(css, "-cr-hint")
end

function TestGenerate:testQuoteCandidateUsesQuoteRole()
    local css = generate({
        {selector = "p.epigraph", level = 2, role = "quote"},
        {selector = "p.calibre7", level = 2},
    })
    local quote = block(css, "p.epigraph")
    luaunit.assertNotNil(quote)
    luaunit.assertStrContains(quote, 'font-family: "EB Garamond" !important;')
    luaunit.assertStrContains(quote, "font-style: italic !important;")
    luaunit.assertNotStrContains(quote, "font-size:")
    luaunit.assertNotStrContains(quote, "-cr-hint")
    luaunit.assertStrContains(css, "p.epigraph * {")
    -- The quote selector is not part of the level-2 heading rule.
    luaunit.assertNotStrContains(block(css, "p.calibre7"), "p.epigraph")
end

function TestGenerate:testPageBreakStillEmitted()
    local css = generate(CANDIDATES)
    luaunit.assertStrContains(css, "page-break-before: always !important;")
    luaunit.assertStrContains(css, "p.calibre7 {")
end

function TestGenerate:testDeterministicOutput()
    local first = generate(CANDIDATES)
    local second = generate({
        {selector = "p.section", level = 3},
        {selector = "p.calibre7", level = 2, page_break = true},
        {selector = "div.part", level = 1},
    })
    luaunit.assertEquals(first, second)
    luaunit.assertEquals(first, generate(CANDIDATES))
end

function TestGenerate:testSelectorsAreDeduplicated()
    local css = generate({
        {selector = "p.dup", level = 2},
        {selector = "p.dup", level = 2},
    })
    luaunit.assertEquals(Helpers.count(css, "p.dup {"), 1)
    luaunit.assertEquals(Helpers.count(css, "p.dup *"), 1)
end

function TestGenerate:testThemeChangeChangesBannerAndRole()
    local base = generate({})
    local theme = Theme.defaults()
    theme.roles.chapter.family = "Literata"
    local changed = generate({}, theme)
    luaunit.assertNotEquals(base, changed)
    luaunit.assertStrContains(changed, 'font-family: "Literata" !important;')
    luaunit.assertStrContains(changed, "theme " .. Theme.hash(theme) .. ".")
    luaunit.assertStrContains(base, "theme " .. Theme.hash(Theme.defaults()) .. ".")
end

function TestGenerate:testNoTimestampsOrBookText()
    local css = generate({
        {selector = "p.calibre7", level = 2, text = "Chapter One", reasons = {"toc"}},
    })
    luaunit.assertNotStrContains(css, "2026")
    luaunit.assertNotStrContains(css, "Chapter One")
    luaunit.assertNil(css:match("%d%d%d%d%-%d%d%-%d%d"))
end

function TestGenerate:testBodySizeIsNeverForced()
    local css = generate(CANDIDATES)
    luaunit.assertNotStrContains(block(css, "p, li, dd, dt, blockquote"), "font-size:")
end

function TestGenerate:testSupAndSubGetDefaults()
    local css = generate({})
    local inline = block(css, "sup, sub")
    luaunit.assertNotNil(inline)
    luaunit.assertStrContains(inline, "font-size: 0.7em !important;")
    luaunit.assertStrContains(inline, "line-height: 0 !important;")
    luaunit.assertStrContains(css, "sup { vertical-align: super !important; }")
    luaunit.assertStrContains(css, "sub { vertical-align: sub !important; }")
end

function TestGenerate:testNoMarkerRuleWithoutMarkers()
    local css = generate({})
    luaunit.assertNotStrContains(css, "display: block !important;")
end

function TestGenerate:testHeadingMarkerGetsItsOwnLine()
    local css = generate({}, nil, {markers = {"h1 .chapter-number"}})
    local marker = block(css, "h1 .chapter-number")
    luaunit.assertNotNil(marker)
    luaunit.assertStrContains(marker, "display: block !important;")
    luaunit.assertStrContains(marker, "font-size: 0.75em !important;")
    luaunit.assertStrContains(marker, "letter-spacing: 0.1em !important;")
    luaunit.assertStrContains(marker, "margin: 0 0 0.3em 0 !important;")
    -- The heading itself keeps the theme type.
    luaunit.assertNotStrContains(marker, "font-family:")
end

function TestGenerate:testMarkersAreSortedAndDeduplicated()
    local css = generate({}, nil, {
        markers = {"h2 .num", "h1 .chapter-number", "h2 .num"},
    })
    luaunit.assertEquals(Helpers.count(css, "h1 .chapter-number,\nh2 .num {"), 1)
end

function TestGenerate:testMarkerRuleAppliesOnlyToTheNamedClass()
    local css = generate({}, nil, {markers = {"h1 .chapter-number"}})
    -- Body paragraphs and other headings are untouched.
    luaunit.assertNotStrContains(block(css, "p, li, dd, dt, blockquote"), "display: block")
    luaunit.assertNotStrContains(block(css, "h1"), "display: block")
end

return TestGenerate
