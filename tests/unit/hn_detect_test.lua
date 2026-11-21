-- Detection fixtures F1-F10 from the corpus audit, plus the layout confidence
-- matrix. Every fixture is a pair: the negative case must not produce a rule,
-- the positive control must. All books are synthetic and built in memory.

local luaunit = require("luaunit")
local Scan = require("hn_scan")
local Html = require("hn_html")
local Css = require("hn_css")
local Classify = require("hn_classify")
local Helpers = require("helpers")

local TestDetect = {}

local CONTAINER = [[
<container><rootfiles><rootfile full-path="OEBPS/content.opf"/></rootfiles></container>
]]

local function build_opf(spec)
    local manifest = {}
    local spine = {}
    for _, doc in ipairs(spec.documents) do
        local properties = doc.properties and (' properties="' .. doc.properties .. '"') or ""
        manifest[#manifest + 1] = string.format(
            '<item id="%s" href="%s" media-type="application/xhtml+xml"%s/>',
            doc.id, doc.path, properties)
        if doc.in_spine ~= false then
            spine[#spine + 1] = '<itemref idref="' .. doc.id .. '"/>'
        end
    end
    if spec.css then
        manifest[#manifest + 1] =
            '<item id="css" href="style.css" media-type="text/css"/>'
    end
    local has_ncx = spec.toc ~= nil and #spec.toc > 0
    if has_ncx then
        manifest[#manifest + 1] =
            '<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>'
    end
    local guide = ""
    if spec.guide then
        guide = "<guide>"
        for _, reference in ipairs(spec.guide) do
            guide = guide .. string.format('<reference type="%s" href="%s"/>',
                reference.type, reference.href)
        end
        guide = guide .. "</guide>"
    end
    local toc_attr = has_ncx and ' toc="ncx"' or ""
    return string.format(
        '<package version="2.0"><manifest>%s</manifest>'
            .. '<spine%s>%s</spine>%s</package>',
        table.concat(manifest), toc_attr, table.concat(spine), guide)
end

local function build_ncx(entries)
    local points = {}
    for index, entry in ipairs(entries or {}) do
        points[#points + 1] = string.format(
            '<navPoint id="n%d"><navLabel><text>%s</text></navLabel>'
                .. '<content src="%s"/></navPoint>',
            index, entry.title or "Title", entry.src)
    end
    return "<navMap>" .. table.concat(points) .. "</navMap>"
end

local function book(spec)
    local files = {
        ["META-INF/container.xml"] = CONTAINER,
        ["OEBPS/content.opf"] = build_opf(spec),
    }
    for _, doc in ipairs(spec.documents) do
        files["OEBPS/" .. doc.path] = doc.html
    end
    if spec.css then files["OEBPS/style.css"] = spec.css end
    if spec.toc and #spec.toc > 0 then files["OEBPS/toc.ncx"] = build_ncx(spec.toc) end
    return Helpers.memory_reader(files)
end

local function scan(spec)
    local result = Scan.scan(book(spec), {})
    luaunit.assertNil(result.error)
    return result
end

local function by_selector(result)
    local found = {}
    for _, candidate in ipairs(result.candidates or {}) do
        found[candidate.selector] = candidate
    end
    return found
end

local function heading_selectors(result)
    local found = by_selector(result)
    for selector, candidate in pairs(found) do
        if candidate.role == "quote" then found[selector] = nil end
    end
    return found
end

local function has_selector_prefix(result, prefix)
    for _, candidate in ipairs(result.candidates or {}) do
        if candidate.selector:sub(1, #prefix) == prefix then return true end
    end
    return false
end

local LONG_TEXT = string.rep("Long body text that is not a heading. ", 12)

-- F1: only an explicit semantic allow-list creates a candidate; a deny token
-- wins even when another token is allowed.
function TestDetect:testF1SemanticKindGate()
    local result = scan({
        documents = {{
            id = "c1", path = "chapter1.xhtml",
            html = [[<html><body>
                <p class="biblio" epub:type="biblioentry">A cited book</p>
                <p class="index" epub:type="index-entry">Indexed term</p>
                <p class="endnote" epub:type="endnote">Note one</p>
                <p class="footnote" epub:type="footnote">Footnote one</p>
                <p class="noteref" epub:type="noteref">Reference</p>
                <p class="backlink" epub:type="backlink">Back</p>
                <p class="pagebreak" epub:type="pagebreak">42</p>
                <p class="caption" epub:type="caption">A caption</p>
                <p class="epi" epub:type="epigraph">An epigraph</p>
                <p class="cover" epub:type="cover">Cover</p>
                <div class="chap" epub:type="chapter">Chapter One</div>
            </body></html>]],
        }},
    })
    local found = heading_selectors(result)
    for _, selector in ipairs({"p.biblio", "p.index", "p.endnote", "p.footnote",
        "p.noteref", "p.backlink", "p.pagebreak", "p.caption", "p.cover"}) do
        luaunit.assertNil(found[selector], selector .. " must be denied")
    end
    luaunit.assertNil(found["p.epi"], "epigraph is never a heading")
    luaunit.assertNotNil(found["div.chap"], "allow-listed chapter must survive")
    -- The epigraph is still styled, with the separate quote role.
    luaunit.assertEquals(by_selector(result)["p.epi"].role, "quote")
end

function TestDetect:testSemanticDenyListBeatsAllowList()
    local result = scan({
        documents = {{
            id = "c1", path = "chapter1.xhtml",
            html = [[<html><body>
                <p class="mixed" epub:type="chapter biblioentry">Chapter One</p>
            </body></html>]],
        }},
    })
    luaunit.assertNil(by_selector(result)["p.mixed"])
end

-- F2: a ToC target that is a long wrapper is not a heading; the short title
-- block in the control document is.
function TestDetect:testF2TocWrapperTarget()
    local result = scan({
        documents = {
            {id = "c1", path = "ch1.xhtml", html =
                '<html><body><div id="thework" class="work"><p>' .. LONG_TEXT ..
                "</p></div></body></html>"},
            {id = "c2", path = "ch2.xhtml", html =
                '<html><body><div id="ch2" class="chapter">'
                .. '<p class="chap-title">Chapter Two</p>'
                .. "<p>Ordinary body text.</p></div></body></html>"},
        },
        toc = {
            {src = "ch1.xhtml#thework", title = "The Work"},
            {src = "ch2.xhtml#ch2", title = "Chapter Two"},
        },
    })
    local found = by_selector(result)
    luaunit.assertNil(found["div.work"])
    luaunit.assertNotNil(found["p.chap-title"])
end

-- F3: a title-page document is furniture. The same class names in a body
-- document still produce a rule.
function TestDetect:testF3TitlePageFurniture()
    local result = scan({
        documents = {
            {id = "fm", path = "fm1.xhtml", html = [[<html><body>
                <p class="title">A Book Title</p>
                <p class="subtitle">A Subtitle</p>
                <p class="author">An Author</p>
                <p class="publisher">A Publisher</p>
                <p class="halftitle">Half Title</p>
            </body></html>]]},
            {id = "c1", path = "ch1.xhtml", html = [[<html><body>
                <div class="chapter">
                  <p class="title">Chapter One</p>
                  <p>Ordinary body text.</p>
                </div>
            </body></html>]]},
        },
        css = [[
            p { font-size: 1em; }
            .chapter { page-break-before: always; }
        ]],
        guide = {{type = "title-page", href = "fm1.xhtml"}},
        toc = {{src = "ch1.xhtml", title = "Chapter One"}},
    })
    local found = by_selector(result)
    luaunit.assertEquals(result.stats.front_matter_documents, 1)
    for _, selector in ipairs({"p.halftitle", "p.subtitle", "p.author",
        "p.publisher"}) do
        luaunit.assertNil(found[selector], selector .. " is title-page furniture")
    end
    luaunit.assertNotNil(found["p.title"])
end

-- F4: a layout selector whose text repeats verbatim in three or more documents
-- is a running head. A ToC-backed occurrence is kept.
function TestDetect:testF4RunningHeadRepetition()
    local documents = {}
    for index = 1, 5 do
        documents[index] = {id = "c" .. index, path = "ch" .. index .. ".xhtml",
            html = '<html><body><p class="rh">The Same Book Title</p>'
                .. "<p>Body text for document " .. index .. ".</p></body></html>"}
    end
    local result = scan({
        documents = documents,
        css = [[
            p { font-size: 1em; }
            .rh { font-size: 1.4em; font-weight: bold; }
        ]],
    })
    luaunit.assertNil(by_selector(result)["p.rh"], "running head must be dropped")

    local control = scan({
        documents = {{
            id = "c1", path = "ch1.xhtml",
            html = '<html><body><p class="rh">A Unique Chapter</p>'
                .. "<p>Body text.</p></body></html>",
        }},
        css = [[
            p { font-size: 1em; }
            .rh { font-size: 1.4em; font-weight: bold; }
        ]],
        toc = {{src = "ch1.xhtml", title = "A Unique Chapter"}},
    })
    luaunit.assertNotNil(by_selector(control)["p.rh"])
end

-- F5: the notes heading is styled; individual note items are not.
function TestDetect:testF5NotesHeadingNotItems()
    local items = {}
    for index = 1, 30 do
        items[#items + 1] = string.format(
            '<li id="n-%d" epub:type="endnote">Note %d.</li>', index, index)
    end
    local result = scan({
        documents = {{
            id = "n1", path = "notes.xhtml",
            html = '<html><body><p class="notes-title" id="notes-head" '
                .. 'epub:type="title">Notes</p><ul>' .. table.concat(items)
                .. "</ul></body></html>",
        }},
        toc = {{src = "notes.xhtml#notes-head", title = "Notes"}},
    })
    local found = by_selector(result)
    luaunit.assertNotNil(found["p.notes-title"])
    luaunit.assertFalse(has_selector_prefix(result, "li"))
end

-- F6: empty spacing blocks are invisible, even when the ToC points at them.
function TestDetect:testF6EmptySpacingBlocks()
    local empty = {}
    for index = 1, 20 do
        empty[#empty + 1] = string.format('<p class="calibre1" id="p%d"></p>', index)
    end
    local result = scan({
        documents = {
            {id = "c1", path = "ch1.xhtml", html =
                "<html><body>" .. table.concat(empty) .. "</body></html>"},
            {id = "c2", path = "ch2.xhtml", html = [[<html><body>
                <p class="calibre1" id="c1">Chapter Two</p>
            </body></html>]]},
        },
        toc = {
            {src = "ch1.xhtml#p1", title = "Empty One"},
            {src = "ch1.xhtml#p10", title = "Empty Ten"},
            {src = "ch2.xhtml#c1", title = "Chapter Two"},
        },
    })
    local found = by_selector(result)
    luaunit.assertEquals(#result.candidates, 1)
    luaunit.assertNotNil(found["p.calibre1"])
end

-- F7: a quote is a quote; a first-block blockquote that the ToC names is a
-- chapter title.
function TestDetect:testF7QuoteVersusChapterTitle()
    local result = scan({
        documents = {
            {id = "c1", path = "ch1.xhtml", html = [[<html><body>
                <p>Opening paragraph.</p>
                <blockquote class="verse">
                  <p>First verse line</p>
                  <p>Second verse line</p>
                </blockquote>
            </body></html>]]},
            {id = "c2", path = "ch2.xhtml", html = [[<html><body>
                <blockquote class="calibre5" id="bq1">Chapter Two</blockquote>
                <p>Ordinary body text.</p>
            </body></html>]]},
        },
        css = [[
            p { font-size: 1em; }
            .calibre5 { font-size: 1.4em; font-weight: bold; text-align: center; }
        ]],
        toc = {{src = "ch2.xhtml#bq1", title = "Chapter Two"}},
    })
    local found = by_selector(result)
    local quote = found["blockquote.verse"]
    luaunit.assertNotNil(quote)
    luaunit.assertEquals(quote.role, "quote")
    luaunit.assertEquals(quote.reasons[1], "quote")
    luaunit.assertNil(heading_selectors(result)["blockquote.verse"])
    local title = found["blockquote.calibre5"]
    luaunit.assertNotNil(title)
    luaunit.assertNil(title.role, "ToC title is a heading, not a quote")
    luaunit.assertEquals(title.reasons[1], "toc")
end

-- F8: a section wrapper containing a real heading never becomes a rule; a
-- section whose first child is a pseudo-heading yields the child selector.
function TestDetect:testF8SectionWrapperWithHeadingChild()
    local result = scan({
        documents = {{
            id = "c1", path = "ch1.xhtml", html = [[<html><body>
                <section class="chapter" id="ch1" epub:type="chapter">
                  <h2>Chapter One</h2>
                  <p>Ordinary body text.</p>
                </section>
            </body></html>]],
        }},
        toc = {{src = "ch1.xhtml#ch1", title = "Chapter One"}},
    })
    luaunit.assertFalse(has_selector_prefix(result, "section"))
    luaunit.assertStrContains(result.css, "h2 {")

    local control = scan({
        documents = {{
            id = "c1", path = "ch1.xhtml", html = [[<html><body>
                <section class="chapter" id="ch1" epub:type="chapter">
                  <p class="chap-title">Chapter One</p>
                  <p>Ordinary body text.</p>
                </section>
            </body></html>]],
        }},
    })
    local found = by_selector(control)
    luaunit.assertNotNil(found["p.chap-title"])
    luaunit.assertFalse(has_selector_prefix(control, "section"))
end

-- F9: id selectors on notes are noise; one real chapter id still works.
function TestDetect:testF9IdSelectorNoise()
    local notes, toc = {}, {}
    for index = 1, 50 do
        notes[#notes + 1] = string.format(
            '<p id="p%d" epub:type="rearnote">Short note %d.</p>', index, index)
        if index <= 10 then
            toc[#toc + 1] = {src = "ch1.xhtml#p" .. index, title = "Note " .. index}
        end
    end
    notes[#notes + 1] = '<p id="chap1">Chapter One</p>'
    toc[#toc + 1] = {src = "ch1.xhtml#chap1", title = "Chapter One"}
    local result = scan({
        documents = {{id = "c1", path = "ch1.xhtml",
            html = "<html><body>" .. table.concat(notes) .. "</body></html>"}},
        toc = toc,
    })
    local found = by_selector(result)
    luaunit.assertNotNil(found["p#chap1"])
    for selector in pairs(found) do
        if selector:sub(1, 2) == "p#" then
            luaunit.assertEquals(selector, "p#chap1")
        end
    end
    luaunit.assertEquals(result.stats.pseudo_headings, 1)
end

-- F10: figure captions are not list titles; a short list introduction is.
function TestDetect:testF10CaptionVersusListTitle()
    local result = scan({
        documents = {{
            id = "c1", path = "ch1.xhtml", html = [[<html><body>
                <figure>
                  <figcaption>Figure 1</figcaption>
                  <p class="cap" epub:type="caption">A caption</p>
                </figure>
            </body></html>]],
        }},
    })
    local found = by_selector(result)
    luaunit.assertNil(found["figcaption"])
    luaunit.assertNil(found["p.cap"])

    local control = scan({
        documents = {{
            id = "c1", path = "ch1.xhtml", html = [[<html><body>
                <p class="other" id="chapter-7-list">The list below has three items</p>
                <ol><li>One</li><li>Two</li><li>Three</li></ol>
            </body></html>]],
        }},
        css = [[
            p { font-size: 1em; }
            .other { margin-top: 2em; }
        ]],
    })
    luaunit.assertNotNil(by_selector(control)["p.other"])
end

-- Front matter from the OPF guide, EPUB 3 landmarks and the filename fallback
-- is skipped for every tier. The body document in the same book still works.
function TestDetect:testFrontMatterGuide()
    local result = scan({
        documents = {
            {id = "fm", path = "fm1.xhtml", html = [[<html><body>
                <p class="title">A Book Title</p>
                <p class="subtitle">A Subtitle</p>
            </body></html>]]},
            {id = "c1", path = "ch1.xhtml", html = [[<html><body>
                <p class="chap">Chapter One</p>
            </body></html>]]},
        },
        guide = {{type = "title-page", href = "fm1.xhtml"}},
        toc = {{src = "ch1.xhtml", title = "Chapter One"}},
    })
    luaunit.assertEquals(result.stats.front_matter_documents, 1)
    luaunit.assertNotNil(by_selector(result)["p.chap"])
    luaunit.assertNil(by_selector(result)["p.title"])
end

function TestDetect:testFrontMatterLandmarks()
    local nav = [[<html><body>
        <nav epub:type="landmarks"><ol>
          <li><a href="fm2.xhtml" epub:type="titlepage">Title Page</a></li>
        </ol></nav>
    </body></html>]]
    local result = scan({
        documents = {
            {id = "nav", path = "nav.xhtml", html = nav, properties = "nav",
                in_spine = false},
            {id = "fm", path = "fm2.xhtml", html = [[<html><body>
                <p class="title">A Book Title</p>
            </body></html>]]},
            {id = "c1", path = "ch1.xhtml", html = [[<html><body>
                <p class="chap">Chapter One</p>
            </body></html>]]},
        },
        toc = {{src = "ch1.xhtml", title = "Chapter One"}},
    })
    luaunit.assertEquals(result.stats.front_matter_documents, 1)
    luaunit.assertNotNil(by_selector(result)["p.chap"])
    luaunit.assertNil(by_selector(result)["p.title"])
end

function TestDetect:testFrontMatterFilenameFallback()
    -- Publisher prefixes are common: the stem must be found inside the name.
    local result = scan({
        documents = {
            {id = "fm", path = "s003-BookTitlePage-01.xhtml", html =
                [[<html><body>
                    <p class="subtitle">A New Science of Consciousness</p>
                </body></html>]]},
            {id = "c1", path = "s010-Chapter-001.xhtml", html = [[<html><body>
                <p class="chap" id="chap">Chapter One</p>
            </body></html>]]},
        },
        toc = {{src = "s010-Chapter-001.xhtml#chap", title = "Chapter One"}},
    })
    luaunit.assertEquals(result.stats.front_matter_documents, 1)
    luaunit.assertNotNil(by_selector(result)["p.chap"])
    luaunit.assertNil(by_selector(result)["p.subtitle"])
end

-- Layout confidence matrix. Scores are deterministic: ratio 1.3 (+18), bold
-- (+12), first block (+18), name hint (+15), single occurrence (+12).
local MATRIX_HTML = [[<html><body>
  <p class="strong" id="chapter-one">Chapter One</p>
</body></html>]]
local MATRIX_CSS = [[
p { font-size: 1em; }
.strong { font-size: 1.3em; font-weight: bold; }
]]

local function classify(html, css, toc, options)
    return Classify.classify_file("chapter1.xhtml", Html.parse(html),
        Css.parse(css or ""), toc or {}, options or {})
end

local function layout_found(html, css, min_score)
    local found = {}
    for _, candidate in ipairs(classify(html, css, nil,
        {min_layout_score = min_score})) do
        found[candidate.selector] = candidate
    end
    return found
end

function TestDetect:testLayoutScoreThreshold()
    luaunit.assertNotNil(layout_found(MATRIX_HTML, MATRIX_CSS, 75)["p.strong"])
    luaunit.assertNotNil(layout_found(MATRIX_HTML, MATRIX_CSS, 74)["p.strong"])
    luaunit.assertNil(layout_found(MATRIX_HTML, MATRIX_CSS, 76)["p.strong"])
end

function TestDetect:testOneSignalIsRejected()
    local html = [[<html><body>
      <p>Ordinary paragraph.</p>
      <p class="boldonly">Short line</p>
    </body></html>]]
    local css = [[p { font-size: 1em; } .boldonly { font-weight: bold; }]]
    luaunit.assertNil(layout_found(html, css, 0)["p.boldonly"])
end

function TestDetect:testPageBreakAloneIsRejected()
    local html = [[<html><body>
      <p class="pb">Page break line</p>
    </body></html>]]
    local css = [[p { font-size: 1em; } .pb { page-break-before: always; }]]
    luaunit.assertNil(layout_found(html, css, 0)["p.pb"])
end

function TestDetect:testPageBreakWithNameHintIsAccepted()
    local html = [[<html><body>
      <p class="pb chapter">Page break chapter</p>
    </body></html>]]
    local css = [[
      p { font-size: 1em; }
      .pb { page-break-before: always; }
    ]]
    luaunit.assertNotNil(layout_found(html, css, 0)["p.pb.chapter"])
end

function TestDetect:testTocIgnoresLayoutScore()
    local html = [[<html><body>
      <p class="plain" id="plain-id">Chapter One</p>
    </body></html>]]
    local toc = {{path = "chapter1.xhtml", fragment = "plain-id",
        title = "Chapter One", depth = 1}}
    local found = {}
    for _, candidate in ipairs(classify(html, "p { font-size: 1em; }", toc,
        {min_layout_score = 1000})) do
        found[candidate.selector] = candidate
    end
    luaunit.assertNotNil(found["p.plain"])
    luaunit.assertEquals(found["p.plain"].reasons[1], "toc")
end

-- A ToC entry names one element. When the class selector it shares with body
-- text would be dropped as too broad, the ToC's own id is used instead: an id
-- rule restyles exactly that element and cannot leak into the other paragraphs.
local function shared_class_book(with_ids)
    local blocks = {}
    for index = 1, 100 do
        local id = ""
        if with_ids and index <= 3 then id = string.format(' id="t%d"', index) end
        blocks[#blocks + 1] = string.format(
            '<p class="calibre1"%s>Chapter %d</p>', id, index)
    end
    return {
        documents = {{
            id = "c1", path = "chapter1.xhtml",
            html = "<html><body>" .. table.concat(blocks) .. "</body></html>",
        }},
        css = "p { font-size: 1em; } .calibre1 { margin: 0; }",
        toc = {
            {title = "Chapter One", src = "chapter1.xhtml#t1"},
            {title = "Chapter Two", src = "chapter1.xhtml#t2"},
            {title = "Chapter Three", src = "chapter1.xhtml#t3"},
        },
    }
end

function TestDetect:testSharedClassTocUsesIdFallback()
    local result = scan(shared_class_book(true))
    local found = by_selector(result)

    luaunit.assertEquals(#result.candidates, 3)
    luaunit.assertEquals(result.stats.pseudo_headings, 3)
    luaunit.assertNil(found["p.calibre1"])
    for _, id in ipairs({"t1", "t2", "t3"}) do
        luaunit.assertNotNil(found["p#" .. id])
        luaunit.assertEquals(found["p#" .. id].reasons[1], "toc")
        luaunit.assertEquals(found["p#" .. id].occurrences, 1)
    end
    -- The 97 paragraphs without a ToC id must not be restyled.
    luaunit.assertNotStrContains(result.css, "p.calibre1")
    luaunit.assertStrContains(result.css, "p#t1")
end

function TestDetect:testSharedClassTocWithoutIdIsDropped()
    local result = scan(shared_class_book(false))
    luaunit.assertEquals(#result.candidates, 0)
    luaunit.assertEquals(result.skipped, "no-pseudo-headings")
end

-- ToC rules are the book's own ground truth, so the rule budget only caps
-- inferred layout rules.
function TestDetect:testRuleBudgetKeepsTocRules()
    local layout_blocks, layout_css = {}, {"p { font-size: 1em; }"}
    for index = 1, 70 do
        layout_blocks[#layout_blocks + 1] = string.format(
            '<p class="hn%d">Layout heading %d</p>', index, index)
        layout_css[#layout_css + 1] = string.format(
            ".hn%d { font-size: 1.6em; font-weight: bold; text-align: center; }",
            index)
    end
    local toc_blocks = {}
    for index = 1, 5 do
        toc_blocks[#toc_blocks + 1] = string.format(
            '<p id="t%d">Chapter %d</p>', index, index)
    end

    local result = scan({
        documents = {{
            id = "c1", path = "chapter1.xhtml",
            html = "<html><body>" .. table.concat(toc_blocks)
                .. table.concat(layout_blocks) .. "</body></html>",
        }},
        css = table.concat(layout_css, "\n"),
        toc = {
            {title = "Chapter One", src = "chapter1.xhtml#t1"},
            {title = "Chapter Two", src = "chapter1.xhtml#t2"},
            {title = "Chapter Three", src = "chapter1.xhtml#t3"},
            {title = "Chapter Four", src = "chapter1.xhtml#t4"},
            {title = "Chapter Five", src = "chapter1.xhtml#t5"},
        },
    })

    local toc_count, layout_count = 0, 0
    for _, candidate in ipairs(result.candidates) do
        if candidate.selector:match("^p#t%d$") then
            toc_count = toc_count + 1
        elseif candidate.selector:match("^p%.hn%d+$") then
            layout_count = layout_count + 1
        end
    end
    luaunit.assertEquals(toc_count, 5)
    luaunit.assertEquals(layout_count, 60)
    luaunit.assertEquals(#result.candidates, 65)
end

return TestDetect
