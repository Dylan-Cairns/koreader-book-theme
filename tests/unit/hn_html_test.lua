local luaunit = require("luaunit")
local Html = require("hn_html")

local TestHtml = {}

local SAMPLE = [[
<html><head><title>Metadata title</title><style>.x { color: red; }</style></head>
<body>
  <div class="chapter" id="c1">
    <p class="calibre7">Chapter <span>One</span></p>
    <p>Body text.</p>
  </div>
  <h2>Real heading</h2>
  <!-- a comment with <p>fake</p> -->
</body></html>
]]

function TestHtml:testFindsElementsAndAttributes()
    local doc = Html.parse(SAMPLE)
    luaunit.assertEquals(doc.by_id.c1.tag, "div")
    luaunit.assertEquals(doc.by_id.c1.class_set.chapter, true)
    luaunit.assertEquals(doc.body.tag, "body")
end

function TestHtml:testAggregatesTextAndSkipsHead()
    local doc = Html.parse(SAMPLE)
    local chapter = doc.by_id.c1
    luaunit.assertStrContains(chapter.text, "Chapter One")
    luaunit.assertStrContains(chapter.text, "Body text.")
    luaunit.assertEquals(doc.by_id.c1.children[1].tag, "p")
    luaunit.assertEquals(doc.by_id.c1.children[1].classes[1], "calibre7")
    local title = doc.elements[1]
    luaunit.assertEquals(title.tag, "html")
    local head_title
    for _, element in ipairs(doc.elements) do
        if element.tag == "title" then head_title = element end
    end
    luaunit.assertTrue(head_title.in_head)
end

function TestHtml:testFirstBlockAndChildren()
    local doc = Html.parse(SAMPLE)
    local first = Html.first_block_in_body(doc)
    luaunit.assertEquals(first.tag, "div")
    luaunit.assertEquals(Html.first_block_child(first).tag, "p")
    luaunit.assertTrue(Html.has_block_children(first))
    luaunit.assertFalse(Html.has_block_children(Html.first_block_child(first)))
end

function TestHtml:testClosesParagraphsImplicitly()
    local doc = Html.parse("<body><p>one<p>two</body>")
    local paragraphs = 0
    for _, element in ipairs(doc.elements) do
        if element.tag == "p" then paragraphs = paragraphs + 1 end
    end
    luaunit.assertEquals(paragraphs, 2)
    luaunit.assertStrContains(doc.body.text, "one")
    luaunit.assertStrContains(doc.body.text, "two")
end

function TestHtml:testIgnoresCommentsAndScriptBodies()
    local doc = Html.parse("<body><!-- <p>no</p> --><script>var x = '<p>no</p>';</script><p>yes</p></body>")
    luaunit.assertEquals(#doc.elements, 3)
    luaunit.assertEquals(doc.body.text, "yes")
end

function TestHtml:testClimbsInlineElementsToBlock()
    local doc = Html.parse("<body><p class=\"title\"><span>x</span></p></body>")
    local span
    for _, element in ipairs(doc.elements) do
        if element.tag == "span" then span = element end
    end
    luaunit.assertEquals(Html.climb_to_block(span).tag, "p")
end

return TestHtml
