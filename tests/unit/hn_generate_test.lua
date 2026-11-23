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
    luaunit.assertStrContains(h1, "font-size: 1.75rem !important;")
    luaunit.assertStrContains(h1, "text-indent: 0 !important;")
    luaunit.assertStrContains(h1, "hyphens: none !important;")
    luaunit.assertStrContains(h1, "page-break-after: avoid !important;")
    luaunit.assertStrContains(h1, "text-transform: none !important;")

    luaunit.assertStrContains(block(css, "h2"), "font-size: 1.50rem !important;")
    luaunit.assertStrContains(block(css, "h3"), "font-size: 1.15rem !important;")
    local minor = block(css, "h4,\nh5,\nh6")
    luaunit.assertNotNil(minor)
    luaunit.assertStrContains(minor, "font-size: 1.00rem !important;")
    luaunit.assertStrContains(minor, "text-transform: none !important;")
    luaunit.assertStrContains(minor, "letter-spacing: normal !important;")

    -- Old-style figures are the default in the Garamond faces; headings and
    -- chapter numbers opt into lining figures.
    luaunit.assertStrContains(h1, "font-variant-numeric: lining-nums !important;")

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
    luaunit.assertStrContains(pseudo, "font-size: 1.50rem !important;")
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
    luaunit.assertNotStrContains(css, "margin-right: 0.35em")
end

function TestGenerate:testHeadingMarkerSitsAboveTheTitleInItsOwnFace()
    local css = generate({}, nil, {markers = {"h1 .chapter-number"}})
    local marker = block(css, "h1 .chapter-number")
    luaunit.assertNotNil(marker)
    -- A block line above the title, in the heading's own face, smaller than
    -- the title: the same treatment as a standalone number heading.
    luaunit.assertStrContains(marker, "display: block !important;")
    luaunit.assertStrContains(marker, "font-family: inherit !important;")
    luaunit.assertStrContains(marker, "font-size: 1.05rem !important;")
    luaunit.assertStrContains(marker, "font-weight: normal !important;")
    luaunit.assertStrContains(marker, "line-height: 1.15 !important;")
    luaunit.assertStrContains(marker, "margin: 0 0 0.3rem 0 !important;")
    luaunit.assertStrContains(marker, "font-variant-numeric: lining-nums !important;")
    luaunit.assertNotStrContains(marker, "display: inline-block")
    luaunit.assertNotStrContains(marker, "margin-right:")
    luaunit.assertNotStrContains(marker, "letter-spacing:")
end

function TestGenerate:testMarkersAreSortedAndDeduplicated()
    local css = generate({}, nil, {
        markers = {"h2 .num", "h1 .chapter-number", "h2 .num"},
    })
    luaunit.assertEquals(Helpers.count(css, "h1 .chapter-number,\nh2 .num {"), 1)
end

function TestGenerate:testStandaloneNumberSitsAboveAndBelowItsTitleInSize()
    local css = generate({}, nil, {
        number_headings = {"h2.ch_title1"},
        number_titles = {"h2.ch_title2"},
    })
    local number = block(css, "h2.ch_title1")
    luaunit.assertNotNil(number)
    -- Smaller than the chapter title above it, in regular weight, with lining
    -- figures.
    luaunit.assertStrContains(number, "font-size: 1.05rem !important;")
    luaunit.assertStrContains(number, "font-weight: normal !important;")
    luaunit.assertStrContains(number, "line-height: 1.15 !important;")
    luaunit.assertStrContains(number, "font-variant-numeric: lining-nums !important;")
    -- Full shorthand: a longhand override lost the other sides in crengine.
    luaunit.assertStrContains(number, "margin: 2.4rem 0 0.3rem 0 !important;")
    local title = block(css, "h2.ch_title2")
    luaunit.assertNotNil(title)
    luaunit.assertStrContains(title, "margin: 0 0 1.5rem 0 !important;")
    -- The title keeps the role size, so it dominates the number.
    luaunit.assertStrContains(block(css, "h2"), "font-size: 1.50rem !important;")
end

function TestGenerate:testStandaloneNumberUsesTheMetricsOfItsHeadingLevel()
    local css = generate({}, nil, {
        number_headings = {"h1.part-number"},
        number_titles = {"h1.part-title"},
    })
    local number = block(css, "h1.part-number")
    luaunit.assertStrContains(number, "font-size: 1.05rem !important;")
    luaunit.assertStrContains(number, "margin: 2.8rem 0 0.3rem 0 !important;")
    local title = block(css, "h1.part-title")
    luaunit.assertStrContains(title, "margin: 0 0 1.8rem 0 !important;")
end

function TestGenerate:testTitleFollowerLosesItsPullUp()
    local css = generate({}, nil, {title_followers = {"div.top", "p.first"}})
    local top = block(css, "div.top")
    luaunit.assertNotNil(top)
    luaunit.assertStrContains(top, "margin-top: 0 !important;")
    -- Deduplicated and sorted into one rule.
    luaunit.assertStrContains(css, "div.top,\np.first {\n    margin-top: 0 !important;\n}")
end

function TestGenerate:testChapterBlockCentredAndSubheadsLeft()
    local theme = Theme.defaults()
    luaunit.assertEquals(theme.roles.part.align, "center")
    luaunit.assertEquals(theme.roles.chapter.align, "center")
    -- Everything below the chapter title sits in prose, so it is left aligned.
    luaunit.assertEquals(theme.roles.section.align, "left")
    luaunit.assertEquals(theme.roles.minor.align, "left")
    local css = generate({})
    local chapter = block(css, "h2")
    luaunit.assertStrContains(chapter, "text-align: center !important;")
    luaunit.assertStrContains(chapter, "margin: 2.4rem 0 1.5rem !important;")
    luaunit.assertStrContains(block(css, "h3"), "text-align: left !important;")
    luaunit.assertStrContains(block(css, "h4,\nh5,\nh6"), "text-align: left !important;")
end

function TestGenerate:testMarkerRuleAppliesOnlyToTheNamedClass()
    local css = generate({}, nil, {markers = {"h1 .chapter-number"}})
    -- Body paragraphs and other headings are untouched.
    luaunit.assertNotStrContains(block(css, "p, li, dd, dt, blockquote"), "display: block")
    luaunit.assertNotStrContains(block(css, "h1"), "display: block")
end

function TestGenerate:testFromGenerationMatchesTheOriginalScan()
    local theme = Theme.defaults()
    local candidates = {
        {selector = "p.section", level = 3, role = "heading", page_break = false},
        {selector = "p.epigraph", role = "quote"},
        {selector = "h1.part", level = 1, page_break = true},
    }
    local options = {
        theme = theme,
        markers = {"h1 .chapter-number"},
        number_headings = {"h2.ch_title1"},
        number_titles = {"h2.ch_title2"},
        title_followers = {"div.top", "p.first"},
    }
    local full = Generate.generate(candidates, options)
    local generation = {
        candidates = candidates,
        markers = options.markers,
        number_headings = options.number_headings,
        number_titles = options.number_titles,
        title_followers = options.title_followers,
    }
    luaunit.assertEquals(Generate.from_generation(generation, theme), full)

    -- A new heading face changes the declarations and the banner hash, not the
    -- selectors or the structure.
    local other = Theme.from_fonts({heading = "Literata"})
    local restyled = Generate.from_generation(generation, other)
    luaunit.assertTrue(restyled ~= full)
    luaunit.assertStrContains(restyled, 'font-family: "Literata" !important;')
    luaunit.assertStrContains(restyled, "p.section {")
    luaunit.assertStrContains(restyled, "-cr-hint: toc-level3;")

    -- A missing or malformed generation is a clean failure, never an error.
    luaunit.assertNil(Generate.from_generation(nil, theme))
    luaunit.assertNil(Generate.from_generation({candidates = "nope"}, theme))
end

return TestGenerate
