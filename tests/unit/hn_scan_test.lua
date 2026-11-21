local luaunit = require("luaunit")
local Scan = require("hn_scan")
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
    luaunit.assertNil(result.css)
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

return TestScan
