local luaunit = require("luaunit")
local Html = require("hn_html")
local Css = require("hn_css")
local Classify = require("hn_classify")

local TestClassify = {}

local SAMPLE = [[
<html><body>
  <div id="ch1" class="chapter">
    <p class="calibre7">Chapter One</p>
    <p class="body">Ordinary body text that is long enough to look like prose.</p>
  </div>
  <p epub:type="chapter" class="sem">Chapter Two</p>
  <p class="epigraph">A quotation at the start.</p>
  <p class="poem">A line of verse</p>
  <p class="dropcap">T</p>
  <h2>Real heading</h2>
</body></html>
]]

local STYLE = [[
p { font-size: 1em; }
body { font-size: 1em; }
.calibre7 { font-size: 1.4em; font-weight: bold; text-align: center; }
.sem { font-size: 1.3em; font-weight: bold; }
.epigraph { font-size: 1.1em; font-style: italic; text-align: center; }
.poem { font-size: 1.1em; text-align: center; }
.dropcap { font-size: 2em; font-weight: bold; }
]]

local function classify(html, style, toc)
    local doc = Html.parse(html)
    local rules = Css.parse(style or STYLE)
    return Classify.classify_file("chapter1.xhtml", doc, rules, toc or {}, {})
end

local function by_selector(candidates)
    local result = {}
    for _, candidate in ipairs(candidates) do result[candidate.selector] = candidate end
    return result
end

function TestClassify:testTocTargetWinsInsideWrapper()
    local candidates = classify(SAMPLE, nil, {
        {path = "chapter1.xhtml", fragment = "ch1", title = "Chapter One", depth = 1},
    })
    local found = by_selector(candidates)
    luaunit.assertNotNil(found["p.calibre7"])
    luaunit.assertEquals(found["p.calibre7"].level, 2)
    luaunit.assertEquals(found["p.calibre7"].score, 100)
    luaunit.assertTrue(found["p.calibre7"].reasons[1] == "toc")
end

function TestClassify:testSemanticHeading()
    local found = by_selector(classify(SAMPLE))
    luaunit.assertNotNil(found["p.sem"])
    luaunit.assertEquals(found["p.sem"].level, 2)
    luaunit.assertEquals(found["p.sem"].score, 80)
end

function TestClassify:testNegativeFixturesAreRejected()
    local found = by_selector(classify(SAMPLE))
    luaunit.assertNil(found["p.epigraph"])
    luaunit.assertNil(found["p.poem"])
    luaunit.assertNil(found["p.dropcap"])
    luaunit.assertNil(found["p.body"])
    luaunit.assertNil(found["h2"])
end

function TestClassify:testLayoutOnlyCandidateNeedsTwoSignals()
    local html = [[
    <body>
      <p class="part-title">Part One</p>
      <p class="noise">Short line</p>
    </body>]]
    local style = [[
    p { font-size: 1em; }
    .part-title { font-size: 1.5em; font-weight: bold; }
    .noise { font-size: 1em; }
    ]]
    local found = by_selector(classify(html, style))
    luaunit.assertNotNil(found["p.part-title"])
    luaunit.assertEquals(found["p.part-title"].level, 1)
    luaunit.assertNil(found["p.noise"])
end

function TestClassify:testSmallSectionTitleAndBoldOpening()
    local html = [[
    <body>
      <p class="section-title">A Section</p>
      <p class="opening">A first paragraph with a bold opening sentence.</p>
    </body>]]
    local style = [[
    p { font-size: 1em; }
    .section-title { font-size: 1.2em; font-weight: bold; }
    .opening { font-weight: bold; }
    ]]
    local found = by_selector(classify(html, style))
    luaunit.assertNotNil(found["p.section-title"])
    luaunit.assertEquals(found["p.section-title"].level, 3)
    luaunit.assertNil(found["p.opening"])
end

function TestClassify:testMergeCombinesSelectorsAcrossFiles()
    local merged = Classify.merge({
        {selector = "p.title", level = 2, score = 100, count = 1, text = "One",
            reasons = {"toc"}, page_break = false, level_scores = {[2] = 100}},
        {selector = "p.title", level = 3, score = 50, count = 1, text = "Two",
            reasons = {"layout"}, page_break = true, level_scores = {[3] = 50}},
        {selector = "div.part", level = 1, score = 80, count = 1, text = "Part",
            reasons = {"epub-semantics"}, page_break = false, level_scores = {[1] = 80}},
    })
    luaunit.assertEquals(#merged, 2)
    luaunit.assertEquals(merged[1].selector, "div.part")
    luaunit.assertEquals(merged[2].selector, "p.title")
    luaunit.assertEquals(merged[2].count, 2)
    luaunit.assertTrue(merged[2].page_break)
end

return TestClassify
