local luaunit = require("luaunit")
local Scan = require("hn_scan")
local Theme = require("hn_theme")
local Generate = require("hn_generate")
local Helpers = require("helpers")

local TestScan = {}

local CONTAINER = [[
<container><rootfiles><rootfile full-path="OEBPS/content.opf"/></rootfiles></container>
]]

local OPF = [[
<package version="2.0">
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    <item id="c1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
    <item id="c2" href="chapter2.xhtml" media-type="application/xhtml+xml"/>
    <item id="css" href="style.css" media-type="text/css"/>
  </manifest>
  <spine toc="ncx"><itemref idref="c1"/><itemref idref="c2"/></spine>
</package>
]]

local NCX = [[
<navMap>
  <navPoint><navLabel><text>Chapter One</text></navLabel><content src="chapter1.xhtml#ch1"/></navPoint>
  <navPoint><navLabel><text>Chapter Two</text></navLabel><content src="chapter2.xhtml#ch2"/></navPoint>
</navMap>
]]

local CSS = [[
body { font-size: 1em; }
p { font-size: 1em; }
.calibre7 { font-size: 1.4em; font-weight: bold; text-align: center; }
]]

local CHAPTER1 = [[
<html><body><div id="ch1" class="chapter">
  <p class="calibre7">Chapter One</p>
  <p class="body">Ordinary text that is clearly a paragraph rather than a heading.</p>
</div></body></html>
]]

local CHAPTER2 = [[
<html><body><div id="ch2" class="chapter">
  <p class="calibre7">Chapter Two</p>
  <p class="body">More ordinary text.</p>
</div></body></html>
]]

local function book(overrides)
    local files = {
        ["META-INF/container.xml"] = CONTAINER,
        ["OEBPS/content.opf"] = OPF,
        ["OEBPS/toc.ncx"] = NCX,
        ["OEBPS/style.css"] = CSS,
        ["OEBPS/chapter1.xhtml"] = CHAPTER1,
        ["OEBPS/chapter2.xhtml"] = CHAPTER2,
    }
    for path, content in pairs(overrides or {}) do files[path] = content end
    return Helpers.memory_reader(files)
end

function TestScan:testTocDrivenScan()
    local result = Scan.scan(book(), {})
    luaunit.assertNil(result.error)
    luaunit.assertNil(result.skipped)
    luaunit.assertNotNil(result.css)
    luaunit.assertStrContains(result.css, "p.calibre7")
    luaunit.assertStrContains(result.css, "-cr-hint: toc-level2;")
    luaunit.assertStrContains(result.css, "body {")
    luaunit.assertStrContains(result.css, "h1 {")
    luaunit.assertStrContains(result.css, "/* book-theme v2")
    luaunit.assertNotStrContains(result.css, "Chapter One")
    luaunit.assertEquals(result.stats.pseudo_headings, 1)
    luaunit.assertEquals(result.candidates[1].count, 2)
end

function TestScan:testLayoutOnlyBook()
    local result = Scan.scan(book({
        ["OEBPS/toc.ncx"] = "",
        ["OEBPS/style.css"] = [[
            body { font-size: 1em; }
            p { font-size: 1em; }
            .chapter { page-break-before: always; }
            .chapter-title { font-size: 1.5em; font-weight: bold; text-align: center; }
        ]],
        ["OEBPS/chapter1.xhtml"] = [[
            <html><body><div class="chapter">
              <p class="chapter-title">Chapter One</p>
              <p class="body">Ordinary text that is clearly a paragraph.</p>
            </div></body></html>]],
        ["OEBPS/chapter2.xhtml"] = [[
            <html><body><div class="chapter">
              <p class="chapter-title">Chapter Two</p>
              <p class="body">More ordinary text.</p>
            </div></body></html>]],
    }), {})
    luaunit.assertNil(result.error)
    luaunit.assertNotNil(result.css)
    luaunit.assertStrContains(result.css, "p.chapter-title")
    luaunit.assertStrContains(result.css, "page-break-before: always")
end

function TestScan:testAlreadySemanticBookIsSkipped()
    local result = Scan.scan(book({
        ["OEBPS/toc.ncx"] = "",
        ["OEBPS/chapter1.xhtml"] = "<html><body><h1>Chapter One</h1><p>Text.</p></body></html>",
        ["OEBPS/chapter2.xhtml"] = "<html><body><h1>Chapter Two</h1><p>Text.</p></body></html>",
    }), {})
    luaunit.assertNil(result.error)
    luaunit.assertEquals(result.skipped, "no-pseudo-headings")
    -- No pseudo-headings, but the base theme still styles body type and the
    -- real headings in the book.
    luaunit.assertNotNil(result.css)
    luaunit.assertStrContains(result.css, "body {")
    luaunit.assertStrContains(result.css, "h1 {")
    luaunit.assertNotStrContains(result.css, "-cr-hint")
    luaunit.assertEquals(result.stats.pseudo_headings, 0)
end

function TestScan:testThemeHashIsReported()
    local result = Scan.scan(book(), {})
    luaunit.assertEquals(result.theme_hash, Theme.hash(Theme.defaults()))

    local theme = Theme.defaults()
    theme.roles.chapter.family = "Literata"
    local custom = Scan.scan(book(), {theme = theme})
    luaunit.assertEquals(custom.theme_hash, Theme.hash(theme))
    luaunit.assertNotEquals(custom.theme_hash, result.theme_hash)
    luaunit.assertStrContains(custom.css, 'font-family: "Literata" !important;')
end

function TestScan:testCssIsDeterministicForABook()
    local first = Scan.scan(book(), {})
    local second = Scan.scan(book(), {})
    luaunit.assertEquals(first.css, second.css)
end

function TestScan:testEncryptedBookIsSkipped()
    local result = Scan.scan(book({
        ["META-INF/encryption.xml"] =
            '<EncryptedData><CipherReference URI="OEBPS/chapter1.xhtml"/></EncryptedData>',
    }), {})
    luaunit.assertEquals(result.skipped, "encrypted")
    luaunit.assertNil(result.css)
end

function TestScan:testMalformedHtmlDoesNotThrow()
    local result = Scan.scan(book({
        ["OEBPS/chapter1.xhtml"] = "<html><body><div class=chapter><p class=calibre7>Chapter One",
        ["OEBPS/chapter2.xhtml"] = "<html><body><p class=calibre7>Chapter Two",
    }), {})
    luaunit.assertNil(result.error)
end

function TestScan:testGluedChapterNumberGetsASpace()
    local result = Scan.scan(book({
        ["OEBPS/chapter1.xhtml"] = [[
            <html><body><div id="ch1" class="chapter">
              <h1><span class="chapter-number">1</span>Chapter One</h1>
              <p class="body">Ordinary text.</p>
            </div></body></html>]],
    }), {})
    luaunit.assertNil(result.error)
    luaunit.assertStrContains(result.css, "h1 .chapter-number {\n" ..
        "    display: block !important;\n" ..
        "    font-family: inherit !important;\n" ..
        "    font-size: 1.05rem !important;\n" ..
        "    font-weight: normal !important;\n" ..
        "    line-height: 1.15 !important;\n" ..
        "    margin: 0 0 0.3rem 0 !important;\n" ..
        "    font-variant-numeric: lining-nums !important;\n}")
    luaunit.assertEquals(result.stats.heading_markers, 1)
end

function TestScan:testHeadingLinksAreNotUnderlined()
    local result = Scan.scan(book({
        ["OEBPS/chapter1.xhtml"] = [[
            <html><body>
              <h3 class="sec1"><a href="contents.xhtml#s1">A Section</a></h3>
              <p class="body">Text with a <a href="notes.xhtml#n1">note</a>.</p>
            </body></html>]],
    }), {})
    luaunit.assertNil(result.error)
    -- crengine underlines every anchor by default (embedded styles off); the
    -- heading's link is reset, but the body link keeps its underline.
    local links = result.css:find("\nh1 a,", 1, true)
    luaunit.assertNotNil(links)
    local finish = result.css:find("}", links, true)
    local reset = result.css:sub(links, finish)
    luaunit.assertStrContains(reset, "h3 a")
    luaunit.assertStrContains(reset, "text-decoration: none !important;")
    luaunit.assertNotStrContains(result.css, "\np.body a")
    luaunit.assertNotStrContains(result.css, "\na {")
end

function TestScan:testBlockAfterTheChapterTitleLosesItsPullUp()
    local result = Scan.scan(book({
        ["OEBPS/chapter1.xhtml"] = [[
            <html><body><div class="chapter">
              <h1 class="chapter-title">Chapter One</h1>
              <div class="top"><p class="epigraph">An epigraph.</p></div>
              <p class="body">Ordinary text.</p>
            </div></body></html>]],
        ["OEBPS/chapter2.xhtml"] = [[
            <html><body><div class="chapter">
              <h1 class="chapter-title">Chapter Two</h1>
              <p class="body">Opening text.</p>
              <h2 class="section">A section</h2>
              <p class="body2">Text after a section heading.</p>
            </div></body></html>]],
    }), {})
    luaunit.assertNil(result.error)
    -- The publisher's negative pull-up is cancelled on the block that directly
    -- follows the chapter title. Both chapters' followers share one rule.
    luaunit.assertStrContains(result.css, "div.top,\np.body {\n" ..
        "    margin-top: 0 !important;\n}")
    -- A section heading mid-chapter leaves the next block alone.
    luaunit.assertNotStrContains(result.css, "p.body2 {\n    margin-top: 0")
end

function TestScan:testStandaloneNumberHeadingIsTightenedToItsTitle()
    local result = Scan.scan(book({
        ["OEBPS/chapter1.xhtml"] = [[
            <html><body>
              <h2 class="ch_title1">1</h2>
              <h2 class="ch_title2">Chapter One</h2>
              <p class="body">Ordinary text.</p>
            </body></html>]],
    }), {})
    luaunit.assertNil(result.error)
    luaunit.assertStrContains(result.css, "h2.ch_title1 {\n" ..
        "    font-size: 1.05rem !important;\n" ..
        "    font-weight: normal !important;\n" ..
        "    line-height: 1.15 !important;\n" ..
        "    margin: 2.4rem 0 0.3rem 0 !important;\n" ..
        "    font-variant-numeric: lining-nums !important;\n}")
    luaunit.assertStrContains(result.css, "h2.ch_title2 {\n" ..
        "    margin: 0 0 1.5rem 0 !important;\n}")
    luaunit.assertEquals(result.stats.heading_numbers, 1)
end

function TestScan:testGenerationInputsRebuildTheSameStylesheet()
    local theme = Theme.defaults()
    local result = Scan.scan(book({
        ["OEBPS/chapter1.xhtml"] = [[
            <html><body><div id="ch1" class="chapter">
              <h1><span class="chapter-number">1</span>Chapter One</h1>
              <div class="top"><p class="epigraph">An epigraph.</p></div>
              <p class="body">Ordinary text.</p>
            </div></body></html>]],
        ["OEBPS/chapter2.xhtml"] = [[
            <html><body><div id="ch2" class="chapter">
              <h2 class="ch_title1">2</h2>
              <h2 class="ch_title2">Chapter Two</h2>
              <p class="body">More ordinary text.</p>
            </div></body></html>]],
    }), {theme = theme})
    luaunit.assertNil(result.error)
    luaunit.assertNotNil(result.generation)
    luaunit.assertEquals(result.generation.markers, {"h1 .chapter-number"})
    luaunit.assertEquals(result.generation.number_headings, {"h2.ch_title1"})
    luaunit.assertEquals(result.generation.number_titles, {"h2.ch_title2"})
    luaunit.assertTrue(#result.generation.title_followers > 0)
    -- The compact inputs in the cache must rebuild exactly the scan's
    -- stylesheet; that is what lets a font change re-render the open book
    -- without reading the EPUB again.
    luaunit.assertEquals(Generate.from_generation(result.generation, theme), result.css)
end

return TestScan
