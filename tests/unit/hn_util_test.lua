local luaunit = require("luaunit")
local Util = require("hn_util")

local TestUtil = {}

function TestUtil:testTrimAndWhitespace()
    luaunit.assertEquals(Util.trim("  a  b  "), "a  b")
    luaunit.assertEquals(Util.trim(nil), "")
    luaunit.assertItemsEquals(Util.split_whitespace(" a  b\tc "), {"a", "b", "c"})
end

function TestUtil:testPathNormalisation()
    luaunit.assertEquals(Util.normalize_path("OEBPS/./text/../chapter1.xhtml"),
        "OEBPS/chapter1.xhtml")
    luaunit.assertEquals(Util.normalize_path("/OEBPS//chapter1.xhtml"),
        "/OEBPS/chapter1.xhtml")
    luaunit.assertEquals(Util.join_path("OEBPS", "../META-INF/container.xml"),
        "META-INF/container.xml")
    luaunit.assertEquals(Util.dirname("OEBPS/text/chapter1.xhtml"), "OEBPS/text")
    luaunit.assertEquals(Util.basename("OEBPS/text/chapter1.xhtml"), "chapter1.xhtml")
end

function TestUtil:testUrlAndEntityDecoding()
    luaunit.assertEquals(Util.url_decode("chapter%201.xhtml"), "chapter 1.xhtml")
    luaunit.assertEquals(Util.decode_entities("A &amp; B &mdash; C"), "A & B - C")
    luaunit.assertEquals(Util.decode_entities("&#65;"), "A")
end

function TestUtil:testAttributeParsing()
    local attrs = Util.parse_attrs(
        '<p class="calibre7 title" id=\'ch1\' epub:type="chapter" style="font-size:1.4em">')
    luaunit.assertEquals(attrs.class, "calibre7 title")
    luaunit.assertEquals(attrs.id, "ch1")
    luaunit.assertEquals(attrs["epub:type"], "chapter")
    luaunit.assertEquals(attrs.style, "font-size:1.4em")
end

return TestUtil
