local luaunit = require("luaunit")
local Epub = require("hn_epub")
local Helpers = require("helpers")

local TestEpub = {}

local CONTAINER = [[
<?xml version="1.0"?>
<container><rootfiles>
  <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
</rootfiles></container>
]]

local OPF = [[
<?xml version="1.0"?>
<package version="2.0">
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    <item id="c1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
    <item id="c2" href="text/chapter2.xhtml" media-type="application/xhtml+xml"/>
    <item id="css" href="style.css" media-type="text/css"/>
  </manifest>
  <spine toc="ncx"><itemref idref="c1"/><itemref idref="c2"/></spine>
</package>
]]

local NCX = [[
<?xml version="1.0"?>
<navMap>
  <navPoint id="n1"><navLabel><text>Part One</text></navLabel>
    <content src="chapter1.xhtml#ch1"/>
    <navPoint id="n2"><navLabel><text>Chapter One</text></navLabel>
      <content src="chapter1.xhtml#ch1"/>
    </navPoint>
  </navPoint>
</navMap>
]]

local NAV = [[
<html><body>
<nav epub:type="toc"><ol>
  <li><a href="chapter1.xhtml#ch1">Chapter One</a>
    <ol><li><a href="text/chapter2.xhtml">Chapter Two</a></li></ol>
  </li>
</ol></nav>
</body></html>
]]

function TestEpub:testContainerAndPackage()
    luaunit.assertEquals(Epub.parse_container(CONTAINER), "OEBPS/content.opf")
    local opf = Epub.parse_opf(OPF, "OEBPS/content.opf")
    luaunit.assertEquals(opf.version, "2.0")
    luaunit.assertEquals(opf.toc_id, "ncx")
    luaunit.assertEquals(#opf.spine, 2)
    luaunit.assertEquals(opf.manifest_by_id.c1.path, "OEBPS/chapter1.xhtml")
    luaunit.assertEquals(opf.manifest_by_id.css.media_type, "text/css")
end

function TestEpub:testSpineAndStylesheets()
    local opf = Epub.parse_opf(OPF, "OEBPS/content.opf")
    luaunit.assertItemsEquals(Epub.spine_documents(nil, opf),
        {"OEBPS/chapter1.xhtml", "OEBPS/text/chapter2.xhtml"})
    luaunit.assertItemsEquals(Epub.css_documents(nil, opf), {"OEBPS/style.css"})
end

function TestEpub:testNcxHierarchy()
    local entries = Epub.parse_ncx(NCX, "OEBPS")
    luaunit.assertEquals(#entries, 2)
    local by_title = {}
    for _, entry in ipairs(entries) do by_title[entry.title] = entry end
    luaunit.assertEquals(by_title["Part One"].depth, 1)
    luaunit.assertEquals(by_title["Chapter One"].depth, 2)
    luaunit.assertEquals(by_title["Chapter One"].path, "OEBPS/chapter1.xhtml")
    luaunit.assertEquals(by_title["Chapter One"].fragment, "ch1")
end

function TestEpub:testNavHierarchy()
    local entries = Epub.parse_nav(NAV, "OEBPS")
    luaunit.assertEquals(#entries, 2)
    luaunit.assertEquals(entries[1].title, "Chapter One")
    luaunit.assertEquals(entries[1].depth, 1)
    luaunit.assertEquals(entries[2].title, "Chapter Two")
    luaunit.assertEquals(entries[2].depth, 2)
    luaunit.assertEquals(entries[2].path, "OEBPS/text/chapter2.xhtml")
end

function TestEpub:testFindsTocAndEncryption()
    local reader = Helpers.memory_reader({
        ["META-INF/container.xml"] = CONTAINER,
        ["OEBPS/content.opf"] = OPF,
        ["OEBPS/toc.ncx"] = NCX,
    })
    luaunit.assertEquals(Epub.find_opf(reader), "OEBPS/content.opf")
    local opf = Epub.parse_opf(OPF, "OEBPS/content.opf")
    local entries = Epub.toc(reader, opf)
    luaunit.assertEquals(#entries, 2)
    luaunit.assertFalse(Epub.is_encrypted(reader))

    reader.files["META-INF/encryption.xml"] =
        '<EncryptedData><CipherReference URI="OEBPS/chapter1.xhtml"/></EncryptedData>'
    luaunit.assertTrue(Epub.is_encrypted(reader))
end

return TestEpub
