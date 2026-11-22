-- A heading that opens with a bare glued number is a real, repeated defect:
-- the publisher separates the number from the title only in its own stylesheet,
-- so with publisher CSS disabled the two run together. These are the positive
-- and negative fixtures for that detection.

local luaunit = require("luaunit")
local Html = require("hn_html")
local Classify = require("hn_classify")

local TestMarker = {}

local function marker(html)
    local doc = Html.parse(html)
    for _, element in ipairs(doc.elements) do
        if Html.is_heading(element.tag) then
            return Classify.heading_marker(element)
        end
    end
    return nil
end

function TestMarker:testGluedChapterNumberIsDetected()
    luaunit.assertEquals(
        marker('<h1><span class="chapter-number">19</span>Philosophy</h1>'),
        "chapter-number")
    luaunit.assertEquals(
        marker('<h2><span class="num">2.</span>The Most Natural State</h2>'),
        "num")
end

function TestMarker:testMarkerAfterAnEmptyAnchorIsStillDetected()
    luaunit.assertEquals(
        marker('<h1><a id="c19"/><span class="chapter-number">19</span>Philosophy</h1>'),
        "chapter-number")
end

function TestMarker:testSpacedNumberNeedsNoRule()
    luaunit.assertNil(
        marker('<h1><span class="chapter-number">19</span> Philosophy</h1>'))
end

function TestMarker:testNumberAfterTitleTextIsNotAnAccessory()
    luaunit.assertNil(
        marker('<h1>Chapter <span class="num">19</span>Philosophy</h1>'))
end

function TestMarker:testHiddenPageNumberIsNotAChapterNumber()
    luaunit.assertNil(
        marker('<h4><span class="pagebreak-rw">281</span>Notes</h4>'))
    luaunit.assertNil(
        marker('<h2><span class="page-number">12</span>Chapter</h2>'))
end

function TestMarker:testFootnoteAndBulletMarkersAreRejected()
    luaunit.assertNil(
        marker('<h2><span class="refnote-marker-container">1</span>Title</h2>'))
    luaunit.assertNil(
        marker('<h2><span class="bullet-marker">1.</span>Title</h2>'))
    luaunit.assertNil(
        marker('<h2><span class="toc-number">4</span>Title</h2>'))
end

function TestMarker:testOnlyHeadingsAreConsidered()
    luaunit.assertNil(
        marker('<p><span class="chapter-number">19</span>Philosophy</p>'))
end

function TestMarker:testDropCapIsNotANumber()
    luaunit.assertNil(
        marker('<h1><span class="dropcap">T</span>he Beginning</h1>'))
end

function TestMarker:testLongerNumbersAndBareNumbersAreRejected()
    luaunit.assertNil(
        marker('<h1><span class="year">2024</span>Annual Report</h1>'))
    -- No title after the number: there is nothing to separate.
    luaunit.assertNil(
        marker('<h1><span class="chapter-number">19</span></h1>'))
end

function TestMarker:testUnselectableMarkerIsSkipped()
    luaunit.assertNil(marker('<h1><span>19</span>Philosophy</h1>'))
end

return TestMarker
